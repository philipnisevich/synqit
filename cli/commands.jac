import sys;
import getpass;
import os;

import from config { load_config, save_config }
import from api { register, login as api_login, call_walker }
import from git_ops { derive_owner_repo, is_git_root, current_branch, head_sha, working_tree_changes, fetch_branch, sync_to_commit }
import from workspace { changed_files, hashes_for, load_state, read_tracked_workspace, save_state }
import from ui { bold, cyan, gray, step, ok, info, fail }

glob DEFAULT_BASE: str = "http://localhost:8899";

def require_session -> dict {
    cfg = load_config();
    if not cfg.get("token") or not cfg.get("base") {
        raise Exception("Not logged in. Run `synqit login --base <server-url>` first.");
    }
    return cfg;
}

def prompt(label: str) -> str {
    out: any = sys.stdout;
    out.write(label);
    out.flush();
    stdin_stream: any = sys.stdin;
    line: str = stdin_stream.readline() as str;
    return line.strip();
}

def normalize_base(value: str) -> str {
    return value.rstrip("/");
}

def cmd_login(base_flag: str | None, username_flag: str | None, password_flag: str | None) {
    cfg = load_config();
    base_raw: str = (base_flag or cfg.get("base") or DEFAULT_BASE) as str;
    base: str = normalize_base(base_raw);

    username: str = username_flag as str if username_flag else "";
    password: str = password_flag as str if password_flag else "";

    if not username or not password {
        stream: any = sys.stdout;
        if not stream.isatty() {
            fail("`synqit login` must run in an interactive terminal, or pass --username/--password.");
            return;
        }
        if not username {
            username = prompt("Username: ");
        }
        if not password {
            password = getpass.getpass("Password: ");
        }
    }

    if not username or not password {
        fail("Username and password are required.");
        return;
    }

    step("Connecting to " + base);
    session: dict = {};
    try {
        session = api_login(base, username, password);
        ok("logged in as " + (session["username"] as str));
    } except Exception as login_error {
        step("No existing account matched - creating one");
        try {
            session = register(base, username, password);
            ok("account created and logged in as " + (session["username"] as str));
        } except Exception as register_error {
            fail("Login failed (" + str(login_error) + "). Tried creating an account too, that also failed: " + str(register_error));
            return;
        }
    }
    save_config({"base": base, "token": session["token"], "username": session["username"]});
    info(gray("    Credentials saved. Run `synqit init` from a project's repo root next."));
}

def cmd_init(project_arg: str | None, branch_flag: str | None, github_flag: str | None) {
    cfg = require_session();
    if load_state() is not None {
        fail("This folder is already connected. Run `synqit status` or `synqit repair` instead.");
        return;
    }
    if not is_git_root() {
        fail("Run `synqit init` from the root of a cloned GitHub repository.");
        return;
    }
    branch: str = branch_flag or "main";
    changes = working_tree_changes();
    if changes {
        fail("This workspace has " + str(len(changes)) + " local change(s). Start from a fresh clone, then run init again.");
        return;
    }
    branch_now: str = current_branch();
    if branch_now != branch {
        fail("You are on " + (branch_now or "no branch") + ", but Synqit requires " + branch + ". Run `git switch " + branch + "` and try again.");
        return;
    }
    remote_sha: str = "";
    try {
        remote_sha = fetch_branch(branch);
    } except Exception {
        fail("Could not fetch origin/" + branch + ". Check your GitHub remote and internet connection.");
        return;
    }
    if head_sha() != remote_sha {
        fail("This clone is behind GitHub " + branch + ". Run `git pull --ff-only origin " + branch + "`, then retry.");
        return;
    }

    owner_repo: tuple[str, str] = derive_owner_repo();
    owner: str = owner_repo[0];
    repo: str = owner_repo[1];
    repository: str = github_flag or (owner + "/" + repo);
    project: str = project_arg or repository.replace("/", "-");

    step("Connecting " + project + " (" + repository + ") on " + (cfg["base"] as str));
    try {
        created: dict = call_walker(cfg["base"] as str, cfg["token"] as str, "create_project", {
            "name": project, "repository": repository, "branch": branch,
        }, 30) as dict;
        if created.get("status") == "created" {
            ok("created project " + project);
        } else {
            info(gray("    project " + project + " already exists - joining it"));
        }

        step("Seeding project graph from GitHub...");
        call_walker(cfg["base"] as str, cfg["token"] as str, "seed_project", {
            "project": project, "owner": owner, "repo": repo, "branch": branch,
        }, 120);

        status: dict = call_walker(cfg["base"] as str, cfg["token"] as str, "get_project", {"name": project}, 30) as dict;
        head: str = status["head"] as str;
        save_state({
            "project": project, "base": cfg["base"], "branch": branch,
            "baseSha": head, "fileHashes": hashes_for(read_tracked_workspace()),
        });
        ok("initialized " + project + " at " + head[:7]);
    } except Exception as error {
        fail(str(error));
    }
}

