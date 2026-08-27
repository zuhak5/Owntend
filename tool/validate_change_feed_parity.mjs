import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

import { createClient } from '@supabase/supabase-js';

const pageSize = 500;

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

export async function validateChangeFeedParity({
  supabaseUrl,
  serviceRoleKey,
  client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }),
}) {
  const userIds = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await client.auth.admin.listUsers({
      page,
      perPage: pageSize,
    });
    if (error) {
      throw new Error(`Account enumeration failed (${error.code ?? 'unknown'}).`);
    }
    const users = data?.users ?? [];
    userIds.push(...users.map((user) => user.id));
    if (users.length < pageSize) break;
  }

  const failures = [];
  let checkedEntities = 0;
  for (const [index, userId] of userIds.entries()) {
    const { data, error } = await client.rpc('validate_change_feed_parity', {
      p_user_id: userId,
    });
    if (error) {
      throw new Error(
        `Parity RPC failed for account #${index + 1} (${error.code ?? 'unknown'}).`,
      );
    }
    const rows = Array.isArray(data) ? data : [];
    checkedEntities += rows.length;
    for (const row of rows) {
      if (row.is_parity !== true) {
        failures.push({
          account_ordinal: index + 1,
          entity_type: String(row.entity_type ?? 'unknown'),
          canonical_count: Number(row.canonical_count ?? 0),
          feed_net_count: Number(row.feed_net_count ?? 0),
        });
      }
    }
  }

  return {
    status: failures.length === 0 ? 'pass' : 'fail',
    accounts_checked: userIds.length,
    entity_results_checked: checkedEntities,
    failures,
    generated_at: new Date().toISOString(),
  };
}

async function main() {
  const report = await validateChangeFeedParity({
    supabaseUrl: requiredEnvironment('SUPABASE_URL'),
    serviceRoleKey: requiredEnvironment('SUPABASE_OPERATOR_SERVICE_ROLE_KEY'),
  });
  const reportPath = process.env.SUPABASE_PARITY_REPORT?.trim();
  if (reportPath) {
    const target = resolve(reportPath);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, `${JSON.stringify(report, null, 2)}\n`, {
      encoding: 'utf8',
      mode: 0o600,
    });
  }
  process.stdout.write(`${JSON.stringify(report)}\n`);
  if (report.status !== 'pass') process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await main();
}
