"""The local push pipeline: intent in, commit on the shared branch out.

This is the server's `walker push` chain reimplemented against the developer's
own machine - and it reuses the exact same integration core (compute_blast_radius
and do_integrate), so there is one implementation of the part that matters and
no chance of the local and hosted paths diverging in behaviour.

What changes locally is only the edges of the pipeline:

  source    GitHub tree API   ->  local git object store
  sink      GitHub commit API ->  git commit + git push
  identity  server JWT        ->  the developer's own git credentials

Concurrency is unchanged, because it was never the server's to own: git rejects
a non-fast-forward push, and a rejection simply means the branch moved while we
were integrating. The retry loop below re-reads the branch and integrates again
against the new baseline, which is the correct resolution and the same one the
hosted path relies on.

The working tree is reset before the integration is applied, so that the commit
is exactly `baseline + integration` and never picks up unrelated local edits.
That reset is why every path through this module records a stash snapshot first.
"""

import from datetime { datetime, timezone }

import from nodes { Project, File, PushRequest, Touches }
import from walkers.blast_radius { compute_blast_radius, BlastFile }
import from walkers.integrate { do_integrate }
import from walkers.seed_project { do_seed_project_local }
import from integrations.local_repo {
    apply_changes, at_repo_root, commit_all, current_branch, derive_owner_repo,
    fetch_branch, git_identity, has_remote, ignore_local_artifacts, reset_to,
    snapshot_at_ref, snapshot_worktree, stash_snapshot, try_push,
}

glob MAX_PUBLISH_ATTEMPTS: int = 3;

obj PushOutcome {
    has status: str;
    has message: str = "";
    has summary: str = "";
    has head: str = "";
    has files_touched: list[str] = [];
    has files_deleted: list[str] = [];
    has context_files: list[str] = [];
    has recovery_sha: str = "";
    has attempts: int = 0;
}

"""Fail fast on the things that make a push meaningless, with a message that
says what to do rather than what went wrong."""
def preflight(branch: str) -> str {
    if not at_repo_root() {
        return "Run this from the root of the repository Synqit manages.";
    }
    if not has_remote("origin") {
        return "This repository has no 'origin' remote. Synqit publishes through it.";
    }
    on: str = current_branch();
    if not on {
        return "You are not on a branch (detached HEAD). Run `git switch " + branch + "` first.";
    }
    if on != branch {
        return "You are on " + on + ", but Synqit publishes to " + branch + ". Run `git switch " + branch + "`.";
    }
    return "";
}

"""Get or create the local Project node. Local graphs are single-user, so this
hangs off `root` directly rather than the hosted graph's `root.shared`."""
def ensure_project(project_name: str, repository: str, branch: str) -> Project {
    existing = [root -->[?:Project, name == project_name]];
    if existing {
        proj = existing[0];
        proj.repository = repository;
        proj.branch = branch;
        return proj;
    }
    return (root ++> Project(
        name=project_name,
        repository=repository,
        branch=branch,
        created_at=datetime.now(timezone.utc).isoformat(),
    ))[0];
}

"""The developer's proposal: every tracked path whose working-tree content
differs from the shared baseline. This replaces the CLI's old hash-state file -
git already knows what changed, so persisting our own copy of that was just a
second source of truth to keep in sync."""
def proposed_changes(baseline: dict[str, str], worktree: dict[str, str]) -> list[dict] {
    changes: list[dict] = [];
    for path in sorted(set(baseline.keys()) | set(worktree.keys())) {
        before = baseline.get(path);
        after = worktree.get(path);
        if before == after {
            continue;
        }
        if after is None {
            changes.append({"path": path, "change_type": "deleted"});
        } else {
            changes.append({
                "path": path,
                "content": after,
                "change_type": "modified" if before is not None else "added",
            });
        }
    }
    return changes;
}

glob SEED_STOPWORDS: set[str] = {
    "add", "and", "the", "for", "with", "that", "this", "from", "into", "when",
    "make", "them", "then", "than", "should", "must", "will", "have", "has",
    "using", "use", "also", "each", "every", "only", "not", "but", "its",
    "it's", "their", "there", "where", "which", "while", "after", "before",
};
glob MAX_SEED_FILES: int = 8;
glob MAX_FALLBACK_FILES: int = 40;

"""Words in the intent worth matching against the codebase."""
def intent_terms(intent: str) -> list[str] {
    import re;
    terms: list[str] = [];
    for match in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", intent.lower()) {
        raw: str = match as str;
        if len(raw) < 4 or raw in SEED_STOPWORDS or raw in terms {
            continue;
        }
        terms.append(raw);
    }
    return terms;
}

