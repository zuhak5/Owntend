import assert from 'node:assert/strict';
import test from 'node:test';

import {
  allowedAdvisorTitles,
  auditSupabaseAdvisors,
} from './audit_supabase_advisors.mjs';

function response(lints) {
  return {
    ok: true,
    status: 200,
    async json() {
      return { lints };
    },
  };
}

test('audits both advisor families, blocks non-info findings, and preserves info evidence', async () => {
  const requested = [];
  const report = await auditSupabaseAdvisors({
    accessToken: 'test-token',
    supabaseUrl: 'https://project-ref.supabase.co',
    fetchImpl: async (url) => {
      requested.push(url);
      if (url.endsWith('/security')) {
        return response([
          {
            name: 'auth_leaked_passwords',
            title: 'Leaked Password Protection Disabled',
            level: 'WARN',
          },
          {
            name: 'mutable_search_path',
            title: 'Function Search Path Mutable',
            level: 'WARN',
          },
          {
            name: 'future_unknown',
            title: 'Future Advisor Severity',
          },
        ]);
      }
      return response([
        {
          name: 'unused_index',
          title: 'Unused Index',
          level: 'INFO',
        },
      ]);
    },
  });

  assert.equal(requested.length, 2);
  assert.equal(report.projectRef, 'project-ref');
  assert.equal(report.allowedExceptionCount, 1);
  assert.equal(report.informationalCount, 1);
  assert.equal(report.actionableCount, 2);
  assert.deepEqual(
    report.actionable.map(({ level, name }) => ({ level, name })),
    [
      { level: 'WARN', name: 'mutable_search_path' },
      { level: 'UNKNOWN', name: 'future_unknown' },
    ],
  );
  assert.deepEqual(
    report.informational.map(({ level, name }) => ({ level, name })),
    [{ level: 'INFO', name: 'unused_index' }],
  );
  assert.deepEqual([...allowedAdvisorTitles], [
    'Leaked Password Protection Disabled',
  ]);
});

test('fails closed when the management API response is unavailable', async () => {
  await assert.rejects(
    auditSupabaseAdvisors({
      accessToken: 'test-token',
      projectRef: 'project-ref',
      fetchImpl: async () => ({ ok: false, status: 403 }),
    }),
    /HTTP 403/,
  );
});
