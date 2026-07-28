"""The escalation surface: the seam between a stuck integration and the human
who pushed it.

In the notchh repo the macOS notch holds an always-on WebSocket to a Synqit
*server*, and the server escalates to it mid-integration. Synqit's CLI has no
server - the integration runs in the developer's own process - so the thing the
notch connects to is this module: a WebSocket endpoint on loopback that lives
exactly as long as a push does.

The wire contract is unchanged from notchh, deliberately. Same `escalation` /
`resolution` / `withdraw` / `pending` / `ack` messages, same `green`/`red`/
`other` choices, same bearer token on the upgrade request. The macOS app in
`notch/` is the notchh app, and it cannot tell the difference between talking
to a hosted Synqit and talking to this - which is the point: the surface is a
seam, and either end can be replaced without touching the other.

Three things are worth stating plainly:

**Loopback is still authenticated.** Binding to 127.0.0.1 keeps other machines
out, not other processes on this one. The token check is what makes an
escalation answerable only by the notch the developer provisioned.

**The bridge never decides anything.** It transports a question and returns an
answer. Every `needs_human` outcome in this file is the *absence* of a decision,
never one this code invented.

**No answer is not the same as a rejected push.** An escalation that nobody
answers withdraws itself and the push ends as `needs_human` with the developer's
work untouched - which is exactly what happens today when no notch is attached
at all.
"""

import base64;
import hashlib;
import hmac;
import json;
import os;
import secrets;
import socket;
import threading;
import time;

import from datetime { datetime, timedelta, timezone }
import from urllib.parse { urlparse }

# RFC 6455 §1.3. Concatenated with the client's key to prove we understood the
# upgrade rather than merely echoing it.
glob WS_GUID: str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

"""`~/.synqit` in every real install - the macOS app reads that path directly and
has no override for it. SYNQIT_HOME exists so a test can point this end at a
scratch directory instead of the developer's own attachment.

Resolved per call rather than once at import: a glob would freeze the path
before a test could redirect it."""
def synqit_dir -> str {
    return os.environ.get("SYNQIT_HOME") or os.path.expanduser("~/.synqit");
}

def config_path -> str {
    return os.path.join(synqit_dir(), "config.json");
}

def token_path -> str {
    return os.path.join(synqit_dir(), "notch-token");
}

glob DEFAULT_HOST: str = "127.0.0.1";
glob DEFAULT_PORT: int = 8787;

"""notchh's SYNQIT_DECISION_TIMEOUT_MS, in seconds. A decision the developer is
sitting on holds their own push open, so it cannot wait forever."""
glob DECISION_TIMEOUT: float = 300.0;

"""The notch reconnects with exponential backoff capped at 30s, so a push that
opens this socket may find nobody listening for up to that long even though the
app is running. An escalation waits this out before giving up on the surface."""
glob ATTACH_GRACE: float = 35.0;

"""Nothing on this wire is large - the biggest message is an escalation with two
sides of intent in it. A frame beyond this is a bug or a probe; either way the
connection is dropped rather than allocated for."""
glob MAX_FRAME_BYTES: int = 1048576;


obj NotchConfig {
    has host: str = DEFAULT_HOST;
    has port: int = DEFAULT_PORT;
    has dev_id: str = "";
    has token: str = "";
}


# ---------------------------------------------------------------- configuration

"""Who this developer is to the notch. The app drops any escalation whose
`dev_id` is not its own, so the two ends have to agree - which is why
`synqit notch` writes one file both of them read rather than each guessing."""
def default_dev_id -> str {
    import subprocess;
    email: str = "";
    try {
        result = subprocess.run(
            ["git", "config", "user.email"],
            capture_output=True, text=True,
        );
        email = (result.stdout as str).strip();
    } except Exception {
        email = "";
    }
    if email {
        return email;
    }
    return os.environ.get("USER") or "dev";
}


