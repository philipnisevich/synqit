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

walker seed_project {
    has project: str;
    has owner: str;
    has repo: str;
    has branch: str = "main";

    can run with Root entry {
        projects = [root.shared -->[?:Project, name == self.project]];
        if not projects {
            report {"error": "project_not_found", "project": self.project};
            disengage;
        }
        proj = projects[0];

        result = read_project(self.owner, self.repo, self.branch);
        snapshot: dict[str, str] = result["snapshot"] as dict[str, str];
        head: str = result["head"] as str;

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

        report {
            "project": self.project,
            "head": head,
            "files": len(snapshot),
            "import_edges": edge_count,
        };
    }
}
