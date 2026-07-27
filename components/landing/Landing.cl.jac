import from react { useEffect }
import from "gsap" { gsap }
import from "gsap/ScrollTrigger" { ScrollTrigger }
import from "lenis" { default as Lenis }
import from "@jac/runtime" { Link }
import from ".Logo" { Logo }
import from ".HeroPanel" { HeroPanel }
import from ".TerminalWindow" { TerminalWindow }
import from ".LandingUI" { Eyebrow, SectionHead, CardGrid, FeatureCard, FaqItem, DetailSection }

"""Synqit marketing page, served at "/".

The dashboard lives at "/app"; this is what a first-time visitor lands on.
"""

glob REPO: str = "https://github.com/philipnisevich/synqit";

glob NAV_LINKS: list[dict[str, str]] = [
    {"href": "#how-it-works", "label": "How it works"},
    {"href": "#features", "label": "Features"},
    {"href": "#faq", "label": "FAQ"}
];

glob FEATURES: list[dict[str, str]] = [
    {"title": "One shared main", "body": "Everyone works against the same branch. Nothing to fork, nothing to open a pull request against."},
    {"title": "Context from your imports", "body": "Your codebase is a graph. A push walks it outward from what you touched to reach callers, dependents, and tests."},
    {"title": "Call sites come along", "body": "Change a function's shape and the files that use it are updated in the same commit, including the tests that asserted the old one."},
    {"title": "Someone else pushed first", "body": "If main moves mid-integration, the push re-reads it and integrates again against the new baseline instead of failing."},
    {"title": "Runs on your machine", "body": "No server, no account. Your API key stays local and commits are published with your own git credentials."},
    {"title": "Real commits", "body": "Ordinary commits on your real main, authored by you, each one explaining what it changed and what it deliberately left alone."}
];

glob OPEN_SOURCE: list[dict[str, str]] = [
    {"title": "Local first", "body": "The CLI runs entirely on your machine. There is no Synqit server in the path between you and GitHub."},
    {"title": "Nothing to trust", "body": "Read every line that touches your code. The whole pipeline is one repo you can clone."},
    {"title": "Built on Jac", "body": "The file graph, the traversal, and the integration are Jac walkers over a real object-spatial graph."}
];

glob ROADMAP: list[str] = [
    "PyPI install",
    "Editor integration",
    "Team activity dashboard",
    "Multi-repo support",
    "Bring your own model",
    "Richer conflict escalation"
];

glob STEPS: list[dict[str, str]] = [
    {"n": "01", "t": "Say what you want", "d": "synqit push \"add avatars\" - or edit the code first and let your diff guide it."},
    {"n": "02", "t": "It scopes the context", "d": "A walker reads the newest main and traverses the import graph to everything your change reaches."},
    {"n": "03", "t": "It publishes to main", "d": "A real commit, and your workspace is already sitting on it. Nothing to pull."}
];

glob FAQS: list[dict[str, str]] = [
    {"q": "How is this different from reviewing pull requests?", "a": "There is no branch and nothing to review. Everyone integrates into the same main continuously, and the agent brings the surrounding call sites and tests along with each change."},
    {"q": "Does this replace Git?", "a": "No. It replaces branches, pull requests, and merges on top of Git. GitHub stays the source of truth, and every push is an ordinary commit."},
    {"q": "Do I push a diff or a description?", "a": "Either. With local edits, they are the proposal and the intent guides how they land. With a clean tree, the intent alone is enough."},
    {"q": "What if someone publishes while I'm integrating?", "a": "Git rejects the push, and Synqit re-reads main and integrates again against the new baseline. Their commit stays intact and history stays linear."},
    {"q": "Is my code sent to a third party?", "a": "The integration calls Anthropic's API with the files around your change, not the whole repo. The key is yours and stays on your machine."},
    {"q": "How does it know which files matter?", "a": "It parses imports into a graph and walks outward from the files you touched, two hops by default. Use --dry-run to see exactly what it would look at."},
    {"q": "What if it gets it wrong?", "a": "It is a normal commit, so git revert works. Your pre-push state is also snapshotted, and any failure prints the command to restore it."}
];

glob CONTEXT_ROWS: list[dict[str, str]] = [
    {"path": "src/lib/validate.js", "hop": "touched"},
    {"path": "src/models/user.js", "hop": "touched"},
    {"path": "src/models/order.js", "hop": "1 hop"},
    {"path": "tests/validate.test.js", "hop": "1 hop"},
    {"path": "src/services/userService.js", "hop": "2 hops"}
];

