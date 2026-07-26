# Synqit

Shared source control for teams building in parallel. Developers push a feature
intent instead of managing branches, PRs, and merges — an integration agent folds the
change into the current codebase and publishes it straight to GitHub `main`, syncing
the developer back automatically.

Built entirely on [Jac](https://www.jac-lang.org/) (Object-Spatial Programming),
CLI included: the codebase is modeled as a persistent graph of files and their
dependencies, and walkers traverse that graph to scope exactly what an
integration needs to see — not the whole repo, not nothing.

## Layout

- `cli/` — the developer-facing CLI, written in Jac. Diffs the local
  workspace by hash (no `git diff` needed), sends changed files + a feature
  description to the server, syncs the local checkout back on success. Run
  via `jac run cli/synqit.jac <command>`.
- `jac/` — the integration service. Persistent per-project graph (files,
  dependency edges), walkers for blast-radius context-scoping and
  LLM-driven integration, served via `jac start`. See `DEPLOYMENT.md` for
  hosting.

## Quickstart

```bash
jac run cli/synqit.jac login --base <server-url>   # or http://localhost:8899 for local dev
jac run cli/synqit.jac init [project-name]         # from the root of a clean, up-to-date clone
jac run cli/synqit.jac push "Add password validation"
```

`jac run cli/synqit.jac status` shows sync state; `... repair` restores a
workspace to shared `main` if a push's local sync ever fails partway.

For convenience, alias it: `alias synqit="jac run /path/to/synqit-hack/cli/synqit.jac"`.

**Distribution note:** the CLI needs `subprocess` (for git) and HTTP calls,
which Jac's native-binary compiler (`nacompile`) doesn't support — so this
runs via `jac run`, not as a single installed binary the way an npm global
install would. A PyPI-packaged distribution (`jac bundle`) is the natural
next step if this needs to be installed more conveniently, not yet done.

## Running the server locally

```bash
cd jac
jac start main.sv.jac --port 8899 --no_client
```

Needs `GITHUB_TOKEN` and `ANTHROPIC_API_KEY` in the environment (see
`jac/.env`, gitignored). See `DEPLOYMENT.md` for real deployment.
