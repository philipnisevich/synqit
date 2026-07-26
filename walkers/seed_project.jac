import from nodes { Project, File, Imports }
import from integrations.github { read_project }

"""Authenticated. One-time (well, idempotent) seed of a Project's graph from
the current state of its GitHub branch: populates File.content for every
tracked file, and a cheap regex import-scan wires Imports edges between them.
This is what gives blast_radius something real to walk - before this runs,
File nodes exist (from pushes) but are empty and disconnected.
"""

# Two import dialects live in this repo (and in most real ones): quoted
# relative specifiers (JS/TS) and Jac's unquoted dotted module paths. Scanning
# for only the first is why a Jac codebase used to seed with zero Imports
# edges, which left blast_radius returning nothing but the touched file.
glob IMPORT_PATTERN: str = r'''(?:import\s+.*?from\s+|require\()\s*['"](\.[^'"]+)['"]''';
glob JAC_IMPORT_PATTERN: str = r'''(?m)^[ \t]*import[ \t]+(?:from[ \t]+)?(\.*)([A-Za-z_][\w.]*)''';

# A specifier names a module, not a file - `./Logo` is `Logo.tsx` on disk and
# `walkers.blast_radius` is `walkers/blast_radius.jac`. Resolution has to try
# the real extensions or every edge silently fails to bind.
glob JS_SUFFIXES: list[str] = [
    "", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css",
    "/index.ts", "/index.tsx", "/index.js", "/index.jsx",
];
glob JAC_SUFFIXES: list[str] = [".jac", ".sv.jac", ".cl.jac", ".impl.jac"];

def resolve_import(from_path: str, import_spec: str) -> list[str] {
    import from os.path { normpath, dirname, join }
    base: str = normpath(join(dirname(from_path), import_spec));
    return [base + suffix for suffix in JS_SUFFIXES];
}

"""Leading dots mean "relative to this file's directory" (`.components.Dashboard`);
without them the path is repo-root relative (`walkers.blast_radius`). Bare
stdlib/third-party imports (`os`, `byllm.lib`) resolve to nothing in the
repo and are simply dropped by the caller's membership check."""
def resolve_jac_import(from_path: str, dots: str, module: str) -> list[str] {
    import from os.path { normpath, dirname, join }
    relative_path: str = module.replace(".", "/");
    base: str = normpath(join(dirname(from_path), relative_path)) if dots else relative_path;
    return [base + suffix for suffix in JAC_SUFFIXES];
}

"""Every candidate path an import in `file_path` could be referring to."""
def import_targets(file_path: str, content: str) -> list[list[str]] {
    import re;
    targets: list[list[str]] = [];
    if file_path.endswith(".jac") {
        for m in re.finditer(JAC_IMPORT_PATTERN, content) {
            targets.append(resolve_jac_import(file_path, m.group(1), m.group(2)));
        }
    }
    for m in re.finditer(IMPORT_PATTERN, content) {
        targets.append(resolve_import(file_path, m.group(1)));
    }
    return targets;
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

    edge_count: int = 0;
    linked: set[str] = set();
    for file_path in snapshot.keys() {
        for candidates in import_targets(file_path, snapshot[file_path]) {
            for target_path in candidates {
                if target_path not in path_to_file or target_path == file_path {
                    continue;
                }
                # A module resolves to exactly one file - stop at the first
                # candidate that exists, and never draw the same edge twice
                # (two imports from one file to another is still one edge).
                pair: str = file_path + " -> " + target_path;
                if pair not in linked {
                    path_to_file[file_path] +>:Imports():+> path_to_file[target_path];
                    linked.add(pair);
                    edge_count += 1;
                }
                break;
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
