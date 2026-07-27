"""Turning a path -> content snapshot into a traversable Jac graph.

This is the piece that makes blast_radius mean anything: without Imports edges,
a push's context is just the files the developer already touched, and the LLM
integrates blind. Everything here is deterministic - no LLM, no network - so it
runs identically whether the snapshot came from GitHub (hosted dashboard) or
from the local object store (CLI). One scanner, one graph shape, no drift.

The scanner is intentionally a cheap regex rather than a real parser. It only
has to be good enough to find *candidate* neighbours; over-inclusion costs the
LLM a little context, while a missed edge costs it a call site it never sees.
"""

import re;

import from nodes { Project, File, Imports }

# Two import dialects show up in real repos and both must be handled: quoted
# relative specifiers (JS/TS) and Jac's unquoted dotted module paths. Scanning
# for only the first is why a Jac codebase used to seed with zero edges.
glob IMPORT_PATTERN: str = r'''(?:import\s+.*?from\s+|require\()\s*['"](\.[^'"]+)['"]''';
glob JAC_IMPORT_PATTERN: str = r'''(?m)^[ \t]*import[ \t]+(?:from[ \t]+)?(\.*)([A-Za-z_][\w.]*)''';
glob PY_IMPORT_PATTERN: str = r'''(?m)^[ \t]*(?:from[ \t]+([.\w]+)[ \t]+import|import[ \t]+([.\w]+))''';

# A specifier names a module, not a file - `./Logo` is `Logo.tsx` on disk and
# `walkers.blast_radius` is `walkers/blast_radius.jac`. Resolution has to try
# the real extensions or every edge silently fails to bind.
glob JS_SUFFIXES: list[str] = [
    "", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css",
    "/index.ts", "/index.tsx", "/index.js", "/index.jsx",
];
glob JAC_SUFFIXES: list[str] = [".jac", ".sv.jac", ".cl.jac", ".impl.jac"];
glob PY_SUFFIXES: list[str] = [".py", "/__init__.py"];

def resolve_relative(from_path: str, spec: str, suffixes: list[str]) -> list[str] {
    import from os.path { normpath, dirname, join }
    base: str = normpath(join(dirname(from_path), spec));
    return [base + suffix for suffix in suffixes];
}

"""Leading dots mean "relative to this file's directory" (`.components.Dashboard`);
without them the path is repo-root relative (`walkers.blast_radius`). Bare
stdlib or third-party imports (`os`, `byllm.lib`) resolve to nothing inside the
repo and are dropped by the membership check in build_import_edges."""
def resolve_dotted(from_path: str, dots: str, module: str, suffixes: list[str]) -> list[str] {
    import from os.path { normpath, dirname, join }
    relative_path: str = module.replace(".", "/");
    if not dots {
        return [relative_path + suffix for suffix in suffixes];
    }
    base: str = normpath(join(dirname(from_path), relative_path));
    return [base + suffix for suffix in suffixes];
}

"""Every candidate path each import in `file_path` could refer to, as a list of
candidate groups - one group per import statement, ordered most to least
likely. The caller takes the first candidate that exists."""
def import_targets(file_path: str, content: str) -> list[list[str]] {
    targets: list[list[str]] = [];

    if file_path.endswith(".jac") {
        for m in re.finditer(JAC_IMPORT_PATTERN, content) {
            targets.append(resolve_dotted(file_path, m.group(1), m.group(2), JAC_SUFFIXES));
        }
    }

    if file_path.endswith(".py") {
        for m in re.finditer(PY_IMPORT_PATTERN, content) {
            module: str = (m.group(1) or m.group(2)) as str;
            dots: str = "";
            trimmed: str = module;
            while trimmed.startswith(".") {
                dots += ".";
                trimmed = trimmed[1:];
            }
            if trimmed {
                targets.append(resolve_dotted(file_path, dots, trimmed, PY_SUFFIXES));
            }
        }
    }

    # Quoted relative specifiers are not exclusive to .js/.ts - .jac client
    # files use them for stylesheets too - so this scan always runs.
    for m in re.finditer(IMPORT_PATTERN, content) {
        targets.append(resolve_relative(file_path, m.group(1), JS_SUFFIXES));
    }

    return targets;
}

"""Create or refresh a File node per snapshot entry, returning the path -> node
map the edge pass needs. Existing nodes are updated rather than replaced so any
edges already pointing at them survive a re-seed."""
def sync_file_nodes(proj: Project, snapshot: dict[str, str], head: str) -> dict[str, File] {
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
    return path_to_file;
}

"""Drop File nodes for paths that no longer exist at this ref. Without this a
deleted file lingers forever and keeps feeding stale content into every future
blast radius."""
def prune_missing_files(proj: Project, snapshot: dict[str, str]) -> int {
    removed: int = 0;
    for file_node in [proj -->[?:File]] {
        if file_node.path not in snapshot {
            del file_node;
            removed += 1;
        }
    }
    return removed;
}

"""Wire Imports edges between the given File nodes.

Idempotent by construction: an edge is only added when the target is not
already reachable from the source. Re-seeding an existing project therefore
never doubles up its edges, which matters because sync_file_nodes deliberately
reuses File nodes rather than recreating them.
"""
def build_import_edges(snapshot: dict[str, str], path_to_file: dict[str, File]) -> int {
    linked: set[str] = set();

    # Seed the seen-set from edges already in the graph so a re-seed is a no-op
    # rather than a duplicate pass.
    for file_path in path_to_file.keys() {
        for existing_target in [path_to_file[file_path] ->:Imports:->] {
            linked.add(file_path + " -> " + existing_target.path);
        }
    }

    for file_path in snapshot.keys() {
        if file_path not in path_to_file {
            continue;
        }
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
                }
                break;
            }
        }
    }
    # Total edges in the graph, not just the ones this call added - a re-seed
    # that adds nothing still has to report the real size of the graph, or
    # callers read "1 edge" as a nearly disconnected codebase.
    return len(linked);
}

"""Rebuild a project's file graph from a snapshot. Source-agnostic on purpose:
the hosted dashboard passes a GitHub tree read, the CLI passes a local git ref
read, and both get an identical graph out."""
def build_project_graph(proj: Project, snapshot: dict[str, str], head: str) -> dict {
    proj.head = head;
    pruned: int = prune_missing_files(proj, snapshot);
    path_to_file: dict[str, File] = sync_file_nodes(proj, snapshot, head);
    edge_count: int = build_import_edges(snapshot, path_to_file);
    return {
        "head": head,
        "files": len(snapshot),
        "import_edges": edge_count,
        "pruned": pruned,
    };
}
