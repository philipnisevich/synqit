"""Graph schema: one persistent graph per project, living under root.shared.

Project is the container (root.shared -> Project). File nodes hang off a Project
and represent the current known state of main. Imports edges between File nodes
are the dependency graph a walker uses to compute blast radius. PushRequest nodes
represent pending work: attached to the Project, and connected via Touches edges
to whichever File nodes their diff starts at.
"""

node Project {
    has name: str;
    has repository: str;
    has branch: str;
    has members: list[str] = [];
    has created_at: str = "";
    has head: str = "";
}

node File {
    has path: str;
    has content: str = "";
    has last_synced_sha: str = "";
}

node PushRequest {
    has intent: str;
    has base_sha: str;
    has changes: list[dict] = [];
    has submitter: str = "";
    has status: str = "pending";
    has created_at: str = "";
    has touched_paths: list[str] = [];
    has deleted_paths: list[str] = [];
    has summary: str = "";
}

edge Imports: File --> File {}

edge Touches: PushRequest --> File {
    has change_type: str = "modified";
}
