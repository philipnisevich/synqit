"""Diagnostic: send an escalation with unusual option ids and print the raw
resolution that comes back. Distinguishes "the app clicked its first button"
from "the app answered with something it invented".

    jac run tools/notch_probe.jac
"""

import sys;
import time;

import from integrations.notch {
    NotchBridge, attach, detach, is_attached, expiry_stamp,
}

with entry {
    opened = attach();
    if opened.bridge is None {
        print("  no notch attached: " + (opened.note or "no config"));
        sys.exit(1);
    }
    bridge: NotchBridge = opened.bridge as NotchBridge;

    waited: float = 0.0;
    while not is_attached() and waited < 30.0 {
        time.sleep(0.5);
        waited += 0.5;
    }
    print("  attached: " + str(is_attached()));

    escalation: dict = {
        "type": "escalation",
        "conflict_id": "c_probe_0001",
        "dev_id": bridge.config.dev_id,
        "title": "PROBE: which button fired?",
        "summary": "Diagnostic escalation with deliberately unusual option ids.",
        "file": "probe.js",
        "options": [
            {"id": "zeta", "label": "Zeta first"},
            {"id": "omega", "label": "Omega second"},
        ],
        "expires_at": expiry_stamp(20.0),
    };

    answer = bridge.ask(escalation, 20.0);
    print("  raw resolution: " + str(answer));
    detach();
}
