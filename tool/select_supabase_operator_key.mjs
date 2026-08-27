import process from 'node:process';
import { pathToFileURL } from 'node:url';

const maximumInputBytes = 1024 * 1024;
const secretKeyPattern = /^sb_secret_[A-Za-z0-9_-]{20,128}$/;

export function selectSupabaseOperatorKey(payload) {
  if (!Array.isArray(payload)) {
    throw new Error('Supabase API-key response must be an array.');
  }

  const candidates = payload.filter(
    (entry) =>
      entry !== null &&
      typeof entry === 'object' &&
      entry.type === 'secret' &&
      entry.name === 'default',
  );
  if (candidates.length !== 1) {
    throw new Error('Expected exactly one default Supabase secret API key.');
  }

  const apiKey = candidates[0].api_key;
  if (typeof apiKey !== 'string' || !secretKeyPattern.test(apiKey)) {
    throw new Error('Default Supabase secret API key has an invalid shape.');
  }
  return apiKey;
}

async function readStandardInput() {
  const chunks = [];
  let totalBytes = 0;
  for await (const chunk of process.stdin) {
    totalBytes += chunk.length;
    if (totalBytes > maximumInputBytes) {
      throw new Error('Supabase API-key response exceeds the size limit.');
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function main() {
  const source = await readStandardInput();
  let payload;
  try {
    payload = JSON.parse(source);
  } catch {
    throw new Error('Supabase API-key response is not valid JSON.');
  }
  process.stdout.write(selectSupabaseOperatorKey(payload));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
