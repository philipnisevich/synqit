"use client";

import { useEffect, useRef } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

/**
 * A fake macOS screen: menu bar, notch, and the Synqit escalation hanging out of
 * it. Modelled on the real capture from the end-to-end run, rebuilt in DOM so it
 * stays sharp at any size and the copy can change without a new screenshot.
 *
 * The escalation stays tucked inside the notch until the screen scrolls into
 * view, then drops out of it once.
 */

function MenuIcon({ children }: { children: React.ReactNode }) {
  return (
    <span className="flex h-4 w-4 items-center justify-center text-white/70">{children}</span>
  );
}

export function NotchMock() {
  const screenRef = useRef<HTMLDivElement>(null);
  const shellRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

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

    mm.add(
      { isDesktop: "(min-width: 640px)", isMobile: "(max-width: 639px)" },
      (ctx) => {
        const { isDesktop } = ctx.conditions as { isDesktop: boolean };
        const closedWidth = isDesktop ? 150 : 120;
        const closedHeight = isDesktop ? 30 : 26;
        const openWidth = Math.min(430, screen.offsetWidth - 24);

        gsap.set(shell, {
          width: closedWidth,
          height: closedHeight,
          borderBottomLeftRadius: 10,
          borderBottomRightRadius: 10,
        });
        gsap.set(content, { opacity: 0 });

        const tl = gsap.timeline({
          scrollTrigger: {
            trigger: screen,
            // Fires once the screen is properly in frame, not at first pixel.
            start: "top 68%",
            once: true,
          },
        });

        if (reduced) {
          tl.set(shell, {
            width: openWidth,
            height: "auto",
            borderBottomLeftRadius: 26,
            borderBottomRightRadius: 26,
          }).set(content, { opacity: 1 });
          return;
        }

        // Width first, then the drop: the notch stretches, then pours out. Doing
        // both at once reads like a box scaling rather than a notch opening.
        tl.to(shell, {
          width: openWidth,
          duration: 0.42,
          ease: "power3.out",
        })
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
          .to(content, { opacity: 1, duration: 0.34, ease: "power2.out" }, "-=0.34");
      },
    );

    return () => mm.revert();
  }, []);

  return (
    <div ref={screenRef} className="mx-auto w-full max-w-4xl">
      {/* Screen bezel */}
      <div className="relative overflow-hidden rounded-[18px] border border-black/20 bg-black p-[6px] shadow-[0_40px_80px_-40px_rgba(0,0,0,0.65)] sm:rounded-[22px]">
        <div className="relative overflow-hidden rounded-[13px] sm:rounded-[16px]">
          {/* Desktop wallpaper */}
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
                {/* Synqit menu-bar item, lit while a decision is pending */}
                <span className="flex items-center gap-1.5 rounded-full bg-accent/25 px-1.5 py-0.5 ring-1 ring-accent/40">
                  <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-accent motion-reduce:animate-none" />
                  <span className="font-mono text-[10px] text-white/90">1</span>
                </span>
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
                <div className="flex items-center gap-2">
                  <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-[#e2665a]" />
                  <h3 className="flex-1 truncate font-mono text-[13px] font-semibold text-white sm:text-[15px]">
                    Conflict in login()
                  </h3>
                  <span className="shrink-0 rounded-full bg-white/[0.08] px-2 py-0.5 text-[10px] text-white/70 tabular-nums sm:text-[11px]">
                    0:59 left
                  </span>
                  <span className="hidden shrink-0 rounded-full bg-white/[0.08] px-2 py-0.5 text-[11px] text-white/70 sm:inline">
                    +2 more
                  </span>
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

                <p className="mt-2.5 text-[12px] leading-relaxed text-white/75 sm:text-[14px]">
                  Your change to <span className="font-mono text-white/90">login()</span>&rsquo;s
                  return type collides with Ana&rsquo;s guard clause, merged 18s ago, which calls
                  it and expects the old shape.
                </p>

                <div className="mt-3.5 flex items-stretch gap-2">
                  <button
                    type="button"
                    className="flex-1 rounded-lg bg-[#6fce89] px-3 py-2 text-[12px] font-semibold text-[#0b2915] transition hover:brightness-105 sm:text-[13px]"
                  >
                    Keep mine
                  </button>
                  <button
                    type="button"
                    className="flex-1 rounded-lg bg-[#e2665a] px-3 py-2 text-[12px] font-semibold text-[#2c0b08] transition hover:brightness-105 sm:text-[13px]"
                  >
                    Keep theirs
                  </button>
                  <button
                    type="button"
                    className="rounded-lg bg-white/[0.04] px-3 py-2 text-[12px] font-semibold text-[#7aa7ff] ring-1 ring-inset ring-[#7aa7ff]/45 transition hover:bg-white/[0.08] sm:px-3.5 sm:text-[13px]"
                  >
                    Instruct
                  </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

      <p className="mt-4 text-center font-mono text-xs text-muted">
        the actual escalation from Synqit&rsquo;s end-to-end test run
      </p>
    </div>
  );
}
