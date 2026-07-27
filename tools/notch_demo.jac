"""Fire one escalation at the notch, without spending a push or an API call.

The equivalent of notchh's mock server: it opens the same loopback socket a real
push opens and asks the same question, so you can see the surface - and prove
the app is attached and answering - without a conflicting intent and a model
call behind it.

    jac run tools/notch_demo.jac

Answer it in the notch (or ignore it and watch it expire). Ctrl-C is safe: the
socket closes with the process.
"""

import os;
import sys;
import time;

import from integrations.notch {
    NotchBridge, attach, detach, is_attached, set_context, ask_developer,
}


def announce(phase: str, detail: str) {
    print("  [" + phase + "] " + detail);
}


with entry {
    opened = attach(announce);
    if opened.bridge is None {
        note: str = opened.note or "No notch is attached on this machine.";
        print("  " + note);
        print("  Run `synqit notch` first, then open the app.");
        sys.exit(1);
    }
    bridge: NotchBridge = opened.bridge as NotchBridge;

    print("  listening on ws://" + bridge.config.host + ":" + str(bridge.config.port));
    print("  waiting for " + bridge.config.dev_id + "'s notch to attach...");

    # The app reconnects with backoff, so give it a moment to notice the socket.
    waited: float = 0.0;
    while not is_attached() and waited < 35.0 {
        time.sleep(0.5);
        waited += 0.5;
    }
    if is_attached() {
        print("  the notch is attached");
    } else {
        print("  nothing attached yet - the question will still be waiting when it connects");
    }

    # The scenario from the notchh README, so what appears here can be compared
    # against it directly.
    set_context(
        "Give free-tier users unlimited projects",
        "f50e1f3aa11",
        1,
        bridge.config.dev_id,
    );

    answer: str = ask_developer(
        title="Free tier removal vs. unlimited free projects",
        summary="Your change gives free-tier users unlimited projects, but the free tier was deliberately removed on main.",
        file="pricing.js",
        conflicts_with="Remove the free tier entirely",
        option_mine="Keep mine",
        option_theirs="Keep theirs",
    );

    print("");
    print("  the agent was told:");
    print("    " + answer);

    detach();
}
