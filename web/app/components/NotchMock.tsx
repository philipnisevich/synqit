"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

/**
 * A fake macOS screen: menu bar, notch, and the Synqit escalation hanging out of
 * it. Modelled on the real capture from the end-to-end run, rebuilt in DOM so it
 * stays sharp at any size and the copy can change without a new screenshot.
 *
 * The escalation stays tucked inside the notch until the screen scrolls into
 * view, then morphs open. The buttons work: resolving advances through the
 * queued conflicts, and emptying the queue collapses the shell back into the
 * notch — the same shape the real menu-bar app has.
 */

const CONFLICTS = [
  {
    title: "Conflict in login()",
    body: (
      <>
        Your change to <span className="font-mono text-white/90">login()</span>&rsquo;s return
        type collides with Ana&rsquo;s guard clause, merged 18s ago, which calls it and expects
        the old shape.
      </>
    ),
    mine: "your return shape",
    theirs: "Ana's guard clause",
    sha: "a91f3c2",
  },
  {
    title: "Conflict in pricing.ts",
    body: (
      <>
        You removed the free tier. Dev A shipped unlimited free projects 40s ago, into the same
        config block. Both cannot be true at once.
      </>
    ),
    mine: "no free tier",
    theirs: "unlimited free projects",
    sha: "4c0be71",
  },
  {
    title: "Conflict in Avatar.tsx",
    body: (
      <>
        Your avatar renders initials. Marco&rsquo;s version, merged 2m ago, expects an image URL
        and falls back to a gradient.
      </>
    ),
    mine: "initials",
    theirs: "image with gradient fallback",
    sha: "7de9a04",
  },
];

const START_SECONDS = 59;

type Phase = "pending" | "resolving" | "resolved" | "expired" | "clear";

function MenuIcon({ children }: { children: React.ReactNode }) {
  return (
    <span className="flex h-4 w-4 items-center justify-center text-white/70">{children}</span>
  );
}

