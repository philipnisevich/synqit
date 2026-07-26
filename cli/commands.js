import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { loadConfig, saveConfig } from './config.js';
import { register, login, callWalker } from './api.js';
import { deriveOwnerRepo, isGitRoot, currentBranch, headSha, workingTreeChanges, fetchBranch, syncToCommit } from './git.js';
import { changedFiles, hashesFor, loadState, readTrackedWorkspace, saveState } from './workspace.js';
import { c, step, ok, info, fail, progress } from './ui.js';

const DEFAULT_BASE = 'http://localhost:8899';

function requireSession() {
  const cfg = loadConfig();
  if (!cfg.token || !cfg.base) throw new Error('Not logged in. Run `synqit login --base <server-url>` first.');
  return cfg;
}

async function ask(rl, prompt) {
  return (await rl.question(prompt)).trim();
}

async function askSecret(rl, prompt) {
  const originalWrite = rl._writeToOutput;
  rl._writeToOutput = (text) => {
    if (text === prompt) originalWrite.call(rl, text);
    else output.write('*');
  };
  try {
    return (await rl.question(prompt)).trim();
  } finally {
    output.write('\n');
    rl._writeToOutput = originalWrite;
  }
}

export async function cmdLogin(flags) {
  const base = (flags.base || loadConfig().base || DEFAULT_BASE).replace(/\/+$/, '');

  // --username/--password support non-interactive use (scripting/CI). Real
  // interactive use should prefer the prompt below, so a password never
  // ends up in shell history.
  let username = flags.username;
  let password = flags.password;
  let rl;
  if (!username || !password) {
    if (!input.isTTY) return fail('`synqit login` must run in an interactive terminal, or pass --username/--password.');
    rl = createInterface({ input, output });
    username = username || await ask(rl, 'Username: ');
    password = password || await askSecret(rl, 'Password: ');
  }

  try {
    if (!username || !password) return fail('Username and password are required.');

    step(`Connecting to ${base}`);
    let session;
    try {
      session = await login(base, username, password);
      ok(`logged in as ${session.username}`);
    } catch (loginError) {
      step('No existing account matched — creating one');
      try {
        session = await register(base, username, password);
        ok(`account created and logged in as ${session.username}`);
      } catch (registerError) {
        return fail(`Login failed (${loginError.message}). Tried creating an account too, that also failed: ${registerError.message}`);
      }
    }
    saveConfig({ base, token: session.token, username: session.username });
    info(c.gray(`    Credentials saved. Run \`synqit init\` from a project's repo root next.`));
  } finally {
    rl?.close();
  }
}

export async function cmdInit(positionals, flags) {
  const cfg = requireSession();
  if (loadState()) return fail('This folder is already connected. Run `synqit status` or `synqit repair` instead.');
  if (!isGitRoot()) return fail('Run `synqit init` from the root of a cloned GitHub repository.');
  const branch = flags.branch || 'main';
  const changes = workingTreeChanges();
  if (changes.length) return fail(`This workspace has ${changes.length} local change${changes.length === 1 ? '' : 's'}. Start from a fresh clone, then run init again.`);
  if (currentBranch() !== branch) return fail(`You are on ${currentBranch() || 'no branch'}, but Synqit requires ${branch}. Run \`git switch ${branch}\` and try again.`);
  let remoteSha;
  try { remoteSha = fetchBranch(branch); } catch { return fail(`Could not fetch origin/${branch}. Check your GitHub remote and internet connection.`); }
  if (headSha() !== remoteSha) return fail(`This clone is behind GitHub ${branch}. Run \`git pull --ff-only origin ${branch}\`, then retry.`);

  const derived = deriveOwnerRepo();
  const repository = flags.github || `${derived.owner}/${derived.repo}`;
  const project = positionals[0] || repository.replace('/', '-');

  step(`Connecting ${project} (${repository}) on ${cfg.base}`);
  try {
    const created = await callWalker(cfg.base, cfg.token, 'create_project', { name: project, repository, branch });
    if (created.status === 'created') ok(`created project ${project}`);
    else info(c.gray(`    project ${project} already exists — joining it`));

    const stop = progress('Seeding project graph from GitHub…');
    await callWalker(cfg.base, cfg.token, 'seed_project', {
      project, owner: derived.owner, repo: derived.repo, branch,
    });
    stop();

    const status = await callWalker(cfg.base, cfg.token, 'get_project', { name: project });
    saveState({ project, base: cfg.base, branch, baseSha: status.head, fileHashes: hashesFor(readTrackedWorkspace()) });
    ok(`initialized ${project} at ${status.head.slice(0, 7)}`);
  } catch (error) {
    fail(error.message);
  }
}

