"""Pin down where the Anthropic key actually came from, before anything can lie.

This module exists because of a genuinely surprising behaviour: constructing
byLLM's `Model` runs `.env` discovery and writes ANTHROPIC_API_KEY into
os.environ. Since `walkers/integrate.jac` builds its Model at module scope,
merely *importing* the integration makes the key appear - so any check written
after that import always passes, including on a machine where the developer
never set one.

That is not just a broken check. It means a run can silently bill a key found
in some unrelated .env up the directory tree, with no indication which key was
used.

The fix is ordering. Jac executes imports and `with entry` blocks in source
order, so a module imported *before* the integration observes the environment
as the developer actually left it. `synqit.jac` imports this first, deliberately.
Nothing here may import byllm, directly or transitively.
"""

import os;

# Captured at import time: the key the developer really had in their shell.
glob SHELL_KEY: str = (os.environ.get("ANTHROPIC_API_KEY") or "") as str;

# Set by the entry block below, once, for the repo being managed.
glob REPO_ENV_PATH: str = "";

"""Load a .env from the repository Synqit is being run against.

Deliberately explicit rather than relying on byLLM's implicit discovery: a
developer can reason about "the .env in the repo I am standing in", but not
about whichever file a library happened to walk up and find. Existing
environment variables always win - an explicit export should never be
overridden by a file.
"""
def load_repo_dotenv(path: str) -> bool {
    if not os.path.exists(path) {
        return False;
    }
    loaded_any: bool = False;
    try {
        handle = open(path, "r", encoding="utf-8");
        lines: list[str] = handle.readlines();
        handle.close();
    } except (OSError, UnicodeDecodeError) {
        return False;
    }

    for line in lines {
        stripped: str = line.strip();
        if not stripped or stripped.startswith("#") or "=" not in stripped {
            continue;
        }
        parts: list[str] = stripped.split("=", 1);
        key: str = parts[0].strip();
        value: str = parts[1].strip().strip('"').strip("'");
        if key and key not in os.environ {
            os.environ[key] = value;
            loaded_any = True;
        }
    }
    return loaded_any;
}

with entry {
    candidate: str = os.path.join(os.getcwd(), ".env");
    if load_repo_dotenv(candidate) {
        REPO_ENV_PATH = candidate;
    }
}

"""Where the key in play came from, decided from state captured before byLLM
could touch it.

  environment    - the developer exported it
  repo-dotenv    - a .env in the repository being managed
  external       - byLLM discovered one somewhere we did not choose
  none           - there is no key at all
"""
def key_source -> str {
    current: str = (os.environ.get("ANTHROPIC_API_KEY") or "") as str;
    if not current {
        return "none";
    }
    if SHELL_KEY {
        return "environment";
    }
    if REPO_ENV_PATH {
        return "repo-dotenv";
    }
    return "external";
}

"""True when a key exists that this module can account for. An 'external' key
works, but the caller should say so out loud rather than use it silently."""
def has_accountable_key -> bool {
    return key_source() in ["environment", "repo-dotenv"];
}
