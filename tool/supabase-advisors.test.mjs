import assert from 'node:assert/strict';
import test from 'node:test';

import {
  allowedAdvisorTitles,
  allowedAuthenticatedSecurityDefinerFunctions,
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

test('allows only reviewed by-design authenticated SECURITY DEFINER functions', async () => {
  const definerFinding = (schema, name) => ({
    name: 'authenticated_security_definer_function_executable',
    title: 'Signed-In Users Can Execute SECURITY DEFINER Function',
    level: 'WARN',
    metadata: { schema, name },
  });
  const report = await auditSupabaseAdvisors({
    accessToken: 'test-token',
    projectRef: 'project-ref',
    fetchImpl: async (url) => {
      if (!url.endsWith('/security')) return response([]);
      return response([
        definerFinding('public', 'create_asset'),
        definerFinding('public', 'unknown_function'),
        {
          name: 'anon_security_definer_function_executable',
          title: 'Public Can Execute SECURITY DEFINER Function',
          level: 'WARN',
          metadata: { schema: 'public', name: 'create_asset' },
        },
        definerFinding('owntend_private', 'compact_user_change_feed'),
        { ...definerFinding('public', 'create_asset'), metadata: null },
      ]);
    },
  });

  assert.equal(report.allowedExceptionCount, 1);
  assert.equal(report.actionableCount, 4);
  assert.ok(
    report.actionable.some(
      (finding) =>
        finding.name === 'anon_security_definer_function_executable',
    ),
    'anon-executable SECURITY DEFINER findings are never allowed',
  );
});

test('the reviewed SECURITY DEFINER allowance list stays pinned', () => {
  assert.deepEqual([...allowedAuthenticatedSecurityDefinerFunctions].sort(), [
    'public.create_asset',
    'public.create_reward_claim_request',
    'public.create_task_with_point_debit',
    'public.delete_asset_photo',
    'public.finalize_asset_photo_upload',
    'public.get_charged_operation_status',
    'public.prepare_asset_photo_upload',
    'public.record_monetization_event',
    'public.set_primary_asset_photo',
  ]);
});
