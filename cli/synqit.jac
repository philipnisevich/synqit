import sys;

import from commands { cmd_login, cmd_init, cmd_push, cmd_status, cmd_repair, cmd_help }
import from ui { fail }

glob KNOWN_FLAGS: list[str] = ["base", "branch", "github", "username", "password"];

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
        if arg.startswith("--") {
            body: str = arg[2:];
            if "=" in body {
                parts: list[str] = body.split("=", 1);
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
        } elif command == "login" {
            cmd_login(parsed.flags.get("base"), parsed.flags.get("username"), parsed.flags.get("password"));
        } elif command == "init" {
            project_arg: str | None = rest[0] if rest else None;
            cmd_init(project_arg, parsed.flags.get("branch"), parsed.flags.get("github"));
        } elif command == "push" {
            cmd_push(rest);
        } elif command == "status" {
            cmd_status();
        } elif command == "repair" {
            cmd_repair();
        } else {
            fail("Unknown command \"" + command + "\". Run `synqit help`.");
            sys.exit(1);
        }
    }
}
