# Synqit

Shared source control for teams building in parallel. Developers push a feature
intent instead of managing branches, PRs, and merges — an integration agent folds the
change into the current codebase and publishes it straight to GitHub `main`, syncing
the developer back automatically.

Built on [Jac](https://www.jac-lang.org/) (Object-Spatial Programming): the codebase
is modeled as a persistent graph of files and their dependencies, and walkers traverse
that graph to detect real conflicts and scope what an integration needs to see.

## Layout

- `cli/` — thin CLI, installed via `npm install -g`. Sends a diff + feature
  description, syncs the local checkout back on success.
- `jac/` — the integration service. Persistent per-project graph, walkers for
  conflict detection and LLM-driven integration, served via `jac serve`.

Nothing runs yet — early build.
