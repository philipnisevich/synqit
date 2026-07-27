"""The `synqit` commands.

Everything runs on this machine. There is no server to log into, no account to
create, and no API key handed to anyone else - the only credentials involved are
the developer's existing git access and an ANTHROPIC_API_KEY that never leaves
their environment.

Each command is a thin shell over cli.pipeline: validate, call, render. Putting
decisions here rather than in the pipeline would place logic outside the part
the hosted dashboard shares, which is exactly how the two would drift.
"""

import os;
import sys;

import from env_guard { key_source, has_accountable_key, REPO_ENV_PATH }
import from pipeline { run_push, preflight, proposed_changes, PushOutcome }
import from integrations.local_repo {
    at_repo_root, current_branch, derive_owner_repo, fetch_branch, has_remote,
    repo_root, run_git, snapshot_at_ref, snapshot_worktree,
}
import from ui { bold, gray, green, red, step, ok, info, fail }

glob DEFAULT_BRANCH: str = "main";

"""The key check, phrased around where the key came from rather than merely
whether one exists - see cli/env_guard.jac for why 'exists' is not a question
that can be answered honestly after byLLM has been imported."""
def missing_api_key -> str {
    source: str = key_source();
    if source == "none" {
        return (
            "No ANTHROPIC_API_KEY. Synqit runs the integration on your machine, "
            + "so the key stays with you:\n"
            + "      export ANTHROPIC_API_KEY=sk-ant-...\n"
            + "    or put it in a .env file in this repository."
        );
    }
    return "";
}

"""An 'external' key works but was found by byLLM in a file we did not choose,
which may not be the account the developer means to bill. Worth one line of
output, not a refusal."""
def key_warning -> str {
    if key_source() == "external" {
        return (
            "Using an ANTHROPIC_API_KEY discovered outside this repository. "
            + "Export one explicitly if that is not the account you meant."
        );
    }
    return "";
}

def render_paths(label: str, paths: list[str]) {
    if not paths {
        return;
    }
    info(gray("    " + label));
    for path in paths {
        info("      " + path);
    }
}

"""Turn a PushOutcome into output plus an exit code. Every non-published status
names an explicit next step - a failed push should never leave someone guessing
what to do, least of all about work that is recoverable but not obvious."""
def report(outcome: PushOutcome, branch: str) -> int {
    status: str = outcome.status;

    for warning in outcome.warnings {
        info(gray("  !  " + warning));
    }

    if status == "dry_run" {
        ok("dry run complete - nothing was committed");
        info(gray("    " + str(len(outcome.context_files)) + " file(s) would be the integration's workspace:"));
        for path in outcome.context_files {
            info("      " + path);
        }
        if outcome.files_touched {
            info(gray("    your local edits used as the proposal:"));
            for path in outcome.files_touched {
                info("      " + path);
            }
        }
        info(gray("    Re-run without --dry-run to integrate and publish."));
        return 0;
    }

    if status == "published" {
        ok("published to " + branch + " at " + outcome.head[:7]);
        if outcome.summary {
            info(gray("    " + outcome.summary));
        }
        render_paths("changed:", outcome.files_touched);
        render_paths("deleted:", outcome.files_deleted);
        if outcome.attempts > 1 {
            info(gray("    took " + str(outcome.attempts) + " attempts - " + branch + " moved while integrating"));
        }
        info(gray("    This workspace is already at that commit."));
        return 0;
    }

    if status == "needs_human" {
        fail("This intent conflicts with what the codebase already does.");
        if outcome.message {
            info(gray("    " + outcome.message));
        }
        info(gray("    Nothing was committed. Adjust the intent and try again."));
        return 2;
    }

    if status == "integration_incomplete" {
        fail("The integration left broken references behind, so nothing was published.");
        if outcome.message {
            info(gray("    " + outcome.message));
        }
        info(gray("    Try a smaller, more specific intent."));
        return 2;
    }

    if status == "no_changes" {
        fail(outcome.message or "Nothing to publish.");
        return 1;
    }

    fail(outcome.message or "Push failed.");
    if outcome.recovery_sha {
        info(gray("    Your original edits were saved before this ran. Restore them with:"));
        info(gray("      git stash apply " + outcome.recovery_sha));
    }
    return 1;
}

