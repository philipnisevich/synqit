# Synqit

Shared source control for teams building in parallel. Developers push a feature
*intent* instead of managing branches, PRs, and merges — an integration agent
folds the change into the current state of the codebase and publishes it
straight to `main`, leaving the developer's workspace already synced.

Built entirely on [Jac](https://www.jac-lang.org/) (Object-Spatial Programming):
the codebase is modeled as a graph of files and their dependencies, and a walker
traverses that graph to scope exactly what an integration needs to see — not the
whole repo, not nothing.

## The CLI is fully local

`synqit` runs entirely on your machine. There is no server to log into, no
account, and no shared deployment in the request path:

```
  read main (local git object store)
      -> build the file graph, walk it for context
      -> integrate with an LLM
      -> git commit + git push
```

Nothing needs to be shared between developers *except git itself*, because
nothing Synqit stores is authoritative — the graph is rebuilt from `main` on
every push. Concurrency is git's: if someone publishes while your integration is
running, the push is rejected, and Synqit re-reads `main` and integrates again
against the new baseline.

Two consequences worth stating plainly:

- **Your API key stays yours.** The integration runs in your process.
- **Publishing uses your own git credentials.** No bot token, no PAT to hand
  around, and commits are authored by you.

## Quickstart

```bash
ln -s "$(pwd)/bin/synqit" /usr/local/bin/synqit   # or anywhere on your PATH
export ANTHROPIC_API_KEY=sk-ant-...

cd ~/code/your-project        # any git repo with an 'origin' remote
synqit status                 # what a push would consider
synqit push "Add password validation"
```

`synqit push` works from intent alone. If you also have local edits, those are
used as the proposal — a strong hint for what to implement, not a literal patch.

| Command | |
|---|---|
| `synqit push "<intent>"` | Make the intent true on the shared branch |
| `synqit status` | How this workspace differs from it |
| `--branch <name>` | Shared branch (default: `main`) |
| `--hops <n>` | Dependency hops of context (default: `2`) |

Your workspace is left at the published commit, so there is no separate pull
step. If anything fails after the working tree is touched, your original edits
are recoverable — Synqit records them with `git stash create` first and prints
the sha.

## Layout

The repo root is also a Jac full-stack app (`jac.toml`, entry `main.jac`) that
serves the hosted dashboard and landing page. That deployment is a *viewer* —
the CLI never calls it.

- `cli/` — the local CLI. `pipeline.jac` is the whole push flow; `commands.jac`
  is presentation only.
- `integrations/local_repo.jac` — every git invocation, in one place.
- `integrations/github.jac` — GitHub API reads, used only by the hosted
  dashboard.
- `walkers/graph_build.jac` — the import scanner and graph builder. Shared by
  both paths, so the local and hosted graphs are identical by construction.
- `walkers/blast_radius.jac` — BFS over `Imports` edges to scope context.
- `walkers/integrate.jac` — the LLM integration loop plus the deterministic
  broken-reference check that verifies its output.
- `nodes.jac` — the graph schema: `Project`, `File`, `PushRequest`, and the
  `Imports` / `Touches` edges.
- `services/`, `components/`, `styles/` — the hosted dashboard and landing page.
- `web/` — a separate Next.js marketing site, not part of the Jac app.

## How context scoping works

A push starts from seed files — the ones you edited, or, for an intent-only
push, the ones whose paths and contents best match the intent's own vocabulary.
From there `blast_radius` walks `Imports` edges outward in both directions
(callers *and* dependencies) up to `--hops`, and only those files become the
LLM's workspace.

This is the part that makes the integration correct rather than merely
plausible: when a change alters a function's contract, its call sites are
already in the workspace, so they get updated in the same pass.

Afterwards a deterministic check diffs exported symbols across every file the
model touched and scans the rest of the workspace for now-dangling references.
If it finds any, the integration is retried with those specific defects named,
and a push that still fails verification is never published.

## Running the dashboard

```bash
jac install
jac start main.jac    # landing page at /, dashboard at /app
```

The dashboard reads the same walkers over its own graph. It needs `GITHUB_TOKEN`
(to read repos it has no checkout of) and `ANTHROPIC_API_KEY`; missing either
degrades that capability instead of taking the app down. See `DEPLOYMENT.md`.

**Distribution note:** the CLI needs `subprocess` and HTTP, which Jac's
native-binary compiler (`nacompile`) doesn't support — so `bin/synqit` is a
shell wrapper around `jac run` rather than a compiled binary. A PyPI-packaged
distribution (`jac bundle`) is the natural next step.
