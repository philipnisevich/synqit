import from react { useEffect }
import from "gsap" { gsap }
import from "gsap/ScrollTrigger" { ScrollTrigger }
import from "lenis" { default as Lenis }
import from "@jac/runtime" { Link }
import from ".Logo" { Logo }
import from ".HeroPanel" { HeroPanel }
import from ".NotchMock" { NotchMock }
import from ".TerminalWindow" { TerminalWindow }
import from ".LandingUI" { Eyebrow, SectionHead, CardGrid, FeatureCard, FaqItem, DetailSection }

"""Synqit marketing page, served at "/".

The dashboard lives at "/app"; this is what a first-time visitor lands on.
"""

glob REPO: str = "https://github.com/julianshekhtmeyster/synqit-hack";

glob NAV_LINKS: list[dict[str, str]] = [
    {"href": "#how-it-works", "label": "How it works"},
    {"href": "#features", "label": "Features"},
    {"href": "#faq", "label": "FAQ"}
];

glob FEATURES: list[dict[str, str]] = [
    {"title": "No branches", "body": "One shared main. Nothing to fork, nothing to open a pull request against."},
    {"title": "Human escalation", "body": "A genuine product decision stops the agent and asks, instead of guessing and shipping the wrong call."},
    {"title": "Native notch", "body": "A real macOS menu-bar app. Always there, out of the way until it isn't."},
    {"title": "Precedent memory", "body": "Once you've decided a concept, the same question isn't asked twice, even from a different file."},
    {"title": "GitHub-backed", "body": "Real commits, on your real main. doctor verifies the token can actually write before you ever push."},
    {"title": "Open source", "body": "MIT licensed, self-hosted. Fork it, read every line that runs your pushes."}
];

glob OPEN_SOURCE: list[dict[str, str]] = [
    {"title": "Self-hosted", "body": "Runs on your machine or your infrastructure. No Synqit account, ever."},
    {"title": "MIT licensed", "body": "Fork it, read it, ship your own escalation surface on top of it."},
    {"title": "Extensible", "body": "The EscalationSurface seam means Slack, Linear, or your own UI can plug in exactly where the notch does."}
];

glob ROADMAP: list[str] = [
    "Slack surface",
    "Windows / Linux client",
    "VS Code extension",
    "Team activity dashboard",
    "Multi-repo orchestration",
    "Bring your own model"
];

glob STEPS: list[dict[str, str]] = [
    {"n": "01", "t": "Push your feature", "d": "Describe the change in plain English: synqit push \"add avatars\""},
    {"n": "02", "t": "An agent integrates it", "d": "It reads the newest main and resolves anything it can safely decide on its own."},
    {"n": "03", "t": "You decide, only when it matters", "d": "A genuine product conflict becomes three choices, right in your notch."}
];

glob FAQS: list[dict[str, str]] = [
    {"q": "How is this different from reviewing pull requests?", "a": "There's nothing to review. One shared main: the agent integrates continuously, and only stops you for a real product call, not a stylistic one."},
    {"q": "Does this replace Git?", "a": "No. It replaces branches, pull requests, and merges on top of Git. GitHub stays the source of truth for every commit."},
    {"q": "What happens if I don't answer in time?", "a": "The push ends in needs_human after five minutes. Your local work is never touched: you can answer later and push again."},
    {"q": "Is my code sent to a third party?", "a": "The integration agent calls an LLM to reason about conflicts. Only the changed files and their intent are sent."},
    {"q": "Can multiple people push at once?", "a": "Pushes are serialized per project: one queue, one integration at a time. No simultaneous integration race to corrupt main."},
    {"q": "What if I haven't installed the notch?", "a": "A conflicting push returns needs_human immediately instead of hanging. Your work stays local and unchanged until you attach a notch."},
    {"q": "Is Synqit open source?", "a": "Yes, MIT licensed. Fork it, self-host it, or swap the escalation surface for your own."}
];

glob QUEUE_ROWS: list[dict[str, str]] = [
    {"dev": "dev_ben", "pct": "62%", "left": "3:07", "expired": ""},
    {"dev": "dev_ana", "pct": "100%", "left": "expired", "expired": "yes"},
    {"dev": "dev_theo", "pct": "18%", "left": "0:54", "expired": ""}
];

glob AUDIT_ROWS: list[dict[str, str]] = [
    {"sha": "a91f3c2", "decision": "kept theirs", "dev": "dev_ana"},
    {"sha": "7c2e0d1", "decision": "mechanical", "dev": "-"},
    {"sha": "e58b420", "decision": "instructed", "dev": "dev_ben"}
];

glob PROJECTS: list[str] = ["pricing-service", "marketing-site", "mobile-app"];

glob CLONE_LINES: list[dict[str, any]] = [
    {"prompt": True, "text": "git clone https://github.com/julianshekhtmeyster/synqit-hack.git", "dim": ""},
    {"prompt": True, "text": "cd synqit-hack && make server", "dim": ""}
];

