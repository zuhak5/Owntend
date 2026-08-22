import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = process.cwd();
const ignoredDirectories = new Set([
  '.dart_tool',
  '.git',
  '.versiondeck-site',
  'build',
  'node_modules',
]);

function markdownFiles(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (ignoredDirectories.has(entry.name)) continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...markdownFiles(absolute));
    else if (entry.isFile() && entry.name.endsWith('.md')) files.push(absolute);
  }
  return files;
}

function withoutFencedCode(source) {
  return source.replace(/```[\s\S]*?```/g, '').replace(/~~~[\s\S]*?~~~/g, '');
}

function localTarget(rawTarget) {
  const target = rawTarget.trim().replace(/^<|>$/g, '');
  if (
    target === '' ||
    target.startsWith('#') ||
    /^(?:https?:|mailto:|tel:|data:)/i.test(target) ||
    target.includes('${{')
  ) {
    return null;
  }
  const pathOnly = target.split('#', 1)[0].split('?', 1)[0];
  try {
    return decodeURIComponent(pathOnly);
  } catch {
    return pathOnly;
  }
}

const failures = [];
for (const file of markdownFiles(repositoryRoot)) {
  const source = withoutFencedCode(fs.readFileSync(file, 'utf8'));
  const linkPattern = /!?(?:\[[^\]]*\])\(([^)\s]+(?:\s+"[^"]*")?)\)/g;
  for (const match of source.matchAll(linkPattern)) {
    const rawTarget = match[1].replace(/\s+"[^"]*"$/, '');
    const target = localTarget(rawTarget);
    if (target == null) continue;
    const resolved = path.resolve(path.dirname(file), target);
    if (!fs.existsSync(resolved)) {
      failures.push(
        `${path.relative(repositoryRoot, file)} -> ${rawTarget}`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error('Broken local Markdown links:');
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exitCode = 1;
} else {
  console.log('Local Markdown links resolve to repository paths.');
}
