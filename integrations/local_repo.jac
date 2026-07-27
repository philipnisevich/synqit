"""Local repository access - the offline replacement for integrations/github.jac.

Synqit's CLI runs entirely on the developer's machine, so every fact it needs
about the codebase is already on disk or in the local object store. This module
is the only place that shells out to git, which keeps the failure modes in one
place: every function here either returns a usable value or raises with a
message a developer can act on.

Two deliberate choices:

1. **Snapshots come from a ref, not the working tree.** The baseline an
   integration reasons against must be the shared branch as everyone else sees
   it, not whatever the local checkout happens to have staged. `git show
   <ref>:<path>` reads straight from the object store, so it is correct even
   with dirty local edits.

2. **Binary files are skipped, never decoded.** The integration pipeline is
   text end to end; a file that cannot round-trip as UTF-8 is left untouched
   rather than corrupted. Same rule the GitHub reader follows.
"""

import os;
import subprocess;

"""Non-zero exit is always an error here. Callers that expect failure (a push
race, a missing ref) use try_git and inspect the code themselves."""
def git(args: list[str], cwd: str | None = None) -> str {
    result = run_git(args, cwd);
    if result["code"] != 0 {
        command: str = "git " + " ".join(args);
        detail: str = (result["err"] as str).strip() or (result["out"] as str).strip();
        raise Exception(command + " failed: " + detail);
    }
    return result["out"] as str;
}

"""Raw git invocation - returns the exit code instead of raising, for the
handful of callers that treat failure as a normal outcome."""
def run_git(args: list[str], cwd: str | None = None) -> dict {
    try {
        result = subprocess.run(
            ["git"] + args,
            capture_output=True,
            text=True,
            cwd=cwd or os.getcwd(),
        );
    } except FileNotFoundError {
        raise Exception("git is not installed or not on PATH. Synqit drives git directly and cannot run without it.");
    }
    return {"code": result.returncode, "out": result.stdout, "err": result.stderr};
}

def repo_root -> str {
    result = run_git(["rev-parse", "--show-toplevel"]);
    if result["code"] != 0 {
        raise Exception("Not inside a git repository. Run this from a cloned repo.");
    }
    return (result["out"] as str).strip();
}

"""True when the process is sitting exactly at the repository root. Synqit
operates on whole-repo snapshots, so running from a subdirectory would silently
scope every path wrong."""
def at_repo_root -> bool {
    try {
        return os.path.realpath(repo_root()) == os.path.realpath(os.getcwd());
    } except Exception {
        return False;
    }
}

def current_branch -> str {
    return git(["branch", "--show-current"]).strip();
}

def head_sha -> str {
    return git(["rev-parse", "HEAD"]).strip();
}

def ref_sha(ref: str) -> str {
    result = run_git(["rev-parse", "--verify", ref + "^{commit}"]);
    if result["code"] != 0 {
        raise Exception("Could not resolve '" + ref + "'. Check the branch name and that you have fetched it.");
    }
    return (result["out"] as str).strip();
}

def has_remote(name: str) -> bool {
    result = run_git(["remote", "get-url", name]);
    return result["code"] == 0;
}

"""Fetch and return the remote branch's sha. Network failures surface as a
plain message - this is the one step that needs connectivity."""
def fetch_branch(branch: str, remote: str = "origin") -> str {
    result = run_git(["fetch", "--quiet", remote, branch]);
    if result["code"] != 0 {
        detail: str = (result["err"] as str).strip();
        raise Exception("Could not fetch " + remote + "/" + branch + ". Check your network and remote. " + detail);
    }
    return ref_sha(remote + "/" + branch);
}

"""Paths tracked at a ref. `-z` because filenames may contain spaces, and a
newline split would corrupt them."""
def paths_at_ref(ref: str) -> list[str] {
    raw: str = git(["ls-tree", "-r", "--name-only", "-z", ref]);
    return [p for p in raw.split("\x00") if p];
}

"""Read one path at a ref, or None when it is not valid UTF-8 text.

Binary blobs are read as bytes and decoded explicitly so a decode failure is
catchable; letting subprocess decode would raise deep inside the runtime with
no path context.
"""
def read_path_at_ref(ref: str, path: str) -> str | None {
    result = subprocess.run(
        ["git", "show", ref + ":" + path],
        capture_output=True,
    );
    if result.returncode != 0 {
        return None;
    }
    try {
        return (result.stdout.decode("utf-8")) as str;
    } except UnicodeDecodeError {
        return None;
    }
}

"""Full path -> content snapshot of a ref, binary files omitted. This is the
local equivalent of github.snapshot_at, minus the per-blob network round trip
that made seeding an 80-request affair."""
def snapshot_at_ref(ref: str) -> dict[str, str] {
    snapshot: dict[str, str] = {};
    for path in paths_at_ref(ref) {
        content = read_path_at_ref(ref, path);
        if content is None {
            continue;
        }
        snapshot[path] = content.replace("\r\n", "\n");
    }
    return snapshot;
}

"""Tracked files as they currently exist on disk, including uncommitted edits.
This is the developer's proposal; snapshot_at_ref is the shared baseline."""
def snapshot_worktree -> dict[str, str] {
    raw: str = git(["ls-files", "-z"]);
    snapshot: dict[str, str] = {};
    for path in [p for p in raw.split("\x00") if p] {
        if not os.path.exists(path) {
            continue;
        }
        try {
            handle = open(path, "r", encoding="utf-8", newline="");
            content: str = handle.read();
            handle.close();
        } except (UnicodeDecodeError, OSError) {
            continue;
        }
        snapshot[path] = content.replace("\r\n", "\n");
    }
    return snapshot;
}

