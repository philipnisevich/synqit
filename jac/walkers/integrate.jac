import from nodes { PushRequest, File, Project }
import from walkers.blast_radius { blast_radius, BlastFile }
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

sem Workspace.integrate = "Make the feature intent true in the CURRENT workspace, which may have moved on since the developer proposed their changes. Use the tools to inspect and edit files - a successful integration MUST call write_file or delete_file at least once, never just describe the change. Only return needs_human when the intent is genuinely incompatible with what the workspace already does (e.g. contradicts a product decision already made elsewhere) - never for ordinary implementation difficulty.";
sem Workspace.integrate.intent = "The feature the developer wants to be true.";
sem Workspace.integrate.proposed_changes = "The developer's own proposed edits, written against their possibly-stale local copy - a strong hint for what to implement, not a literal patch to apply verbatim.";

walker integrate {
    has push_id: str;
    has max_hops: int = 2;

    can run with Root entry {
        push = jobj(self.push_id);
        if not isinstance(push, PushRequest) {
            report {"error": "push_not_found", "push_id": self.push_id};
            disengage;
        }

        projects: list[Project] = [push <-- [?:Project]];
        if not projects {
            report {"error": "project_not_found_for_push"};
            disengage;
        }
        proj = projects[0];

        radius = blast_radius(push_id=self.push_id, max_hops=self.max_hops);
        root spawn radius;
        context_files: list[BlastFile] = radius.reports[0] if radius.reports else [];

        workspace_files: dict[str, str] = {};
        for f in context_files {
            workspace_files[f.path] = f.content;
        }
        ws = Workspace(files=workspace_files);

        result = ws.integrate(intent=push.intent, proposed_changes=push.changes);

        if result.status == "needs_human" {
            push.status = "needs_human";
            report {"status": "needs_human", "reason": result.reason};
            disengage;
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
        report {
            "status": "integrated",
            "summary": result.summary,
            "activity": ws.activity,
            "files_touched": touched_paths,
            "files_deleted": ws.deleted,
        };
    }
}
