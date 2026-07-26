import from nodes { Project, File, PushRequest, Touches }

"""Attaches to the shared project graph under root.shared, not the caller's
own isolated root - Synqit's graph is one shared space per project, not
per-user. do_ingest_push is a plain function (not walker-spawn-only) so the
`push` walker can call it directly without the nested-spawn report bug.
"""

def do_ingest_push(project: str, intent: str, base_sha: str, changes: list[dict], submitter: str) -> dict {
    projects = [root.shared -->[?:Project, name == project]];
    if not projects {
        return {"error": "project_not_found", "project": project};
    }
    proj = projects[0];

    push = (proj ++> PushRequest(
        intent=intent,
        base_sha=base_sha,
        changes=changes,
        submitter=submitter,
    ))[0];

    touched: list[str] = [];
    for change in changes {
        target_path: str = change["path"] as str;
        existing = [proj -->[?:File, path == target_path]];
        if existing {
            file_node = existing[0];
        } else {
            file_node = (proj ++> File(path=target_path))[0];
        }
        change_type: str = change.get("change_type", "modified") as str;
        push +>:Touches(change_type=change_type):+> file_node;
        touched.append(target_path);
    }

    return {
        "push_id": jid(push),
        "project": project,
        "status": push.status,
        "touched": touched,
    };
}

"""Authenticated (plain walker, JWT required)."""
walker ingest_push {
    has project: str;
    has intent: str;
    has base_sha: str;
    has changes: list[dict] = [];
    has submitter: str = "";

    can run with Root entry {
        report do_ingest_push(self.project, self.intent, self.base_sha, self.changes, self.submitter);
    }
}
