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

The repo root **is** the Jac app (`jac.toml`, entry point `main.jac`) — one
project that serves the web UI and the REST API the CLI drives from a single
process.

- `main.jac` — entry point. Server imports register the endpoints; the
  `cl { }` block mounts the browser app.
- `nodes.jac` — the graph schema: `Project`, `File`, `PushRequest`, and the
  `Imports` / `Touches` edges.
- `walkers/` — the integration service. Blast-radius context-scoping,
  LLM-driven integration, GitHub publishing. Each walker is exposed at
  `POST /walker/<name>` for the CLI.
- `integrations/github.jac` — GitHub Git Data API calls.
- `services/synqitService.sv.jac` — server bootstrap plus the `def:pub`
  functions the browser calls at `POST /function/<name>`. Thin wrappers over
  the same `do_*` functions the walkers use, so UI and CLI cannot drift.
- `components/`, `lib/`, `styles/` — the web UI (Jac client components).
- `cli/` — the developer-facing CLI, written in Jac. Diffs the local
  workspace by hash (no `git diff` needed), sends changed files + a feature
  description to the server, syncs the local checkout back on success.
- `bin/synqit` — a thin shell wrapper so `synqit <command>` works as a real
  command instead of typing `jac run cli/synqit.jac <command>` every time.
- `web/` — a separate Next.js marketing site, not part of the Jac app.

See `DEPLOYMENT.md` for hosting.

## Get the `synqit` command

```bash
ln -s "$(pwd)/bin/synqit" /usr/local/bin/synqit   # or anywhere else on your PATH
```

## One-time server setup

Run once, from the machine that will host the server, from the repo root:

```bash
synqit configure
```

Prompts for a GitHub token (fine-grained, `Contents: read and write`) and an
Anthropic API key, **verifies both against the real GitHub/Anthropic APIs
before saving anything**, and writes `.env` at the repo root. Refuses to save if either
credential fails verification — so `.env` can never end up holding a broken
token silently. `jac start` auto-loads this file.

If a credential is missing the server still boots and the UI still works —
it warns loudly and the capabilities that need that credential (seed,
integrate, publish) return a clear "server not configured" error naming the
variable. A missing secret degrades one feature instead of taking down the
whole deployment.

## Running the server

```bash
jac install          # once, to pull Python + npm dependencies
jac start main.jac   # serves the UI at / and the API on the same port (8000)
```

Add `--no_client` to skip the browser bundle and run headless (API only).

## Quickstart (developer / CLI side)

```bash
synqit login --base <server-url>      # or http://localhost:8000 for local dev
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