"""Read the shared config the macOS app also reads. Returns None when no notch
has ever been attached on this machine, which every caller treats as "no
surface" rather than as an error."""
def read_config -> NotchConfig | None {
    if not os.path.exists(config_path()) {
        return None;
    }
    try {
        handle = open(config_path(), "r");
        raw: str = handle.read();
        handle.close();
        parsed: any = json.loads(raw);
    } except Exception {
        return None;
    }
    if not isinstance(parsed, dict) {
        return None;
    }
    shape: dict = parsed as dict;

    server_url: str = (shape.get("server_url") or "") as str;
    host: str = DEFAULT_HOST;
    port: int = DEFAULT_PORT;
    if server_url {
        try {
            parsed_url = urlparse(server_url);
            host = (parsed_url.hostname or DEFAULT_HOST) as str;
            port = (parsed_url.port or DEFAULT_PORT) as int;
        } except Exception {
            host = DEFAULT_HOST;
        }
    }

    return NotchConfig(
        host=host,
        port=port,
        dev_id=(shape.get("dev_id") or "") as str,
        token=read_token(),
    );
}


def read_token -> str {
    if not os.path.exists(token_path()) {
        return "";
    }
    try {
        handle = open(token_path(), "r");
        token: str = handle.read().strip();
        handle.close();
        return token;
    } except Exception {
        return "";
    }
}


