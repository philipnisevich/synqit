import from nodes { Project, File, Imports }
import from integrations.github { read_project }

"""Authenticated. One-time (well, idempotent) seed of a Project's graph from
the current state of its GitHub branch: populates File.content for every
tracked file, and a cheap regex import-scan wires Imports edges between them.
This is what gives blast_radius something real to walk - before this runs,
File nodes exist (from pushes) but are empty and disconnected.
"""

glob IMPORT_PATTERN: str = r'''(?:import\s+.*?from\s+|require\()\s*['"](\.[^'"]+)['"]''';

def resolve_import(from_path: str, import_spec: str) -> str {
    import from os.path { normpath, dirname, join }
    resolved: str = normpath(join(dirname(from_path), import_spec));
    return resolved;
}

"""Plain function (not walker-spawn-only) so the web service layer can call it
directly - same lesson as blast_radius/compute_blast_radius."""
def do_seed_project(project: str, owner: str, repo: str, branch: str) -> dict {
    import os;
    if not os.environ.get("GITHUB_TOKEN") {
        return {
            "error": "server_not_configured",
            "missing": "GITHUB_TOKEN",
            "message": "This Synqit server has no GitHub token, so it cannot read the repository. Set GITHUB_TOKEN in the server environment (or run `synqit configure` from the repo root) and restart.",
        };
    }

    projects = [root.shared -->[?:Project, name == project]];
    if not projects {
        return {"error": "project_not_found", "project": project};
    }
    proj = projects[0];

    result = read_project(owner, repo, branch);
    snapshot: dict[str, str] = result["snapshot"] as dict[str, str];
    head: str = result["head"] as str;
    proj.head = head;

    path_to_file: dict[str, File] = {};
    for file_path in snapshot.keys() {
        content: str = snapshot[file_path];
        existing = [proj -->[?:File, path == file_path]];
        file_node: File;
        if existing {
            file_node = existing[0];
            file_node.content = content;
            file_node.last_synced_sha = head;
        } else {
            file_node = (proj ++> File(path=file_path, content=content, last_synced_sha=head))[0];
        }
        path_to_file[file_path] = file_node;
    }

    import re;
    edge_count: int = 0;
    for file_path in snapshot.keys() {
        for match in re.finditer(IMPORT_PATTERN, snapshot[file_path]) {
            target_path: str = resolve_import(file_path, match.group(1));
            if target_path in path_to_file {
                path_to_file[file_path] +>:Imports():+> path_to_file[target_path];
                edge_count += 1;
            }
        }
    }

    return {
        "project": project,
        "head": head,
        "files": len(snapshot),
        "import_edges": edge_count,
    };
}

"""Authenticated."""
walker seed_project {
    has project: str;
    has owner: str;
    has repo: str;
    has branch: str = "main";

    can run with Root entry {
        report do_seed_project(self.project, self.owner, self.repo, self.branch);
    }
}
