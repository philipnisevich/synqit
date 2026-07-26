import from react { useEffect }
import from "gsap" { gsap }
import from "gsap/ScrollTrigger" { ScrollTrigger }
import from "lucide-react" { Check, ChevronDown, Wifi, BatteryCharging }

"""A fake macOS screen: menu bar, notch, and the Synqit escalation hanging out
of it. Rebuilt in DOM rather than shipped as a screenshot so it stays sharp at
any size and the copy can change without a re-capture.

The escalation IS the notch. It stays tucked inside until the screen scrolls
into view, then morphs open: widens at notch height first, then drops. The
buttons work - resolving walks the queue, and emptying it collapses the shell
back into the notch.
"""

glob CONFLICTS: list[dict[str, str]] = [
    {
        "title": "Conflict in login()",
        "body": "Your change to login()'s return type collides with Ana's guard clause, merged 18s ago, which calls it and expects the old shape.",
        "mine": "your return shape",
        "theirs": "Ana's guard clause",
        "sha": "a91f3c2"
    },
    {
        "title": "Conflict in pricing.ts",
        "body": "You removed the free tier. Dev A shipped unlimited free projects 40s ago, into the same config block. Both cannot be true at once.",
        "mine": "no free tier",
        "theirs": "unlimited free projects",
        "sha": "4c0be71"
    },
    {
        "title": "Conflict in Avatar.tsx",
        "body": "Your avatar renders initials. Marco's version, merged 2m ago, expects an image URL and falls back to a gradient.",
        "mine": "initials",
        "theirs": "image with gradient fallback",
        "sha": "7de9a04"
    }
];

glob START_SECONDS: int = 59;

glob CODE_LINES: list[dict[str, str]] = [
    {"w": "62%", "c": "bg-white/[0.16]", "i": "0"},
    {"w": "44%", "c": "bg-brand/40", "i": "1"},
    {"w": "73%", "c": "bg-white/[0.10]", "i": "1"},
    {"w": "36%", "c": "bg-white/[0.10]", "i": "2"},
    {"w": "55%", "c": "bg-[#6fce89]/35", "i": "2"},
    {"w": "48%", "c": "bg-white/[0.08]", "i": "2"},
    {"w": "30%", "c": "bg-white/[0.10]", "i": "1"},
    {"w": "67%", "c": "bg-white/[0.10]", "i": "0"},
    {"w": "41%", "c": "bg-[#e2665a]/35", "i": "1"},
    {"w": "58%", "c": "bg-white/[0.08]", "i": "2"},
    {"w": "35%", "c": "bg-white/[0.10]", "i": "2"},
    {"w": "70%", "c": "bg-white/[0.06]", "i": "1"},
    {"w": "26%", "c": "bg-white/[0.10]", "i": "0"},
    {"w": "52%", "c": "bg-white/[0.06]", "i": "1"}
];

glob TREE_ROWS: list[str] = ["68%", "52%", "80%", "44%", "61%", "73%"];