"""Highest score first, then path alphabetically. Negating the score gives a
descending sort on it while leaving the path ascending, in one pass."""
def seed_rank(pair: tuple[int, str]) -> tuple[int, str] {
    return (-(pair[0] as int), pair[1] as str);
}

"""Pick starting files for an intent-only push.

A push with local edits seeds the graph walk from those edits. A push that is
pure intent has no such anchor, and starting from nothing hands the LLM an
empty workspace - it then invents new files instead of changing the ones that
already exist. So match the intent's own vocabulary against paths and contents,
and expand outward from the best hits.

Path matches outweigh content matches: a file literally named for the thing
being changed is a far stronger signal than one that merely mentions the word.
Falls back to the whole (capped) repo rather than returning nothing, because
too much context degrades an integration while no context breaks it.
"""
def select_seed_files(snapshot: dict[str, str], intent: str) -> list[str] {
    terms: list[str] = intent_terms(intent);
    if not terms {
        return sorted(snapshot.keys())[:MAX_FALLBACK_FILES];
    }

    scored: list[tuple[int, str]] = [];
    for path in snapshot.keys() {
        lowered_path: str = path.lower();
        lowered_content: str = snapshot[path].lower();
        score: int = 0;
        for term in terms {
            if term in lowered_path {
                score += 3;
            }
            if term in lowered_content {
                score += 1;
            }
        }
        if score > 0 {
            scored.append((score, path));
        }
    }

    if not scored {
        return sorted(snapshot.keys())[:MAX_FALLBACK_FILES];
    }

    # Sort by score descending, then path, so the choice is stable and
    # reproducible across runs rather than dependent on dict ordering.
    scored.sort(key=seed_rank);
    return [(pair[1] as str) for pair in scored[:MAX_SEED_FILES]];
}

"""Record the push in the local graph and wire Touches edges to its seed files -
this is what compute_blast_radius expands outward from. `seed_paths` is the
developer's changed files when they have any, and intent-matched files when
they don't."""
def record_push(proj: Project, intent: str, base_sha: str, changes: list[dict], seed_paths: list[str], submitter: str) -> PushRequest {
    push = (proj ++> PushRequest(
        intent=intent,
        base_sha=base_sha,
        changes=changes,
        submitter=submitter,
        created_at=datetime.now(timezone.utc).isoformat(),
    ))[0];

    change_types: dict[str, str] = {};
    for change in changes {
        change_types[change["path"] as str] = change.get("change_type", "modified") as str;
    }

    for target_path in seed_paths {
        existing = [proj -->[?:File, path == target_path]];
        file_node: File;
        if existing {
            file_node = existing[0];
        } else {
            file_node = (proj ++> File(path=target_path))[0];
        }
        # An intent-seeded file is context, not a claimed edit - only files the
        # developer actually changed carry a real change_type.
        push +>:Touches(change_type=change_types.get(target_path, "context")):+> file_node;
    }
    return push;
}

"""Everything the integration decided, as a path -> content-or-None map ready
for the working tree."""
def integration_changes(proj: Project, push: PushRequest) -> dict[str, str | None] {
    changes: dict[str, str | None] = {};
    for touched_path in push.touched_paths {
        found = [proj -->[?:File, path == touched_path]];
        if found {
            changes[touched_path] = found[0].content;
        }
    }
    for deleted_path in push.deleted_paths {
        changes[deleted_path] = None;
    }
    return changes;
}

