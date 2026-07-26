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
