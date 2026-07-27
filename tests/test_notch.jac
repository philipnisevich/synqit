"""The escalation seam, exercised over a real loopback socket.

`FakeNotch` below is a WebSocket client written against the same contract the
macOS app implements: masked client frames, a bearer token on the upgrade, a
ping to confirm the handshake, then `hello` / `fetch_pending` and a `resolution`
in reply to an `escalation`. If these pass and the real notch still fails, the
bug is in the app - which is the point of testing this end separately.

Nothing here needs an API key: the escalation surface is transport and state,
and the model that decides *whether* to ask is not part of it.
"""

import base64;
import json;
import os;
import secrets;
import socket;
import tempfile;
import threading;

import from integrations.notch {
    NotchBridge, attach, build_escalation, detach, set_context, ask_developer,
    read_config, write_config, ACTIVE,
}


# ------------------------------------------------------------------ the client

obj FakeNotch {
    has host: str = "127.0.0.1";
    has port: int = 0;
    has token: str = "";
    has dev_id: str = "dev_test";
    has sock: any = None;
    has stream: any = None;
    has status: int = 0;

    """The upgrade request the app sends, header for header."""
    def connect(timeout: float = 5.0) -> bool {
        self.sock = socket.create_connection((self.host, self.port), timeout=timeout);
        key: str = base64.b64encode(secrets.token_bytes(16)).decode("ascii");
        request: str = (
            "GET / HTTP/1.1\r\n"
            + "Host: " + self.host + ":" + str(self.port) + "\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Key: " + key + "\r\n"
            + "Sec-WebSocket-Version: 13\r\n"
            + "Authorization: Bearer " + self.token + "\r\n"
            + "X-Synqit-Dev-Id: " + self.dev_id + "\r\n\r\n"
        );
        self.sock.sendall(request.encode("latin-1"));
        self.stream = self.sock.makefile("rb");

        status_line: str = (self.stream.readline() as bytes).decode("latin-1");
        parts: list[str] = status_line.split(" ");
        if len(parts) > 1 {
            self.status = int(parts[1]);
        }
        while True {
            line = self.stream.readline();
            if not line or line == b"\r\n" or line == b"\n" {
                break;
            }
        }
        return self.status == 101;
    }

    """Client frames are always masked (RFC 6455 §5.3) - the server drops any
    that are not, so this is not an optional nicety."""
    def send_frame(payload: bytes, opcode: int) {
        mask: bytes = secrets.token_bytes(4);
        masked = bytearray();
        index: int = 0;
        for byte in payload {
            masked.append(byte ^ mask[index % 4]);
            index += 1;
        }
        header: bytes = bytes([0x80 | opcode]);
        length: int = len(payload);
        if length < 126 {
            header += bytes([0x80 | length]);
        } else {
            header += bytes([0x80 | 126]) + length.to_bytes(2, "big");
        }
        self.sock.sendall(header + bytes(mask) + bytes(masked));
    }

    def send(message: dict) {
        self.send_frame(json.dumps(message).encode("utf-8"), 0x1);
    }

    def ping {
        self.send_frame(b"synqit", 0x9);
    }

    def take(count: int) -> bytes | None {
        raw = self.stream.read(count);
        if not raw {
            return None;
        }
        data: bytes = raw as bytes;
        if len(data) != count {
            return None;
        }
        return data;
    }

    """One inbound frame as {"opcode", "payload"}. Server frames are unmasked."""
    def recv_frame -> dict | None {
        header = self.take(2);
        if header is None {
            return None;
        }
        opcode: int = (header as bytes)[0] & 0x0F;
        length: int = (header as bytes)[1] & 0x7F;
        if length == 126 {
            extended = self.take(2);
            if extended is None {
                return None;
            }
            length = int.from_bytes(extended, "big");
        }
        payload: bytes = b"";
        if length > 0 {
            got = self.take(length);
            if got is None {
                return None;
            }
            payload = got as bytes;
        }
        return {"opcode": opcode, "payload": payload};
    }

    """The next JSON message, skipping the pong that answers our ping."""
    def recv -> dict | None {
        while True {
            frame = self.recv_frame();
            if frame is None {
                return None;
            }
            opcode: int = (frame as dict)["opcode"] as int;
            if opcode != 0x1 {
                continue;
            }
            decoded: any = json.loads(((frame as dict)["payload"] as bytes).decode("utf-8"));
            if isinstance(decoded, dict) {
                return decoded as dict;
            }
        }
    }

    """Everything the app does on connect: prove the upgrade with a ping, then
    announce itself and reconcile against whatever is already open."""
    def handshake -> dict | None {
        self.ping();
        self.send({"type": "hello", "dev_id": self.dev_id, "client": "fake-notch/1.0"});
        self.send({"type": "fetch_pending", "dev_id": self.dev_id});
        return self.recv();
    }

    def close {
        try {
            self.sock.close();
        } except Exception {
            # Already gone.
        }
    }
}


