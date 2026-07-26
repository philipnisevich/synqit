import Image from "next/image";

/**
 * The synqit mark — two paths converging into one. Single source of truth for
 * every placement on the site; `height` drives the size, width follows the
 * mark's own 216:128 ratio.
 */
export function Logo({
  height = 18,
  withWordmark = true,
  className = "",
}: {
  height?: number;
  withWordmark?: boolean;
  className?: string;
}) {
  const mark = (
    <Image
      src="/logo.png"
      alt={withWordmark ? "" : "synqit"}
      width={Math.round((216 / 128) * height)}
      height={height}
      priority
      className="h-[var(--logo-h)] w-auto"
      style={{ "--logo-h": `${height}px` } as React.CSSProperties}
    />
  );

  if (!withWordmark) return <span className={className}>{mark}</span>;

  return (
    <span className={`flex items-center gap-2 ${className}`}>
      {mark}
      <span className="font-mono text-sm tracking-tight">synqit</span>
    </span>
  );
}
