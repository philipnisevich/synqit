"""Synqit service layer - the web UI's view onto the same shared graph the
CLI drives.

Two things happen in this module:

1. **Server bootstrap.** Loads .env and reports which credentials are
   missing. Deliberately does NOT exit on a missing secret: on a hosted
   platform that would take the UI down too, leaving nothing to diagnose the
   misconfiguration with. Each capability that genuinely needs a credential
   refuses individually, with a message naming what to set.

2. **Endpoint registration.** Importing every walker module here is what
   publishes `POST /walker/<name>` for the CLI, alongside the
   `POST /function/<name>` RPC endpoints the `def:pub` functions below give
   the browser client. One server, one graph, two call styles.

The graph schema itself lives in nodes.jac and the real logic lives in
walkers/ - nothing is reimplemented here. These functions are typed views
over the same do_* functions `walker push` calls, so the UI and the CLI can
never drift apart.
"""

import os;
import sys;

import from nodes { Project, File, PushRequest, Touches }
import from walkers.ingest_push { ingest_push, do_ingest_push }
import from walkers.project { create_project, get_project, do_create_project, do_get_project }
import from walkers.seed_project { seed_project, do_seed_project }
import from walkers.blast_radius { blast_radius, compute_blast_radius, BlastFile }
import from walkers.integrate { integrate, do_integrate }
import from walkers.publish { publish, do_publish }
import from walkers.push { push, do_push }

"""Auto-load .env from the working directory so the server doesn't depend on
manually `source .env`-ing first."""
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
glob MISSING_ENV: list[str] = [];

with entry {
    load_dotenv_file(os.path.join(os.getcwd(), ".env"));

    MISSING_ENV = [key for key in REQUIRED_ENV if not os.environ.get(key)];
    if MISSING_ENV {
        stderr_stream: any = sys.stderr;
        stderr_stream.write("WARNING: missing environment variable(s): " + ", ".join(MISSING_ENV) + "\n");
        stderr_stream.write("The UI and the graph work, but integrate/publish/seed will refuse until these are set.\n");
        stderr_stream.write("Run `synqit configure` from this directory, or set them in the hosting platform's environment.\n");
    }
}

"""The *_label fields are pre-joined on purpose. `", ".join(xs)` compiles to
a polymorphic client call that jac-client 0.3.25 has no `join` entry for, so
it throws at render time. Formatting list-to-string here keeps the client on
plain string fields and is the cheaper place to do it anyway."""
obj ServerStatus {
    has ready: bool;
    has missing: list[str];
    has missing_label: str;
}

obj ProjectView {
    has id: str;
    has name: str;
    has repository: str;
    has branch: str;
    has head: str;
    has created_at: str;
}

obj PushView {
    has id: str;
    has intent: str;
    has base_sha: str;
    has submitter: str;
    has status: str;
    has created_at: str;
    has summary: str;
    has touched_paths: list[str];
    has deleted_paths: list[str];
    has touched_label: str;
    has deleted_label: str;
}

obj ActionResult {
    has ok: bool;
    has status: str;
    has message: str;
    has detail: str;
}

def _project_view(proj: Project) -> ProjectView {
    return ProjectView(
        id=jid(proj),
        name=proj.name,
        repository=proj.repository,
        branch=proj.branch,
        head=proj.head,
        created_at=proj.created_at,
    );
}

def _push_view(push: PushRequest) -> PushView {
    return PushView(
        id=jid(push),
        intent=push.intent,
        base_sha=push.base_sha,
        submitter=push.submitter,
        status=push.status,
        created_at=push.created_at,
        summary=push.summary,
        touched_paths=push.touched_paths,
        deleted_paths=push.deleted_paths,
        touched_label=", ".join(push.touched_paths),
        deleted_label=", ".join(push.deleted_paths),
    );
}

"""Turns any do_* return dict into the one shape the client renders. Soft
errors from the walkers ({"error": ...}) and hard exceptions both land here,
so the UI only ever has to check `ok`."""
def _as_result(payload: dict) -> ActionResult {
    if "error" in payload {
        message: str = payload.get("message", payload["error"]) as str;
        return ActionResult(
            ok=False,
            status=payload["error"] as str,
            message=message,
            detail=str(payload.get("reason", "")),
        );
    }
    return ActionResult(
        ok=True,
        status=payload.get("status", "ok") as str,
        message=str(payload.get("summary", "")),
        detail=str(payload.get("head", "")),
    );
}

def:pub server_status() -> ServerStatus {
    return ServerStatus(
        ready=not MISSING_ENV,
        missing=MISSING_ENV,
        missing_label=", ".join(MISSING_ENV),
    );
}

def:pub list_projects() -> list[ProjectView] {
    results: list[ProjectView] = [];
    for p in [root.shared -->[?:Project]] {
        results.append(_project_view(p));
    }
    return results;
}

def:pub create_project_rpc(name: str, repository: str, branch: str) -> ActionResult {
    return _as_result(do_create_project(name, repository, branch));
}

def:pub get_project_rpc(project_name: str) -> ProjectView | None {
    found = [root.shared -->[?:Project, name == project_name]];
    if not found {
        return None;
    }
    return _project_view(found[0]);
}

def:pub list_pushes(project_name: str) -> list[PushView] {
    results: list[PushView] = [];
    projects = [root.shared -->[?:Project, name == project_name]];
    if not projects {
        return results;
    }
    for push in [projects[0] -->[?:PushRequest]] {
        results.append(_push_view(push));
    }
    return results;
}

"""Records a push without integrating it - the graph half of the flow, for
inspecting blast radius before spending an LLM call."""
def:pub submit_push(project_name: str, intent: str, base_sha: str, submitter: str, touched_paths: list[str]) -> ActionResult {
    changes: list[dict] = [{"path": p, "content": "", "change_type": "modified"} for p in touched_paths];
    return _as_result(do_ingest_push(project_name, intent, base_sha, changes, submitter));
}

"""The full product loop, identical to what `synqit push` runs through
`walker push`: ingest -> integrate (LLM) -> publish (GitHub)."""
def:pub run_push(project_name: str, intent: str, base_sha: str, submitter: str, touched_paths: list[str], max_hops: int) -> ActionResult {
    changes: list[dict] = [{"path": p, "content": "", "change_type": "modified"} for p in touched_paths];
    return _as_result(do_push(project_name, intent, base_sha, changes, submitter, max_hops));
}

"""Integrate + publish a push that was already ingested."""
def:pub integrate_push(push_id: str, max_hops: int) -> ActionResult {
    integrated = do_integrate(push_id, max_hops);
    if "error" in integrated or integrated.get("status") != "integrated" {
        return _as_result(integrated);
    }
    return _as_result(do_publish(push_id));
}

"""Populates File nodes and Imports edges from the live GitHub branch. Until
this runs, blast_radius has an empty graph to walk."""
def:pub seed(project_name: str, owner: str, repo: str, branch: str) -> ActionResult {
    return _as_result(do_seed_project(project_name, owner, repo, branch));
}

def:pub blast_radius_for(push_id: str, max_hops: int) -> list[BlastFile] {
    return compute_blast_radius(push_id, max_hops);
}
