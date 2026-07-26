import from nodes { Project }

"""Creates a project on the shared commons graph (root.shared), open
(ConnectPerm) so any authenticated dev can attach pushes/files under it.
Real membership enforcement (who may push to THIS project) is still owed -
this only proves the shared-graph creation path.

do_create_project is a plain function (not walker-spawn-only) so the web
service layer can call it directly without the nested-spawn report bug -
same lesson as blast_radius/compute_blast_radius. The parameter is named
`wanted` rather than `name` on purpose: inside a filter comprehension the
bare `name` binds to the node's own attribute, so a same-named parameter
would silently compare the field against itself.
"""
def do_create_project(wanted: str, repository: str, branch: str) -> dict {
    import from datetime { datetime, timezone }
    grant(root.shared, level=WritePerm);
    existing = [root.shared -->[?:Project, name == wanted]];
    if existing {
        return {"project": wanted, "status": "already_exists", "id": jid(existing[0])};
    }
    proj = (root.shared ++> Project(
        name=wanted,
        repository=repository,
        branch=branch,
        created_at=datetime.now(timezone.utc).isoformat(),
    ))[0];
    grant(proj, level=ConnectPerm);
    return {"project": wanted, "status": "created", "id": jid(proj)};
}

"""Authenticated."""
walker create_project {
    has name: str;
    has repository: str;
    has branch: str = "main";

    can run with Root entry {
        report do_create_project(self.name, self.repository, self.branch);
    }
}

"""Read-only: current known head sha for a project - what `status`/`repair`
compare a developer's local base_sha against."""
def do_get_project(wanted: str) -> dict {
    existing = [root.shared -->[?:Project, name == wanted]];
    if not existing {
        return {"error": "project_not_found", "project": wanted};
    }
    proj = existing[0];
    return {
        "id": jid(proj),
        "project": proj.name,
        "repository": proj.repository,
        "branch": proj.branch,
        "head": proj.head,
        "created_at": proj.created_at,
    };
}

"""Authenticated."""
walker get_project {
    has name: str;

    can run with Root entry {
        report do_get_project(self.name);
    }
}
