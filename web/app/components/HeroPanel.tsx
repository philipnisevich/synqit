"use client";

import { useState } from "react";

type Tab = {
  id: string;
  label: string;
  path: string;
  blurb: string;
  command: string;
  output?: { text: string; dim?: string };
};

const TABS: Tab[] = [
  {
    id: "install",
    label: "Install",
    path: "~/your-project",
    blurb:
      "One global install, pointed at the repo you already have. No server to stand up, no account to create.",
    command: "npm i -g synqit && synqit init",
    output: { text: "→ linked to", dim: " julianshekhtmeyster/synqit-hack" },
  },
  {
    id: "push",
    label: "Push",
    path: "~/your-project",
    blurb:
      "Describe what you meant to do. The agent folds it into the newest main and syncs your checkout back.",
    command: 'synqit push "add avatars"',
    output: { text: "→ integrated onto main", dim: "  a91f3c2" },
  },
  {
    id: "resolve",
    label: "Resolve",
    path: "~/your-project",
    blurb:
      "A genuine product decision stops the agent and asks you in the notch. You never see a merge marker.",
    command: "synqit status",
    output: { text: "→ needs_human", dim: "  free tier vs. unlimited" },
  },
];

function CopyButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <button
      type="button"
      aria-label={copied ? "Copied" : `Copy "${value}"`}
      onClick={() => {
        navigator.clipboard?.writeText(value).then(
          () => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1600);
          },
          () => {},
        );
      }}
      className="shrink-0 rounded-md p-1.5 text-[#8b8d92] transition hover:bg-white/[0.06] hover:text-[#d8d9dc] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
    >
      {copied ? (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path
            d="m5 13 4 4L19 7"
            stroke="#3fb37f"
            strokeWidth="2.2"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      ) : (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <rect
            x="9"
            y="9"
            width="11"
            height="11"
            rx="2.5"
            stroke="currentColor"
            strokeWidth="1.8"
          />
          <path
            d="M5 15V6.5A2.5 2.5 0 0 1 7.5 4H15"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
          />
        </svg>
      )}
    </button>
  );
}

export function HeroPanel() {
  const [active, setActive] = useState(TABS[1].id);
  const tab = TABS.find((t) => t.id === active) ?? TABS[0];

  return (
    <div className="w-full">
      {/* Pill switcher, same glass treatment as the nav so the hero reads as one surface. */}
      <div
        role="tablist"
        aria-label="What synqit does"
        className="mb-3 inline-flex items-center gap-1 rounded-full border border-black/[0.06] bg-white/70 p-1 shadow-[0_2px_20px_-6px_rgba(0,0,0,0.18)] backdrop-blur-md"
      >
        {TABS.map((t) => {
          const selected = t.id === tab.id;
          return (
            <button
              key={t.id}
              role="tab"
              type="button"
              id={`tab-${t.id}`}
              aria-selected={selected}
              aria-controls={`panel-${t.id}`}
              onClick={() => setActive(t.id)}
              className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                selected
                  ? "bg-accent text-white shadow-sm"
                  : "text-muted hover:bg-black/[0.04] hover:text-text"
              }`}
            >
              {t.label}
            </button>
          );
        })}
      </div>

      <div
        role="tabpanel"
        id={`panel-${tab.id}`}
        aria-labelledby={`tab-${tab.id}`}
        className="overflow-hidden rounded-xl border border-border bg-[#0d0e11] shadow-[0_30px_60px_-30px_rgba(0,0,0,0.5)]"
      >
        {/* Title bar: lit traffic lights plus the working directory. */}
        <div className="flex items-center gap-1.5 border-b border-white/10 px-4 py-2.5">
          <span className="h-2.5 w-2.5 rounded-full bg-[#e2665a]" />
          <span className="h-2.5 w-2.5 rounded-full bg-[#e0b341]" />
          <span className="h-2.5 w-2.5 rounded-full bg-[#3fb37f]" />
          <span className="ml-2 truncate font-mono text-[12px] text-[#8b8d92]">
            {tab.path}
          </span>
        </div>

        <div className="p-4 sm:p-5">
          <p className="text-[14px] leading-relaxed text-[#b9bbc0]">{tab.blurb}</p>

          {/* Command row: inset, horizontally scrollable, copyable. */}
          <div className="mt-4 flex items-center gap-2 rounded-lg bg-white/[0.05] py-2.5 pr-1.5 pl-3.5 ring-1 ring-inset ring-white/[0.07]">
            <code className="min-w-0 flex-1 overflow-x-auto font-mono text-[13px] whitespace-pre text-[#d8d9dc]">
              <span className="text-accent">$ </span>
              {tab.command}
            </code>
            <CopyButton value={tab.command} />
          </div>

          {tab.output && (
            <p className="mt-3 overflow-x-auto font-mono text-[13px] whitespace-pre">
              <span className="text-[#3fb37f]">{tab.output.text}</span>
              {tab.output.dim && <span className="text-[#5b5d63]">{tab.output.dim}</span>}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
