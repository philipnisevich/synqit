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
  description to the server, syncs the local checkout back on success.
- `bin/synqit` — a thin shell wrapper so `synqit <command>` works as a real
  command instead of typing `jac run cli/synqit.jac <command>` every time.
- `jac/` — the integration service. Persistent per-project graph (files,
  dependency edges), walkers for blast-radius context-scoping and
  LLM-driven integration, served via `jac start`. See `DEPLOYMENT.md` for
  hosting.

## Get the `synqit` command

```bash
ln -s "$(pwd)/bin/synqit" /usr/local/bin/synqit   # or anywhere else on your PATH
```

## One-time server setup

Run once, from the machine that will host the server, from the `jac/` directory:

```bash
cd jac
synqit configure
```

Prompts for a GitHub token (fine-grained, `Contents: read and write`) and an
Anthropic API key, **verifies both against the real GitHub/Anthropic APIs
before saving anything**, and writes `jac/.env`. Refuses to save if either
credential fails verification — so `jac/.env` can never end up holding a
broken token silently. `jac start` auto-loads this file and refuses to boot
at all (clear fatal error, not a mysterious later failure) if either
variable is missing.

## Running the server

```bash
cd jac
jac start main.sv.jac --port 8899 --no_client
```

## Quickstart (developer / CLI side)

```bash
synqit login --base <server-url>      # or http://localhost:8899 for local dev
synqit init [project-name]            # from the root of a clean, up-to-date clone
synqit push "Add password validation"
```

`synqit status` shows sync state; `synqit repair` restores a workspace to
shared `main` if a push's local sync ever fails partway.

**Distribution note:** the CLI needs `subprocess` (for git) and HTTP calls,
which Jac's native-binary compiler (`nacompile`) doesn't support — so
`bin/synqit` is a shell wrapper around `jac run`, not a single compiled
binary the way an npm global install would be. A PyPI-packaged distribution
(`jac bundle`) is the natural next step for a more conventional install, not
yet done.

See `DEPLOYMENT.md` for real (non-local) hosting.
