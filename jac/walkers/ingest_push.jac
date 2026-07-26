import from nodes { Project, File, PushRequest, Touches }

"""Authenticated (plain walker, JWT required). Attaches to the shared project
graph under root.shared, not the caller's own isolated root - Synqit's graph is
one shared space per project, not per-user.
"""
walker ingest_push {
    has project: str;
    has intent: str;
    has base_sha: str;
    has changes: list[dict] = [];
    has submitter: str = "";

    can run with Root entry {
        projects = [root.shared -->[?:Project, name == self.project]];
        if not projects {
            report {"error": "project_not_found", "project": self.project};
            disengage;
        }
        proj = projects[0];

        push = (proj ++> PushRequest(
            intent=self.intent,
            base_sha=self.base_sha,
            changes=self.changes,
            submitter=self.submitter,
        ))[0];

        touched: list[str] = [];
        for change in self.changes {
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

        report {
            "push_id": jid(push),
            "project": self.project,
            "status": push.status,
            "touched": touched,
        };
    }
}
