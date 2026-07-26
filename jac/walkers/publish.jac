import from nodes { PushRequest, File, Project }
import from integrations.github { publish_changes }

"""Commits an already-integrated push to GitHub main. Reads exactly the paths
integrate touched/deleted (recorded on the PushRequest) - no full-snapshot
diffing needed, integrate already knows what changed. Project.head is the
concurrency check: Synqit is the sole writer to main, so this walker is also
the one that advances Project.head, keeping graph and repo in lockstep.
"""

walker publish {
    has push_id: str;

    can run with Root entry {
        push = jobj(self.push_id);
        if not isinstance(push, PushRequest) {
            report {"error": "push_not_found", "push_id": self.push_id};
            disengage;
        }
        if push.status != "integrated" {
            report {"error": "push_not_integrated", "status": push.status};
            disengage;
        }

        projects: list[Project] = [push <-- [?:Project]];
        if not projects {
            report {"error": "project_not_found_for_push"};
            disengage;
        }
        proj = projects[0];

        parts: list[str] = proj.repository.split("/");
        owner: str = parts[0];
        repo: str = parts[1];

        changes: dict[str, str | None] = {};
        for touched_path in push.touched_paths {
            found = [proj -->[?:File, path == touched_path]];
            if found {
                changes[touched_path] = found[0].content;
            }
        }
        for deleted_path in push.deleted_paths {
            changes[deleted_path] = None;
        }

        new_head: str = publish_changes(owner, repo, proj.branch, proj.head, changes, push.summary);

        proj.head = new_head;
        for touched_path in push.touched_paths {
            found = [proj -->[?:File, path == touched_path]];
            if found {
                found[0].last_synced_sha = new_head;
            }
        }

        push.status = "published";
        report {"status": "published", "head": new_head};
    }
}
