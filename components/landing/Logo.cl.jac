"""Synqit mark, optionally with the wordmark beside it."""

def:pub Logo(height: int = 18, withWordmark: bool = True, className: str = "") -> JsxElement {
    wrapper = ("flex items-center gap-2 " + className) if withWordmark else className;

    return <span className={wrapper}>
        <img
            src="/logo.png"
            alt={"" if withWordmark else "synqit"}
            style={{"height": f"{height}px", "width": "auto"}}
        />
        {if withWordmark {
            <span className="font-mono text-sm tracking-tight">synqit</span>
        }}
    </span>;
}
