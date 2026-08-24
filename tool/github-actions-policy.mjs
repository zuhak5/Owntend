import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  isAlias,
  isMap,
  isScalar,
  isSeq,
  LineCounter,
  parseDocument,
} from 'yaml';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const workflowRoot = path.join(repositoryRoot, '.github', 'workflows');
const localActionRoot = path.join(repositoryRoot, '.github', 'actions');

export const approvedActionReleases = Object.freeze({
  'actions/attest-build-provenance': Object.freeze({
    '977bb373ede98d70efdf65b84cb5f73e068dcc2a': 'v3.0.0',
  }),
  'actions/checkout': Object.freeze({
    d23441a48e516b6c34aea4fa41551a30e30af803: 'v6.1.0',
  }),
  'actions/configure-pages': Object.freeze({
    '45bfe0192ca1faeb007ade9deae92b16b8254a0d': 'v6.0.0',
  }),
  'actions/deploy-pages': Object.freeze({
    cd2ce8fcbc39b97be8ca5fce6e763baed58fa128: 'v5.0.0',
  }),
  'actions/download-artifact': Object.freeze({
    '37930b1c2abaa49bbe596cd826c3c89aef350131': 'v7.0.0',
  }),
  'actions/setup-java': Object.freeze({
    b6effb05e454b25005698d916606bdc6ffcbf961: 'v5.7.0',
  }),
  'actions/setup-node': Object.freeze({
    '249970729cb0ef3589644e2896645e5dc5ba9c38': 'v6.5.0',
  }),
  'actions/upload-artifact': Object.freeze({
    '043fb46d1a93c77aae656e7c1c64a875d1fc6a0a': 'v7.0.1',
    b7c566a772e6b6bfb58ed0dc250532a479d7789f: 'v6.0.0',
    ea165f8d65b6e75b540449e92b4886f43607fa02: 'v4.6.2',
  }),
  'actions/upload-pages-artifact': Object.freeze({
    fc324d3547104276b827a68afc52ff2a11cc49c9: 'v5.0.0',
  }),
  'denoland/setup-deno': Object.freeze({
    '22d081ff2d3a40755e97629de92e3bcbfa7cf2ed': 'v2.0.5',
  }),
  'google-github-actions/auth': Object.freeze({
    '7c6bc770dae815cd3e89ee6cdf493a5fab2cc093': 'v3.0.0',
  }),
  'google-github-actions/setup-gcloud': Object.freeze({
    aa5489c8933f4cc7a4f7d45035b3b1440c9c10db: 'v3.0.1',
  }),
  'subosito/flutter-action': Object.freeze({
    '1a449444c387b1966244ae4d4f8c696479add0b2': 'v2.23.0',
  }),
});

const fullCommitPattern = /^[0-9a-f]{40}$/;

const splitYamlComment = (line) => {
  let singleQuoted = false;
  let doubleQuoted = false;
  let escaped = false;

  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];

    if (doubleQuoted && escaped) {
      escaped = false;
      continue;
    }
    if (doubleQuoted && character === '\\') {
      escaped = true;
      continue;
    }
    if (!doubleQuoted && character === "'") {
      if (singleQuoted && line[index + 1] === "'") {
        index += 1;
      } else {
        singleQuoted = !singleQuoted;
      }
      continue;
    }
    if (!singleQuoted && character === '"') {
      doubleQuoted = !doubleQuoted;
      continue;
    }
    if (
      !singleQuoted &&
      !doubleQuoted &&
      character === '#' &&
      (index === 0 || /\s/.test(line[index - 1]))
    ) {
      return {
        content: line.slice(0, index),
        comment: line.slice(index + 1).trim(),
      };
    }
  }

  return { content: line, comment: '' };
};

const nodeLine = (node, lineCounter) => {
  const offset = node?.range?.[0] ?? 0;
  return lineCounter.linePos(offset).line;
};

const extractUsesEntries = (source, sourcePath) => {
  const normalizedSource = source.replaceAll('\r\n', '\n');
  const lines = normalizedSource.split('\n');
  const lineCounter = new LineCounter();
  const document = parseDocument(normalizedSource, {
    lineCounter,
    prettyErrors: false,
    strict: true,
    uniqueKeys: true,
  });
  const entries = [];
  const errors = [];

  for (const issue of [...document.errors, ...document.warnings]) {
    const offset = issue.pos?.[0] ?? 0;
    const lineNumber = lineCounter.linePos(offset).line;
    errors.push(`${sourcePath}:${lineNumber}: invalid YAML: ${issue.message}`);
  }
  if (document.errors.length > 0) {
    return { entries, errors };
  }

  const walk = (node) => {
    if (node === null || node === undefined) {
      return;
    }

    const lineNumber = nodeLine(node, lineCounter);
    if (isAlias(node)) {
      errors.push(
        `${sourcePath}:${lineNumber}: YAML aliases are not permitted in action policy files`,
      );
      return;
    }
    if (node.anchor !== undefined) {
      errors.push(
        `${sourcePath}:${lineNumber}: YAML anchors are not permitted in action policy files`,
      );
    }
    if (node.tag !== undefined) {
      errors.push(
        `${sourcePath}:${lineNumber}: YAML tags are not permitted in action policy files`,
      );
    }

    if (isMap(node)) {
      for (const pair of node.items) {
        if (isScalar(pair.key) && pair.key.value === 'uses') {
          const keyLine = nodeLine(pair.key, lineCounter);
          if (!isScalar(pair.value) || typeof pair.value.value !== 'string') {
            errors.push(
              `${sourcePath}:${keyLine}: uses must have one literal scalar value`,
            );
          } else {
            const valueLine = nodeLine(pair.value, lineCounter);
            const { comment } = splitYamlComment(lines[valueLine - 1] ?? '');
            entries.push({
              comment,
              lineNumber: keyLine,
              sourcePath,
              value: pair.value.value,
            });
          }
        }
        walk(pair.key);
        walk(pair.value);
      }
      return;
    }

    if (isSeq(node)) {
      for (const item of node.items) {
        walk(item);
      }
    }
  };

  walk(document.contents);
  return { entries, errors };
};

