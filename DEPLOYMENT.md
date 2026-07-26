# Deployment — Fly.io and JacHammer

Where things actually live: the whole running service is `jac/` — a Jac
(`jaclang`) API server, entry point `jac/main.sv.jac`, config in
`jac/jac.toml`. It's the entire "brain" of Synqit: the graph, the walkers,
the LLM integration step, the GitHub commit step. Everything under `jac/`
is what needs to get deployed. `cli/` and `web/` are separate pieces, not
part of this.

## Why we need a real deployed server at all

Up to now everything has been tested against `localhost:8899` on one
machine, which only that machine can reach. The entire point of this
project is a **shared graph that multiple developers push into** — that
only means anything once it's one server multiple people (and their CLIs)
can actually hit. So: deploy `jac/` somewhere with a real URL, set the
three required secrets there, and everyone points at that URL instead of
their own localhost.

**Required secrets/env vars on whatever hosts it:**
- `GITHUB_TOKEN` — fine-grained GitHub PAT with `Contents: read and write`
  on whatever repo(s) it needs to touch.
- `ANTHROPIC_API_KEY` — used by byLLM (Jac's native LLM-calling feature)
  for the `integrate` step. Model is pinned to `claude-sonnet-5` in
  `jac/walkers/integrate.jac` (cost call, not a capability limit).
- Ideally also a real `JWT_SECRET` — Jac's built-in auth defaults to a
  public, well-known test signing secret
  (`supersecretkey_for_testing_only!`). Fine on localhost, not fine on a
  real shared URL other people register accounts against.

## Option 1: JacHammer (current plan for the hackathon)

**What it is:** an AI-chat-driven full-stack app builder from Jaseci Labs
(the people who make Jac). You describe what to build and their agent
writes code, with live preview, git-backed history, and one-click deploy —
think a Jac-flavored v0/bolt.new. This is **not** a bare hosting provider
the way Fly.io is; deployment is a feature of their platform, done entirely
through their browser UI (no CLI).

**Why we're using it for the hackathon specifically:** the organizers
"highly encourage" hosting through it so judges can view submissions
easily, and it's free for a hackathon's timeframe. It also directly
supports importing an existing GitHub repo (not just projects built inside
their own chat UI), so `synqit-hack` can be pointed at it as-is.

**Sandbox vs. permanent deploy — read this carefully, it's not what the
Discord announcement said:**
- **Sandbox deploy** — free on every plan, but **expires automatically
  after 7 days**. Explicitly described in their docs as "meant for
  testing," not long-term hosting. (The Discord message said sandbox
  hosts "for free forever" — that's not what JacHammer's own docs say.
  Don't plan around indefinite uptime on the free tier.)
- **Permanent deploy** — a real stable deployment with its own subdomain
  (custom domain supported too), but **requires a paid plan** (Builder
  tier: 1 deploy).

For a hackathon submission, sandbox is the right call — 7 days is more
than enough runway for the judging window, and the graph resetting after
the event doesn't matter for a demo.

**The one real risk, and why it needs to be tested early, not assumed:**
JacHammer's docs say nothing about database/persistence durability for a
deployed app — no mention of surviving restarts, no disk/volume guarantee,
nothing. That's the single property this whole architecture depends on:
the graph (`.jac/data`, SQLite by default) has to survive between
requests, or every restart silently wipes every project/push/integration
we've ever recorded. **Before relying on this for real testing or a live
demo: seed a test project on the deployed instance, wait a while (or
trigger whatever their platform does on idle/restart), then check the
project/graph is still there.** If it isn't, that's the moment to fall back
to Fly.io (below), not mid-demo.

**How to actually deploy it (from their docs):**
1. In the JacHammer dashboard, start a new project via "import an existing
   repository" and point it at `julianshekhtmeyster/synqit-hack`.
2. JacHammer's own docs don't describe monorepo subfolder deploys
   explicitly — worth checking whether it wants the whole repo or can be
   pointed specifically at the `jac/` subdirectory as the app root. If it
   insists on repo-root, may need to confirm with JacHammer's project
   settings how to set `jac/` as the working directory / entry point
   (`main.sv.jac`).
3. Set the two (ideally three) secrets above as **project environment
   variables** in their dashboard — these get "sourced into your app's own
   running process — the preview and any deploy," per their docs.
4. Deploy from the **Deploy tab**, choose **Sandbox** (not Permanent,
   unless we're on a paid plan).
5. You'll get a subdomain automatically. That URL is what the CLI (once
   built) and any collaborator points `--base` at.
6. Do the persistence check described above before trusting it.

Docs: `docs.jachammer.ai` (their `llms.txt`/`llms-full.txt` renders more
reliably than the regular pages if a fetch tool comes back empty).

## Option 2: Fly.io (built, not deployed — the fallback)

Already fully scaffolded and sitting in `jac/`, untouched, ready to use if
JacHammer's persistence turns out not to hold up, or if this needs to run
somewhere real beyond the hackathon:

- `jac/Dockerfile` — `python:3.12-slim`, installs `jaclang`/`byllm`/
  `requests`, runs `jac start main.sv.jac --port 8080 --no_client`.
- `jac/fly.toml` — one always-on machine
  (`min_machines_running = 1`, `auto_stop_machines = false` — **not**
  auto-scaled, because Jac's default SQLite persistence backend doesn't
  support multiple machines writing to the same file), plus a **mounted
  Fly Volume at `/app/jac/.jac`** — this is the line that actually makes
  the graph survive restarts/redeploys. Without it, same failure mode as
  the JacHammer risk above.
- `jac/.dockerignore` — keeps `.env`, local `.jac/` data, and caches out
  of the built image.

**To deploy:**
```bash
cd jac
flyctl auth login          # needs a real browser session
flyctl launch              # reads fly.toml, creates the app + volume
flyctl volumes create synqit_data --size 1   # if launch doesn't create it automatically
flyctl secrets set GITHUB_TOKEN=... ANTHROPIC_API_KEY=... JWT_SECRET=...
flyctl deploy
```

`flyctl` is installed in the dev environment already (`v0.4.74`). Not yet
authenticated as of this doc — needs `flyctl auth login` run interactively
by whoever has the Fly.io account.

## Bottom line

Use JacHammer sandbox as the primary server for the hackathon — it's what
gets us judge visibility and it's genuinely fine for the event's
timeframe. Just don't skip the persistence check. Fly.io is sitting there,
fully built, the moment it's actually needed.