glob STATUS_LINES: list[dict[str, any]] = [
    {"prompt": True, "text": "synqit status", "dim": ""},
    {"prompt": False, "text": "Synqit project: pricing-service", "dim": ""},
    {"prompt": False, "text": "  server: http://127.0.0.1:8899", "dim": ""},
    {"prompt": False, "text": "  local changes ready to push: 2", "dim": ""},
    {"prompt": False, "text": "  you: dev_ben", "dim": ""},
    {"prompt": False, "text": "  notch: attached", "dim": ""},
    {"prompt": False, "text": "  shared GitHub commit: a91f3c2", "dim": " (up to date)"}
];

glob DOCTOR_LINES: list[dict[str, any]] = [
    {"prompt": False, "text": "✓ GitHub token configured", "dim": ""},
    {"prompt": False, "text": "✓ OpenRouter API key configured", "dim": ""},
    {"prompt": False, "text": "✓ Contents verified on acme/pricing-service", "dim": " at a91f3c2"}
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
                            {"One shared "}
                            <span className="text-brand italic">main</span>
                            {", no branches "}
                            <span className="text-brand italic">to review.</span>
                        </h1>
                        <p className="mt-6 max-w-lg text-[17px] leading-relaxed text-ink/70">
                            Push a feature. An agent integrates it into the newest main. When it hits a
                            decision only you can make, not a merge conflict but a product one, it asks.
                            Right in your notch.
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

        {#* ---------- The escalation itself ---------- *#}
        <section className="px-6 py-24">
            <NotchMock />
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
                <SectionHead eyebrow="Features" sub="Everything shared source control needs to not be Git plus a chatbot.">
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
            heading="Any GitHub repo, one fine-grained token."
            visual={<TerminalWindow lines={DOCTOR_LINES} />}
        >
            <p>
                Point Synqit at a repo with Contents: read and write. doctor --verify exercises the
                permission for real, against a real ref, not an identity check that passes for any
                token and then fails on your first push.
            </p>
        </DetailSection>

        <DetailSection
            eyebrow="Timeout safety"
            heading="Escalations that don't hang your team."
            band={True}
            reverse={True}
            visual={
                <div className="space-y-3 rounded-xl border border-rule bg-white p-6 font-mono text-sm">
                    {for r in QUEUE_ROWS {
                        <div key={r["dev"]} className="flex items-center gap-3">
                            <span className="w-20 shrink-0 text-ink-soft">{r["dev"]}</span>
                            <div className="h-1.5 flex-1 rounded-full bg-paper-2">
                                <div
                                    className="h-1.5 rounded-full"
                                    style={{"width": r["pct"], "background": "var(--danger)" if r["expired"] else "var(--brand)"}}
                                />
                            </div>
                            <span className="w-16 text-right text-ink-soft">{r["left"]}</span>
                        </div>
                    }}
                </div>
            }
        >
            <ul className="space-y-2">
                <li>A question waits five minutes, not forever.</li>
                <li>No answer? The push ends in needs_human, your local work untouched.</li>
                <li>Every fallback is today's behavior: no notch, a timeout, too many rounds.</li>
                <li>One slow decision never wedges the rest of the queue.</li>
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
                                <th className="px-4 py-3 font-normal">Decision</th>
                                <th className="px-4 py-3 font-normal">Dev</th>
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
                Which decision was made, and why, is part of the published commit message, not a
                side channel that drifts from what actually shipped.
            </p>
        </DetailSection>

        <DetailSection
            eyebrow="Multi-project"
            heading="One shared queue, however many repos."
            reverse={True}
            visual={
                <div className="grid grid-cols-2 gap-3">
                    {for p in PROJECTS {
                        <div key={p} className="rounded-lg border border-rule bg-white p-4">
                            <p className="text-sm font-medium text-ink">{p}</p>
                            <p className="mt-1 font-mono text-xs text-ok">active</p>
                        </div>
                    }}
                    <div className="flex items-center justify-center rounded-lg border border-dashed border-rule p-4 text-sm text-ink-soft">
                        + Add project
                    </div>
                </div>
            }
        >
            <p>
                One person runs one server. Every project your team connects shares the same
                notch, the same identity, the same escalation surface.
            </p>
        </DetailSection>

        {#* ---------- Open source ---------- *#}
        <section data-reveal className="py-20">
            <div className="mx-auto max-w-6xl px-6">
                <SectionHead eyebrow="Open source" sub="Read every line that runs your pushes, then change the ones you don't like.">
                    Extensible, adaptable, open source.
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
                <h2 className="mt-4 font-display text-4xl">Where a surface could plug in next.</h2>
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
                        Suggest a surface
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
                    From clone to shared main in one command.
                </h2>
                {#* max-w-xl, not md: the clone URL needs the room to sit on one line. *#}
                <div className="mx-auto mt-8 max-w-xl text-left">
                    <TerminalWindow lines={CLONE_LINES} />
                </div>
                <p className="mx-auto mt-6 max-w-md text-sm text-ink-soft">
                    Open source. Self-hosted. First run walks you through setup, no Synqit account
                    required.
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
                            A conflict becomes a question, not a rejected push.
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
                            <li><a href="#features" className="hover:text-ink">Notch</a></li>
                            <li><a href="#features" className="hover:text-ink">Precedent memory</a></li>
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
                    <span>© 2026 synqit. Open source under MIT.</span>
                </div>
            </div>
        </footer>
    </div>;
}