# ------------------------------------------------------------------- harness

"""A scratch ~/.synqit so a test never reads or writes the developer's own
attachment, and a port nothing else is on."""
def isolate -> int {
    os.environ["SYNQIT_HOME"] = tempfile.mkdtemp(prefix="synqit-notch-test-");
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    probe.bind(("127.0.0.1", 0));
    port: int = probe.getsockname()[1] as int;
    probe.close();
    return port;
}


obj Attached {
    has bridge: NotchBridge;
    has token: str;
    has port: int;
}


def open_bridge(dev_id: str) -> Attached {
    port: int = isolate();
    config = write_config(dev_id, "127.0.0.1", port);
    opened = attach();
    assert opened.bridge is not None;
    return Attached(bridge=opened.bridge as NotchBridge, token=config.token, port=port);
}


obj Answerer {
    has port: int;
    has token: str;
    has dev_id: str;
    has choice: str = "green";
    has custom_text: any = None;
    has seen: dict = {};
    has ack: dict = {};
    """Set once this thread is finished. `ask_developer` returns the moment the
    resolution lands, which is before this side has read its ack - so a test
    that asserts on the ack has to wait for the notch, not for the agent."""
    has done: any = None;

    """Play the developer: wait for the question, answer it, keep the ack."""
    def run {
        notch = FakeNotch(port=self.port, token=self.token, dev_id=self.dev_id);
        if not notch.connect() {
            self.done.set();
            return;
        }
        notch.handshake();

        while True {
            message = notch.recv();
            if message is None {
                self.done.set();
                return;
            }
            kind: str = ((message as dict).get("type") or "") as str;
            if kind != "escalation" {
                continue;
            }
            self.seen = message as dict;
            notch.send({
                "type": "resolution",
                "conflict_id": (message as dict)["conflict_id"],
                "dev_id": self.dev_id,
                "choice": self.choice,
                "custom_text": self.custom_text,
            });
            acknowledgement = notch.recv();
            if acknowledgement is not None {
                self.ack = acknowledgement as dict;
            }
            notch.close();
            self.done.set();
            return;
        }
    }
}


def push_context(dev_id: str) {
    set_context(
        "Give free-tier users unlimited projects",
        "f50e1f3ab00",
        1,
        dev_id,
    );
}


def question(bridge: NotchBridge) -> str {
    return ask_developer(
        title="Free tier removal vs. unlimited free projects",
        summary="Your change gives free-tier users unlimited projects, but the free tier was removed on main.",
        file="pricing.js",
        conflicts_with="The free tier was deliberately removed",
        option_mine="Keep unlimited free projects",
        option_theirs="Keep the free tier removed",
    );
}


# --------------------------------------------------------------------- tests

test "the upgrade is refused without the right bearer token" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;

    notch = FakeNotch(port=bridge.config.port, token="not-the-token", dev_id="dev_test");
    upgraded: bool = notch.connect();

    assert not upgraded;
    assert notch.status == 401;
    assert not bridge.attached();

    notch.close();
    detach();
}