def parse_hops(hops_flag: str | None) -> int {
    if not hops_flag {
        return 2;
    }
    try {
        value: int = int(hops_flag);
    } except ValueError {
        raise Exception("--hops must be a whole number.");
    }
    if value < 0 {
        raise Exception("--hops cannot be negative.");
    }
    return value;
}

"""Live phase reporting. An integration can take the better part of a minute
and a retry doubles it, so silence reads as a hang."""
def show_progress(phase: str, detail: str) {
    step(gray(phase.ljust(12)) + detail);
}

def cmd_push(args: list[str], branch_flag: str | None, hops_flag: str | None, dry_run: bool) {
    intent: str = " ".join([a for a in args if a]).strip();
    if not intent {
        fail("Describe what you want to be true, e.g. synqit push \"Add password validation\".");
        info(gray("    Run `synqit doctor` if you are not sure this repo is set up."));
        sys.exit(1);
    }

    blocked: str = missing_api_key();
    if blocked {
        fail(blocked);
        sys.exit(1);
    }

    branch: str = branch_flag or DEFAULT_BRANCH;
    max_hops: int = 2;
    try {
        max_hops = parse_hops(hops_flag);
    } except Exception as error {
        fail(str(error));
        sys.exit(1);
    }

    warning: str = key_warning();
    if warning {
        info(gray("  !  " + warning));
    }

    if dry_run {
        info(gray("  -- dry run: nothing will be committed or pushed --"));
    }

    outcome = run_push(
        intent=intent,
        branch=branch,
        submitter="",
        max_hops=max_hops,
        dry_run=dry_run,
        progress=show_progress,
    );
    sys.exit(report(outcome, branch));
}

"""Read-only view of exactly what a push would consider: how this workspace
differs from the shared branch, and anything that would block publishing."""
def cmd_status(branch_flag: str | None) {
    branch: str = branch_flag or DEFAULT_BRANCH;

    if not at_repo_root() {
        fail("Run this from the root of a git repository.");
        sys.exit(1);
    }

    owner_repo: tuple[str, str] = derive_owner_repo();
    info(bold("  " + owner_repo[0] + "/" + owner_repo[1]) + gray("   shared branch: " + branch));

    if not has_remote("origin") {
        fail("No 'origin' remote - Synqit publishes through it.");
        sys.exit(1);
    }

    head: str = "";
    try {
        head = fetch_branch(branch);
    } except Exception as error {
        fail(str(error));
        sys.exit(1);
    }

    on: str = current_branch();
    if on != branch {
        info(gray("    on " + (on or "detached HEAD") + " - Synqit publishes to " + branch));
    }

    baseline: dict[str, str] = snapshot_at_ref(head);
    worktree: dict[str, str] = snapshot_worktree();
    changes = proposed_changes(baseline, worktree);

    info(gray("    " + branch + " is at " + head[:7] + " (" + str(len(baseline)) + " text files)"));

    if not changes {
        info(green("    workspace matches " + branch + " - a push would work from intent alone"));
    } else {
        info(gray("    " + str(len(changes)) + " local change(s) a push would use as its proposal:"));
        for change in changes {
            label: str = (change["change_type"] as str).ljust(8);
            info("      " + label + " " + (change["path"] as str));
        }
    }

    key_warning: str = missing_api_key();
    if key_warning {
        info(gray("    ANTHROPIC_API_KEY is not set - `synqit push` will not run"));
    }

    blocked: str = preflight(branch);
    if blocked {
        info(gray("    blocked: " + blocked));
    }
    sys.exit(0);
}

