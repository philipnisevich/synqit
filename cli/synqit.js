#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { cmdLogin, cmdInit, cmdPush, cmdStatus, cmdRepair, cmdHelp } from './commands.js';
import { fail } from './ui.js';

const options = {
  base: { type: 'string' },
  github: { type: 'string' },
  branch: { type: 'string' },
  username: { type: 'string' },
  password: { type: 'string' },
  help: { type: 'boolean', short: 'h', default: false },
};

let parsed;
try {
  parsed = parseArgs({
    args: process.argv.slice(2),
    options,
    allowPositionals: true,
    strict: true,
  });
} catch (err) {
  fail(err.message);
  process.exit(1);
}

const { values: flags, positionals } = parsed;
const [command, ...rest] = positionals;

async function main() {
  if (flags.help || !command || command === 'help') {
    cmdHelp();
    return;
  }

  switch (command) {
    case 'login':
      await cmdLogin(flags);
      break;
    case 'init':
      await cmdInit(rest, flags);
      break;
    case 'push':
      await cmdPush(rest, flags);
      break;
    case 'status':
      await cmdStatus();
      break;
    case 'repair':
      await cmdRepair();
      break;
    default:
      fail(`Unknown command "${command}". Run \`synqit help\`.`);
  }
}

main().catch((err) => {
  fail(err.stack || err.message);
  process.exit(1);
});
