import subprocess;
import os;

def git(args: list[str]) -> str {
    result = subprocess.run(["git"] + args, capture_output=True, text=True);
    if result.returncode != 0 {
        raise Exception("git " + " ".join(args) + " failed: " + result.stderr);
    }
    return result.stdout;
}

def is_git_root -> bool {
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True);
    if result.returncode != 0 {
        return False;
    }
    top: str = result.stdout.strip();
    return os.path.realpath(top) == os.path.realpath(os.getcwd());
}

def current_branch -> str {
    return git(["branch", "--show-current"]).strip();
}

def head_sha -> str {
    return git(["rev-parse", "HEAD"]).strip();
}

def working_tree_changes -> list[str] {
    output: str = git(["status", "--porcelain=v1", "--untracked-files=all"]);
    lines: list[str] = [line for line in output.split("\n") if line.strip()];
    return lines;
}

def fetch_branch(branch: str) -> str {
    git(["fetch", "--quiet", "origin", branch]);
    return git(["rev-parse", "origin/" + branch]).strip();
}

def sync_to_commit(branch: str) -> str {
    fetched: str = fetch_branch(branch);
    git(["reset", "--hard", fetched]);
    return fetched;
}

def derive_owner_repo -> tuple[str, str] {
    owner: str = "";
    repo: str = "";
    try {
        url: str = git(["config", "--get", "remote.origin.url"]).strip();
        import re;
        m = re.search(r'[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$', url);
        if m {
            owner = m.group(1);
            repo = m.group(2);
        }
    } except Exception {
        owner = "";
    }
    if not owner {
        try {
            owner = git(["config", "user.name"]).strip();
        } except Exception {
            owner = "anon";
        }
        if not owner {
            owner = "anon";
        }
    }
    if not repo {
        try {
            top: str = git(["rev-parse", "--show-toplevel"]).strip();
            repo = os.path.basename(top);
        } except Exception {
            repo = "repo";
        }
    }
    return (owner, repo);
}
