"""Seeding a Project's file graph from whatever the current source of truth is.

Two entry points, one graph shape:

- `do_seed_project` reads the branch through the GitHub API. This is the hosted
  dashboard's path, where there is no checkout to read from.
- `do_seed_project_local` reads the same branch out of the local git object
  store. This is the CLI's path, and it is strictly better where it applies:
  no token, no rate limit, and one subprocess instead of one HTTP request per
  blob.

Both hand the snapshot to graph_build.build_project_graph, so the graph the LLM
eventually reasons over is identical either way.
"""

import from nodes { Project, File, Imports }
import from integrations.github { read_project }
import from integrations.local_repo { fetch_branch, ref_sha, snapshot_at_ref }
import from walkers.graph_build { build_project_graph }

"""Plain function (not walker-spawn-only) so the web service layer can call it
directly - same lesson as blast_radius/compute_blast_radius."""
def do_seed_project(project: str, owner: str, repo: str, branch: str) -> dict {
    import os;
    if not os.environ.get("GITHUB_TOKEN") {
        return {
            "error": "server_not_configured",
            "missing": "GITHUB_TOKEN",
            "message": "This Synqit server has no GitHub token, so it cannot read the repository. Set GITHUB_TOKEN in the server environment and restart.",
        };
    }

    projects = [root.shared -->[?:Project, name == project]];
    if not projects {
        return {"error": "project_not_found", "project": project};
    }
    proj = projects[0];

    try {
        result = read_project(owner, repo, branch);
    } except Exception as error {
        return {"error": "github_read_failed", "message": str(error)};
    }

    summary = build_project_graph(
        proj,
        result["snapshot"] as dict[str, str],
        result["head"] as str,
    );
    summary["project"] = project;
    return summary;
}

"""Seed from the local clone. `remote_ref` is resolved after a fetch so the
baseline is the shared branch as it exists right now, not a stale local ref -
integrating against a stale baseline is how a push silently reverts someone
else's work."""
def do_seed_project_local(project: str, branch: str, fetch: bool = True) -> dict {
    projects = [root -->[?:Project, name == project]];
    if not projects {
        return {"error": "project_not_found", "project": project};
    }
    proj = projects[0];

    try {
        head: str = fetch_branch(branch) if fetch else ref_sha("origin/" + branch);
    } except Exception as error {
        return {"error": "git_read_failed", "message": str(error)};
    }

    try {
        snapshot: dict[str, str] = snapshot_at_ref(head);
    } except Exception as error {
        return {"error": "snapshot_failed", "message": str(error)};
    }

    if not snapshot {
        return {
            "error": "empty_snapshot",
            "message": "No readable text files found at " + head[:7] + ". An empty repository has nothing to integrate against.",
        };
    }

    summary = build_project_graph(proj, snapshot, head);
    summary["project"] = project;
    return summary;
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
