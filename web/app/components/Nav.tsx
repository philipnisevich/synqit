const LINKS = [
  { href: "#how-it-works", label: "How it works" },
  { href: "#features", label: "Features" },
  { href: "#faq", label: "FAQ" },
];

export function Nav() {
  return (
    <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
      <div className="pointer-events-auto flex items-center gap-1 rounded-full border border-black/[0.06] bg-white/70 px-2 py-1.5 shadow-[0_2px_20px_-6px_rgba(0,0,0,0.18)] backdrop-blur-md">
        <a
          href="#top"
          className="flex items-center gap-2 rounded-full px-3 py-1.5 font-mono text-sm tracking-tight text-text"
        >
          <span className="relative inline-flex h-4 w-7 items-center justify-center rounded-full bg-text">
            <span className="h-1.5 w-1.5 rounded-full bg-accent" />
          </span>
          synqit
        </a>

        <nav className="hidden items-center sm:flex">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="rounded-full px-3 py-1.5 text-sm text-muted transition hover:bg-black/[0.04] hover:text-text"
            >
              {l.label}
            </a>
          ))}
        </nav>

        <a
          href="https://github.com/ben564885/bens-attempt"
          className="rounded-full bg-text px-3.5 py-1.5 text-sm font-medium text-white transition hover:opacity-85"
        >
          GitHub
        </a>
      </div>
    </header>
  );
}
