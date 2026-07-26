import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';

const STATE_DIR = '.synqit';
const STATE_FILE = 'state.json';

export function statePath(root = process.cwd()) {
  return join(root, STATE_DIR, STATE_FILE);
}

export function loadState(root = process.cwd()) {
  const file = statePath(root);
  if (!existsSync(file)) return null;
  return JSON.parse(readFileSync(file, 'utf8'));
}

export function saveState(state, root = process.cwd()) {
  ignoreSynqitState(root);
  mkdirSync(dirname(statePath(root)), { recursive: true });
  writeFileSync(statePath(root), JSON.stringify(state, null, 2) + '\n', 'utf8');
}

// Keep per-workspace Synqit metadata out of normal Git workflows without
// changing the project's shared .gitignore file.
function ignoreSynqitState(root) {
  const exclude = join(root, '.git', 'info', 'exclude');
  if (!existsSync(exclude)) return;
  const current = readFileSync(exclude, 'utf8');
  if (!current.split(/\r?\n/).includes('.synqit/')) {
    appendFileSync(exclude, `${current.endsWith('\n') || !current ? '' : '\n'}.synqit/\n`, 'utf8');
  }
}

export function hash(content) {
  return createHash('sha256').update(content).digest('hex');
}

// Every git-tracked file's content, keyed by repo-relative path. Reading via
// `git ls-files` (not walking the directory tree) means .gitignore is
// respected automatically and matches exactly what a push should be judged
// against - untracked scratch files never leak into a push.
export function readTrackedWorkspace(root = process.cwd()) {
  const files = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' })
    .split('\0')
    .filter(Boolean);
  return Object.fromEntries(
    files.map((path) => [path, readFileSync(join(root, path), 'utf8').replace(/\r\n/g, '\n')])
  );
}

export function hashesFor(snapshot) {
  return Object.fromEntries(Object.entries(snapshot).map(([path, content]) => [path, hash(content)]));
}

// Diff the current tracked workspace against the hashes recorded at last
// sync. Hash-based, not `git diff` - works whether or not anything was
// staged or committed, since Synqit doesn't use commits as its unit of work.
export function changedFiles(snapshot, knownHashes) {
  const paths = new Set([...Object.keys(snapshot), ...Object.keys(knownHashes || {})]);
  const changes = [];
  for (const path of paths) {
    const content = snapshot[path];
    const currentHash = content === undefined ? null : hash(content);
    const knownHash = knownHashes?.[path] ?? null;
    if (currentHash === knownHash) continue;
    if (content === undefined) {
      changes.push({ path, change_type: 'deleted' });
    } else {
      changes.push({ path, content, change_type: knownHash === null ? 'added' : 'modified' });
    }
  }
  return changes.sort((a, b) => a.path.localeCompare(b.path));
}