export function NotchMock() {
  const screenRef = useRef<HTMLDivElement>(null);
  const shellRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  // Closed/open geometry is resolved once by matchMedia and reused by the
  // collapse and replay paths so they cannot drift from the open animation.
  const dims = useRef({ closedWidth: 150, closedHeight: 30, openWidth: 430 });
  const openedRef = useRef(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  const [opened, setOpened] = useState(false);
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>("pending");
  const [choice, setChoice] = useState<string | null>(null);
  const [instructing, setInstructing] = useState(false);
  const [instruction, setInstruction] = useState("");
  const [seconds, setSeconds] = useState(START_SECONDS);

  const conflict = CONFLICTS[index];
  const remaining = CONFLICTS.length - index - 1;

  const after = useCallback((ms: number, fn: () => void) => {
    const t = setTimeout(fn, ms);
    timers.current.push(t);
  }, []);

  const clearTimers = useCallback(() => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  }, []);

  useEffect(() => () => clearTimers(), [clearTimers]);

  /* ---------- open on scroll ---------- */

  useEffect(() => {
    const screen = screenRef.current;
    const shell = shellRef.current;
    const content = contentRef.current;
    if (!screen || !shell || !content) return;

    gsap.registerPlugin(ScrollTrigger);
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    // matchMedia so the open width re-resolves on resize instead of freezing at
    // whatever the viewport was on first load.
    const mm = gsap.matchMedia();

    mm.add({ isDesktop: "(min-width: 640px)", isMobile: "(max-width: 639px)" }, (ctx) => {
      const { isDesktop } = ctx.conditions as { isDesktop: boolean };
      const closedWidth = isDesktop ? 150 : 120;
      const closedHeight = isDesktop ? 30 : 26;
      const openWidth = Math.min(430, screen.offsetWidth - 24);
      dims.current = { closedWidth, closedHeight, openWidth };

      // Re-opening after a replay should not re-run the scroll trigger.
      if (openedRef.current) {
        gsap.set(shell, {
          width: openWidth,
          height: "auto",
          borderBottomLeftRadius: 26,
          borderBottomRightRadius: 26,
        });
        return;
      }

      gsap.set(shell, {
        width: closedWidth,
        height: closedHeight,
        borderBottomLeftRadius: 10,
        borderBottomRightRadius: 10,
      });
      gsap.set(content, { opacity: 0 });

      const markOpen = () => {
        openedRef.current = true;
        setOpened(true);
        // Hand height back to the content so later state changes can reflow.
        gsap.set(shell, { height: "auto" });
      };

      const tl = gsap.timeline({
        scrollTrigger: { trigger: screen, start: "top 68%", once: true },
      });

      if (reduced) {
        tl.set(shell, {
          width: openWidth,
          height: "auto",
          borderBottomLeftRadius: 26,
          borderBottomRightRadius: 26,
        })
          .set(content, { opacity: 1 })
          .call(markOpen);
        return;
      }

      // Width first, then the drop: the notch stretches, then pours out. Doing
      // both at once reads like a box scaling rather than a notch opening.
      tl.to(shell, { width: openWidth, duration: 0.42, ease: "power3.out" })
        .to(
          shell,
          {
            height: "auto",
            borderBottomLeftRadius: 26,
            borderBottomRightRadius: 26,
            duration: 0.62,
            ease: "power4.out",
          },
          "-=0.12",
        )
        .to(content, { opacity: 1, duration: 0.34, ease: "power2.out" }, "-=0.34")
        .call(markOpen);
    });

    return () => mm.revert();
  }, []);

  /* ---------- animate height when the content changes ---------- */

  const prevHeight = useRef<number | null>(null);

  useLayoutEffect(() => {
    const shell = shellRef.current;
    if (!shell || !openedRef.current) return;

    const from = prevHeight.current;
    gsap.set(shell, { height: "auto" });
    const to = shell.offsetHeight;
    prevHeight.current = to;

    if (from === null || from === to) return;

    // FLIP the height so swapping conflicts or opening the instruct field
    // grows the shell smoothly instead of snapping.
    gsap.fromTo(
      shell,
      { height: from },
      {
        height: to,
        duration: 0.32,
        ease: "power2.out",
        onComplete: () => gsap.set(shell, { height: "auto" }),
      },
    );
  }, [index, phase, instructing, opened]);

  /* ---------- countdown ---------- */

  useEffect(() => {
    if (!opened || phase !== "pending") return;

    const id = setInterval(() => {
      setSeconds((s) => {
        if (s <= 1) {
          clearInterval(id);
          // Matches the real timeout: the push ends in needs_human and the
          // developer's local work is left untouched.
          setPhase("expired");
          return 0;
        }
        return s - 1;
      });
    }, 1000);

    return () => clearInterval(id);
  }, [opened, phase, index]);

  /* ---------- collapse back into the notch ---------- */

  const collapse = useCallback(() => {
    const shell = shellRef.current;
    const content = contentRef.current;
    if (!shell || !content) return;

    const { closedWidth, closedHeight } = dims.current;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const done = () => {
      openedRef.current = false;
      prevHeight.current = null;
      setOpened(false);
    };

    if (reduced) {
      gsap.set(content, { opacity: 0 });
      gsap.set(shell, {
        width: closedWidth,
        height: closedHeight,
        borderBottomLeftRadius: 10,
        borderBottomRightRadius: 10,
      });
      done();
      return;
    }

    gsap
      .timeline({ onComplete: done })
      .to(content, { opacity: 0, duration: 0.2, ease: "power2.in" })
      .to(shell, {
        height: closedHeight,
        borderBottomLeftRadius: 10,
        borderBottomRightRadius: 10,
        duration: 0.42,
        ease: "power3.inOut",
      })
      .to(shell, { width: closedWidth, duration: 0.34, ease: "power3.inOut" }, "-=0.1");
  }, []);

  /* ---------- resolve ---------- */

  const resolve = useCallback(
    (label: string) => {
      if (phase !== "pending") return;

      clearTimers();
      setChoice(label);
      setPhase("resolving");
      setInstructing(false);

      after(620, () => {
        setPhase("resolved");

        after(1100, () => {
          if (index < CONFLICTS.length - 1) {
            setIndex((i) => i + 1);
            setPhase("pending");
            setChoice(null);
            setInstruction("");
            setSeconds(START_SECONDS);
          } else {
            setPhase("clear");
            after(1000, collapse);
          }
        });
      });
    },
    [phase, index, after, clearTimers, collapse],
  );

  const replay = useCallback(() => {
    const shell = shellRef.current;
    const content = contentRef.current;
    if (!shell || !content) return;

    clearTimers();
    setIndex(0);
    setPhase("pending");
    setChoice(null);
    setInstruction("");
    setInstructing(false);
    setSeconds(START_SECONDS);

    const { closedWidth, openWidth } = dims.current;
    openedRef.current = true;
    prevHeight.current = null;
    setOpened(true);

    gsap.set(shell, { width: closedWidth });
    gsap
      .timeline()
      .to(shell, { width: openWidth, duration: 0.4, ease: "power3.out" })
      .to(
        shell,
        {
          height: "auto",
          borderBottomLeftRadius: 26,
          borderBottomRightRadius: 26,
          duration: 0.56,
          ease: "power4.out",
        },
        "-=0.12",
      )
      .to(content, { opacity: 1, duration: 0.3 }, "-=0.3");
  }, [clearTimers]);

  const busy = phase !== "pending";
  const mmss = `0:${String(seconds).padStart(2, "0")}`;

  return (
    <div ref={screenRef} className="mx-auto w-full max-w-4xl">
      {/* Screen bezel */}
      <div className="relative overflow-hidden rounded-[18px] border border-black/20 bg-black p-[6px] shadow-[0_40px_80px_-40px_rgba(0,0,0,0.65)] sm:rounded-[22px]">
        <div className="relative overflow-hidden rounded-[13px] sm:rounded-[16px]">
          {/* Taller on phones so the escalation panel doesn't swallow the whole screen. */}
          <div className="relative aspect-[4/5] w-full bg-[linear-gradient(160deg,#3b2f63_0%,#243a63_38%,#1d5563_70%,#2a6b58_100%)] sm:aspect-[16/10]">
            {/* Editor window behind, to sell the desktop */}
            <div className="absolute inset-x-4 top-[52%] bottom-0 flex flex-col overflow-hidden rounded-t-lg bg-[#101114]/95 ring-1 ring-white/10 sm:inset-x-12 sm:top-[40%]">
              <div className="flex shrink-0 items-center gap-2 border-b border-white/[0.07] px-3 py-1.5">
                <span className="h-2 w-2 rounded-full bg-white/15" />
                <span className="h-2 w-2 rounded-full bg-white/15" />
                <span className="h-2 w-2 rounded-full bg-white/15" />
                <span className="ml-2 font-mono text-[10px] text-white/40">src/auth.ts</span>
              </div>

              <div className="flex min-h-0 flex-1">
                {/* File tree */}
                <div className="hidden w-[22%] shrink-0 space-y-2 border-r border-white/[0.06] p-2.5 sm:block">
                  {["68%", "52%", "80%", "44%", "61%", "73%"].map((w, i) => (
                    <div key={i} className="flex items-center gap-1.5">
                      <span className="h-1.5 w-1.5 shrink-0 rounded-[2px] bg-white/[0.14]" />
                      <span
                        className={`h-[5px] rounded-sm ${i === 2 ? "bg-accent/45" : "bg-white/[0.09]"}`}
                        style={{ width: w }}
                      />
                    </div>
                  ))}
                </div>

                {/* Code lines */}
                <div className="min-w-0 flex-1 space-y-[7px] p-2.5 sm:p-3">
                  {[
                    { w: "62%", c: "bg-white/[0.16]", i: 0 },
                    { w: "44%", c: "bg-accent/40", i: 1 },
                    { w: "73%", c: "bg-white/[0.10]", i: 1 },
                    { w: "36%", c: "bg-white/[0.10]", i: 2 },
                    { w: "55%", c: "bg-[#6fce89]/35", i: 2 },
                    { w: "48%", c: "bg-white/[0.08]", i: 2 },
                    { w: "30%", c: "bg-white/[0.10]", i: 1 },
                    { w: "67%", c: "bg-white/[0.10]", i: 0 },
                    { w: "41%", c: "bg-[#e2665a]/35", i: 1 },
                    { w: "58%", c: "bg-white/[0.08]", i: 2 },
                    { w: "35%", c: "bg-white/[0.10]", i: 2 },
                    { w: "70%", c: "bg-white/[0.06]", i: 1 },
                    { w: "26%", c: "bg-white/[0.10]", i: 0 },
                    { w: "52%", c: "bg-white/[0.06]", i: 1 },
                  ].map((l, n) => (
                    <div key={n} className="flex items-center gap-2">
                      <span className="w-3 shrink-0 text-right font-mono text-[8px] leading-none text-white/20">
                        {n + 1}
                      </span>
                      <span
                        className={`h-[5px] rounded-sm ${l.c}`}
                        style={{ width: l.w, marginLeft: `${l.i * 10}px` }}
                      />
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Menu bar */}
            <div className="absolute inset-x-0 top-0 z-20 flex h-[26px] items-center justify-between bg-black/35 px-3 text-[11px] text-white/80 backdrop-blur-md sm:h-[30px] sm:px-4 sm:text-[12px]">
              <div className="flex items-center gap-3 sm:gap-4">
                <span aria-hidden="true" className="text-[13px] leading-none">
                  &#63743;
                </span>
                <span className="font-semibold">Code</span>
                <span className="hidden sm:inline">File</span>
                <span className="hidden sm:inline">Edit</span>
                <span className="hidden md:inline">Go</span>
                <span className="hidden md:inline">Run</span>
                <span className="hidden md:inline">Terminal</span>
              </div>

              <div className="flex items-center gap-2.5 sm:gap-3.5">
                {/* Synqit menu-bar item: pending count, or a check once cleared. */}
                {opened && phase !== "clear" ? (
                  <span className="flex items-center gap-1.5 rounded-full bg-accent/25 px-1.5 py-0.5 ring-1 ring-accent/40">
                    <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-accent motion-reduce:animate-none" />
                    <span className="font-mono text-[10px] text-white/90 tabular-nums">
                      {remaining + 1}
                    </span>
                  </span>
                ) : (
                  <span className="flex items-center gap-1.5 rounded-full bg-[#6fce89]/20 px-1.5 py-0.5 ring-1 ring-[#6fce89]/40">
                    <svg width="9" height="9" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                      <path
                        d="m5 13 4 4L19 7"
                        stroke="#6fce89"
                        strokeWidth="3"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                  </span>
                )}
                <MenuIcon>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <path
                      d="M2 8.5a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16.5a5 5 0 0 1 6 0"
                      stroke="currentColor"
                      strokeWidth="1.9"
                      strokeLinecap="round"
                    />
                    <circle cx="12" cy="20" r="1.2" fill="currentColor" />
                  </svg>
                </MenuIcon>
                <MenuIcon>
                  <svg width="20" height="13" viewBox="0 0 28 14" fill="none" aria-hidden="true">
                    <rect
                      x="1"
                      y="1.5"
                      width="22"
                      height="11"
                      rx="3"
                      stroke="currentColor"
                      strokeWidth="1.4"
                    />
                    <rect x="3" y="3.5" width="14" height="7" rx="1.5" fill="currentColor" />
                    <path
                      d="M25 5.5v3"
                      stroke="currentColor"
                      strokeWidth="1.6"
                      strokeLinecap="round"
                    />
                  </svg>
                </MenuIcon>
                <span className="hidden font-mono text-[10px] tracking-tight text-white/70 sm:inline">
                  Thu 2:14 PM
                </span>
              </div>
            </div>

            {/* The notch, which is also the escalation: it morphs open in place. */}
            <div className="absolute inset-x-0 top-0 z-30 flex justify-center">
              <div ref={shellRef} className="notch-shell">
                <div>
                  <div
                    ref={contentRef}
                    className="px-3.5 pt-[30px] pb-3.5 text-left sm:px-5 sm:pt-[36px] sm:pb-5"
                  >
                    {phase === "clear" ? (
                      <div className="flex items-center gap-2.5 py-1" aria-live="polite">
                        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[#6fce89]/20">
                          <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
                            <path
                              d="m5 13 4 4L19 7"
                              stroke="#6fce89"
                              strokeWidth="3"
                              strokeLinecap="round"
                              strokeLinejoin="round"
                            />
                          </svg>
                        </span>
                        <p className="font-mono text-[13px] text-white sm:text-[14px]">
                          All clear. Nothing left to decide.
                        </p>
                      </div>
                    ) : (
                      <>
                        <div className="flex items-center gap-2">
                          <span
                            className={`h-2.5 w-2.5 shrink-0 rounded-full ${
                              phase === "resolved"
                                ? "bg-[#6fce89]"
                                : phase === "expired"
                                  ? "bg-white/30"
                                  : "bg-[#e2665a]"
                            }`}
                          />
                          <h3 className="flex-1 truncate font-mono text-[13px] font-semibold text-white sm:text-[15px]">
                            {conflict.title}
                          </h3>

                          {phase === "pending" && (
                            <span
                              className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] tabular-nums sm:text-[11px] ${
                                seconds <= 10
                                  ? "bg-[#e2665a]/20 text-[#e2665a]"
                                  : "bg-white/[0.08] text-white/70"
                              }`}
                            >
                              {mmss} left
                            </span>
                          )}
                          {phase === "pending" && remaining > 0 && (
                            <span className="hidden shrink-0 rounded-full bg-white/[0.08] px-2 py-0.5 text-[11px] text-white/70 sm:inline">
                              +{remaining} more
                            </span>
                          )}

                          <svg
                            width="14"
                            height="14"
                            viewBox="0 0 24 24"
                            fill="none"
                            aria-hidden="true"
                            className="shrink-0 text-white/50"
                          >
                            <path
                              d="m6 9 6 6 6-6"
                              stroke="currentColor"
                              strokeWidth="2"
                              strokeLinecap="round"
                              strokeLinejoin="round"
                            />
                          </svg>
                        </div>

                        <div aria-live="polite">
                          {phase === "resolved" ? (
                            <p className="mt-2.5 font-mono text-[12px] leading-relaxed sm:text-[13px]">
                              <span className="text-[#6fce89]">
                                &rarr; kept {choice}, integrated onto main
                              </span>
                              <span className="text-white/40"> {conflict.sha}</span>
                            </p>
                          ) : phase === "expired" ? (
                            <p className="mt-2.5 text-[12px] leading-relaxed text-white/75 sm:text-[14px]">
                              <span className="font-mono text-[#e0b341]">needs_human</span> — the
                              question expired. Your local work was left untouched.
                            </p>
                          ) : (
                            <p className="mt-2.5 text-[12px] leading-relaxed text-white/75 sm:text-[14px]">
                              {conflict.body}
                            </p>
                          )}
                        </div>

                        {phase === "expired" ? (
                          <div className="mt-3.5">
                            <button
                              type="button"
                              onClick={replay}
                              className="rounded-lg bg-white/[0.06] px-3 py-2 text-[12px] font-semibold text-white ring-1 ring-inset ring-white/20 transition hover:bg-white/[0.12] sm:text-[13px]"
                            >
                              Answer anyway
                            </button>
                          </div>
                        ) : instructing ? (
                          <div className="mt-3">
                            <textarea
                              autoFocus
                              rows={2}
                              value={instruction}
                              onChange={(e) => setInstruction(e.target.value)}
                              placeholder="Tell the agent how to resolve it…"
                              className="w-full resize-none rounded-lg bg-white/[0.06] px-3 py-2 text-[12px] text-white ring-1 ring-inset ring-white/15 outline-none placeholder:text-white/35 focus:ring-[#7aa7ff]/60 sm:text-[13px]"
                            />
                            <div className="mt-2 flex items-center gap-2">
                              <button
                                type="button"
                                disabled={!instruction.trim()}
                                onClick={() => resolve("your instruction")}
                                className="rounded-lg bg-[#7aa7ff] px-3 py-2 text-[12px] font-semibold text-[#0a1733] transition hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-40 sm:text-[13px]"
                              >
                                Send
                              </button>
                              <button
                                type="button"
                                onClick={() => setInstructing(false)}
                                className="rounded-lg px-3 py-2 text-[12px] font-medium text-white/60 transition hover:text-white sm:text-[13px]"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        ) : (
                          <div className="mt-3.5 flex items-stretch gap-2">
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => resolve(conflict.mine)}
                              className="flex-1 rounded-lg bg-[#6fce89] px-3 py-2 text-[12px] font-semibold text-[#0b2915] transition hover:brightness-105 disabled:opacity-45 sm:text-[13px]"
                            >
                              Keep mine
                            </button>
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => resolve(conflict.theirs)}
                              className="flex-1 rounded-lg bg-[#e2665a] px-3 py-2 text-[12px] font-semibold text-[#2c0b08] transition hover:brightness-105 disabled:opacity-45 sm:text-[13px]"
                            >
                              Keep theirs
                            </button>
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => setInstructing(true)}
                              className="rounded-lg bg-white/[0.04] px-3 py-2 text-[12px] font-semibold text-[#7aa7ff] ring-1 ring-inset ring-[#7aa7ff]/45 transition hover:bg-white/[0.08] disabled:opacity-45 sm:px-3.5 sm:text-[13px]"
                            >
                              Instruct
                            </button>
                          </div>
                        )}
                      </>
                    )}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <p className="mt-4 flex flex-wrap items-center justify-center gap-x-2 gap-y-1 text-center font-mono text-xs text-muted">
        <span>the actual escalation from Synqit&rsquo;s end-to-end test run</span>
        {!opened && (
          <button
            type="button"
            onClick={replay}
            className="rounded-full px-2 py-0.5 text-text underline underline-offset-2 transition hover:text-accent"
          >
            replay
          </button>
        )}
      </p>
    </div>
  );
}
