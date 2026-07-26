"""
Synqit service layer - exposes project and push request management
endpoints on the shared graph.
"""

node Project {
    has name: str;
    has repository: str;
    has branch: str = "main";
    has created_at: str = "";
}

node PushRequest {
    has project_name: str;
    has intent: str;
    has base_sha: str;
    has submitter: str = "";
    has status: str = "pending";
    has created_at: str = "";
    has touched_paths: list[str] = [];
}

obj ProjectView {
    has id: str;
    has name: str;
    has repository: str;
    has branch: str;
    has created_at: str;
}

obj PushView {
    has id: str;
    has project_name: str;
    has intent: str;
    has base_sha: str;
    has submitter: str;
    has status: str;
    has created_at: str;
    has touched_paths: list[str];
}

def:pub list_projects() -> list[ProjectView] {
    results: list[ProjectView] = [];
    for p in [root.shared -->[?:Project]] {
        results.append(ProjectView(
            id=jid(p),
            name=p.name,
            repository=p.repository,
            branch=p.branch,
            created_at=p.created_at,
        ));
    }
    return results;
}

def:pub create_project(name: str, repository: str, branch: str) -> ProjectView {
    import from datetime { datetime }
    existing = [root.shared -->[?:Project, name == name]];
    if existing {
        p = existing[0];
        return ProjectView(
            id=jid(p),
            name=p.name,
            repository=p.repository,
            branch=p.branch,
            created_at=p.created_at,
        );
    }
    now: str = datetime.utcnow().isoformat();
    p = root.shared ++> Project(
        name=name,
        repository=repository,
        branch=branch,
        created_at=now,
    );
    return ProjectView(
        id=jid(p),
        name=p.name,
        repository=p.repository,
        branch=p.branch,
        created_at=p.created_at,
    );
}

def:pub list_pushes(project_name: str) -> list[PushView] {
    results: list[PushView] = [];
    projects = [root.shared -->[?:Project, name == project_name]];
    if not projects {
        return results;
    }
    proj = projects[0];
    for push in [proj -->[?:PushRequest]] {
        results.append(PushView(
            id=jid(push),
            project_name=push.project_name,
            intent=push.intent,
            base_sha=push.base_sha,
            submitter=push.submitter,
            status=push.status,
            created_at=push.created_at,
            touched_paths=push.touched_paths,
        ));
    }
    return results;
}

def:pub ingest_push(
    project_name: str,
    intent: str,
    base_sha: str,
    submitter: str,
    touched_paths: list[str],
) -> PushView {
    import from datetime { datetime }
    projects = [root.shared -->[?:Project, name == project_name]];
    if not projects {
        return PushView(
            id="",
            project_name=project_name,
            intent=intent,
            base_sha=base_sha,
            submitter=submitter,
            status="error",
            created_at="",
            touched_paths=touched_paths,
        );
    }
    proj = projects[0];
    now: str = datetime.utcnow().isoformat();
    push = proj ++> PushRequest(
        project_name=project_name,
        intent=intent,
        base_sha=base_sha,
        submitter=submitter,
        status="pending",
        created_at=now,
        touched_paths=touched_paths,
    );
    return PushView(
        id=jid(push),
        project_name=push.project_name,
        intent=push.intent,
        base_sha=push.base_sha,
        submitter=push.submitter,
        status=push.status,
        created_at=push.created_at,
        touched_paths=push.touched_paths,
    );
}
