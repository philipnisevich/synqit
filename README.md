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
git clone https://github.com/philipnisevich/synqit.git
cd synqit && ./install.sh          # symlinks `synqit` onto your PATH

cd ~/code/your-project             # any git repo with an 'origin' remote
synqit configure                   # verifies your key, then saves it
synqit doctor                      # check everything a push needs
synqit push --dry-run "Add password validation"
synqit push "Add password validation"
```

`synqit configure` checks the key against the real Anthropic API **before**
writing anything, saves it to a `.env` at mode 600, and adds that file to
`.git/info/exclude` first — so a verified key never lands in a committable
file, and a typo'd one is never saved at all.

`install.sh` links rather than copies, so `git pull` updates the command. It
also warns if another `synqit` earlier on your PATH would shadow it.

**Start with `synqit doctor`.** It checks git, the repository root, the remote,
your branch, fetch access, and the API key — and prints the exact command to fix
anything that would block a push.

`synqit push` works from intent alone. If you also have local edits, those are
used as the proposal — a strong hint for what to implement, not a literal patch.

| Command | |
|---|---|
| `synqit configure` | Verify and save your Anthropic API key |
| `synqit push "<intent>"` | Make the intent true on the shared branch |
| `synqit status` | How this workspace differs from it |
| `synqit doctor` | Check everything a push needs |
| `synqit notch` | Attach the notch that asks you to decide |
| `synqit notch status` | Show the notch attached to this machine |
| `synqit notch demo` | Pop up a random test issue in the notch |
| `--dry-run` | Show the context and proposal, change nothing |
| `--branch <name>` | Shared branch (default: `main`) |
| `--hops <n>` | Dependency hops of context (default: `2`) |
| `--key <value>` | Non-interactive key for `configure` |

### Where your API key comes from

Precedence is explicit, and `synqit doctor` always tells you which applied:

1. `ANTHROPIC_API_KEY` exported in your environment
2. a `.env` in the repository you are running against (what `configure` writes)
3. otherwise byLLM may discover one elsewhere on the machine — this works, but
   Synqit warns, because it may not be the account you meant to bill

This matters more than it looks. Constructing byLLM's `Model` writes the key
into the environment at *import* time, so any check written after that import
passes unconditionally. `cli/env_guard.jac` is imported first, before the
integration, specifically so it observes the environment as you left it.

Your workspace is left at the published commit, so there is no separate pull
step. If anything fails after the working tree is touched, your original edits
are recoverable — Synqit records them with `git stash create` first and prints
the sha.

## When the agent can't decide: the notch

Most conflicts have a right answer the agent can work out by reading the code.
Some don't. If your intent and what `main` already does are both coherent but
mutually exclusive — you want unlimited free projects, the free tier was
deliberately removed last week — then no amount of context resolves it. That is
a product decision, and it belongs to you.

So the agent stops and asks, in your Mac's notch:

```
  ?  Free tier removal vs. unlimited free projects
     answer it in the notch - this push is waiting
```

Answering it is not the end of the push. Your choice comes back as the result of
the agent's own tool call, and the *same* integration carries on with it —
`ask_developer` is a suspend, not an exit. A conflict becomes a question, not a
rejected push.

```
synqit push ──> blast radius ──> integration agent ──┐
                                    │  ▲             │
                        ask_developer│  │your answer  │ complete
                                    ▼  │             ▼
                              Synqit Notch      git commit + push
```

The macOS app is [ben564885/notchh](https://github.com/ben564885/notchh),
vendored unchanged in `notch/`. It speaks the same `escalation` / `resolution` /
`withdraw` wire contract it always did — the difference is what sits on the other
end. Synqit has no server, so the thing the notch connects to is the push itself:
`integrations/notch.jac` opens a WebSocket on `127.0.0.1` for exactly as long as
a push runs, and closes it on the way out.

### Attaching it

```bash
cd notch && make install     # builds the .app, copies it to /Applications
cd .. && synqit notch        # writes ~/.synqit/config.json, stores a token
open "/Applications/Synqit Notch.app"
```

`synqit notch` provisions both ends from one file so they cannot disagree about
who you are, and hands the app a token on **stdin** — it goes to your login
keychain, never to disk or your shell history. Check it took with `synqit notch
status`. Turn on **Launch at login** from the menu-bar item and you are done.

See the surface without spending a push or an API call:

```bash
jac run tools/notch_demo.jac
```

### What it does when nobody answers

Not answering is safe, and it is the same outcome as never attaching a notch at
all: after five minutes (`SYNQIT_DECISION_TIMEOUT`) the question withdraws
itself, the push ends as `needs_human`, and **nothing is committed** — your
local work is untouched either way. The agent is told no answer was available
and stops; it is never told to pick a side.

Three properties worth stating plainly, because they are what make this safe to
put in front of a model:

- **The bridge never decides anything.** It carries a question and returns an
  answer. Every `needs_human` is the *absence* of a decision, never one the code
  invented.
- **Loopback is still authenticated.** Binding to `127.0.0.1` keeps other
  machines out, not other processes on this one.
- **Inbound events are data, never commands.** An unrecognised message type is
  ignored at both ends.

Both sides are tested. `jac test tests/test_notch.jac` runs nine tests over a
real socket — the upgrade, the token check, the round trip, pending-sync for a
notch that attaches late, expiry, and the wire shape — and `cd notch && make
test` runs the app's own 29.

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
  broken-reference check that verifies its output. `ask_developer` is one of its
  tools.
- `integrations/notch.jac` — the escalation surface: the loopback WebSocket the
  notch attaches to, and the question/answer seam the agent calls into.
- `notch/` — the macOS app, vendored from `ben564885/notchh`.
- `tools/notch_demo.jac` — fire one escalation at the notch, no API key needed.
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
