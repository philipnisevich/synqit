# Synqit

Shared source control for teams building in parallel. Developers push a feature
intent instead of managing branches, PRs, and merges — an integration agent folds the
change into the current codebase and publishes it straight to GitHub `main`, syncing
the developer back automatically.

Built on [Jac](https://www.jac-lang.org/) (Object-Spatial Programming): the codebase
is modeled as a persistent graph of files and their dependencies, and walkers traverse
that graph to scope exactly what an integration needs to see — not the whole repo,
not nothing.

## Layout

- `cli/` — thin Node CLI, installed via `npm install -g`. Diffs the local
  workspace by hash, sends changed files + a feature description, syncs the
  local checkout back on success. No graph logic, no LLM calls here.
- `jac/` — the integration service. Persistent per-project graph (files,
  dependency edges), walkers for blast-radius context-scoping and
  LLM-driven integration, served via `jac start`. See `DEPLOYMENT.md` for
  hosting.

## Quickstart

```bash
npm install -g .
synqit login --base <server-url>      # or http://localhost:8899 for local dev
synqit init [project-name]            # from the root of a clean, up-to-date clone
synqit push "Add password validation"
```

`synqit status` shows sync state; `synqit repair` restores a workspace to
shared `main` if a push's local sync ever fails partway.

## Running the server locally

```bash
cd jac
jac start main.sv.jac --port 8899 --no_client
```

Needs `GITHUB_TOKEN` and `ANTHROPIC_API_KEY` in the environment (see
`jac/.env`, gitignored). See `DEPLOYMENT.md` for real deployment.
