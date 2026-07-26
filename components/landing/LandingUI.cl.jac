"""Shared primitives for the landing page.

Colour classes here use the landing palette (paper/ink/rule/brand), never the
dashboard's shadcn tokens - see the note in styles/global.css.
"""

def:pub Eyebrow(children: any = None) -> JsxElement {
    return <span className="inline-block rounded-md border border-rule bg-paper-2 px-2.5 py-1 font-mono text-[11px] tracking-wide text-ink-soft uppercase">
        {children}
    </span>;
}

"""Section heading in the display serif, with an optional standfirst under it."""
def:pub SectionHead(eyebrow: str, children: any = None, sub: any = None) -> JsxElement {
    return <div className="max-w-2xl">
        <Eyebrow>{eyebrow}</Eyebrow>
        <h2 className="mt-4 font-display text-4xl leading-[1.1] sm:text-[42px]">{children}</h2>
        {if sub {
            <p className="mt-3 text-[15px] leading-relaxed text-ink-soft">{sub}</p>
        }}
    </div>;
}

"""Hairline grid that reads as one table rather than floating tiles: inner
borders only, so the group shares a single outer frame."""
def:pub CardGrid(columns: int = 3, children: any = None) -> JsxElement {
    cls = "grid overflow-hidden rounded-xl border border-rule bg-white sm:grid-cols-2";
    if columns == 3 {
        cls = cls + " lg:grid-cols-3";
    }
    return <div className={cls}>{children}</div>;
}

def:pub FeatureCard(title: str, children: any = None) -> JsxElement {
    return <div className="border-b border-rule p-6 transition last:border-b-0 hover:bg-paper-2/50 sm:border-r sm:[&:nth-child(2n)]:border-r-0 lg:[&:nth-child(2n)]:border-r lg:[&:nth-child(3n)]:border-r-0">
        <h3 className="text-[15px] font-medium text-ink">{title}</h3>
        <p className="mt-1.5 text-sm leading-relaxed text-ink-soft">{children}</p>
    </div>;
}

def:pub DetailSection(
    eyebrow: str,
    heading: str,
    visual: any = None,
    children: any = None,
    reverse: bool = False,
    band: bool = False
) -> JsxElement {
    section_cls = "bg-paper-2/60 py-24" if band else "py-24";
    grid_cls = "grid items-center gap-10 lg:grid-cols-2 lg:gap-16";
    if reverse {
        grid_cls = grid_cls + " lg:[&>*:first-child]:order-2";
    }

    return <section data-reveal className={section_cls}>
        <div className="mx-auto max-w-6xl px-6">
            <div className={grid_cls}>
                <div className="min-w-0">
                    <Eyebrow>{eyebrow}</Eyebrow>
                    <h2 className="mt-4 font-display text-3xl leading-[1.15] sm:text-4xl">{heading}</h2>
                    <div className="mt-4 space-y-3 text-[15px] leading-relaxed text-ink-soft">
                        {children}
                    </div>
                </div>
                <div className="min-w-0">{visual}</div>
            </div>
        </div>
    </section>;
}

def:pub FaqItem(q: str, a: str) -> JsxElement {
    return <details className="group border-b border-rule py-4 [&_summary::-webkit-details-marker]:hidden">
        <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-[15px] text-ink">
            {q}
            <span className="shrink-0 text-ink-soft transition group-open:rotate-45">+</span>
        </summary>
        <p className="faq-answer mt-2 max-w-2xl text-sm leading-relaxed text-ink-soft">{a}</p>
    </details>;
}
