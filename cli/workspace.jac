import hashlib;
import json;
import os;
import subprocess;

glob STATE_DIR: str = ".synqit";
glob STATE_FILE: str = "state.json";

def state_path -> str {
    return os.path.join(os.getcwd(), STATE_DIR, STATE_FILE);
}

def load_state -> dict[str, any] | None {
    path: str = state_path();
    if not os.path.exists(path) {
        return None;
    }
    handle = open(path, "r");
    data = json.load(handle);
    handle.close();
    return data as dict[str, any];
}

def save_state(state: dict[str, any]) {
    ignore_synqit_state();
    dir_path: str = os.path.join(os.getcwd(), STATE_DIR);
    os.makedirs(dir_path, exist_ok=True);
    handle = open(state_path(), "w");
    json.dump(state, handle, indent=2);
    handle.close();
}

"""Keep Synqit's own housekeeping out of the developer's shared .gitignore.
Covers both .synqit/ (our state file) and .jac/ - running any .jac script
with `jac run` provisions a local graph database in the cwd by default, even
though this CLI never touches the graph itself. Without this, every
`synqit` command run inside a project silently drops an untracked database
file into that project's working directory."""
def ignore_synqit_state {
    exclude: str = os.path.join(os.getcwd(), ".git", "info", "exclude");
    if not os.path.exists(exclude) {
        return;
    }
    handle = open(exclude, "r");
    current: str = handle.read();
    handle.close();
    lines: list[str] = current.split("\n");
    needed: list[str] = [entry for entry in [".synqit/", ".jac/"] if entry not in lines];
    if needed {
        append_handle = open(exclude, "a");
        prefix: str = "" if (current == "" or current.endswith("\n")) else "\n";
        append_handle.write(prefix + "\n".join(needed) + "\n");
        append_handle.close();
    }
}

def content_hash(content: str) -> str {
    return hashlib.sha256(content.encode("utf-8")).hexdigest();
}

def read_tracked_workspace -> dict[str, str] {
    result = subprocess.run(["git", "ls-files", "-z"], capture_output=True, text=True);
    raw: str = result.stdout;
    files: list[str] = [p for p in raw.split("\x00") if p];
    snapshot: dict[str, str] = {};
    for path in files {
        handle = open(path, "r", encoding="utf-8", newline="");
        content: str = handle.read();
        handle.close();
        snapshot[path] = content.replace("\r\n", "\n");
    }
    return snapshot;
}

def hashes_for(snapshot: dict[str, str]) -> dict[str, str] {
    hashes: dict[str, str] = {};
    for path in snapshot.keys() {
        hashes[path] = content_hash(snapshot[path]);
    }
    return hashes;
}

"""Diff the current tracked workspace against the hashes recorded at last
sync. Hash-based, not `git diff` - works whether or not anything was staged
or committed, since Synqit doesn't use commits as its unit of work."""
def changed_files(snapshot: dict[str, str], known_hashes: dict[str, str]) -> list[dict] {
    all_paths: set[str] = set(snapshot.keys()) | set(known_hashes.keys());
    changes: list[dict] = [];
    for path in all_paths {
        has_content: bool = path in snapshot;
        current_hash: str | None = content_hash(snapshot[path]) if has_content else None;
        known_hash: str | None = known_hashes.get(path);
        if current_hash == known_hash {
            continue;
        }
        if not has_content {
            changes.append({"path": path, "change_type": "deleted"});
        } else {
            change_type: str = "added" if known_hash is None else "modified";
            changes.append({"path": path, "content": snapshot[path], "change_type": change_type});
        }
    }
    changes.sort(key=change_sort_key);
    return changes;
}

def change_sort_key(change: dict) -> str {
    return change["path"] as str;
}
