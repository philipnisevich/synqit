import os;
import requests;

"""GitHub Git Data API calls, ported from the original Synqit's src/github.js.
Plain functions (not walkers/endpoints) - called by seed_project and the future
integrate/publish walkers. Requires GITHUB_TOKEN in the environment.
"""

glob GITHUB_API: str = "https://api.github.com";

def gh_headers -> dict[str, str] {
    token: str = os.environ.get("GITHUB_TOKEN", "") as str;
    if not token {
        raise Exception("GITHUB_TOKEN is required on the Synqit server.");
    }
    return {
        "accept": "application/vnd.github+json",
        "authorization": f"Bearer {token}",
        "x-github-api-version": "2022-11-28",
    };
}

def gh_request(method: str, path: str, body: dict | None = None) -> dict[str, any] {
    response = requests.request(method, f"{GITHUB_API}{path}", headers=gh_headers(), json=body);
    if response.status_code >= 300 {
        if response.status_code == 401 {
            raise Exception("GitHub rejected the token on the Synqit server.");
        }
        if response.status_code == 403 {
            raise Exception("GitHub denied access. Check the token has Contents: read and write on this repo.");
        }
        raise Exception(f"GitHub responded {response.status_code}: {response.text}");
    }
    if not response.text {
        return {};
    }
    return response.json() as dict[str, any];
}

def repo_head(owner: str, repo: str, branch: str) -> str {
    data = gh_request("GET", f"/repos/{owner}/{repo}/git/ref/heads/{branch}");
    return data["object"]["sha"] as str;
}

def snapshot_at(owner: str, repo: str, commit_sha: str) -> dict[str, str] {
    commit = gh_request("GET", f"/repos/{owner}/{repo}/git/commits/{commit_sha}");
    tree_sha: str = commit["tree"]["sha"] as str;
    tree = gh_request("GET", f"/repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1");
    entries = [e for e in tree["tree"] if e["type"] == "blob"];
    contents: dict[str, str] = {};
    for entry in entries {
        blob = gh_request("GET", f"/repos/{owner}/{repo}/git/blobs/{entry['sha']}");
        raw: str = blob["content"] as str;
        contents[entry["path"]] = base64_decode(raw.replace("\n", ""));
    }
    return contents;
}

def base64_decode(value: str) -> str {
    import base64;
    return base64.b64decode(value).decode("utf-8");
}

"""Read the current state of `branch` on GitHub. Returns the head sha and a
full path -> content snapshot - this is what seeds/refreshes File nodes."""
def read_project(owner: str, repo: str, branch: str) -> dict[str, any] {
    head: str = repo_head(owner, repo, branch);
    return {"head": head, "snapshot": snapshot_at(owner, repo, head)};
}

"""Read a specific commit's snapshot - used to resolve a push's base_sha."""
def read_commit(owner: str, repo: str, commit_sha: str) -> dict[str, str] {
    return snapshot_at(owner, repo, commit_sha);
}

"""Publish next_snapshot as one commit on top of expected_head. Only writes
blobs for paths that actually changed; raises if `branch` moved since
expected_head (someone/something committed outside Synqit) rather than
silently overwriting it."""
def publish_snapshot(
    owner: str,
    repo: str,
    branch: str,
    expected_head: str,
    previous_snapshot: dict[str, str],
    next_snapshot: dict[str, str],
    message: str,
) -> str {
    remote_head: str = repo_head(owner, repo, branch);
    if remote_head != expected_head {
        raise Exception(f"GitHub {branch} advanced outside Synqit (expected {expected_head}, found {remote_head}).");
    }

    commit = gh_request("GET", f"/repos/{owner}/{repo}/git/commits/{remote_head}");
    base_tree_sha: str = commit["tree"]["sha"] as str;

    paths: set[str] = set(previous_snapshot.keys()) | set(next_snapshot.keys());
    tree_entries: list[dict] = [];
    for path in paths {
        prev_content = previous_snapshot.get(path);
        next_content = next_snapshot.get(path);
        if prev_content == next_content {
            continue;
        }
        if next_content is None {
            tree_entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None});
            continue;
        }
        blob = gh_request("POST", f"/repos/{owner}/{repo}/git/blobs", {"content": next_content, "encoding": "utf-8"});
        tree_entries.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]});
    }

    if not tree_entries {
        return remote_head;
    }

    next_tree = gh_request("POST", f"/repos/{owner}/{repo}/git/trees", {"base_tree": base_tree_sha, "tree": tree_entries});
    next_commit = gh_request("POST", f"/repos/{owner}/{repo}/git/commits", {
        "message": f"synqit: {message}",
        "tree": next_tree["sha"],
        "parents": [remote_head],
    });
    gh_request("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}", {"sha": next_commit["sha"], "force": False});
    return next_commit["sha"] as str;
}