def check_line(label: str, passed: bool, detail: str) -> bool {
    marker: str = green("  [ok] ") if passed else red("  [x]  ");
    info(marker + label.ljust(22) + gray(detail));
    return passed;
}

"""Diagnose every prerequisite at once, so a failure is found here rather than
halfway through an integration. Exits non-zero if anything would block a push,
which also makes it usable as a setup check in CI or a install script."""
def cmd_doctor(branch_flag: str | None) {
    branch: str = branch_flag or DEFAULT_BRANCH;
    info("");
    info(bold("  synqit doctor"));
    info("");

    blocking: list[str] = [];

    git_probe = run_git(["--version"]);
    if not check_line("git", git_probe["code"] == 0, (git_probe["out"] as str).strip() or "not found") {
        blocking.append("Install git.");
    }

    in_repo: bool = at_repo_root();
    repo_detail: str = "";
    if in_repo {
        repo_detail = repo_root();
    } else {
        try {
            repo_detail = "inside " + repo_root() + " - run from its root";
        } except Exception {
            repo_detail = "not a git repository";
        }
    }
    if not check_line("repository root", in_repo, repo_detail) {
        blocking.append("Run synqit from the root of the repository it manages.");
    }

    if in_repo {
        remote_ok: bool = has_remote("origin");
        remote_url: str = "";
        if remote_ok {
            remote_url = (run_git(["remote", "get-url", "origin"])["out"] as str).strip();
        }
        if not check_line("origin remote", remote_ok, remote_url or "missing") {
            blocking.append("Add an 'origin' remote - Synqit publishes through it.");
        }

        on: str = current_branch();
        if not check_line("on " + branch, on == branch, "currently " + (on or "detached HEAD")) {
            blocking.append("git switch " + branch);
        }

        reachable: bool = True;
        detail: str = "";
        try {
            detail = fetch_branch(branch)[:7];
        } except Exception as error {
            reachable = False;
            detail = str(error)[:70];
        }
        if not check_line("can fetch " + branch, reachable, detail) {
            blocking.append("Check network access and push permission on this remote.");
        }
    }

    source: str = key_source();
    key_detail: str = {
        "environment": "from your environment",
        "repo-dotenv": "from " + REPO_ENV_PATH,
        "external": "found outside this repo - export one explicitly",
        "none": "not set",
    }.get(source, source) as str;
    if not check_line("ANTHROPIC_API_KEY", source != "none", key_detail) {
        blocking.append("export ANTHROPIC_API_KEY=sk-ant-...");
    }

    info("");
    if blocking {
        fail(str(len(blocking)) + " thing(s) to fix before `synqit push` will work:");
        for item in blocking {
            info(gray("      - " + item));
        }
        info("");
        sys.exit(1);
    }
    ok("ready to push");
    if key_source() == "external" {
        info(gray("    " + key_warning()));
    }
    info("");
    sys.exit(0);
}

def cmd_help {
    info("");
    info(bold("  synqit") + gray(" - shared source control without branches, commits, or pulls"));
    info("");
    info(bold("  Usage"));
    info("    synqit push \"feature intent\"     Make the intent true on the shared branch");
    info("    synqit status                    Show how this workspace differs from it");
    info("    synqit doctor                    Check everything a push needs");
    info("    synqit help                      Show this help");
    info("");
    info(bold("  Options"));
    info("    --dry-run                        Show the context and proposal, change nothing");
    info("    --branch <name>                  Shared branch (default: main)");
    info("    --hops <n>                       Dependency hops of context (default: 2)");
    info("");
    info(bold("  Setup"));
    info("    export ANTHROPIC_API_KEY=sk-ant-...");
    info(gray("    Everything runs locally; publishing uses your own git credentials."));
    info(gray("    Run `synqit doctor` first - it names anything that would block a push."));
    info("");
}
