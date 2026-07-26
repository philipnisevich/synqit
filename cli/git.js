import { execFileSync } from 'node:child_process';
import { basename, resolve } from 'node:path';

function git(args, opts = {}) {
  return execFileSync('git', args, {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    ...opts,
  });
}

export function isGitRepo() {
  try {
    git(['rev-parse', '--is-inside-work-tree']);
    return true;
  } catch {
    return false;
  }
}

export function isGitRoot() {
  try {
    return resolve(git(['rev-parse', '--show-toplevel']).trim()) === resolve(process.cwd());
  } catch {
    return false;
  }
}

export function currentBranch() {
  return git(['branch', '--show-current']).trim();
}

export function headSha() {
  return git(['rev-parse', 'HEAD']).trim();
}

export function workingTreeChanges() {
  return git(['status', '--porcelain=v1', '--untracked-files=all'])
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => ({ status: line.slice(0, 2), path: line.slice(3) }));
}

export function fetchBranch(branch = 'main') {
  git(['fetch', '--quiet', 'origin', branch]);
  return git(['rev-parse', `origin/${branch}`]).trim();
}

export function syncToCommit(branch = 'main') {
  const fetched = fetchBranch(branch);
  git(['reset', '--hard', fetched]);
  return fetched;
}

// owner/repo from the origin remote when it looks like GitHub-style.
export function deriveOwnerRepo() {
  let owner = null;
  let repo = null;
  try {
    const url = git(['config', '--get', 'remote.origin.url']).trim();
    const m = url.match(/[:/]([^/:]+)\/([^/]+?)(?:\.git)?\/?$/);
    if (m) {
      owner = m[1];
      repo = m[2];
    }
  } catch {
    /* no remote */
  }
  if (!owner) {
    try {
      owner = git(['config', 'user.name']).trim() || 'anon';
    } catch {
      owner = 'anon';
    }
  }
  if (!repo) {
    try {
      repo = basename(git(['rev-parse', '--show-toplevel']).trim());
    } catch {
      repo = 'repo';
    }
  }
  return { owner, repo };
}
