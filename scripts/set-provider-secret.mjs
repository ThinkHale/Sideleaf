import { emitKeypressEvents } from 'node:readline';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const allowed = new Set(['OPENAI_API_KEY', 'STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET']);
const name = process.argv[2];
const environment = process.argv[3] || 'production';
if (
  !allowed.has(name) ||
  !['preview', 'production'].includes(environment) ||
  !process.stdin.isTTY
) {
  console.error(
    'Run in an interactive terminal: node scripts/set-provider-secret.mjs OPENAI_API_KEY',
  );
  process.exit(1);
}
const cli = process.env.LOCALAPPDATA
  ? join(process.env.LOCALAPPDATA, 'Sideleaf', 'cli', 'node_modules', 'vercel', 'dist', 'index.js')
  : process.env.SIDELEAF_VERCEL_CLI;
if (!cli || !existsSync(cli)) {
  console.error('The signed-in Sideleaf Vercel CLI is not available on this computer.');
  process.exit(1);
}
process.stdout.write(`Paste ${name} and press Enter. Input stays hidden: `);
emitKeypressEvents(process.stdin);
process.stdin.setRawMode(true);
let value = await new Promise((resolve) => {
  let input = '';
  function listener(text, key) {
    if (key?.ctrl && key.name === 'c') process.exit(130);
    if (key?.name === 'return' || key?.name === 'enter') {
      process.stdin.removeListener('keypress', listener);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      resolve(input.trim());
    } else if (key?.name === 'backspace') input = input.slice(0, -1);
    else if (text && !key?.ctrl && !key?.meta) input += text;
  }
  process.stdin.on('keypress', listener);
});
process.stdout.write('\n');
if (!value || /[\r\n]/.test(value)) process.exit(1);
const result = spawnSync(
  process.execPath,
  [cli, 'env', 'add', name, environment, '--scope', 'sideleaf', '--sensitive', '--force', '--yes'],
  { input: value, encoding: 'utf8', windowsHide: true },
);
value = '';
if (result.status !== 0) {
  console.error(`Vercel could not save ${name}. Check that the CLI is signed in, then retry.`);
  process.exit(1);
}
console.log(
  `${name} was saved to Vercel's ${environment} environment. No secret file was created.`,
);
console.log('Tell Codex it is ready. A deployment is needed before the running app can use it.');
