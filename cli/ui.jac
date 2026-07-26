import sys;
import os;

def stdout_is_tty -> bool {
    stream: any = sys.stdout;
    return stream.isatty() as bool;
}

glob USE_COLOR: bool = stdout_is_tty() and os.environ.get("NO_COLOR") is None;

def colorize(code: str, text: str) -> str {
    if not USE_COLOR {
        return text;
    }
    return "\x1b[" + code + "m" + text + "\x1b[0m";
}

def bold(text: str) -> str { return colorize("1", text); }
def gray(text: str) -> str { return colorize("90", text); }
def green(text: str) -> str { return colorize("32", text); }
def red(text: str) -> str { return colorize("31", text); }
def cyan(text: str) -> str { return colorize("36", text); }

def step(msg: str) { print(gray("  -> ") + msg); }
def ok(msg: str) { print(green("  [ok] ") + msg); }
def info(msg: str) { print(msg); }

def fail(msg: str) {
    stream: any = sys.stderr;
    stream.write(red("  [x] ") + msg + "\n");
}