"""One integrate-and-publish attempt against the current shared baseline.

Returns a PushOutcome whose status is one of: published, needs_human,
integration_incomplete, no_changes, rejected (branch moved - caller retries),
or error.
"""
def attempt(project: str, intent: str, branch: str, submitter: str, max_hops: int, recovery_sha: str) -> PushOutcome {
    seeded = do_seed_project_local(project, branch);
    if "error" in seeded {
        return PushOutcome(
            status="error",
            message=(seeded.get("message") or seeded["error"]) as str,
            recovery_sha=recovery_sha,
        );
    }

    base_sha: str = seeded["head"] as str;
    proj = [root -->[?:Project, name == project]][0];

    baseline: dict[str, str] = snapshot_at_ref(base_sha);
    worktree: dict[str, str] = snapshot_worktree();
    changes: list[dict] = proposed_changes(baseline, worktree);

    # Local edits are the strongest possible anchor for the graph walk. With
    # none, fall back to matching the intent's own words against the codebase -
    # anything is better than starting the traversal from an empty set.
    seed_paths: list[str] = [change["path"] as str for change in changes];
    if not seed_paths {
        seed_paths = select_seed_files(baseline, intent);
    }
    if not seed_paths {
        return PushOutcome(
            status="error",
            message="Could not find anywhere in this repository to start from.",
            recovery_sha=recovery_sha,
        );
    }

    push = record_push(proj, intent, base_sha, changes, seed_paths, submitter);

    context: list[BlastFile] = compute_blast_radius(jid(push), max_hops);
    context_paths: list[str] = [f.path for f in context];

    result = do_integrate(jid(push), max_hops);

    if "error" in result {
        return PushOutcome(
            status="error",
            message=(result.get("message") or result["error"]) as str,
            context_files=context_paths,
            recovery_sha=recovery_sha,
        );
    }

    status: str = result["status"] as str;
    if status != "integrated" {
        return PushOutcome(
            status=status,
            message=(result.get("reason") or "") as str,
            context_files=context_paths,
            recovery_sha=recovery_sha,
        );
    }

    to_apply: dict[str, str | None] = integration_changes(proj, push);
    if not to_apply {
        return PushOutcome(
            status="no_changes",
            message="The integration reported success but changed no files.",
            context_files=context_paths,
            recovery_sha=recovery_sha,
        );
    }

    # From here the working tree is rewritten. Everything above was read-only,
    # and recovery_sha holds the developer's original state either way.
    reset_to(base_sha);
    apply_changes(to_apply);

    identity: tuple[str, str] = git_identity();
    message: str = "synqit: " + ((push.summary or intent).strip() or intent);
    new_head = commit_all(message, identity[0], identity[1]);
    if new_head is None {
        reset_to(base_sha);
        return PushOutcome(
            status="no_changes",
            message="The integration produced no net change against " + branch + ".",
            context_files=context_paths,
            recovery_sha=recovery_sha,
        );
    }

    pushed = try_push(branch);
    if pushed["ok"] {
        push.status = "published";
        proj.head = new_head as str;
        return PushOutcome(
            status="published",
            summary=push.summary,
            head=new_head as str,
            files_touched=push.touched_paths,
            files_deleted=push.deleted_paths,
            context_files=context_paths,
            recovery_sha=recovery_sha,
        );
    }

    # The shared branch moved underneath us. Unwind this attempt completely so
    # the retry integrates against the new baseline rather than stacking on a
    # commit the remote never accepted.
    reset_to(base_sha);
    if pushed["rejected"] {
        return PushOutcome(status="rejected", context_files=context_paths, recovery_sha=recovery_sha);
    }
    return PushOutcome(
        status="error",
        message="git push failed: " + (pushed["detail"] as str),
        context_files=context_paths,
        recovery_sha=recovery_sha,
    );
}

"""Run the full local pipeline, retrying when the shared branch moves.

A rejection is not an error: it means someone else published first, which is
the normal case Synqit exists to handle. Each retry re-reads the branch, so the
integration is always made against what `main` actually is right now.
"""
def run_push(intent: str, branch: str = "main", submitter: str = "", max_hops: int = 2) -> PushOutcome {
    if not (intent or "").strip() {
        return PushOutcome(status="error", message="A feature intent is required.");
    }

    blocked: str = preflight(branch);
    if blocked {
        return PushOutcome(status="error", message=blocked);
    }

    ignore_local_artifacts();

    try {
        fetch_branch(branch);
    } except Exception as error {
        return PushOutcome(status="error", message=str(error));
    }

    owner_repo: tuple[str, str] = derive_owner_repo();
    repository: str = owner_repo[0] + "/" + owner_repo[1];
    project: str = repository.replace("/", "-");
    ensure_project(project, repository, branch);

    recovery = stash_snapshot();
    recovery_sha: str = (recovery or "") as str;

    outcome = PushOutcome(status="error", message="Push did not run.");
    attempt_number: int = 0;
    while attempt_number < MAX_PUBLISH_ATTEMPTS {
        attempt_number += 1;
        outcome = attempt(project, intent, branch, submitter, max_hops, recovery_sha);
        outcome.attempts = attempt_number;
        if outcome.status != "rejected" {
            return outcome;
        }
    }

    outcome.status = "error";
    outcome.message = (
        branch + " kept moving while integrating (" + str(MAX_PUBLISH_ATTEMPTS)
        + " attempts). Someone is publishing rapidly - try again in a moment."
    );
    return outcome;
}
