"""`synqit` entry point - argument parsing and dispatch only.

Unknown flags are rejected rather than ignored: a typo in `--branch` silently
publishing to the wrong branch is a far worse outcome than an error message.
"""

import sys;

import from commands { cmd_push, cmd_status, cmd_help }
import from ui { fail }

glob KNOWN_FLAGS: list[str] = ["branch", "hops"];

obj ParsedArgs {
    has positionals: list[str] = [];
    has flags: dict[str, str] = {};
}

def parse_args(argv: list[str]) -> ParsedArgs {
    result = ParsedArgs();
    i: int = 0;
    while i < len(argv) {
        arg: str = argv[i];

        if arg == "-h" or arg == "--help" {
            result.flags["help"] = "true";
            i += 1;
            continue;
        }

        # Everything after a bare `--` is literal text, so an intent may
        # contain leading dashes without being mistaken for a flag.
        if arg == "--" {
            result.positionals += argv[i + 1:];
            break;
        }

        if arg.startswith("--") {
            body: str = arg[2:];
            if "=" in body {
                parts: list[str] = body.split("=", 1);
                if parts[0] not in KNOWN_FLAGS {
                    raise Exception("Unknown flag --" + parts[0]);
                }
                result.flags[parts[0]] = parts[1];
                i += 1;
                continue;
            }
            if body not in KNOWN_FLAGS {
                raise Exception("Unknown flag --" + body);
            }
            if i + 1 >= len(argv) {
                raise Exception("--" + body + " needs a value");
            }
            result.flags[body] = argv[i + 1];
            i += 2;
            continue;
        }

        result.positionals.append(arg);
        i += 1;
    }
    return result;
}

with entry {
    argv: list[str] = sys.argv[1:];
    parsed = ParsedArgs();
    try {
        parsed = parse_args(argv);
    } except Exception as err {
        fail(str(err));
        sys.exit(1);
    }

    if parsed.flags.get("help") or not parsed.positionals {
        cmd_help();
    } else {
        command: str = parsed.positionals[0];
        rest: list[str] = parsed.positionals[1:];

        if command == "help" {
            cmd_help();
        } elif command == "push" {
            cmd_push(rest, parsed.flags.get("branch"), parsed.flags.get("hops"));
        } elif command == "status" {
            cmd_status(parsed.flags.get("branch"));
        } else {
            fail("Unknown command '" + command + "'. Run `synqit help`.");
            sys.exit(1);
        }
    }
}
