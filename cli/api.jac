import requests;
import json;

"""Thin client for the Jac service. Two distinct failure shapes: framework-
level (`ok: false`) and our own walkers' soft errors (`ok: true`, but the
reported value is `{"error": "..."}`) - call_walker surfaces both the same
way so callers only check one thing."""

def headers(token: str | None) -> dict[str, str] {
    h: dict[str, str] = {"content-type": "application/json"};
    if token {
        h["authorization"] = "Bearer " + token;
    }
    return h;
}

def do_request(url: str, method: str, token: str | None, payload: dict | None, timeout_s: int) -> dict {
    try {
        response = requests.request(method, url, headers=headers(token), json=payload, timeout=timeout_s);
    } except requests.exceptions.RequestException {
        raise Exception("Could not reach Synqit at " + url + ".");
    }
    body: dict = {};
    try {
        body = response.json() as dict;
    } except Exception {
        body = {};
    }
    if response.status_code >= 300 or not body.get("ok", True) {
        error = body.get("error");
        message: str = "Server responded " + str(response.status_code) + ".";
        if isinstance(error, dict) {
            message = error.get("message", message) as str;
        } elif isinstance(error, str) {
            message = error;
        }
        raise Exception(message);
    }
    return body;
}

def register(base: str, username: str, password: str) -> dict {
    body = do_request(base + "/user/register", "POST", None, {
        "identities": [{"type": "username", "value": username}],
        "credential": {"type": "password", "password": password},
    }, 30);
    return body["data"] as dict;
}

def login(base: str, username: str, password: str) -> dict {
    body = do_request(base + "/user/login", "POST", None, {
        "identity": {"type": "username", "value": username},
        "credential": {"type": "password", "password": password},
    }, 30);
    return body["data"] as dict;
}

"""Every walker in this service reports exactly one value. Unwrap to that
value, and treat a reported `{"error": ...}` the same as a hard failure -
callers never need to know which failure style produced it."""
def call_walker(base: str, token: str, name: str, payload: dict, timeout_s: int) -> any {
    body = do_request(base + "/walker/" + name, "POST", token, payload, timeout_s);
    data: dict = body.get("data", {}) as dict;
    reports: list = data.get("reports", []) as list;
    if not reports {
        return {};
    }
    result = reports[0];
    if isinstance(result, dict) and "error" in result {
        error_value = result["error"];
        message: str = error_value if isinstance(error_value, str) else json.dumps(error_value);
        raise Exception(message);
    }
    return result;
}
