import from nodes { PushRequest, File, Project }
import from integrations.github { publish_changes }

"""Commits an already-integrated push to GitHub main. Reads exactly the paths
integrate touched/deleted (recorded on the PushRequest) - no full-snapshot
diffing needed, integrate already knows what changed. Project.head is the
concurrency check: Synqit is the sole writer to main, so this walker is also
the one that advances Project.head, keeping graph and repo in lockstep.

do_publish is a plain function (not walker-spawn-only) so the `push` walker
can call it directly - same nested-spawn lesson as blast_radius/integrate.
"""

def do_publish(push_id: str) -> dict {
    push = jobj(push_id);
    if not isinstance(push, PushRequest) {
        return {"error": "push_not_found", "push_id": push_id};
    }
    if push.status != "integrated" {
        return {"error": "push_not_integrated", "status": push.status};
    }

    projects: list[Project] = [push <-- [?:Project]];
    if not projects {
        return {"error": "project_not_found_for_push"};
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
    return {"status": "published", "head": new_head};
}

walker publish {
    has push_id: str;

    can run with Root entry {
        report do_publish(self.push_id);
    }
}