"""Apply the integration's result to the working tree. Deletions run through
git so the index stays consistent; writes create parent directories because an
integration may legitimately add a file in a new package."""
def apply_changes(changes: dict[str, str | None]) {
    for path in changes.keys() {
        content = changes[path];
        if content is None {
            run_git(["rm", "--quiet", "--ignore-unmatch", "--", path]);
            continue;
        }
        parent: str = os.path.dirname(path);
        if parent {
            os.makedirs(parent, exist_ok=True);
        }
        handle = open(path, "w", encoding="utf-8", newline="\n");
        handle.write(content as str);
        handle.close();
    }
}

def has_staged_or_unstaged_changes -> bool {
    output: str = git(["status", "--porcelain=v1", "--untracked-files=all"]);
    return bool([line for line in output.split("\n") if line.strip()]);
}

"""Commit every pending change under the given message. Returns None when
there was nothing to commit, so callers can distinguish "no-op integration"
from "commit failed"."""
def commit_all(message: str, author_name: str, author_email: str) -> str | None {
    git(["add", "--all"]);
    staged = run_git(["diff", "--cached", "--quiet"]);
    if staged["code"] == 0 {
        return None;
    }
    git([
        "-c", "user.name=" + author_name,
        "-c", "user.email=" + author_email,
        "commit", "--quiet", "-m", message,
    ]);
    return head_sha();
}

"""Push, reporting a rejected non-fast-forward as a normal outcome rather than
an exception. A rejection means the shared branch moved while this integration
was running - the caller re-reads the branch and integrates again, which is
exactly the optimistic-concurrency retry git itself is built around."""
def try_push(branch: str, remote: str = "origin") -> dict {
    result = run_git(["push", remote, "HEAD:" + branch]);
    if result["code"] == 0 {
        return {"ok": True, "rejected": False, "detail": ""};
    }
    detail: str = ((result["err"] as str) + (result["out"] as str)).strip();
    lowered: str = detail.lower();
    rejected: bool = (
        "non-fast-forward" in lowered
        or "fetch first" in lowered
        or "rejected" in lowered
        or "behind" in lowered
    );
    return {"ok": False, "rejected": rejected, "detail": detail};
}

"""Discard local commits and edits, returning the checkout to the shared
branch. Used to unwind a failed integration attempt before retrying."""
def reset_to(ref: str) {
    git(["reset", "--hard", ref]);
}

"""Record the working tree as a dangling commit WITHOUT modifying it, and
return its sha (None when there was nothing to save).

The push flow resets the checkout to the shared branch before applying an
integration, which would otherwise destroy uncommitted work if a later step
failed. `git stash create` builds the stash commit without touching the index
or the tree, so this is a pure safety net: if anything downstream goes wrong,
the developer recovers with `git stash apply <sha>`.
"""
def stash_snapshot -> str | None {
    if not has_staged_or_unstaged_changes() {
        return None;
    }
    result = run_git(["stash", "create", "synqit: pre-integration snapshot"]);
    if result["code"] != 0 {
        return None;
    }
    sha: str = (result["out"] as str).strip();
    if not sha {
        return None;
    }
    # A dangling commit is garbage-collectable. Anchoring it in the reflog is
    # what makes the recovery instruction we print actually reliable.
    run_git(["update-ref", "-m", "synqit pre-integration snapshot", "refs/synqit/last-snapshot", sha]);
    return sha;
}

"""Keep Synqit's own housekeeping out of the developer's shared .gitignore.

Running any .jac program provisions a local graph database in the working
directory, so without this every `synqit` command silently drops an untracked
`.jac/` directory into the repo it manages - and eventually into someone's
commit. `.git/info/exclude` is the right home for it: it is per-clone and never
travels, so we are not editing a tracked file on the developer's behalf.
"""
def ignore_local_artifacts {
    exclude: str = os.path.join(".git", "info", "exclude");
    if not os.path.exists(exclude) {
        return;
    }
    try {
        handle = open(exclude, "r");
        current: str = handle.read();
        handle.close();
    } except OSError {
        return;
    }
    lines: list[str] = current.split("\n");
    needed: list[str] = [entry for entry in [".jac/", ".synqit/"] if entry not in lines];
    if not needed {
        return;
    }
    try {
        append_handle = open(exclude, "a");
        prefix: str = "" if (current == "" or current.endswith("\n")) else "\n";
        append_handle.write(prefix + "\n".join(needed) + "\n");
        append_handle.close();
    } except OSError {
        return;
    }
}

def derive_owner_repo -> tuple[str, str] {
    import re;
    owner: str = "";
    repo: str = "";
    result = run_git(["config", "--get", "remote.origin.url"]);
    if result["code"] == 0 {
        m = re.search(r'[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$', (result["out"] as str).strip());
        if m {
            owner = m.group(1);
            repo = m.group(2);
        }
    }
    if not repo {
        try {
            repo = os.path.basename(repo_root());
        } except Exception {
            repo = "repo";
        }
    }
    return (owner or "local", repo);
}

"""Best-effort identity for the commit Synqit authors. Falls back rather than
failing: a missing git identity should not block an integration."""
def git_identity -> tuple[str, str] {
    name: str = "";
    email: str = "";
    name_result = run_git(["config", "user.name"]);
    if name_result["code"] == 0 {
        name = (name_result["out"] as str).strip();
    }
    email_result = run_git(["config", "user.email"]);
    if email_result["code"] == 0 {
        email = (email_result["out"] as str).strip();
    }
    return (name or "Synqit", email or "synqit@localhost");
}