def cmd_push(intent_parts: list[str]) {
    cfg = require_session();
    intent: str = " ".join(intent_parts).strip();
    if not intent {
        fail("Describe the feature: synqit push \"Add password validation\"");
        return;
    }
    state = load_state();
    if state is None {
        fail("This folder is not connected. Run `synqit init` first.");
        return;
    }

    snapshot = read_tracked_workspace();
    changes = changed_files(snapshot, state["fileHashes"] as dict);
    if not changes {
        info(gray("Nothing to push - this workspace is already synced."));
        return;
    }

    info(bold("synqit: pushing feature -> " + (state["project"] as str)));
    info(gray("    \"" + intent + "\""));
    base_sha: str = state["baseSha"] as str;
    info(gray("    " + str(len(changes)) + " changed file(s) from " + base_sha[:7]));

    step("Integrating and publishing (this calls an LLM, can take a minute)...");
    try {
        result: dict = call_walker(cfg["base"] as str, cfg["token"] as str, "push", {
            "project": state["project"], "intent": intent, "base_sha": base_sha,
            "changes": changes, "submitter": cfg["username"],
        }, 300) as dict;

        status: str = result.get("status", "") as str;
        if status == "needs_human" {
            fail("Synqit needs a human product decision.");
            if result.get("reason") {
                info(gray("    " + (result["reason"] as str)));
            }
            info(gray("    Your local work is unchanged."));
            return;
        }
        if status == "integration_incomplete" {
            fail("Integration could not be verified as complete after retries.");
            if result.get("reason") {
                info(gray("    " + (result["reason"] as str)));
            }
            info(gray("    Your local work is unchanged. Try a smaller/more specific push."));
            return;
        }
        if status != "published" {
            fail("Unexpected result: " + str(result));
            return;
        }

        try {
            synced_sha: str = sync_to_commit(state["branch"] as str or "main");
            new_state: dict = dict(state);
            new_state["baseSha"] = synced_sha;
            new_state["fileHashes"] = hashes_for(read_tracked_workspace());
            save_state(new_state);
            head: str = result["head"] as str;
            ok("published -> GitHub " + head[:7]);
            info(cyan("    synced this workspace to the new shared main. You are ready for the next feature."));
        } except Exception as sync_error {
            fail("Published to GitHub " + (result["head"] as str)[:7] + ", but this workspace could not sync automatically. Run `synqit repair`. (" + str(sync_error) + ")");
        }
    } except Exception as error {
        fail(str(error));
    }
}

def cmd_status {
    cfg = require_session();
    state = load_state();
    if state is None {
        fail("This folder is not connected. Run `synqit init` first.");
        return;
    }
    changes = changed_files(read_tracked_workspace(), state["fileHashes"] as dict);
    info("Synqit project: " + (state["project"] as str));
    info("  server: " + (state["base"] as str));
    info("  logged in as: " + (cfg["username"] as str));
    info("  local changes ready to push: " + str(len(changes)));
    try {
        proj: dict = call_walker(cfg["base"] as str, cfg["token"] as str, "get_project", {"name": state["project"]}, 30) as dict;
        head: str = proj["head"] as str;
        suffix: str = " (up to date)" if head == state["baseSha"] else " (newer version available - run synqit repair)";
        info("  shared GitHub commit: " + head[:7] + suffix);
    } except Exception as error {
        fail(str(error));
    }
}

def cmd_repair {
    cfg = require_session();
    state = load_state();
    if state is None {
        fail("This folder is not connected. Run `synqit init` first.");
        return;
    }
    step("Restoring this workspace to " + (state["project"] as str));
    try {
        call_walker(cfg["base"] as str, cfg["token"] as str, "get_project", {"name": state["project"]}, 30);
        synced_sha: str = sync_to_commit(state["branch"] as str or "main");
        new_state: dict = dict(state);
        new_state["baseSha"] = synced_sha;
        new_state["fileHashes"] = hashes_for(read_tracked_workspace());
        save_state(new_state);
        ok("restored GitHub " + synced_sha[:7] + " - this workspace is clean and synced");
    } except Exception as error {
        fail(str(error));
    }
}

def cmd_help {
    print(bold("synqit") + " - shared source control without branches, commits, or pulls\n");
    print(bold("Usage"));
    print("  synqit login [--base <url>]      Log in (or create an account) on a Synqit server");
    print("  synqit init [project]            Connect this repo root to Synqit");
    print("  synqit push \"feature intent\"     Submit a feature and sync this workspace");
    print("  synqit status                    Show this workspace's sync state");
    print("  synqit repair                    Restore this workspace to shared GitHub main");
    print("  synqit help                      Show this help\n");
    print(bold("Example"));
    print("  synqit login --base https://synqit.example");
    print("  synqit init hackathon-demo");
    print("  synqit push \"Add password validation\"");
}