const validateEntry = (entry) => {
  const errors = [];
  const location = `${entry.sourcePath}:${entry.lineNumber}`;

  if (entry.value.startsWith('./')) {
    if (!entry.value.startsWith('./.github/actions/')) {
      errors.push(
        `${location}: local action must be owned under ./.github/actions/`,
      );
    }
    return { errors, local: true };
  }

  const separator = entry.value.lastIndexOf('@');
  if (separator <= 0 || separator === entry.value.length - 1) {
    errors.push(`${location}: external action must use owner/repository@commit`);
    return { errors, local: false };
  }

  const action = entry.value.slice(0, separator);
  const commit = entry.value.slice(separator + 1);
  if (!fullCommitPattern.test(commit)) {
    errors.push(`${location}: ${action} must use a full 40-character commit SHA`);
    return { errors, local: false };
  }

  const approvedCommits = approvedActionReleases[action];
  if (approvedCommits === undefined) {
    errors.push(`${location}: ${action} is not an owned, reviewed action`);
    return { errors, local: false };
  }

  const version = approvedCommits[commit];
  if (version === undefined) {
    errors.push(`${location}: ${action}@${commit} is not a reviewed release`);
    return { errors, local: false };
  }

  if (entry.comment !== version) {
    errors.push(
      `${location}: ${action}@${commit} must retain the exact comment # ${version}`,
    );
  }

  return { errors, local: false };
};

export const validateActionSource = (source, sourcePath = 'fixture.yml') => {
  const extracted = extractUsesEntries(source, sourcePath);
  const errors = [...extracted.errors];
  let externalReferences = 0;
  let localReferences = 0;

  for (const entry of extracted.entries) {
    const result = validateEntry(entry);
    errors.push(...result.errors);
    if (result.local) {
      localReferences += 1;
    } else {
      externalReferences += 1;
    }
  }

  return {
    entries: extracted.entries,
    errors,
    externalReferences,
    localReferences,
  };
};

const listYamlFiles = async (directory, { allowMissing = false } = {}) => {
  let directoryEntries;
  try {
    directoryEntries = await fs.readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (allowMissing && error.code === 'ENOENT') {
      return [];
    }
    throw error;
  }

  const files = [];
  for (const entry of directoryEntries) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await listYamlFiles(entryPath)));
    } else if (/\.ya?ml$/i.test(entry.name)) {
      files.push(entryPath);
    }
  }
  return files.sort();
};

const localActionDefinitionExists = async (reference) => {
  const resolved = path.resolve(repositoryRoot, reference.slice(2));
  const relative = path.relative(localActionRoot, resolved);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    return false;
  }

  for (const filename of ['action.yml', 'action.yaml']) {
    try {
      const stat = await fs.stat(path.join(resolved, filename));
      if (stat.isFile()) {
        return true;
      }
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }
  return false;
};

export const validateRepositoryActionReferences = async () => {
  const files = [
    ...(await listYamlFiles(workflowRoot)),
    ...(await listYamlFiles(localActionRoot, { allowMissing: true })),
  ];
  const errors = [];
  const localEntries = [];
  let externalReferences = 0;
  let localReferences = 0;

  for (const file of files) {
    const sourcePath = path.relative(repositoryRoot, file).replaceAll('\\', '/');
    const source = await fs.readFile(file, 'utf8');
    const result = validateActionSource(source, sourcePath);
    errors.push(...result.errors);
    externalReferences += result.externalReferences;
    localReferences += result.localReferences;
    localEntries.push(
      ...result.entries.filter((entry) => entry.value.startsWith('./')),
    );
  }

  for (const entry of localEntries) {
    if (!(await localActionDefinitionExists(entry.value))) {
      errors.push(
        `${entry.sourcePath}:${entry.lineNumber}: local action ${entry.value} has no owned action.yml or action.yaml`,
      );
    }
  }

  return { errors, externalReferences, files, localReferences };
};
