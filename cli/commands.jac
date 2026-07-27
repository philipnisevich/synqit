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

import from pipeline { run_push, preflight, proposed_changes, PushOutcome }
import from integrations.local_repo {
    at_repo_root, current_branch, derive_owner_repo, fetch_branch, has_remote,
    snapshot_at_ref, snapshot_worktree,
}
import from ui { bold, gray, green, step, ok, info, fail }

glob DEFAULT_BRANCH: str = "main";

"""byLLM reads the key at call time, not import time, so without this check a
missing key surfaces as a stack trace from inside the integration instead of a
one-line CLI error."""
def missing_api_key -> str {
    if not os.environ.get("ANTHROPIC_API_KEY") {
        return (
            "ANTHROPIC_API_KEY is not set. Synqit runs the integration on your "
            + "machine, so the key stays with you: export ANTHROPIC_API_KEY=sk-ant-..."
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

def cmd_push(args: list[str], branch_flag: str | None, hops_flag: str | None) {
    intent: str = " ".join([a for a in args if a]).strip();
    if not intent {
        fail("Describe what you want to be true, e.g. synqit push \"Add password validation\".");
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

    step("integrating against " + branch + " - this runs an LLM and may take a moment");
    outcome = run_push(intent=intent, branch=branch, submitter="", max_hops=max_hops);
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

def cmd_help {
    info("");
    info(bold("  synqit") + gray(" - shared source control without branches, commits, or pulls"));
    info("");
    info(bold("  Usage"));
    info("    synqit push \"feature intent\"     Make the intent true on the shared branch");
    info("    synqit status                    Show how this workspace differs from it");
    info("    synqit help                      Show this help");
    info("");
    info(bold("  Options"));
    info("    --branch <name>                  Shared branch (default: main)");
    info("    --hops <n>                       Dependency hops of context (default: 2)");
    info("");
    info(bold("  Setup"));
    info("    export ANTHROPIC_API_KEY=sk-ant-...");
    info(gray("    Everything runs locally; publishing uses your own git credentials."));
    info("");
}
