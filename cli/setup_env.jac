"""Credential setup for the local CLI.

`synqit configure` verifies a key against the real Anthropic API *before*
writing it anywhere. That ordering is the whole point: a .env holding a typo'd
key fails later, from inside an integration, where the error looks like a
Synqit bug rather than a wrong paste.

The key is written to a .env in the repository being managed, and that path is
added to .git/info/exclude in the same step - writing a secret into someone's
working tree without ensuring git ignores it would be an unforced error.
"""

import os;
import requests;

glob ANTHROPIC_URL: str = "https://api.anthropic.com/v1/messages";
glob VERIFY_MODEL: str = "claude-sonnet-5";

"""Send the smallest possible real request. A 200 or 400 both prove the key is
accepted - only auth failures are disqualifying, and a 400 from a deliberately
minimal body still means we got past authentication."""
def verify_anthropic_key(key: str) -> str {
    try {
        response = requests.post(
            ANTHROPIC_URL,
            headers={
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": VERIFY_MODEL,
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "hi"}],
            },
            timeout=30,
        );
    } except requests.exceptions.RequestException as error {
        return "Could not reach the Anthropic API: " + str(error);
    }

    if response.status_code in [401, 403] {
        return "Anthropic rejected that key (HTTP " + str(response.status_code) + ").";
    }
    if response.status_code == 429 {
        return "";
    }
    if response.status_code >= 500 {
        return "Anthropic returned " + str(response.status_code) + ". Try again shortly.";
    }
    return "";
}

"""Add an entry to .git/info/exclude - per-clone, so we never modify a tracked
.gitignore on the developer's behalf."""
def exclude_from_git(pattern: str) -> bool {
    exclude_path: str = os.path.join(".git", "info", "exclude");
    if not os.path.exists(exclude_path) {
        return False;
    }
    try {
        handle = open(exclude_path, "r", encoding="utf-8");
        current: str = handle.read();
        handle.close();
    } except OSError {
        return False;
    }
    if pattern in current.split("\n") {
        return True;
    }
    try {
        append_handle = open(exclude_path, "a", encoding="utf-8");
        prefix: str = "" if (current == "" or current.endswith("\n")) else "\n";
        append_handle.write(prefix + pattern + "\n");
        append_handle.close();
    } except OSError {
        return False;
    }
    return True;
}

"""Write or replace a single key in a .env, preserving every other line. A
blunt overwrite would silently discard unrelated variables the developer put
there."""
def write_env_value(path: str, key: str, value: str) -> str {
    lines: list[str] = [];
    if os.path.exists(path) {
        try {
            handle = open(path, "r", encoding="utf-8");
            lines = handle.read().split("\n");
            handle.close();
        } except (OSError, UnicodeDecodeError) as error {
            return "Could not read " + path + ": " + str(error);
        }
    }

    updated: list[str] = [];
    replaced: bool = False;
    for line in lines {
        if line.strip().startswith(key + "=") {
            if not replaced {
                updated.append(key + "=" + value);
                replaced = True;
            }
            continue;
        }
        updated.append(line);
    }
    if not replaced {
        while updated and not updated[-1].strip() {
            updated.pop();
        }
        updated.append(key + "=" + value);
    }

    body: str = "\n".join([line for line in updated if line is not None]).strip() + "\n";
    try {
        out = open(path, "w", encoding="utf-8");
        out.write(body);
        out.close();
        os.chmod(path, 0o600);
    } except OSError as error {
        return "Could not write " + path + ": " + str(error);
    }
    return "";
}