def:pub NotchMock() -> JsxElement {
    # gsap/ScrollTrigger are npm modules with no Jac type surface; bind them
    # through an `any` handle so attribute access type-checks.
    g: any = gsap;
    has screenRef: Ref[HTMLDivElement] = Ref();
    has shellRef: Ref[HTMLDivElement] = Ref();
    has contentRef: Ref[HTMLDivElement] = Ref();

    # Geometry resolved once by matchMedia, reused by collapse/replay so they
    # cannot drift from the open animation.
    has closedW: Ref[int] = Ref(150);
    has closedH: Ref[int] = Ref(30);
    has openW: Ref[int] = Ref(430);
    has openedRef: Ref[bool] = Ref(False);
    has secondsRef: Ref[int] = Ref(59);
    has prevHeight: Ref[int] = Ref(0);

    has opened: bool = False;
    has index: int = 0;
    has phase: str = "pending";
    has choice: str = "";
    has instructing: bool = False;
    has instruction: str = "";
    has seconds: int = 59;

    conflict: dict[str, str] = CONFLICTS[index];
    remaining: int = len(CONFLICTS) - index - 1;
    busy: bool = phase != "pending";

    # Open on scroll: ScrollTrigger fires the morph once the screen is in frame.
    useEffect(lambda {
        screen: any = screenRef.current;
        shell: any = shellRef.current;
        content: any = contentRef.current;
        if not screen or not shell or not content {
            return lambda { };
        }

        g.registerPlugin(ScrollTrigger);
        mq = window.matchMedia("(prefers-reduced-motion: reduce)") as any;
        reduced = mq.matches;
        mm = g.matchMedia();

        mm.add({"isDesktop": "(min-width: 640px)"}, lambda (ctx: any) {
            isDesktop = ctx.conditions.isDesktop;
            cw = 150 if isDesktop else 120;
            ch = 30 if isDesktop else 26;
            avail: int = (screen.offsetWidth as int) - 24;
            ow = 430 if avail > 430 else avail;
            closedW.current = cw;
            closedH.current = ch;
            openW.current = ow;

            if openedRef.current {
                g.set(shell, {
                    "width": ow,
                    "height": "auto",
                    "borderBottomLeftRadius": 26,
                    "borderBottomRightRadius": 26
                });
                return None;
            }

            g.set(shell, {
                "width": cw,
                "height": ch,
                "borderBottomLeftRadius": 10,
                "borderBottomRightRadius": 10
            });
            g.set(content, {"opacity": 0});

            mark_open = lambda {
                openedRef.current = True;
                opened = True;
                # Hand height back to the content so later states can reflow.
                g.set(shell, {"height": "auto"});
            };

            tl = g.timeline({
                "scrollTrigger": {"trigger": screen, "start": "top 68%", "once": True}
            });

            if reduced {
                tl.set(shell, {
                    "width": ow,
                    "height": "auto",
                    "borderBottomLeftRadius": 26,
                    "borderBottomRightRadius": 26
                });
                tl.set(content, {"opacity": 1});
                tl.call(mark_open);
                return None;
            }

            # Width first, then the drop. Both at once reads like a box scaling
            # rather than a notch opening.
            tl.to(shell, {"width": ow, "duration": 0.42, "ease": "power3.out"});
            tl.to(shell, {
                "height": "auto",
                "borderBottomLeftRadius": 26,
                "borderBottomRightRadius": 26,
                "duration": 0.62,
                "ease": "power4.out"
            }, "-=0.12");
            tl.to(content, {"opacity": 1, "duration": 0.34, "ease": "power2.out"}, "-=0.34");
            tl.call(mark_open);
            return lambda { };
        });

        return lambda { mm.revert(); };
    }, []);

    # FLIP the shell height between states so swapping conflicts or opening the
    # instruct field grows it smoothly instead of snapping.
    useEffect(lambda {
        shell: any = shellRef.current;
        if not shell or not openedRef.current {
            return lambda { };
        }
        frm = prevHeight.current;
        g.set(shell, {"height": "auto"});
        to: int = shell.offsetHeight as int;
        prevHeight.current = to;
        if frm and frm != to {
            g.fromTo(
                shell,
                {"height": frm},
                {
                    "height": to,
                    "duration": 0.32,
                    "ease": "power2.out",
                    "onComplete": lambda { g.set(shell, {"height": "auto"}); }
                }
            );
        }
        return lambda { };
    }, [index, phase, instructing, opened]);

    # Countdown. Reads through a ref so the interval closure never sees a stale
    # render snapshot of `seconds`.
    useEffect(lambda {
        if not opened or phase != "pending" {
            return lambda { };
        }
        tick = lambda {
            left = secondsRef.current - 1;
            secondsRef.current = left;
            seconds = left;
            if left <= 0 {
                # Matches the real timeout: the push ends in needs_human and the
                # developer's local work is left untouched.
                phase = "expired";
            }
        };
        iid = setInterval(tick, 1000);
        return lambda { clearInterval(iid); };
    }, [opened, phase, index]);

    def collapse() -> None {
        shell: any = shellRef.current;
        content: any = contentRef.current;
        if not shell or not content {
            return;
        }
        finish = lambda {
            openedRef.current = False;
            prevHeight.current = 0;
            opened = False;
        };
        tl = g.timeline({"onComplete": finish});
        tl.to(content, {"opacity": 0, "duration": 0.2, "ease": "power2.in"});
        tl.to(shell, {
            "height": closedH.current,
            "borderBottomLeftRadius": 10,
            "borderBottomRightRadius": 10,
            "duration": 0.42,
            "ease": "power3.inOut"
        });
        tl.to(shell, {"width": closedW.current, "duration": 0.34, "ease": "power3.inOut"}, "-=0.1");
    }

    def advance() -> None {
        if index < len(CONFLICTS) - 1 {
            index = index + 1;
            phase = "pending";
            choice = "";
            instruction = "";
            secondsRef.current = START_SECONDS;
            seconds = START_SECONDS;
        } else {
            phase = "clear";
            setTimeout(collapse, 1000);
        }
    }

    def resolve(label: str) -> None {
        if phase != "pending" {
            return;
        }
        choice = label;
        phase = "resolving";
        instructing = False;
        setTimeout(lambda {
            phase = "resolved";
            setTimeout(advance, 1100);
        }, 620);
    }

    def replay(e: MouseEvent) {
        shell: any = shellRef.current;
        content: any = contentRef.current;
        if not shell or not content {
            return;
        }
        index = 0;
        phase = "pending";
        choice = "";
        instruction = "";
        instructing = False;
        secondsRef.current = START_SECONDS;
        seconds = START_SECONDS;
        openedRef.current = True;
        prevHeight.current = 0;
        opened = True;

        g.set(shell, {"width": closedW.current});
        tl = g.timeline();
        tl.to(shell, {"width": openW.current, "duration": 0.4, "ease": "power3.out"});
        tl.to(shell, {
            "height": "auto",
            "borderBottomLeftRadius": 26,
            "borderBottomRightRadius": 26,
            "duration": 0.56,
            "ease": "power4.out"
        }, "-=0.12");
        tl.to(content, {"opacity": 1, "duration": 0.3}, "-=0.3");
    }

    def keep_mine(e: MouseEvent) { resolve(conflict["mine"]); }
    def keep_theirs(e: MouseEvent) { resolve(conflict["theirs"]); }
    def open_instruct(e: MouseEvent) { instructing = True; }
    def cancel_instruct(e: MouseEvent) { instructing = False; }
    def send_instruct(e: MouseEvent) { resolve("your instruction"); }
    def on_instruction(e: ChangeEvent) { instruction = e.target.value; }

    dot_cls = "bg-[#e2665a]";
    if phase == "resolved" {
        dot_cls = "bg-[#6fce89]";
    } elif phase == "expired" {
        dot_cls = "bg-white/30";
    }

    timer_cls = "bg-[#e2665a]/20 text-[#e2665a]" if seconds <= 10 else "bg-white/[0.08] text-white/70";

    return <div ref={screenRef} className="mx-auto w-full max-w-4xl">
        {#* Screen bezel *#}
        <div className="relative overflow-hidden rounded-[18px] border border-black/20 bg-black p-[6px] shadow-[0_40px_80px_-40px_rgba(0,0,0,0.65)] sm:rounded-[22px]">
            <div className="relative overflow-hidden rounded-[13px] sm:rounded-[16px]">
                {#* Taller on phones so the panel doesn't swallow the whole screen. *#}
                <div className="relative aspect-[4/5] w-full bg-[linear-gradient(160deg,#3b2f63_0%,#243a63_38%,#1d5563_70%,#2a6b58_100%)] sm:aspect-[16/10]">

                    {#* Editor window behind, to sell the desktop *#}
                    <div className="absolute inset-x-4 top-[52%] bottom-0 flex flex-col overflow-hidden rounded-t-lg bg-[#101114]/95 ring-1 ring-white/10 sm:inset-x-12 sm:top-[40%]">
                        <div className="flex shrink-0 items-center gap-2 border-b border-white/[0.07] px-3 py-1.5">
                            <span className="h-2 w-2 rounded-full bg-white/15" />
                            <span className="h-2 w-2 rounded-full bg-white/15" />
                            <span className="h-2 w-2 rounded-full bg-white/15" />
                            <span className="ml-2 font-mono text-[10px] text-white/40">src/auth.ts</span>
                        </div>

                        <div className="flex min-h-0 flex-1">
                            <div className="hidden w-[22%] shrink-0 space-y-2 border-r border-white/[0.06] p-2.5 sm:block">
                                {for (i, w) in enumerate(TREE_ROWS) {
                                    <div key={str(i)} className="flex items-center gap-1.5">
                                        <span className="h-1.5 w-1.5 shrink-0 rounded-[2px] bg-white/[0.14]" />
                                        <span
                                            className={"h-[5px] rounded-sm " + ("bg-brand/45" if i == 2 else "bg-white/[0.09]")}
                                            style={{"width": w}}
                                        />
                                    </div>
                                }}
                            </div>

                            <div className="min-w-0 flex-1 space-y-[7px] p-2.5 sm:p-3">
                                {for (n, l) in enumerate(CODE_LINES) {
                                    <div key={str(n)} className="flex items-center gap-2">
                                        <span className="w-3 shrink-0 text-right font-mono text-[8px] leading-none text-white/20">
                                            {str(n + 1)}
                                        </span>
                                        <span
                                            className={"h-[5px] rounded-sm " + l["c"]}
                                            style={{"width": l["w"], "marginLeft": f"{int(l['i']) * 10}px"}}
                                        />
                                    </div>
                                }}
                            </div>
                        </div>
                    </div>

                    {#* Menu bar *#}
                    <div className="absolute inset-x-0 top-0 z-20 flex h-[26px] items-center justify-between bg-black/35 px-3 text-[11px] text-white/80 backdrop-blur-md sm:h-[30px] sm:px-4 sm:text-[12px]">
                        <div className="flex items-center gap-3 sm:gap-4">
                            <span className="font-semibold">Code</span>
                            <span className="hidden sm:inline">File</span>
                            <span className="hidden sm:inline">Edit</span>
                            <span className="hidden md:inline">Go</span>
                            <span className="hidden md:inline">Run</span>
                            <span className="hidden md:inline">Terminal</span>
                        </div>

                        <div className="flex items-center gap-2.5 sm:gap-3.5">
                            {#* Synqit menu-bar item: pending count, or a check once cleared. *#}
                            {if opened and phase != "clear" {
                                <span className="flex items-center gap-1.5 rounded-full bg-brand/25 px-1.5 py-0.5 ring-1 ring-brand/40">
                                    <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-brand motion-reduce:animate-none" />
                                    <span className="font-mono text-[10px] text-white/90 tabular-nums">{str(remaining + 1)}</span>
                                </span>
                            } else {
                                <span className="flex items-center gap-1 rounded-full bg-[#6fce89]/20 px-1.5 py-0.5 ring-1 ring-[#6fce89]/40">
                                    <Check size={9} className="text-[#6fce89]" />
                                </span>
                            }}
                            <Wifi size={13} className="text-white/70" />
                            <BatteryCharging size={15} className="text-white/70" />
                            <span className="hidden font-mono text-[10px] tracking-tight text-white/70 sm:inline">Thu 2:14 PM</span>
                        </div>
                    </div>

                    {#* The notch, which is also the escalation: it morphs open in place. *#}
                    <div className="absolute inset-x-0 top-0 z-30 flex justify-center">
                        <div ref={shellRef} className="notch-shell">
                            <div>
                                <div ref={contentRef} className="px-3.5 pt-[30px] pb-3.5 text-left sm:px-5 sm:pt-[36px] sm:pb-5">
                                    {if phase == "clear" {
                                        <div className="flex items-center gap-2.5 py-1" aria-live="polite">
                                            <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[#6fce89]/20">
                                                <Check size={11} className="text-[#6fce89]" />
                                            </span>
                                            <p className="font-mono text-[13px] text-white sm:text-[14px]">
                                                All clear. Nothing left to decide.
                                            </p>
                                        </div>
                                        skip;
                                    }}

                                    <div className="flex items-center gap-2">
                                        <span className={"h-2.5 w-2.5 shrink-0 rounded-full " + dot_cls} />
                                        <h3 className="flex-1 truncate font-mono text-[13px] font-semibold text-white sm:text-[15px]">
                                            {conflict["title"]}
                                        </h3>
                                        {if phase == "pending" {
                                            <span className={"shrink-0 rounded-full px-2 py-0.5 text-[10px] tabular-nums sm:text-[11px] " + timer_cls}>
                                                {f"0:{seconds:02d} left"}
                                            </span>
                                        }}
                                        {if phase == "pending" and remaining > 0 {
                                            <span className="hidden shrink-0 rounded-full bg-white/[0.08] px-2 py-0.5 text-[11px] text-white/70 sm:inline">
                                                {f"+{remaining} more"}
                                            </span>
                                        }}
                                        <ChevronDown size={14} className="shrink-0 text-white/50" />
                                    </div>

                                    <div aria-live="polite">
                                        {if phase == "resolved" {
                                            <p className="mt-2.5 font-mono text-[12px] leading-relaxed sm:text-[13px]">
                                                <span className="text-[#6fce89]">{f"→ kept {choice}, integrated onto main"}</span>
                                                <span className="text-white/40">{" " + conflict["sha"]}</span>
                                            </p>
                                        } elif phase == "expired" {
                                            <p className="mt-2.5 text-[12px] leading-relaxed text-white/75 sm:text-[14px]">
                                                <span className="font-mono text-[#e0b341]">needs_human</span>
                                                {" - the question expired. Your local work was left untouched."}
                                            </p>
                                        } else {
                                            <p className="mt-2.5 text-[12px] leading-relaxed text-white/75 sm:text-[14px]">
                                                {conflict["body"]}
                                            </p>
                                        }}
                                    </div>

                                    {if phase == "expired" {
                                        <div className="mt-3.5">
                                            <button type="button" onClick={replay}
                                                className="rounded-lg bg-white/[0.06] px-3 py-2 text-[12px] font-semibold text-white ring-1 ring-inset ring-white/20 transition hover:bg-white/[0.12] sm:text-[13px]">
                                                Answer anyway
                                            </button>
                                        </div>
                                    } elif instructing {
                                        <div className="mt-3">
                                            <textarea
                                                rows={2}
                                                value={instruction}
                                                onChange={on_instruction}
                                                placeholder="Tell the agent how to resolve it..."
                                                className="w-full resize-none rounded-lg bg-white/[0.06] px-3 py-2 text-[12px] text-white ring-1 ring-inset ring-white/15 outline-none placeholder:text-white/35 focus:ring-[#7aa7ff]/60 sm:text-[13px]"
                                            />
                                            <div className="mt-2 flex items-center gap-2">
                                                <button type="button" disabled={len(instruction.strip()) == 0} onClick={send_instruct}
                                                    className="rounded-lg bg-[#7aa7ff] px-3 py-2 text-[12px] font-semibold text-[#0a1733] transition hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-40 sm:text-[13px]">
                                                    Send
                                                </button>
                                                <button type="button" onClick={cancel_instruct}
                                                    className="rounded-lg px-3 py-2 text-[12px] font-medium text-white/60 transition hover:text-white sm:text-[13px]">
                                                    Cancel
                                                </button>
                                            </div>
                                        </div>
                                    } else {
                                        <div className="mt-3.5 flex items-stretch gap-2">
                                            <button type="button" disabled={busy} onClick={keep_mine}
                                                className="flex-1 rounded-lg bg-[#6fce89] px-3 py-2 text-[12px] font-semibold text-[#0b2915] transition hover:brightness-105 disabled:opacity-45 sm:text-[13px]">
                                                Keep mine
                                            </button>
                                            <button type="button" disabled={busy} onClick={keep_theirs}
                                                className="flex-1 rounded-lg bg-[#e2665a] px-3 py-2 text-[12px] font-semibold text-[#2c0b08] transition hover:brightness-105 disabled:opacity-45 sm:text-[13px]">
                                                Keep theirs
                                            </button>
                                            <button type="button" disabled={busy} onClick={open_instruct}
                                                className="rounded-lg bg-white/[0.04] px-3 py-2 text-[12px] font-semibold text-[#7aa7ff] ring-1 ring-inset ring-[#7aa7ff]/45 transition hover:bg-white/[0.08] disabled:opacity-45 sm:px-3.5 sm:text-[13px]">
                                                Instruct
                                            </button>
                                        </div>
                                    }}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <p className="mt-4 flex flex-wrap items-center justify-center gap-x-2 gap-y-1 text-center font-mono text-xs text-ink-soft">
            <span>the actual escalation from Synqit's end-to-end test run</span>
            {if not opened {
                <button type="button" onClick={replay}
                    className="rounded-full px-2 py-0.5 text-ink underline underline-offset-2 transition hover:text-brand">
                    replay
                </button>
            }}
        </p>
    </div>;
}
