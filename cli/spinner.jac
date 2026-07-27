"""A live status line for the long part of a push.

The integration blocks for twenty to forty seconds, and a retry doubles it. A
static line makes that look like a hang, so this animates and rotates through
phrases describing what is actually happening.

Two rules keep it from becoming a liability:

1. **TTY only.** When stdout is a pipe, a file, or CI, `start` does nothing.
   Carriage-return animation in captured output produces unreadable logs.
2. **Never fatal.** A spinner that crashes must not take a working push with
   it, so the thread swallows its own errors and `stop` always restores the
   cursor line.
"""

import sys;
import threading;
import time;

glob FRAMES: list[str] = ["|", "/", "-", "\\"];
glob FRAME_SECONDS: float = 0.12;
glob PHRASE_SECONDS: float = 3.2;

obj Spinner {
    has phrases: list[str] = [];
    has stop_event: any = None;
    has worker: any = None;
    has enabled: bool = False;

    def render {
        stream: any = sys.stdout;
        started: float = time.time();
        tick: int = 0;
        try {
            while not self.stop_event.is_set() {
                elapsed: float = time.time() - started;
                phrase: str = self.phrases[
                    int(elapsed / PHRASE_SECONDS) % len(self.phrases)
                ];
                frame: str = FRAMES[tick % len(FRAMES)];
                line: str = "  " + frame + "  " + phrase + "  (" + str(int(elapsed)) + "s)";
                stream.write("\r\x1b[2K" + line);
                stream.flush();
                tick += 1;
                time.sleep(FRAME_SECONDS);
            }
        } except Exception {
            # A cosmetic failure must never surface as a push failure.
            return;
        }
    }

    def start {
        stream: any = sys.stdout;
        if not self.phrases or not stream.isatty() {
            self.enabled = False;
            return;
        }
        self.enabled = True;
        self.stop_event = threading.Event();
        self.worker = threading.Thread(target=self.render, daemon=True);
        self.worker.start();
    }

    """Clear the animated line so whatever the caller prints next starts on a
    clean row. Safe to call whether or not start() ever ran."""
    def stop {
        if not self.enabled {
            return;
        }
        self.stop_event.set();
        if self.worker is not None {
            self.worker.join(timeout=1.0);
        }
        stream: any = sys.stdout;
        stream.write("\r\x1b[2K");
        stream.flush();
        self.enabled = False;
    }
}

"""What Synqit is actually doing while the model works, in the order it tends
to happen. Accurate rather than decorative - each line names a real step of the
integration loop."""
glob INTEGRATION_PHRASES: list[str] = [
    "reading the files around your change",
    "working out what the intent implies",
    "checking who calls what you are changing",
    "writing the change into the workspace",
    "looking for call sites that would break",
    "updating anything that referenced the old shape",
    "verifying nothing was left dangling",
    "still going - larger changes take longer",
];
