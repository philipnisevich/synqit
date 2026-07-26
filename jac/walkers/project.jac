import from nodes { Project }

"""Authenticated. Creates a project on the shared commons graph (root.shared),
open (ConnectPerm) so any authenticated dev can attach pushes/files under it.
Real membership enforcement (who may push to THIS project) is still owed -
this only proves the shared-graph creation path.
"""
walker create_project {
    has name: str;
    has repository: str;
    has branch: str = "main";

    can run with Root entry {
        grant(root.shared, level=WritePerm);
        existing = [root.shared -->[?:Project, name == self.name]];
        if existing {
            report {"project": self.name, "status": "already_exists"};
            disengage;
        }
        proj = (root.shared ++> Project(
            name=self.name,
            repository=self.repository,
            branch=self.branch,
        ))[0];
        grant(proj, level=ConnectPerm);
        report {"project": self.name, "status": "created", "id": jid(proj)};
    }
}

"""Authenticated. Read-only: current known head sha for a project - what
`status`/`repair` compare a developer's local base_sha against."""
walker get_project {
    has name: str;

    can run with Root entry {
        existing = [root.shared -->[?:Project, name == self.name]];
        if not existing {
            report {"error": "project_not_found", "project": self.name};
            disengage;
        }
        proj = existing[0];
        report {
            "project": proj.name,
            "repository": proj.repository,
            "branch": proj.branch,
            "head": proj.head,
        };
    }
}