"""Provision this machine's notch: the config the app reads and the token it
authenticates with. Both are rewritten on every `synqit notch` so a re-run is
the repair path, not a duplicate."""
def write_config(dev_id: str, host: str, port: int) -> NotchConfig {
    os.makedirs(synqit_dir(), exist_ok=True);

    server_url: str = "ws://" + host + ":" + str(port);
    payload: str = json.dumps({"server_url": server_url, "dev_id": dev_id}, indent=2) + "\n";

    handle = open(config_path(), "w");
    handle.write(payload);
    handle.close();

    token: str = read_token();
    if not token {
        token = secrets.token_urlsafe(32);
        # Written before the mode is tightened would leave a readable window, so
        # create it closed and widen nothing afterwards.
        descriptor = os.open(token_path(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600);
        os.write(descriptor, token.encode("utf-8"));
        os.close(descriptor);
    }
    os.chmod(token_path(), 0o600);

    return NotchConfig(host=host, port=port, dev_id=dev_id, token=token);
}


# ------------------------------------------------------------------- the app

"""Where the macOS notch is installed, or "" if it is not.

An installed bundle wins over a build tree: if someone has both, the one they
launch from Finder is the one that needs the token."""
def app_binary -> str {
    candidates: list[str] = [
        "/Applications/Synqit Notch.app/Contents/MacOS/SynqitNotch",
        os.path.expanduser("~/Applications/Synqit Notch.app/Contents/MacOS/SynqitNotch"),
        os.path.join(os.getcwd(), "notch/.build/Synqit Notch.app/Contents/MacOS/SynqitNotch"),
        os.path.join(os.getcwd(), "notch/.build/release/SynqitNotch"),
        os.path.join(os.getcwd(), "notch/.build/debug/SynqitNotch"),
    ];
    for candidate in candidates {
        if os.path.exists(candidate) {
            return candidate;
        }
    }
    return "";
}


"""Hand the token to the app, which stores it in the login keychain.

Passed on stdin rather than as an argument: `--login TOKEN` would put a live
credential in the process list and the shell history. Returns "" on success or a
sentence describing what went wrong."""
def install_token(binary: str, token: str) -> str {
    import subprocess;
    try {
        result = subprocess.run(
            [binary, "--login"],
            input=token, capture_output=True, text=True, timeout=20,
        );
    } except Exception as error {
        return "Could not run the notch app to store the token (" + str(error) + ").";
    }
    if result.returncode != 0 {
        detail: str = ((result.stderr as str) or (result.stdout as str)).strip();
        return "The notch app refused the token: " + detail;
    }
    return "";
}


"""Whether the app is running right now. Only used to tell the developer
whether to launch it - never to decide anything about a push."""
def app_running -> bool {
    import subprocess;
    try {
        result = subprocess.run(
            ["pgrep", "-f", "Synqit Notch.app"],
            capture_output=True, text=True,
        );
        return result.returncode == 0;
    } except Exception {
        return False;
    }
}


# ------------------------------------------------------------- WebSocket codec

"""One unmasked frame. Server-to-client frames are never masked (RFC 6455 §5.1),
and every message here fits in a single frame - the notch sends nothing this
code needs to reassemble."""
def encode_frame(payload: bytes, opcode: int) -> bytes {
    header: bytes = bytes([0x80 | opcode]);
    length: int = len(payload);
    if length < 126 {
        header += bytes([length]);
    } elif length < 65536 {
        header += bytes([126]) + length.to_bytes(2, "big");
    } else {
        header += bytes([127]) + length.to_bytes(8, "big");
    }
    return header + payload;
}


"""Exactly `count` bytes, or None if the peer closed first. A short read here is
always end-of-stream: the buffered reader only returns early at EOF."""
def read_exactly(stream: any, count: int) -> bytes | None {
    if count == 0 {
        return b"";
    }
    raw = stream.read(count);
    if not raw {
        return None;
    }
    data: bytes = raw as bytes;
    if len(data) != count {
        return None;
    }
    return data;
}


def unmask(payload: bytes, key: bytes) -> bytes {
    out = bytearray();
    index: int = 0;
    for byte in payload {
        out.append(byte ^ key[index % 4]);
        index += 1;
    }
    return bytes(out);
}


"""One inbound frame as {"opcode", "payload"}, or None when the connection is
finished. Client frames are always masked; an unmasked one is a protocol
violation and closes the connection rather than being interpreted."""
def read_frame(stream: any) -> dict | None {
    header = read_exactly(stream, 2);
    if header is None {
        return None;
    }
    opcode: int = header[0] & 0x0F;
    masked: bool = (header[1] & 0x80) != 0;
    length: int = header[1] & 0x7F;

    if length == 126 {
        extended = read_exactly(stream, 2);
        if extended is None {
            return None;
        }
        length = int.from_bytes(extended, "big");
    } elif length == 127 {
        extended = read_exactly(stream, 8);
        if extended is None {
            return None;
        }
        length = int.from_bytes(extended, "big");
    }

    if length > MAX_FRAME_BYTES or not masked {
        return None;
    }

    mask_key = read_exactly(stream, 4);
    if mask_key is None {
        return None;
    }
    payload = read_exactly(stream, length);
    if payload is None {
        return None;
    }
    return {"opcode": opcode, "payload": unmask(payload as bytes, mask_key as bytes)};
}


def accept_key(key: str) -> str {
    digest = hashlib.sha1((key + WS_GUID).encode("utf-8")).digest();
    return base64.b64encode(digest).decode("ascii");
}


"""Headers of the upgrade request, lowercased. None if the peer hung up mid
request."""
def read_headers(stream: any) -> dict[str, str] | None {
    request_line = stream.readline();
    if not request_line {
        return None;
    }
    headers: dict[str, str] = {};
    while True {
        line = stream.readline();
        if not line or line == b"\r\n" or line == b"\n" {
            break;
        }
        text: str = (line as bytes).decode("latin-1").strip();
        if ":" not in text {
            continue;
        }
        parts: list[str] = text.split(":", 1);
        headers[parts[0].strip().lower()] = parts[1].strip();
    }
    return headers;
}


# ------------------------------------------------------------------ connection

obj NotchConn {
    has sock: any = None;
    has stream: any = None;
    has send_lock: any = None;
    has dev_id: str = "";
    has alive: bool = True;

    """Serialized because the reader thread sends acks while the pushing thread
    broadcasts escalations - two frames interleaved on one socket would corrupt
    both."""
    def send_frame(payload: bytes, opcode: int) -> bool {
        if not self.alive {
            return False;
        }
        frame: bytes = encode_frame(payload, opcode);
        self.send_lock.acquire();
        try {
            self.sock.sendall(frame);
            return True;
        } except Exception {
            self.alive = False;
            return False;
        } finally {
            self.send_lock.release();
        }
    }

    def send(message: dict) -> bool {
        return self.send_frame(json.dumps(message).encode("utf-8"), 0x1);
    }

    def close {
        self.alive = False;
        try {
            self.sock.close();
        } except Exception {
            # Already gone; nothing left to release.
        }
    }
}


# ---------------------------------------------------------------------- bridge

obj NotchBridge {
    has config: NotchConfig;
    has server: any = None;
    has conns: list[NotchConn] = [];
    has state_lock: any = None;
    has running: bool = False;

    """Questions currently awaiting an answer, keyed by conflict id. This is
    what a reconnecting notch is handed on `fetch_pending`, which is how a
    laptop that was asleep catches up instead of missing the escalation."""
    has pending: dict[str, dict] = {};
    has answers: dict[str, dict] = {};
    has signals: dict[str, any] = {};

    """Progress sink, `(phase, detail)`. The CLI passes its own so an escalation
    can interrupt the spinner - a push that silently blocks for five minutes
    looks identical to a hung one."""
    has on_event: any = None;

    """Every decision made through this bridge, in order. The commit that lands
    should be traceable to the answer that shaped it, so the push report says
    what was asked and what the developer said."""
    has decided: list[str] = [];

    def report(phase: str, detail: str) {
        if self.on_event is None {
            return;
        }
        try {
            (self.on_event)(phase, detail);
        } except Exception {
            # Reporting is cosmetic; it must never take a push down with it.
        }
    }

    # -- lifecycle

    """Open the socket. Returns "" on success or a sentence explaining why the
    surface is unavailable - never raises, because a notch that cannot start is
    a degraded push, not a failed one."""
    def start -> str {
        if self.running {
            return "";
        }
        if not self.config.token {
            return "No notch token on this machine. Run `synqit notch` to attach one.";
        }
        self.state_lock = threading.Lock();
        try {
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
            server.bind((self.config.host, self.config.port));
            server.listen(8);
        } except Exception as error {
            return (
                "Could not open the notch socket on " + self.config.host + ":"
                + str(self.config.port) + " (" + str(error) + "). Another push may be running."
            );
        }
        self.server = server;
        self.running = True;
        threading.Thread(target=self.accept_loop, daemon=True).start();
        return "";
    }

    def stop {
        self.running = False;
        if self.server is not None {
            try {
                self.server.close();
            } except Exception {
                # Closing an already-closed listener is not a failure.
            }
            self.server = None;
        }
        for conn in list(self.conns) {
            conn.close();
        }
        self.conns = [];
    }

    def attached -> bool {
        for conn in list(self.conns) {
            if conn.alive {
                return True;
            }
        }
        return False;
    }

    def accept_loop {
        while self.running {
            try {
                pair = self.server.accept();
            } except Exception {
                # stop() closed the listener - the only way out of this loop.
                return;
            }
            threading.Thread(target=self.serve, args=(pair[0],), daemon=True).start();
        }
    }

    # -- one connection

    def serve(sock: any) {
        conn = self.handshake(sock);
        if conn is None {
            return;
        }
        self.state_lock.acquire();
        try {
            self.conns.append(conn);
        } finally {
            self.state_lock.release();
        }
        # Deliberately not reported: this runs on the accept thread, and the CLI
        # is animating a spinner from the main one. Every other report here is
        # raised from the pushing thread, where printing is safe.

        try {
            self.read_loop(conn);
        } except Exception {
            # A malformed peer closes its own connection, not the push.
        }

        conn.close();
        self.state_lock.acquire();
        try {
            self.conns = [c for c in self.conns if c is not conn];
        } finally {
            self.state_lock.release();
        }
    }

    """The upgrade, and the only place a caller is turned away. The notch sends
    the same bearer header it would send to a hosted Synqit, so this is the
    identical check the server does - it just runs on the developer's machine."""
    def handshake(sock: any) -> NotchConn | None {
        try {
            stream = sock.makefile("rb");
            headers = read_headers(stream);
        } except Exception {
            headers = None;
        }
        if headers is None {
            try {
                sock.close();
            } except Exception {
                # Nothing to clean up.
            }
            return None;
        }

        found: dict[str, str] = headers as dict[str, str];
        key: str = found.get("sec-websocket-key", "") as str;
        if not key {
            self.refuse(sock, "400 Bad Request");
            return None;
        }

        authorization: str = found.get("authorization", "") as str;
        presented: str = "";
        if authorization.lower().startswith("bearer ") {
            presented = authorization[7:].strip();
        }
        # Constant-time: this is a shared secret, and a timing oracle on a local
        # socket is still a timing oracle.
        if not hmac.compare_digest(presented, self.config.token) {
            self.refuse(sock, "401 Unauthorized");
            return None;
        }

        response: str = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: " + accept_key(key) + "\r\n\r\n"
        );
        try {
            sock.sendall(response.encode("latin-1"));
        } except Exception {
            return None;
        }
        return NotchConn(sock=sock, stream=stream, send_lock=threading.Lock());
    }

    def refuse(sock: any, status: str) {
        try {
            sock.sendall(("HTTP/1.1 " + status + "\r\nConnection: close\r\n\r\n").encode("latin-1"));
            sock.close();
        } except Exception {
            # The peer gave up first.
        }
    }

    def read_loop(conn: NotchConn) {
        while conn.alive and self.running {
            frame = read_frame(conn.stream);
            if frame is None {
                return;
            }
            opcode: int = (frame as dict)["opcode"] as int;
            payload: bytes = (frame as dict)["payload"] as bytes;

            if opcode == 0x8 {
                return;
            }
            # The notch's heartbeat, and the ping it uses to confirm the upgrade
            # succeeded before it considers itself connected. Answer promptly.
            if opcode == 0x9 {
                conn.send_frame(payload, 0xA);
                continue;
            }
            if opcode != 0x1 {
                continue;
            }

            try {
                message: any = json.loads(payload.decode("utf-8"));
            } except Exception {
                continue;
            }
            if isinstance(message, dict) {
                self.handle(conn, message as dict);
            }
        }
    }

    """Inbound events are data, never commands - an unrecognised `type` is
    ignored on this end exactly as it is on the notch's."""
    def handle(conn: NotchConn, message: dict) {
        kind: str = (message.get("type") or "") as str;

        if os.environ.get("SYNQIT_NOTCH_DEBUG") {
            print("  <- " + json.dumps(message));
        }

        if kind == "hello" {
            conn.dev_id = (message.get("dev_id") or "") as str;
            return;
        }
        if kind == "fetch_pending" {
            self.state_lock.acquire();
            try {
                items: list[dict] = list(self.pending.values());
            } finally {
                self.state_lock.release();
            }
            conn.send({"type": "pending", "escalations": items});
            return;
        }
        if kind == "resolution" {
            self.resolve(conn, message);
        }
    }

    def resolve(conn: NotchConn, message: dict) {
        conflict_id: str = (message.get("conflict_id") or "") as str;
        dev_id: str = (message.get("dev_id") or "") as str;

        if dev_id and dev_id != self.config.dev_id {
            conn.send({
                "type": "ack", "conflict_id": conflict_id, "status": "rejected",
                "message": "That conflict belongs to another developer.",
            });
            return;
        }

        self.state_lock.acquire();
        try {
            known: bool = conflict_id in self.pending;
            if known {
                self.answers[conflict_id] = {
                    "choice": (message.get("choice") or "") as str,
                    "custom_text": message.get("custom_text"),
                };
                signal = self.signals.get(conflict_id);
            }
        } finally {
            self.state_lock.release();
        }

        if not known {
            # Already answered, expired, or from a previous push. Saying so is
            # better than a silent drop: the notch leaves its submitting state.
            conn.send({
                "type": "ack", "conflict_id": conflict_id, "status": "rejected",
                "message": "That conflict is no longer awaiting a decision.",
            });
            return;
        }

        conn.send({"type": "ack", "conflict_id": conflict_id, "status": "applied"});
        if signal is not None {
            signal.set();
        }
    }

    def broadcast(message: dict) -> int {
        delivered: int = 0;
        for conn in list(self.conns) {
            if conn.alive and conn.send(message) {
                delivered += 1;
            }
        }
        return delivered;
    }

    # -- the seam itself

    """Put a question on the notch and block until it is answered.

    Returns the resolution, or None when nobody answered - the caller turns that
    into `needs_human`, which is the same outcome as having no notch at all.
    """
    def ask(escalation: dict, timeout: float) -> dict | None {
        conflict_id: str = escalation["conflict_id"] as str;
        signal = threading.Event();

        self.state_lock.acquire();
        try {
            self.pending[conflict_id] = escalation;
            self.signals[conflict_id] = signal;
        } finally {
            self.state_lock.release();
        }

        # The app may still be in reconnect backoff when the push opens this
        # socket. Registering the question first means a notch that attaches
        # during the wait picks it up from `fetch_pending` regardless of whether
        # it was connected for the broadcast below.
        waited: float = 0.0;
        while not self.attached() and waited < ATTACH_GRACE {
            time.sleep(0.25);
            waited += 0.25;
        }

        self.broadcast(escalation);

        answered: bool = signal.wait(timeout=timeout);

        self.state_lock.acquire();
        try {
            self.pending.pop(conflict_id, None);
            self.signals.pop(conflict_id, None);
            resolution: dict | None = self.answers.pop(conflict_id, None);
        } finally {
            self.state_lock.release();
        }

        if not answered or resolution is None {
            # Don't leave a dead question sitting on someone's screen after the
            # push that asked it has moved on.
            self.broadcast({"type": "withdraw", "conflict_id": conflict_id, "reason": "expired"});
            return None;
        }
        return resolution;
    }
}


