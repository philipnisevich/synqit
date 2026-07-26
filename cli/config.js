import { homedir } from 'node:os';
import { join } from 'node:path';
import { mkdirSync, readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs';

// Everything lives under ~/.config/synqit so the tool works from any directory.
const CONFIG_DIR = process.env.SYNQIT_HOME || join(homedir(), '.config', 'synqit');
const CONFIG_PATH = join(CONFIG_DIR, 'config.json');

export const paths = {
  configDir: CONFIG_DIR,
  configFile: CONFIG_PATH,
};

function ensureDir() {
  mkdirSync(CONFIG_DIR, { recursive: true });
}

export function loadConfig() {
  if (!existsSync(CONFIG_PATH)) return {};
  try {
    return JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
  } catch (err) {
    throw new Error(`Could not read config at ${CONFIG_PATH}: ${err.message}`);
  }
}

// Holds { base, token, username } - the server this CLI is logged into and
// as whom. Kept out of any git repo (lives under the user's home directory,
// not the project), and file-permissioned since it carries a bearer token.
export function saveConfig(cfg) {
  ensureDir();
  writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
  try { chmodSync(CONFIG_PATH, 0o600); } catch { /* Windows does not support POSIX file modes. */ }
}
