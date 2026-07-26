import from nodes { PushRequest, File, Project }
import from walkers.blast_radius { compute_blast_radius, BlastFile }
import from byllm.lib { Model }

glob llm: Model = Model(model_name="claude-sonnet-5");

"""The actual integration step. Takes a push's blast-radius context (not the
whole codebase) and the developer's proposed changes, and uses byLLM's own
ReAct tool loop (not a hand-rolled one) to make the intent true against
whatever the workspace currently is. needs_human is the LLM's own judgment
call about genuine intent conflicts - nothing upstream of this decides that.
"""

obj IntegrationResult {
    has status: str;
    has reason: str = "";
    has summary: str = "";
}
sem IntegrationResult.status = "Either 'integrated' (the feature is now true in the workspace) or 'needs_human' (the intent is genuinely incompatible with the current codebase - not ordinary implementation difficulty).";
sem IntegrationResult.reason = "If status is needs_human, a short explanation of the incompatibility.";
sem IntegrationResult.summary = "If status is integrated, a short summary of what changed and why.";

obj Workspace {
    has files: dict[str, str] = {};
    has deleted: list[str] = [];
    has activity: list[str] = [];

    def list_files -> list[str] {
        return list(self.files.keys());
    }

    def read_file(path: str) -> str | None {
        return self.files.get(path);
    }

    def write_file(path: str, content: str) -> str {
        self.files[path] = content;
        self.activity.append(f"wrote {path}");
        return "written";
    }

    def delete_file(path: str) -> str {
        self.files.pop(path, None);
        self.deleted.append(path);
        self.activity.append(f"deleted {path}");
        return "deleted";
    }

    def integrate(intent: str, proposed_changes: list[dict]) -> IntegrationResult by llm(
        tools=[self.list_files, self.read_file, self.write_file, self.delete_file],
        max_react_iterations=20,
        temperature=None,
    );
}

sem Workspace.list_files = "List every file path currently visible in the workspace.";

sem Workspace.read_file = "Read a file's current content. Returns null if the file doesn't exist yet.";
sem Workspace.read_file.path = "The file path to read.";

sem Workspace.write_file = "Write (create or overwrite) a file's full content.";
sem Workspace.write_file.path = "The file path to write.";
sem Workspace.write_file.content = "The complete new content of the file - not a diff or patch.";

sem Workspace.delete_file = "Delete a file.";
sem Workspace.delete_file.path = "The file path to delete.";

sem Workspace.integrate = "Make the feature intent true in the CURRENT workspace, which may have moved on since the developer proposed their changes. Use the tools to inspect and edit files - a successful integration MUST call write_file or delete_file at least once, never just describe the change. The workspace contains every file structurally reachable from what you're changing (callers, dependents, tests) - before finishing, use list_files and read_file to check whether anything else in the workspace references what you changed (a renamed or removed function, a changed signature, a moved export), and update every call site you find so nothing is left broken. Only return needs_human when the intent is genuinely incompatible with what the workspace already does (e.g. contradicts a product decision already made elsewhere) - never for ordinary implementation difficulty.";
sem Workspace.integrate.intent = "The feature the developer wants to be true.";
sem Workspace.integrate.proposed_changes = "The developer's own proposed edits, written against their possibly-stale local copy - a strong hint for what to implement, not a literal patch to apply verbatim.";

"""Deterministic - no LLM involved. Regex-extract exported symbol names
(matches the same cheap-regex philosophy as seed_project's import scan)."""
def extract_exports(content: str) -> set[str] {
    import re;
    names: set[str] = set();
    for m in re.finditer(r'export\s+(?:async\s+)?function\s+(\w+)', content) {
        names.add(m.group(1));
    }
    for m in re.finditer(r'export\s+(?:const|let|var)\s+(\w+)', content) {
        names.add(m.group(1));
    }
    for m in re.finditer(r'export\s+class\s+(\w+)', content) {
        names.add(m.group(1));
    }
    return names;
}

