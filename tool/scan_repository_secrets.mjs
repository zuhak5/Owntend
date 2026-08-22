import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

const patterns = [
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['GitHub token', /\bgh[pousr]_[A-Za-z0-9]{30,}\b/],
  ['OpenAI API key', /\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b/],
  ['Supabase secret key', /\bsb_secret_[A-Za-z0-9_-]{12,}\b/],
  ['AWS access key', /\bAKIA[0-9A-Z]{16}\b/],
  ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/],
  ['Slack token', /\bxox[baprs]-[0-9A-Za-z-]{20,}\b/],
];

const repositoryFiles = execFileSync(
  'git',
  ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
  {
  encoding: 'utf8',
  },
)
  .split('\0')
  .filter(Boolean);
const failures = [];

for (const file of repositoryFiles) {
  if (!fs.existsSync(file)) continue;
  const bytes = fs.readFileSync(file);
  if (bytes.includes(0)) continue;
  const source = bytes.toString('utf8');
  for (const [label, pattern] of patterns) {
    if (pattern.test(source)) failures.push(`${file}: ${label}`);
  }
}

if (failures.length > 0) {
  console.error('Potential committed secrets detected:');
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exitCode = 1;
} else {
  console.log(
    `Secret scan passed across ${repositoryFiles.length} tracked and untracked repository files.`,
  );
}
