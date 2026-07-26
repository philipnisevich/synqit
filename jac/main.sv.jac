"""Synqit integration service entry point."""

import os;
import sys;

"""Auto-load .env from this file's directory (normally jac/, wherever `jac
start` is run from) so the server doesn't depend on manually `source .env`-
ing first. Runs before any walker imports below - integrate.jac constructs
its byLLM Model at import time, which needs ANTHROPIC_API_KEY already in
the environment by then."""
def load_dotenv_file(path: str) {
    if not os.path.exists(path) {
        return;
    }
    handle = open(path, "r");
    for line in handle {
        stripped: str = line.strip();
        if not stripped or stripped.startswith("#") or "=" not in stripped {
            continue;
        }
        parts: list[str] = stripped.split("=", 1);
        key: str = parts[0].strip();
        value: str = parts[1].strip();
        if key not in os.environ {
            os.environ[key] = value;
        }
    }
    handle.close();
}

glob REQUIRED_ENV: list[str] = ["GITHUB_TOKEN", "ANTHROPIC_API_KEY"];

with entry {
    load_dotenv_file(os.path.join(os.getcwd(), ".env"));

    missing: list[str] = [key for key in REQUIRED_ENV if not os.environ.get(key)];
    if missing {
        stderr_stream: any = sys.stderr;
        stderr_stream.write("FATAL: missing required environment variable(s): " + ", ".join(missing) + "\n");
        stderr_stream.write("Run `synqit configure` from this directory (jac/) to set them up, or set them in the environment before starting.\n");
        sys.exit(1);
    }
}

import from nodes { Project, File, PushRequest, Touches }
import from walkers.ingest_push { ingest_push }
import from walkers.project { create_project, get_project }
import from walkers.seed_project { seed_project }
import from walkers.blast_radius { blast_radius }
import from walkers.integrate { integrate }
import from walkers.publish { publish }
import from walkers.push { push }