test "a real token upgrades, and the ping that proves it is answered" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;

    notch = FakeNotch(port=bridge.config.port, token=attached.token, dev_id="dev_test");
    assert notch.connect();
    assert notch.status == 101;

    notch.ping();
    frame = notch.recv_frame();
    assert frame is not None;
    # Opcode 0xA, echoing our payload: the app treats a completed ping as the
    # signal that it is genuinely connected.
    assert (frame as dict)["opcode"] == 0xA;
    assert (frame as dict)["payload"] == b"synqit";

    notch.close();
    detach();
}


test "an escalation round trip hands the developer's choice back to the agent" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;
    push_context("dev_test");

    answerer = Answerer(port=bridge.config.port, token=attached.token, dev_id="dev_test", choice="green", done=threading.Event());
    threading.Thread(target=answerer.run, daemon=True).start();

    answer: str = question(bridge);
    answerer.done.wait(timeout=10.0);

    # What the notch was shown.
    assert (answerer.seen.get("type") as str) == "escalation";
    assert (answerer.seen.get("dev_id") as str) == "dev_test";
    assert (answerer.seen.get("file") as str) == "pricing.js";
    assert "unlimited projects" in (answerer.seen.get("summary") as str);
    options: list = answerer.seen.get("options") as list;
    assert [(option["id"] as str) for option in options] == ["green", "red", "other"];
    assert (options[0]["label"] as str) == "Keep unlimited free projects";
    # Only the instruct option carries free text.
    assert options[2]["input"] == True;
    assert (answerer.seen.get("your_change") as dict)["intent"] == "Give free-tier users unlimited projects";
    assert (answerer.seen.get("their_change") as dict)["intent"] == "The free tier was deliberately removed";
    assert (answerer.seen.get("expires_at") as str).endswith("Z");

    # What the agent was told.
    assert "Keep unlimited free projects" in answer;
    assert "needs_human" not in answer;

    # The ack is what lets the notch leave its submitting state.
    assert (answerer.ack.get("type") as str) == "ack";
    assert (answerer.ack.get("status") as str) == "applied";

    detach();
}


test "choosing the other side is relayed as that side, not as the developer's" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;
    push_context("dev_test");

    answerer = Answerer(port=bridge.config.port, token=attached.token, dev_id="dev_test", choice="red", done=threading.Event());
    threading.Thread(target=answerer.run, daemon=True).start();

    answer: str = question(bridge);

    assert "Keep the free tier removed" in answer;
    assert "Keep unlimited free projects" not in answer;
    assert "needs_human" not in answer;

    detach();
}


test "an instruction comes back to the agent in the developer's own words" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;
    push_context("dev_test");

    answerer = Answerer(
        port=bridge.config.port, token=attached.token, dev_id="dev_test",
        choice="other", custom_text="Keep the tier removed but grandfather existing free projects.",
        done=threading.Event(),
    );
    threading.Thread(target=answerer.run, daemon=True).start();

    answer: str = question(bridge);

    assert "grandfather existing free projects" in answer;
    assert "needs_human" not in answer;

    detach();
}


test "a notch that attaches late is handed the question it missed" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;
    push_context("dev_test");

    # Nobody is connected when this is registered, so the escalation is never
    # broadcast to this client - it can only arrive via pending-sync.
    holder = Holder(bridge=bridge, done=threading.Event());
    threading.Thread(target=holder.run, daemon=True).start();

    while not holder.asking {
        # Wait for the question to be open before connecting.
        continue;
    }

    notch = FakeNotch(port=bridge.config.port, token=attached.token, dev_id="dev_test");
    assert notch.connect();
    caught = notch.handshake();

    assert caught is not None;
    assert ((caught as dict).get("type") as str) == "pending";
    waiting: list = (caught as dict).get("escalations") as list;
    assert len(waiting) == 1;
    assert (waiting[0]["title"] as str) == "Free tier removal vs. unlimited free projects";

    notch.send({
        "type": "resolution",
        "conflict_id": waiting[0]["conflict_id"],
        "dev_id": "dev_test",
        "choice": "green",
        "custom_text": None,
    });
    notch.recv();
    notch.close();

    holder.done.wait(timeout=10.0);
    assert "Keep unlimited free projects" in holder.answer;

    detach();
}


