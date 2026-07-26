import json;
import os;

glob CONFIG_DIR: str = os.environ.get("SYNQIT_HOME", os.path.join(os.path.expanduser("~"), ".config", "synqit"));
glob CONFIG_FILE: str = os.path.join(CONFIG_DIR, "config.json");

def load_config -> dict[str, any] {
    if not os.path.exists(CONFIG_FILE) {
        return {};
    }
    handle = open(CONFIG_FILE, "r");
    data = json.load(handle);
    handle.close();
    return data as dict[str, any];
}

def save_config(cfg: dict[str, any]) {
    os.makedirs(CONFIG_DIR, exist_ok=True);
    handle = open(CONFIG_FILE, "w");
    json.dump(cfg, handle, indent=2);
    handle.close();
    os.chmod(CONFIG_FILE, 0o600);
}
