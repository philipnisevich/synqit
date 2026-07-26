"""Static terminal chrome with a list of pre-formatted lines.

Each line is a dict with explicit keys - `prompt` is always present rather than
relying on a missing key, because a missing dict key reads back as JS
`undefined` in the browser and would flip the check the wrong way.
"""

def:pub TerminalWindow(lines: list[dict]) -> JsxElement {
    return <div className="overflow-x-auto rounded-xl border border-rule bg-[#0d0e11] shadow-[0_1px_0_rgba(255,255,255,0.04)_inset]">
        <div className="flex items-center gap-1.5 border-b border-white/10 px-4 py-2.5">
            <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
            <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
            <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
        </div>
        <div className="px-4 py-4 font-mono text-[13px] leading-relaxed whitespace-pre">
            {for (i, line) in enumerate(lines) {
                <div key={str(i)} className="text-[#d8d9dc]">
                    {if line["prompt"] {
                        <span className="text-brand">{"$ "}</span>
                    }}
                    {line["text"]}
                    {if line["dim"] {
                        <span className="text-[#5b5d63]">{line["dim"]}</span>
                    }}
                </div>
            }}
        </div>
    </div>;
}