# --------------------------------------------------------------- module handle

"""The bridge for the push currently running, or None.

Module-level rather than a field on the integration Workspace on purpose: that
object is handed to byLLM, which serializes its fields into the prompt. A live
socket has no business being described to a model, and the workspace's contents
are the only state the model should see.
"""
glob ACTIVE: NotchBridge | None = None;


"""The result of trying to open the surface. `note` is a sentence for the
developer explaining why they will not be asked - information rather than an
error, since the push proceeds either way. It is deliberately empty when no
notch has ever been attached: that is a choice, not a fault."""
obj Attachment {
    has bridge: NotchBridge | None = None;
    has note: str = "";
}


def attach(on_event: any = None) -> Attachment {
    global ACTIVE;

    config = read_config();
    if config is None {
        return Attachment();
    }
    if not config.dev_id {
        return Attachment(note="~/.synqit/config.json has no dev_id. Run `synqit notch` to repair it.");
    }

    bridge = NotchBridge(config=config, on_event=on_event);
    problem: str = bridge.start();
    if problem {
        return Attachment(note=problem);
    }
    ACTIVE = bridge;
    return Attachment(bridge=bridge);
}


def detach {
    global ACTIVE;
    if ACTIVE is not None {
        ACTIVE.stop();
    }
    ACTIVE = None;
}