"""Deterministic verification of the AI's output - not a judgment call. Diffs
exported symbols on every file the AI actually changed to find what it
removed or renamed, then checks every OTHER file in the same workspace for a
lingering reference. Returns {path: [broken_symbol, ...]} - empty means clean.
"""
def find_broken_references(original: dict[str, str], updated: dict[str, str]) -> dict[str, list[str]] {
    import re;
    removed_symbols: set[str] = set();
    for path in original.keys() {
        old_content: str = original[path];
        new_content: str = updated.get(path, old_content);
        if old_content != new_content {
            removed_symbols = removed_symbols | (extract_exports(old_content) - extract_exports(new_content));
        }
    }
    if not removed_symbols {
        return {};
    }
    broken: dict[str, list[str]] = {};
    for path in updated.keys() {
        content: str = updated[path];
        if original.get(path) != content {
            continue;
        }
        hits: list[str] = [s for s in removed_symbols if re.search(r'\b' + re.escape(s) + r'\b', content)];
        if hits {
            broken[path] = hits;
        }
    }
    return broken;
}

"""Plain function (not walker-spawn-only) so the `push` walker can call it
directly - same nested-spawn lesson as blast_radius/compute_blast_radius."""
def do_integrate(push_id: str, max_hops: int) -> dict {
    push = jobj(push_id);
    if not isinstance(push, PushRequest) {
        return {"error": "push_not_found", "push_id": push_id};
    }

    projects: list[Project] = [push <-- [?:Project]];
    if not projects {
        return {"error": "project_not_found_for_push"};
    }
    proj = projects[0];

    context_files: list[BlastFile] = compute_blast_radius(push_id, max_hops);

    workspace_files: dict[str, str] = {};
    for f in context_files {
        workspace_files[f.path] = f.content;
    }
    original_files: dict[str, str] = dict(workspace_files);
    ws = Workspace(files=dict(workspace_files));

    result = ws.integrate(intent=push.intent, proposed_changes=push.changes);

    if result.status == "needs_human" {
        push.status = "needs_human";
        return {"status": "needs_human", "reason": result.reason};
    }

    broken = find_broken_references(original_files, ws.files);
    attempts: int = 0;
    while broken and attempts < 2 {
        fix_notes: list[str] = [];
        for path in broken.keys() {
            syms: str = ", ".join(broken[path]);
            fix_notes.append(path + " still references removed/renamed: " + syms);
        }
        follow_up_intent = push.intent + "\n\nVerification found unfinished work - fix these exactly: " + "; ".join(fix_notes);
        result = ws.integrate(intent=follow_up_intent, proposed_changes=push.changes);
        broken = find_broken_references(original_files, ws.files);
        attempts += 1;
    }

    if broken {
        push.status = "integration_incomplete";
        return {
            "status": "integration_incomplete",
            "reason": "Deterministic check still finds broken references after retries.",
            "broken": broken,
        };
    }

    touched_paths: list[str] = [];
    for file_path in ws.files.keys() {
        new_content: str = ws.files[file_path];
        existing = [proj -->[?:File, path == file_path]];
        if existing {
            file_node = existing[0];
            file_node.content = new_content;
        } else {
            file_node = (proj ++> File(path=file_path, content=new_content))[0];
        }
        touched_paths.append(file_path);
    }

    for deleted_path in ws.deleted {
        gone = [proj -->[?:File, path == deleted_path]];
        for g in gone {
            del g;
        }
    }

    push.status = "integrated";
    push.touched_paths = touched_paths;
    push.deleted_paths = ws.deleted;
    push.summary = result.summary;
    return {
        "status": "integrated",
        "summary": result.summary,
        "activity": ws.activity,
        "files_touched": touched_paths,
        "files_deleted": ws.deleted,
    };
}

walker integrate {
    has push_id: str;
    has max_hops: int = 2;

    can run with Root entry {
        report do_integrate(self.push_id, self.max_hops);
    }
}