glob AUDIT_ROWS: list[dict[str, str]] = [
    {"sha": "15b389e", "decision": "migrated validation + tests", "dev": "4 files"},
    {"sha": "fd471ec", "decision": "added route + wired call sites", "dev": "3 files"},
    {"sha": "cabcebb", "decision": "new rule, tests updated", "dev": "2 files"}
];

glob CLONE_LINES: list[dict[str, any]] = [
    {"prompt": True, "text": "git clone https://github.com/philipnisevich/synqit.git", "dim": ""},
    {"prompt": True, "text": "cd synqit && ./install.sh", "dim": ""},
    {"prompt": True, "text": "cd ~/your-repo && synqit configure", "dim": ""}
];

glob STATUS_LINES: list[dict[str, any]] = [
    {"prompt": True, "text": "synqit status", "dim": ""},
    {"prompt": False, "text": "philipnisevich/synqit-lab", "dim": "   shared branch: main"},
    {"prompt": False, "text": "  main is at 19fe09b", "dim": " (18 text files)"},
    {"prompt": False, "text": "  2 local change(s) a push would use as its proposal:", "dim": ""},
    {"prompt": False, "text": "    modified src/lib/validate.js", "dim": ""},
    {"prompt": False, "text": "    modified src/models/user.js", "dim": ""}
];

glob DOCTOR_LINES: list[dict[str, any]] = [
    {"prompt": True, "text": "synqit doctor", "dim": ""},
    {"prompt": False, "text": "  [ok] git", "dim": "                 git version 2.52.0"},
    {"prompt": False, "text": "  [ok] repository root", "dim": "     ~/synqit-lab"},
    {"prompt": False, "text": "  [ok] on main", "dim": "             currently main"},
    {"prompt": False, "text": "  [ok] can fetch main", "dim": "      19fe09b"},
    {"prompt": False, "text": "  [ok] ANTHROPIC_API_KEY", "dim": "   from .env"},
    {"prompt": False, "text": "  [ok] ready to push", "dim": ""}
];

