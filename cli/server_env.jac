import requests;
import os;

"""Verifies credentials against their real providers before anything gets
saved - `configure` refuses to write a .env with a token that doesn't
actually work, rather than saving first and discovering the problem later
when a push mysteriously fails."""

def verify_github_token(token: str) -> str {
    response = requests.get("https://api.github.com/user", headers={
        "accept": "application/vnd.github+json",
        "authorization": "Bearer " + token,
        "x-github-api-version": "2022-11-28",
    }, timeout=15);
    if response.status_code != 200 {
        raise Exception("GitHub rejected this token (status " + str(response.status_code) + "). Check it's valid and has Contents: read and write access.");
    }
    data = response.json();
    return data.get("login", "unknown") as str;
}

def verify_anthropic_key(key: str) {
    response = requests.get("https://api.anthropic.com/v1/models", headers={
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
    }, timeout=15);
    if response.status_code != 200 {
        raise Exception("Anthropic rejected this API key (status " + str(response.status_code) + ").");
    }
}

def write_env_file(path: str, values: dict[str, str]) {
    lines: list[str] = [];
    for key in values.keys() {
        lines.append(key + "=" + values[key]);
    }
    handle = open(path, "w");
    handle.write("\n".join(lines) + "\n");
    handle.close();
    os.chmod(path, 0o600);
}
