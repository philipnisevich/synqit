"""Synqit web service layer - the RPC functions the browser client
(components/*.cl.jac) calls via `sv import`. Wraps the SAME graph and the
SAME do_* functions the CLI's walkers use (nodes.jac + walkers/*.jac) - no
separate schema here, so a project or push created from the CLI shows up in
the web UI and vice versa. This file owns view-model shaping
(ProjectView/PushView/ActionResult) and RPC-friendly error handling; all
actual graph mutation and LLM/GitHub work stays in the walkers' do_*
functions - never reimplemented here.
"""

import os;

import from nodes { Project, PushRequest }
import from walkers.project { do_create_project, do_get_project }
import from walkers.ingest_push { do_ingest_push }
import from walkers.seed_project { do_seed_project }
import from walkers.integrate { do_integrate }
import from walkers.publish { do_publish }
import from walkers.push { do_push }
import from walkers.blast_radius { compute_blast_radius, BlastFile }

obj ServerStatus {
    has ready: bool;
    has missing_label: str;
}

obj ProjectView {
    has id: str;
    has name: str;
    has repository: str;
    has branch: str;
    has created_at: str;
    has head: str;
}

obj PushView {
    has id: str;
    has intent: str;
    has submitter: str;
    has base_sha: str;
    has status: str;
    has created_at: str;
    has summary: str;
    has touched_label: str;
    has deleted_label: str;
}

obj ActionResult {
    has ok: bool;
    has message: str;
    has detail: str = "";
}

obj BlastFileView {
    has path: str;
    has distance: int;
}

def project_view(p: Project) -> ProjectView {
    return ProjectView(
        id=jid(p), name=p.name, repository=p.repository, branch=p.branch,
        created_at=p.created_at, head=p.head,
    );
}

def push_view(p: PushRequest) -> PushView {
    return PushView(
        id=jid(p), intent=p.intent, submitter=p.submitter, base_sha=p.base_sha,
        status=p.status, created_at=p.created_at, summary=p.summary,
        touched_label=", ".join(p.touched_paths), deleted_label=", ".join(p.deleted_paths),
    );
}

def:pub server_status() -> ServerStatus {
    required: list[str] = ["GITHUB_TOKEN", "ANTHROPIC_API_KEY"];
    missing: list[str] = [key for key in required if not os.environ.get(key)];
    return ServerStatus(ready=not missing, missing_label=", ".join(missing));
}

def:pub list_projects() -> list[ProjectView] {
    return [project_view(p) for p in [root.shared -->[?:Project]]];
}

def:pub create_project_rpc(project_name: str, repository: str, branch: str) -> ActionResult {
    result: dict = do_create_project(project_name, repository, branch);
    if "error" in result {
        return ActionResult(ok=False, message=result["error"] as str);
    }
    return ActionResult(ok=True, message=result.get("status", "created") as str);
}

def:pub get_project_rpc(project_name: str) -> ProjectView | None {
    result: dict = do_get_project(project_name);
    if "error" in result {
        return None;
    }
    return ProjectView(
        id=result["id"] as str,
        name=result["project"] as str,
        repository=result["repository"] as str,
        branch=result["branch"] as str,
        created_at=result["created_at"] as str,
        head=result["head"] as str,
    );
}

def:pub list_pushes(project_name: str) -> list[PushView] {
    projects = [root.shared -->[?:Project, name == project_name]];
    if not projects {
        return [];
    }
    proj = projects[0];
    return [push_view(p) for p in [proj -->[?:PushRequest]]];
}

"""Web-submitted pushes carry intent + touched paths only, no file content -
there's no local diff to send from a browser form. The LLM does the full
generative work from intent alone, using blast radius for the touched
files' actual current content. A real diff-carrying push (from the CLI)
works the same way, it just gives the LLM a stronger starting hint."""
def:pub submit_push(project_name: str, intent: str, base_sha: str, submitter: str, touched_paths: list[str]) -> ActionResult {
    changes: list[dict] = [{"path": p, "change_type": "modified"} for p in touched_paths];
    result: dict = do_ingest_push(project_name, intent, base_sha, changes, submitter);
    if "error" in result {
        return ActionResult(ok=False, message=result["error"] as str);
    }
    return ActionResult(ok=True, message="Push submitted.", detail=result["push_id"] as str);
}

def:pub seed(project_name: str, owner: str, repo: str, branch: str) -> ActionResult {
    result: dict = do_seed_project(project_name, owner, repo, branch);
    if "error" in result {
        return ActionResult(ok=False, message=result["error"] as str, detail=result.get("message", "") as str);
    }
    return ActionResult(ok=True, message=str(result.get("files", 0)) + " file(s) seeded.");
}

"""Runs integrate -> publish on an already-ingested push (created via
submit_push) - the same chain `synqit push` drives through the push
walker's do_push, minus the ingest step since the push already exists."""
def:pub integrate_push(push_id: str, max_hops: int) -> ActionResult {
    integrated: dict = do_integrate(push_id, max_hops);
    if "error" in integrated {
        return ActionResult(ok=False, message=integrated["error"] as str, detail=integrated.get("message", "") as str);
    }
    status: str = integrated.get("status", "") as str;
    if status == "needs_human" {
        return ActionResult(ok=False, message="Needs a human decision: " + (integrated.get("reason", "") as str));
    }
    if status == "integration_incomplete" {
        return ActionResult(ok=False, message="Integration incomplete: " + (integrated.get("reason", "") as str));
    }
    if status != "integrated" {
        return ActionResult(ok=False, message="Unexpected integration result: " + status);
    }

    published: dict = do_publish(push_id);
    if "error" in published {
        return ActionResult(ok=False, message=published["error"] as str, detail=published.get("message", "") as str);
    }
    return ActionResult(ok=True, message=(integrated.get("summary", "") as str), detail=published["head"] as str);
}

"""Full one-shot chain (ingest -> integrate -> publish), matching the CLI's
`synqit push`. Not wired into the current UI (which uses the two-step
submit_push / integrate_push flow instead so a submitted push is visible
before it runs), kept for API completeness and any future single-action UI."""
def:pub run_push(project_name: str, intent: str, base_sha: str, touched_paths: list[str], submitter: str, max_hops: int) -> ActionResult {
    changes: list[dict] = [{"path": p, "change_type": "modified"} for p in touched_paths];
    result: dict = do_push(project_name, intent, base_sha, changes, submitter, max_hops);
    if "error" in result {
        return ActionResult(ok=False, message=result["error"] as str);
    }
    status: str = result.get("status", "") as str;
    if status == "needs_human" {
        return ActionResult(ok=False, message="Needs a human decision: " + (result.get("reason", "") as str));
    }
    if status == "integration_incomplete" {
        return ActionResult(ok=False, message="Integration incomplete: " + (result.get("reason", "") as str));
    }
    if status != "published" {
        return ActionResult(ok=False, message="Unexpected result: " + status);
    }
    return ActionResult(ok=True, message="Published.", detail=result["head"] as str);
}

"""Read-only context-scoping preview. Paths and hop distance only - never
ships full file content over the RPC channel to the browser."""
def:pub blast_radius_for(push_id: str, max_hops: int) -> list[BlastFileView] {
    files: list[BlastFile] = compute_blast_radius(push_id, max_hops);
    return [BlastFileView(path=f.path, distance=f.distance) for f in files];
}