def is_attached -> bool {
    if ACTIVE is None {
        return False;
    }
    return ACTIVE.attached();
}


"""Context the escalation carries about the developer's side. Set once per push
attempt so the notch can show both intents side by side - without the other
side's intent it is a coin flip rather than a decision."""
obj PushContext {
    has intent: str = "";
    has base_sha: str = "";
    has change_count: int = 0;
    has submitter: str = "";
}

glob CONTEXT: PushContext = PushContext();


def set_context(intent: str, base_sha: str, change_count: int, submitter: str) {
    global CONTEXT;
    CONTEXT = PushContext(
        intent=intent, base_sha=base_sha,
        change_count=change_count, submitter=submitter,
    );
}


def expiry_stamp(seconds: float) -> str {
    moment = datetime.now(timezone.utc) + timedelta(seconds=seconds);
    # Exactly the shape the notch's decoder expects: ISO-8601, UTC, no
    # fractional seconds.
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ");
}


"""Build the escalation payload. Split out so a test can assert the wire shape
without opening a socket."""
def build_escalation(
    conflict_id: str,
    dev_id: str,
    title: str,
    summary: str,
    file: str,
    conflicts_with: str,
    option_mine: str,
    option_theirs: str,
    timeout: float,
) -> dict {
    proposal: str = "intent only";
    if CONTEXT.change_count > 0 {
        proposal = str(CONTEXT.change_count) + " file(s) changed";
    }
    if CONTEXT.base_sha {
        proposal += " from " + CONTEXT.base_sha[:7];
    }

    return {
        "type": "escalation",
        "conflict_id": conflict_id,
        "dev_id": dev_id,
        "title": title,
        "summary": summary,
        "file": file,
        "colliding_edge": file + " already carries a decision your intent reverses",
        "your_change": {
            "dev_id": CONTEXT.submitter or dev_id,
            "intent": CONTEXT.intent,
            "diff_summary": proposal,
        },
        "their_change": {
            "intent": conflicts_with,
            "diff_summary": "already true on the shared branch",
        },
        # The notch renders whatever it is given and falls back to this exact
        # triple when options are omitted; sending them explicitly is what lets
        # the model label the two sides in the developer's own vocabulary.
        "options": [
            {"id": "green", "label": option_mine, "detail": "Integrate your intent and change what the branch does today."},
            {"id": "red", "label": option_theirs, "detail": "Leave the branch as it is and drop the conflicting part of your intent."},
            {"id": "other", "label": "Instruct", "detail": "Describe how these should merge.", "input": True},
        ],
        "expires_at": expiry_stamp(timeout),
    };
}