def:pub Landing() -> JsxElement {
    # gsap/lenis are npm modules with no Jac type surface; bind through `any`.
    g: any = gsap;
    st: any = ScrollTrigger;

    # Lenis and ScrollTrigger must share a clock. Lenis animates scroll on its
    # own RAF; if ScrollTrigger keeps its own, trigger positions resolve against
    # a stale scroll value and reveals fire early or late. So Lenis runs off the
    # GSAP ticker (autoRaf: false) and pushes every scroll into st.
    useEffect(lambda {
        g.registerPlugin(ScrollTrigger);
        mq = window.matchMedia("(prefers-reduced-motion: reduce)") as any;
        reduced = mq.matches;

        # Hidden only once JS runs, so a JS failure leaves the page readable
        # rather than blank.
        g.set("[data-reveal]", {"opacity": 0, "y": 0 if reduced else 28});
        st.batch("[data-reveal]", {
            "start": "top 88%",
            "once": True,
            "onEnter": lambda (els: any) {
                g.to(els, {
                    "opacity": 1,
                    "y": 0,
                    "duration": 0 if reduced else 0.7,
                    "stagger": 0.08,
                    "ease": "power3.out"
                });
            }
        });

        if reduced {
            st.refresh();
        # React calls whatever an effect returns as its cleanup. Returning
        # None lowers to `null`, which React then tries to invoke -> "is not
        # a function". Always hand back a real (possibly no-op) function.
            return lambda { };
        }

        # Lenis is a JS class: it must be constructed via the `new()` builtin.
        # Calling it plainly throws "V is not a function" at runtime.
        # E1053 here is the known false positive for `new()` on an npm class -
        # jac check has no typed stub for it; the build and runtime are correct.
        # Lenis drives its own RAF here rather than riding the GSAP ticker.
        # `gsap.ticker.add(...)` lowers through Jac's polymorphic dispatch
        # (`.add`/`.remove` collide with stdlib set/list method names) and blows
        # up on a GSAP ticker object. Pushing every Lenis scroll into
        # ScrollTrigger.update is the part that actually keeps the two in sync,
        # and these triggers are fire-once reveals, not scrubs, so shared-ticker
        # frame ordering buys nothing.
        lenis: any = new(Lenis, {  # jac:ignore[E1053]
            "autoRaf": True,
            "anchors": {"offset": -80},
            "lerp": 0.11,
            "wheelMultiplier": 1,
            "touchMultiplier": 1.6
        });
        lenis.on("scroll", st.update);
        st.refresh();

        return lambda { lenis.destroy(); };
    }, []);

    return <div id="top" className="landing-root flex min-h-screen flex-col">
        {#* ---------- Nav ---------- *#}
        <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
            <div className="pointer-events-auto flex items-center gap-1 rounded-full border border-black/[0.06] bg-white/70 px-2 py-1.5 shadow-[0_2px_20px_-6px_rgba(0,0,0,0.18)] backdrop-blur-md">
                <a href="#top" className="rounded-full px-3 py-1.5 text-ink">
                    <Logo height={16} />
                </a>
                <nav className="hidden items-center sm:flex">
                    {for l in NAV_LINKS {
                        <a
                            key={l["href"]}
                            href={l["href"]}
                            className="rounded-full px-3 py-1.5 text-sm text-ink-soft transition hover:bg-black/[0.04] hover:text-ink"
                        >
                            {l["label"]}
                        </a>
                    }}
                </nav>
                <Link to="/app" className="rounded-full px-3 py-1.5 text-sm text-ink-soft transition hover:bg-black/[0.04] hover:text-ink">
                    Dashboard
                </Link>
                <a
                    target="_blank"
                    rel="noopener noreferrer"
                    href={REPO}
                    className="rounded-full bg-ink px-3.5 py-1.5 text-sm font-medium text-white transition hover:opacity-85"
                >
                    GitHub
                </a>
            </div>
        </header>

        {#* ---------- Hero ---------- *#}
        <section className="hero-art relative isolate min-h-svh">
            <div className="hero-veil flex min-h-svh flex-col justify-center px-6 pt-36 pb-28 sm:pt-44">
                <div className="mx-auto grid w-full max-w-6xl items-center gap-12 lg:grid-cols-[1.05fr_1fr] lg:gap-16">
                    <div>
                        <h1 className="font-display text-5xl leading-[1.08] sm:text-[58px]">
                            {"A new way to "}
                            <span className="text-brand italic">work together</span>
                            {" on one shared "}
                            <span className="text-brand italic">main.</span>
                        </h1>
                        <p className="mt-6 max-w-lg text-[17px] leading-relaxed text-ink/70">
                            Push a feature intent, or the code you already wrote. An agent integrates it
                            into the newest main, reading the files around your change so call sites and
                            tests come along with it.
                        </p>
                        <div className="mt-8 flex flex-wrap items-center gap-3">
                            <a href="#quickstart" className="rounded-full bg-brand px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:opacity-90">
                                Get started
                            </a>
                            <a href="#how-it-works" className="flex items-center gap-2 rounded-full border border-black/[0.07] bg-white/80 px-5 py-2.5 text-sm font-medium text-ink shadow-sm backdrop-blur transition hover:bg-white">
                                See how it works
                            </a>
                        </div>
                    </div>

                    <div className="min-w-0 lg:pl-4">
                        <HeroPanel />
                    </div>
                </div>
            </div>
        </section>

        {#* ---------- How it works ---------- *#}
        <section id="how-it-works" data-reveal className="py-20">
            <div className="mx-auto max-w-6xl px-6">
                <div className="max-w-xl">
                    <Eyebrow>How it works</Eyebrow>
                    <h2 className="mt-4 font-display text-4xl">From push to shared main.</h2>
                </div>
                <div className="mt-12 grid gap-8 sm:grid-cols-3">
                    {for s in STEPS {
                        <div key={s["n"]} className="border-t border-rule pt-5">
                            <span className="font-mono text-sm text-brand">{s["n"]}</span>
                            <h3 className="mt-2 font-medium text-ink">{s["t"]}</h3>
                            <p className="mt-1.5 text-sm leading-relaxed text-ink-soft">{s["d"]}</p>
                        </div>
                    }}
                </div>
            </div>
        </section>

        {#* ---------- Status mock ---------- *#}
        <section data-reveal className="py-10">
            <div className="mx-auto max-w-6xl px-6 text-center">
                <h2 className="font-display text-3xl sm:text-4xl">See your workspace, not your diff.</h2>
                <div className="mx-auto mt-10 max-w-xl text-left">
                    <TerminalWindow lines={STATUS_LINES} />
                </div>
            </div>
        </section>

        {#* ---------- Features ---------- *#}
        <section id="features" data-reveal className="py-20">
            <div className="mx-auto max-w-6xl px-6">
                <SectionHead eyebrow="Features" sub="Continuous integration into main, with the context to do it correctly.">
                    Built for one shared main.
                </SectionHead>
                <div className="mt-10">
                    <CardGrid>
                        {for f in FEATURES {
                            <FeatureCard key={f["title"]} title={f["title"]}>{f["body"]}</FeatureCard>
                        }}
                    </CardGrid>
                </div>
            </div>
        </section>

        {#* ---------- Detail sections ---------- *#}
        <DetailSection
            eyebrow="Bring your own repo"
            heading="Any git repo, nothing to stand up."
            visual={<TerminalWindow lines={DOCTOR_LINES} />}
        >
            <p>
                Point Synqit at a repo with an origin remote and run doctor. It checks git, your
                branch, whether it can actually reach main, and where your API key came from, then
                names the exact command for anything that would block a push.
            </p>
        </DetailSection>

        <DetailSection
            eyebrow="Scoped context"
            heading="It reads what your change touches."
            band={True}
            reverse={True}
            visual={
                <div className="space-y-3 rounded-xl border border-rule bg-white p-6 font-mono text-sm">
                    {for r in CONTEXT_ROWS {
                        <div key={r["path"]} className="flex items-center gap-3">
                            <span className="min-w-0 flex-1 truncate text-ink">{r["path"]}</span>
                            <span className="shrink-0 text-ink-soft">{r["hop"]}</span>
                        </div>
                    }}
                </div>
            }
        >
            <ul className="space-y-2">
                <li>Imports are parsed into a graph of files.</li>
                <li>A walker starts at what you touched and moves outward, two hops by default.</li>
                <li>Callers and dependents both count: the test that asserts your old behavior is reachable from it.</li>
                <li>Run with --dry-run to see the exact set before anything is written.</li>
            </ul>
        </DetailSection>

        <DetailSection
            eyebrow="Audit trail"
            heading="Every push explains itself."
            visual={
                <div className="overflow-x-auto rounded-xl border border-rule bg-white">
                    <table className="w-full text-left text-sm">
                        <thead>
                            <tr className="border-b border-rule text-xs text-ink-soft uppercase">
                                <th className="px-4 py-3 font-normal">Commit</th>
                                <th className="px-4 py-3 font-normal">What it did</th>
                                <th className="px-4 py-3 font-normal">Scope</th>
                            </tr>
                        </thead>
                        <tbody className="font-mono text-[13px] [font-variant-numeric:tabular-nums]">
                            {for r in AUDIT_ROWS {
                                <tr key={r["sha"]} className="border-b border-rule last:border-0">
                                    <td className="px-4 py-3 text-ink">{r["sha"]}</td>
                                    <td className="px-4 py-3 text-ink-soft">{r["decision"]}</td>
                                    <td className="px-4 py-3 text-ink-soft">{r["dev"]}</td>
                                </tr>
                            }}
                        </tbody>
                    </table>
                </div>
            }
        >
            <p>
                What changed, and what was deliberately left alone, is written into the commit
                message itself, not a side channel that drifts from what actually shipped.
            </p>
        </DetailSection>

        {#* ---------- Open source ---------- *#}
        <section data-reveal className="py-20">
            <div className="mx-auto max-w-6xl px-6">
                <SectionHead eyebrow="Open source" sub="Read every line that runs your pushes, then change the ones you don't like.">
                    Local, inspectable, open source.
                </SectionHead>
                <div className="mt-10">
                    <CardGrid>
                        {for o in OPEN_SOURCE {
                            <FeatureCard key={o["title"]} title={o["title"]}>{o["body"]}</FeatureCard>
                        }}
                    </CardGrid>
                </div>
            </div>
        </section>

        {#* ---------- Roadmap ---------- *#}
        <section data-reveal className="py-20">
            <div className="mx-auto max-w-6xl px-6">
                <Eyebrow>Roadmap</Eyebrow>
                <h2 className="mt-4 font-display text-4xl">What comes next.</h2>
                <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    {for r in ROADMAP {
                        <div key={r} className="flex items-center justify-between rounded-xl border border-dashed border-rule p-5 text-ink-soft">
                            <span className="text-sm">{r}</span>
                            <span className="rounded-full bg-paper-2 px-2.5 py-1 font-mono text-[11px] tracking-wide uppercase">Soon</span>
                        </div>
                    }}
                    <a
                        target="_blank"
                        rel="noopener noreferrer"
                        href={REPO}
                        className="flex items-center justify-center rounded-xl border border-rule p-5 text-sm font-medium text-ink hover:border-brand/50"
                    >
                        Suggest something
                    </a>
                </div>
            </div>
        </section>

        {#* ---------- FAQ ---------- *#}
        <section id="faq" data-reveal className="py-20">
            <div className="mx-auto max-w-3xl px-6">
                <Eyebrow>FAQ</Eyebrow>
                <h2 className="mt-4 font-display text-4xl">Questions, answered.</h2>
                <div className="mt-8">
                    {for f in FAQS {
                        <FaqItem key={f["q"]} q={f["q"]} a={f["a"]} />
                    }}
                </div>
            </div>
        </section>

        {#* ---------- Final CTA, also the #quickstart target ---------- *#}
        <section id="quickstart" data-reveal className="bg-paper-2 py-24 text-center">
            <div className="mx-auto max-w-2xl px-6">
                <Eyebrow>Get started</Eyebrow>
                <h2 className="mt-4 font-display text-4xl sm:text-5xl">
                    From clone to shared main in three commands.
                </h2>
                {#* max-w-xl, not md: the clone URL needs the room to sit on one line. *#}
                <div className="mx-auto mt-8 max-w-xl text-left">
                    <TerminalWindow lines={CLONE_LINES} />
                </div>
                <p className="mx-auto mt-6 max-w-md text-sm text-ink-soft">
                    Runs entirely on your machine. configure verifies your API key before saving it,
                    and doctor tells you if anything else would block a push.
                </p>
                <div className="mt-6 flex items-center justify-center gap-3">
                    <a
                        target="_blank"
                        rel="noopener noreferrer"
                        href={REPO}
                        className="rounded-full bg-ink px-4 py-2 text-sm font-medium text-white transition hover:opacity-85"
                    >
                        Star on GitHub
                    </a>
                    <Link to="/app" className="text-sm font-medium text-ink hover:text-brand">
                        Open the dashboard
                    </Link>
                </div>
            </div>
        </section>

        {#* ---------- Footer ---------- *#}
        <footer className="footer-art relative isolate mt-auto border-t border-rule py-16 text-ink-soft">
            <div className="mx-auto max-w-6xl px-6">
                <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
                    <div>
                        <Logo height={18} className="text-ink" />
                        <p className="mt-3 max-w-[22ch] text-sm text-ink-soft">
                            Integration into one shared main, with the context to get it right.
                        </p>
                    </div>
                    <div>
                        <p className="font-mono text-xs tracking-wide text-ink-soft uppercase">Product</p>
                        <ul className="mt-3 space-y-2 text-sm">
                            <li><a href="#quickstart" className="hover:text-ink">Get started</a></li>
                            <li><a href="#how-it-works" className="hover:text-ink">How it works</a></li>
                        </ul>
                    </div>
                    <div>
                        <p className="font-mono text-xs tracking-wide text-ink-soft uppercase">Platform</p>
                        <ul className="mt-3 space-y-2 text-sm">
                            <li><Link to="/app" className="hover:text-ink">Dashboard</Link></li>
                            <li><a href="#features" className="hover:text-ink">Features</a></li>
                            <li><a href="#how-it-works" className="hover:text-ink">How it works</a></li>
                        </ul>
                    </div>
                    <div>
                        <p className="font-mono text-xs tracking-wide text-ink-soft uppercase">Developer</p>
                        <ul className="mt-3 space-y-2 text-sm">
                            <li><a target="_blank" rel="noopener noreferrer" href={REPO} className="hover:text-ink">GitHub</a></li>
                            <li><a href="#faq" className="hover:text-ink">FAQ</a></li>
                        </ul>
                    </div>
                </div>
                <div className="mt-12 flex flex-col-reverse items-center justify-between gap-4 border-t border-rule pt-6 text-xs text-ink-soft sm:flex-row">
                    <span>© 2026 synqit. Open source.</span>
                </div>
            </div>
        </footer>
    </div>;
}
