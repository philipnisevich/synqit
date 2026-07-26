import from "lucide-react" { Check, Copy }

"""Tabbed hero panel: pick a step, see the command, copy it.

Structure follows the Inkbox reference - pill switcher above a titled card with
a prose line and an inset, copyable command row.
"""

glob TABS: list[dict[str, str]] = [
    {
        "id": "install",
        "label": "Install",
        "blurb": "One global install, pointed at the repo you already have. No server to stand up, no account to create.",
        "command": "npm i -g synqit && synqit init",
        "out": "→ linked to",
        "dim": " julianshekhtmeyster/synqit-hack"
    },
    {
        "id": "push",
        "label": "Push",
        "blurb": "Describe what you meant to do. The agent folds it into the newest main and syncs your checkout back.",
        "command": "synqit push \"add avatars\"",
        "out": "→ integrated onto main",
        "dim": "  a91f3c2"
    },
    {
        "id": "resolve",
        "label": "Resolve",
        "blurb": "A genuine product decision stops the agent and asks you in the notch. You never see a merge marker.",
        "command": "synqit status",
        "out": "→ needs_human",
        "dim": "  free tier vs. unlimited"
    }
];

def:pub HeroPanel() -> JsxElement {
    has active: str = "push";
    has copied: bool = False;

    tab: dict[str, str] = TABS[1];
    for t in TABS {
        if t["id"] == active {
            tab = t;
        }
    }

    def handle_copy(e: MouseEvent) {
        nav = navigator as any;
        nav.clipboard.writeText(tab["command"]);
        copied = True;
        setTimeout(lambda { copied = False; }, 1600);
    }

    return <div className="w-full">
        {#* Pill switcher, same glass treatment as the nav so the hero reads as one surface. *#}
        <div
            role="tablist"
            aria-label="What synqit does"
            className="mb-3 inline-flex items-center gap-1 rounded-full border border-black/[0.06] bg-white/70 p-1 shadow-[0_2px_20px_-6px_rgba(0,0,0,0.18)] backdrop-blur-md"
        >
            {for t in TABS {
                <button
                    key={t["id"]}
                    role="tab"
                    type="button"
                    aria-selected={t["id"] == active}
                    onClick={lambda (e: MouseEvent) { active = t["id"]; }}
                    className={
                        "rounded-full px-3.5 py-1.5 text-sm font-medium transition "
                        + ("bg-brand text-white shadow-sm" if t["id"] == active else "text-ink-soft hover:bg-black/[0.04] hover:text-ink")
                    }
                >
                    {t["label"]}
                </button>
            }}
        </div>

        <div
            role="tabpanel"
            className="overflow-hidden rounded-xl border border-rule bg-[#0d0e11] shadow-[0_30px_60px_-30px_rgba(0,0,0,0.5)]"
        >
            {#* Title bar: lit traffic lights plus the working directory. *#}
            <div className="flex items-center gap-1.5 border-b border-white/10 px-4 py-2.5">
                <span className="h-2.5 w-2.5 rounded-full bg-[#e2665a]" />
                <span className="h-2.5 w-2.5 rounded-full bg-[#e0b341]" />
                <span className="h-2.5 w-2.5 rounded-full bg-[#3fb37f]" />
                <span className="ml-2 truncate font-mono text-[12px] text-[#8b8d92]">~/your-project</span>
            </div>

            <div className="p-4 sm:p-5">
                <p className="text-[14px] leading-relaxed text-[#b9bbc0]">{tab["blurb"]}</p>

                {#* Command row: inset, horizontally scrollable, copyable. *#}
                <div className="mt-4 flex items-center gap-2 rounded-lg bg-white/[0.05] py-2.5 pr-1.5 pl-3.5 ring-1 ring-inset ring-white/[0.07]">
                    <code className="min-w-0 flex-1 overflow-x-auto font-mono text-[13px] whitespace-pre text-[#d8d9dc]">
                        <span className="text-brand">{"$ "}</span>
                        {tab["command"]}
                    </code>
                    <button
                        type="button"
                        aria-label={"Copied" if copied else "Copy command"}
                        onClick={handle_copy}
                        className="shrink-0 rounded-md p-1.5 text-[#8b8d92] transition hover:bg-white/[0.06] hover:text-[#d8d9dc]"
                    >
                        {if copied {
                            <Check size={15} className="text-[#3fb37f]" />
                        } else {
                            <Copy size={15} />
                        }}
                    </button>
                </div>

                <p className="mt-3 overflow-x-auto font-mono text-[13px] whitespace-pre">
                    <span className="text-[#3fb37f]">{tab["out"]}</span>
                    <span className="text-[#5b5d63]">{tab["dim"]}</span>
                </p>
            </div>
        </div>
    </div>;
}