test "an unanswered escalation expires and asks for a human instead" {
    attached = open_bridge("dev_test");
    bridge = attached.bridge;
    push_context("dev_test");
    # The five-minute production timeout is the same code path; this only makes
    # the test finish.
    os.environ["SYNQIT_DECISION_TIMEOUT"] = "2";

    notch = FakeNotch(port=bridge.config.port, token=attached.token, dev_id="dev_test");
    assert notch.connect();
    notch.handshake();

    watcher = Watcher(notch=notch, done=threading.Event());
    threading.Thread(target=watcher.run, daemon=True).start();

    answer: str = question(bridge);

    assert "needs_human" in answer;
    assert "expired" in answer;

    # The question must not be left sitting on the developer's screen after the
    # push that asked it has given up.
    watcher.done.wait(timeout=5.0);
    assert (watcher.withdrawal.get("type") as str) == "withdraw";
    assert (watcher.withdrawal.get("reason") as str) == "expired";

    os.environ.pop("SYNQIT_DECISION_TIMEOUT", None);
    notch.close();
    detach();
}


test "with no notch attached the agent is told to stop rather than guess" {
    os.environ["SYNQIT_HOME"] = tempfile.mkdtemp(prefix="synqit-notch-none-");
    detach();

    # No config, so nothing to attach to - exactly a machine that never ran
    # `synqit notch`.
    opened = attach();
    assert opened.bridge is None;

    answer: str = ask_developer(
        title="t", summary="s", file="f.js", conflicts_with="c",
        option_mine="mine", option_theirs="theirs",
    );

    assert "needs_human" in answer;
    assert "synqit notch" in answer;
}


test "the escalation payload matches the notch's wire contract" {
    set_context("Add avatars", "abc1234def", 2, "dev_ben");

    payload: dict = build_escalation(
        "c_b4d22156", "dev_ben", "Avatars vs. anonymous profiles",
        "Two intents disagree about identity.", "profile.js",
        "Profiles were made anonymous on purpose",
        "Show avatars", "Stay anonymous", 300.0,
    );

    assert (payload["type"] as str) == "escalation";
    assert (payload["conflict_id"] as str) == "c_b4d22156";
    assert (payload["dev_id"] as str) == "dev_ben";
    # The notch renders the developer's own proposal alongside what the branch
    # already does - without both sides it is a coin flip, not a decision.
    assert (payload["your_change"] as dict)["diff_summary"] == "2 file(s) changed from abc1234";
    assert (payload["their_change"] as dict)["intent"] == "Profiles were made anonymous on purpose";
    assert len(payload["options"] as list) == 3;

    # Decodable by the app: ISO-8601, UTC, no fractional seconds.
    stamp: str = payload["expires_at"] as str;
    assert stamp.endswith("Z");
    assert len(stamp) == 20;
}


"""Runs `ask_developer` off the main thread so a test can drive the notch side
while the question is genuinely open."""
obj Holder {
    has bridge: NotchBridge;
    has answer: str = "";
    has asking: bool = False;
    has done: any = None;

    def run {
        self.asking = True;
        self.answer = question(self.bridge);
        self.done.set();
    }
}


"""Watches for the withdraw that follows an unanswered escalation."""
obj Watcher {
    has notch: FakeNotch;
    has withdrawal: dict = {};
    has done: any = None;

    def run {
        while True {
            message = self.notch.recv();
            if message is None {
                self.done.set();
                return;
            }
            if ((message as dict).get("type") as str) == "withdraw" {
                self.withdrawal = message as dict;
                self.done.set();
                return;
            }
        }
    }
}
