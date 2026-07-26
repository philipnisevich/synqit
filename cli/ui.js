// Tiny ANSI helpers - no dependencies. Carried over from the original Synqit.
const useColor = process.stdout.isTTY && process.env.NO_COLOR === undefined;

const wrap = (code) => (s) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : String(s));

export const c = {
  bold: wrap('1'),
  dim: wrap('2'),
  green: wrap('32'),
  red: wrap('31'),
  yellow: wrap('33'),
  cyan: wrap('36'),
  gray: wrap('90'),
};

export const step = (msg) => console.log(c.gray('  → ') + msg);
export const ok = (msg) => console.log(c.green('  ✓ ') + msg);
export const info = (msg) => console.log(msg);
export const warn = (msg) => console.log(c.yellow('  ! ') + msg);

export function progress(message) {
  if (!process.stdout.isTTY) {
    step(message);
    return () => {};
  }
  const frames = ['·', '•', '●', '•'];
  let index = 0;
  const draw = () => process.stdout.write(`\r${c.cyan(`  ${frames[index++ % frames.length]}`)} ${message}`);
  draw();
  const timer = setInterval(draw, 180);
  return () => {
    clearInterval(timer);
    process.stdout.write('\r\x1b[2K');
  };
}

export function fail(msg) {
  console.error(c.red('  ✗ ') + msg);
  process.exitCode = 1;
}