export async function cmdPush(positionals) {
  const cfg = requireSession();
  const intent = positionals.join(' ').trim();
  if (!intent) return fail('Describe the feature: synqit push "Add password validation"');
  const state = loadState();
  if (!state) return fail('This folder is not connected. Run `synqit init` first.');

  const snapshot = readTrackedWorkspace();
  const changes = changedFiles(snapshot, state.fileHashes);
  if (!changes.length) return info(c.gray('Nothing to push — this workspace is already synced.'));

  info(c.bold(`synqit: pushing feature → ${state.project}`));
  info(c.gray(`    "${intent}"`));
  info(c.gray(`    ${changes.length} changed file${changes.length === 1 ? '' : 's'} from ${state.baseSha.slice(0, 7)}`));

  const stopProgress = progress('Integrating and publishing (this calls an LLM, can take a minute)…');
  try {
    const result = await callWalker(cfg.base, cfg.token, 'push', {
      project: state.project,
      intent,
      base_sha: state.baseSha,
      changes,
      submitter: cfg.username,
    }, { timeoutMs: 300000 });
    stopProgress();

    if (result.status === 'needs_human') {
      fail('Synqit needs a human product decision.');
      if (result.reason) info(c.gray(`    ${result.reason}`));
      return info(c.gray('    Your local work is unchanged.'));
    }
    if (result.status === 'integration_incomplete') {
      fail('Integration could not be verified as complete after retries.');
      if (result.reason) info(c.gray(`    ${result.reason}`));
      return info(c.gray('    Your local work is unchanged. Try a smaller/more specific push.'));
    }
    if (result.status !== 'published') {
      return fail(`Unexpected result: ${JSON.stringify(result)}`);
    }

    try {
      const syncedSha = syncToCommit(state.branch || 'main');
      saveState({ ...state, baseSha: syncedSha, fileHashes: hashesFor(readTrackedWorkspace()) });
      ok(`published → GitHub ${result.head.slice(0, 7)}`);
      info(c.cyan('    synced this workspace to the new shared main. You are ready for the next feature.'));
    } catch (syncError) {
      fail(`Published to GitHub ${result.head.slice(0, 7)}, but this workspace could not sync automatically. Run \`synqit repair\`. (${syncError.message})`);
    }
  } catch (error) {
    stopProgress();
    fail(error.message);
  }
}

export async function cmdStatus() {
  const cfg = requireSession();
  const state = loadState();
  if (!state) return fail('This folder is not connected. Run `synqit init` first.');
  const changes = changedFiles(readTrackedWorkspace(), state.fileHashes);
  info(`Synqit project: ${state.project}`);
  info(`  server: ${state.base}`);
  info(`  logged in as: ${cfg.username}`);
  info(`  local changes ready to push: ${changes.length}`);
  try {
    const proj = await callWalker(cfg.base, cfg.token, 'get_project', { name: state.project });
    info(`  shared GitHub commit: ${proj.head.slice(0, 7)}${proj.head === state.baseSha ? ' (up to date)' : ' (newer version available — run synqit repair)'}`);
  } catch (error) {
    fail(error.message);
  }
}

export async function cmdRepair() {
  const cfg = requireSession();
  const state = loadState();
  if (!state) return fail('This folder is not connected. Run `synqit init` first.');
  step(`Restoring this workspace to ${state.project}`);
  try {
    await callWalker(cfg.base, cfg.token, 'get_project', { name: state.project });
    const syncedSha = syncToCommit(state.branch || 'main');
    saveState({ ...state, baseSha: syncedSha, fileHashes: hashesFor(readTrackedWorkspace()) });
    ok(`restored GitHub ${syncedSha.slice(0, 7)} — this workspace is clean and synced`);
  } catch (error) {
    fail(error.message);
  }
}

export function cmdHelp() {
  info(`${c.bold('synqit')} — shared source control without branches, commits, or pulls

${c.bold('Usage')}
  synqit login [--base <url>]      Log in (or create an account) on a Synqit server
  synqit init [project]            Connect this repo root to Synqit
  synqit push "feature intent"     Submit a feature and sync this workspace
  synqit status                    Show this workspace's sync state
  synqit repair                    Restore this workspace to shared GitHub main
  synqit help                      Show this help

${c.bold('Example')}
  synqit login --base https://synqit.example
  synqit init hackathon-demo
  synqit push "Add password validation"`);
}
