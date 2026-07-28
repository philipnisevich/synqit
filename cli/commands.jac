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
import time;
import random;
import getpass;

import from env_guard { key_source, has_accountable_key, REPO_ENV_PATH }
import from spinner { Spinner, INTEGRATION_PHRASES }
import from setup_env { verify_anthropic_key, exclude_from_git, write_env_value }
import from pipeline { run_push, preflight, proposed_changes, PushOutcome }
import from integrations.notch {
    NotchConfig, app_binary, app_running, config_path as notch_config_path,
    default_dev_id, install_token, read_config as read_notch_config,
    write_config as notch_write_config,
    attach as notch_attach_bridge, detach as notch_detach_bridge,
    is_attached as notch_is_attached, set_context as notch_set_context,
    ask_developer as notch_ask_developer,
}
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
            + "so the key stays with you.\n"
            + "      Run `synqit configure` to set one up, or export it yourself."
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
    # The spinner may still be running if the pipeline returned straight out of
    # the integration phase. Stopping twice is safe; leaving it running would
    # overwrite the result the developer is waiting to read.
    ACTIVE_SPINNER.stop();
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
        render_paths("you decided:", outcome.decisions);
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
        # The agent reaches this only when it could not ask: no notch attached,
        # or the question went unanswered. Which of the two it was decides what
        # the developer should do next, so say so rather than guessing.
        if read_notch_config() is None {
            info(gray("    No notch is attached, so it had to stop instead of asking you."));
            info(gray("    Run `synqit notch` and push again to be asked in the notch instead."));
        } else {
            info(gray("    The question went unanswered, so nothing was decided."));
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

"""One spinner for the whole push, started when the integration begins and
stopped the moment any other phase reports. Module-level because the pipeline
calls back into show_progress with no object to hang state on."""
glob ACTIVE_SPINNER: Spinner = Spinner();

"""Live phase reporting. The `integrating` phase is the long one - it hands off
to an animated line so the CLI never looks hung. Every other phase is a plain
printed step."""
def show_progress(phase: str, detail: str) {
    ACTIVE_SPINNER.stop();
    if phase == "integrating" {
        ACTIVE_SPINNER.phrases = INTEGRATION_PHRASES;
        ACTIVE_SPINNER.start();
        return;
    }

    # The integration has stopped at something only the developer can settle.
    # Say so in the terminal too: the question is in the notch, but the push is
    # what is holding, and this is where they are looking.
    if phase == "escalation" {
        info("");
        info("  " + bold("?  " + detail));
        info(gray("     answer it in the notch - this push is waiting"));
        return;
    }
    if phase == "decided" {
        ok("you chose: " + detail);
        # Back to work: the agent carries on integrating with that answer.
        ACTIVE_SPINNER.phrases = INTEGRATION_PHRASES;
        ACTIVE_SPINNER.start();
        return;
    }
    if phase == "unanswered" {
        info(gray("     " + detail));
        return;
    }

    step(gray(phase.ljust(12)) + detail);
}

"""Guided local setup: verify a key against the real API, then save it where
the CLI will actually look for it."""
def cmd_configure(key_flag: str | None) {
    if not at_repo_root() {
        fail("Run `synqit configure` from the root of the repository Synqit manages.");
        info(gray("    The key is saved to a .env there, and git-ignored automatically."));
        sys.exit(1);
    }

    key: str = (key_flag or "").strip();
    if not key {
        stream: any = sys.stdout;
        if not stream.isatty() {
            fail("No terminal to prompt on. Pass the key directly: synqit configure --key sk-ant-...");
            sys.exit(1);
        }
        info("");
        info(bold("  synqit configure"));
        info(gray("    Synqit runs the integration on this machine, so the key stays here."));
        info(gray("    Get one at https://console.anthropic.com/settings/keys"));
        info("");
        key = getpass.getpass("  Anthropic API key: ").strip();
    }

    if not key {
        fail("No key entered. Nothing was saved.");
        sys.exit(1);
    }

    step("verifying the key against the Anthropic API");
    problem: str = verify_anthropic_key(key);
    if problem {
        fail(problem);
        info(gray("    Nothing was saved. Fix the key and run `synqit configure` again."));
        sys.exit(1);
    }
    ok("key verified");

    env_path: str = os.path.join(os.getcwd(), ".env");
    # Ignore first, write second: if the write succeeded and the ignore failed,
    # a live key would be sitting in a tracked file waiting to be committed.
    if not exclude_from_git(".env") {
        fail("Could not add .env to .git/info/exclude, so the key was NOT saved.");
        info(gray("    Add `.env` to your .gitignore, then re-run."));
        sys.exit(1);
    }

    write_problem: str = write_env_value(env_path, "ANTHROPIC_API_KEY", key);
    if write_problem {
        fail(write_problem);
        sys.exit(1);
    }

    ok("saved to " + env_path + " (mode 600, git-ignored)");
    info(gray("    Run `synqit doctor` to confirm, then `synqit push \"...\"`."));
    sys.exit(0);
}

"""Attach this machine's notch, or report on the one already attached.

Two files make an attachment: `~/.synqit/config.json`, which both ends read so
they agree on who this developer is, and a token, which the app keeps in the
login keychain rather than on disk. Re-running is the repair path - it rewrites
the config and re-hands the same token to the app."""
def cmd_notch(args: list[str]) {
    subcommand: str = "";
    if args {
        subcommand = args[0];
    }

    if subcommand == "status" {
        cmd_notch_status();
        return;
    }
    if subcommand == "demo" {
        cmd_notch_demo();
        return;
    }
    if subcommand {
        fail("Unknown subcommand '" + subcommand + "'. Try `synqit notch`, `synqit notch status`, or `synqit notch demo`.");
        sys.exit(1);
    }

    dev_id: str = default_dev_id();
    config = notch_write_config(dev_id, "127.0.0.1", 8787);
    ok("attached " + dev_id + " at " + "ws://" + config.host + ":" + str(config.port));
    info(gray("    " + notch_config_path()));

    binary: str = app_binary();
    if not binary {
        fail("The notch app isn't built yet, so it has no token.");
        info(gray("    Build and install it, then run `synqit notch` again:"));
        info("      cd notch && make install");
        sys.exit(1);
    }

    step("storing the token in your login keychain");
    problem: str = install_token(binary, config.token);
    if problem {
        fail(problem);
        sys.exit(1);
    }
    ok("token stored (keychain, never written to disk)");

    if app_running() {
        info(gray("    The notch is running and will reconnect on your next push."));
    } else {
        info(gray("    Launch it, then turn on Launch at login from the menu bar:"));
        info("      open \"/Applications/Synqit Notch.app\"");
    }
    info(gray("    A push that hits a decision only you can make will now ask you."));
    sys.exit(0);
}


def cmd_notch_status {
    found = read_notch_config();
    if found is None {
        fail("No notch attached on this machine.");
        info(gray("    Run `synqit notch` to attach one. Without it, a push that hits a"));
        info(gray("    genuine product conflict stops instead of asking you."));
        sys.exit(1);
    }
    config: NotchConfig = found as NotchConfig;

    info(bold("  synqit notch") + gray("   " + notch_config_path()));
    info("    dev id     " + config.dev_id);
    info("    endpoint   ws://" + config.host + ":" + str(config.port) + gray("  (loopback, opened only during a push)"));

    if config.token {
        info("    token      " + green("set"));
    } else {
        info("    token      " + red("missing") + gray("  - run `synqit notch` to store one"));
    }

    binary: str = app_binary();
    if binary {
        info("    app        " + binary);
    } else {
        info("    app        " + red("not installed") + gray("  - build it with `cd notch && make install`"));
    }

    if app_running() {
        info("    running    " + green("yes"));
    } else {
        info("    running    " + gray("no") + gray("  - open \"/Applications/Synqit Notch.app\""));
    }

    if not config.token or not binary {
        sys.exit(1);
    }
    sys.exit(0);
}


glob NOTCH_DEMO_SCENARIOS: list = [
    {
        "intent": "Give free-tier users unlimited projects",
        "base_sha": "f50e1f3aa11",
        "title": "Free tier removal vs. unlimited free projects",
        "summary": "Your change gives free-tier users unlimited projects, but the free tier was deliberately removed on main.",
        "file": "pricing.js",
        "conflicts_with": "Remove the free tier entirely",
    },
    {
        "intent": "Switch default export format to JSON",
        "base_sha": "9c2ab41d0f3",
        "title": "Default export format: JSON vs. CSV",
        "summary": "Your change makes JSON the default export, but main deliberately switched to CSV for spreadsheet users last week.",
        "file": "exporter.py",
        "conflicts_with": "Make CSV the default export",
    },
    {
        "intent": "Allow guest checkout without an account",
        "base_sha": "12d8e9aa607",
        "title": "Guest checkout vs. mandatory accounts",
        "summary": "Your change allows checkout without an account, but main deliberately requires accounts to cut fraud.",
        "file": "checkout.ts",
        "conflicts_with": "Require an account before checkout",
    },
    {
        "intent": "Retry failed webhooks indefinitely",
        "base_sha": "77aa310bc44",
        "title": "Webhook retries: indefinite vs. capped",
        "summary": "Your change retries failed webhooks forever, but main deliberately caps retries at 5 to protect downstream services.",
        "file": "webhooks.go",
        "conflicts_with": "Cap webhook retries at 5 attempts",
    },
];

"""Fire one randomly chosen escalation at the attached notch, so you can see it
light up without spending a push or an API call."""
def cmd_notch_demo {
    found = read_notch_config();
    if found is None {
        fail("No notch attached on this machine.");
        info(gray("    Run `synqit notch` to attach one, then open the app."));
        sys.exit(1);
    }
    config: NotchConfig = found as NotchConfig;

    opened = notch_attach_bridge();
    if opened.bridge is None {
        note: str = opened.note or "No notch is attached on this machine.";
        fail(note);
        sys.exit(1);
    }

    info(gray("    listening on ws://" + config.host + ":" + str(config.port)));
    step("waiting for " + config.dev_id + "'s notch to attach");

    waited: float = 0.0;
    while not notch_is_attached() and waited < 35.0 {
        time.sleep(0.5);
        waited += 0.5;
    }
    if notch_is_attached() {
        ok("the notch is attached");
    } else {
        info(gray("    nothing attached yet - the question will still be waiting when it connects"));
    }

    scenario: dict = random.choice(NOTCH_DEMO_SCENARIOS);
    info(gray("    scenario: " + scenario["title"]));

    notch_set_context(scenario["intent"], scenario["base_sha"], 1, config.dev_id);

    answer: str = notch_ask_developer(
        title=scenario["title"],
        summary=scenario["summary"],
        file=scenario["file"],
        conflicts_with=scenario["conflicts_with"],
        option_mine="Keep mine",
        option_theirs="Keep theirs",
    );

    info("");
    info(bold("  the agent was told:"));
    info("    " + answer);

    notch_detach_bridge();
    sys.exit(0);
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
        blocking.append("synqit configure");
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
    info("    synqit configure                 Verify and save your Anthropic API key");
    info("    synqit push \"feature intent\"     Make the intent true on the shared branch");
    info("    synqit status                    Show how this workspace differs from it");
    info("    synqit doctor                    Check everything a push needs");
    info("    synqit notch                     Attach the notch that asks you to decide");
    info("    synqit notch status              Show the notch attached to this machine");
    info("    synqit notch demo                Pop up a random test issue in the notch");
    info("    synqit help                      Show this help");
    info("");
    info(bold("  Options"));
    info("    --dry-run                        Show the context and proposal, change nothing");
    info("    --branch <name>                  Shared branch (default: main)");
    info("    --hops <n>                       Dependency hops of context (default: 2)");
    info("    --key <value>                    Non-interactive key for `configure`");
    info("");
    info(bold("  Getting started"));
    info("    cd <your repo> && synqit configure && synqit doctor");
    info(gray("    Everything runs locally; publishing uses your own git credentials."));
    info("");
}