"""Ask the developer who pushed, and return the answer as text for the agent's
tool loop.

This is the whole feature: the return value becomes the result of the model's
own tool call, so an escalation is a *suspend*, not an exit. The agent asks, the
notch lights up, the developer clicks, and the same integration carries on with
the answer in hand.

Every path returns a sentence rather than raising, because the caller is a
language model mid-loop: it needs to be told what happened in terms it can act
on, including when the answer is "nobody is there".
"""
def ask_developer(
    title: str,
    summary: str,
    file: str,
    conflicts_with: str,
    option_mine: str,
    option_theirs: str,
) -> str {
    unavailable: str = (
        "No decision surface answered, so this cannot be resolved by asking. "
        + "Stop integrating and return status 'needs_human' with the conflict as the reason."
    );

    if ACTIVE is None {
        return (
            "No notch is attached to this machine (run `synqit notch` to attach one). "
            + unavailable
        );
    }
    bridge: NotchBridge = ACTIVE;

    timeout: float = DECISION_TIMEOUT;
    override: str = (os.environ.get("SYNQIT_DECISION_TIMEOUT") or "").strip();
    if override {
        try {
            timeout = float(override);
        } except ValueError {
            timeout = DECISION_TIMEOUT;
        }
    }

    conflict_id: str = "c_" + secrets.token_hex(4);
    escalation: dict = build_escalation(
        conflict_id, bridge.config.dev_id, title, summary, file,
        conflicts_with, option_mine, option_theirs, timeout,
    );

    bridge.report("escalation", title);
    resolution = bridge.ask(escalation, timeout);

    if resolution is None {
        bridge.report("unanswered", "no decision came back - ending the push instead of guessing");
        return "The escalation went unanswered and has expired. " + unavailable;
    }

    choice: str = ((resolution as dict).get("choice") or "") as str;
    custom: str = (((resolution as dict).get("custom_text") or "") as str).strip();

    if choice == "green" {
        bridge.report("decided", option_mine);
        bridge.decided.append(title + " -> " + option_mine);
        return (
            "The developer chose: " + option_mine + ". Integrate their intent accordingly "
            + "and change what the branch currently does. Continue with the integration - "
            + "this decision is made, do not ask again."
        );
    }
    if choice == "red" {
        bridge.report("decided", option_theirs);
        bridge.decided.append(title + " -> " + option_theirs);
        return (
            "The developer chose: " + option_theirs + ". Leave what the branch already does "
            + "intact and drop the conflicting part of their intent, integrating whatever "
            + "remains. Continue with the integration - this decision is made, do not ask again."
        );
    }
    if custom {
        bridge.report("decided", "instruction: " + custom);
        bridge.decided.append(title + " -> " + custom);
        return (
            "The developer answered with an instruction: \"" + custom + "\". Follow it exactly "
            + "and continue with the integration - this decision is made, do not ask again."
        );
    }

    bridge.report("unanswered", "the decision came back empty");
    return "The decision came back empty. " + unavailable;
}


"""What the developer decided during the push that is running, for the report
the CLI prints at the end."""
def decisions -> list[str] {
    if ACTIVE is None {
        return [];
    }
    return list(ACTIVE.decided);
}
