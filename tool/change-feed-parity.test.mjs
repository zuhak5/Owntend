import assert from 'node:assert/strict';
import test from 'node:test';

import { validateChangeFeedParity } from './validate_change_feed_parity.mjs';

function fakeClient({ users = [], parityByUser = {}, rpcErrorByUser = {} }) {
  return {
    auth: {
      admin: {
        async listUsers({ page, perPage }) {
          const from = (page - 1) * perPage;
          return {
            data: { users: users.slice(from, from + perPage) },
            error: null,
          };
        },
      },
    },
    async rpc(name, { p_user_id: userId }) {
      assert.equal(name, 'validate_change_feed_parity');
      if (rpcErrorByUser[userId]) {
        return { data: null, error: rpcErrorByUser[userId] };
      }
      return { data: parityByUser[userId] ?? [], error: null };
    },
  };
}

test('zero hosted accounts is an explicit parity success', async () => {
  const report = await validateChangeFeedParity({
    supabaseUrl: 'https://example.invalid',
    serviceRoleKey: 'test-only',
    client: fakeClient({}),
  });
  assert.equal(report.status, 'pass');
  assert.equal(report.accounts_checked, 0);
  assert.deepEqual(report.failures, []);
});

test('parity evidence is aggregate and never emits user identifiers', async () => {
  const report = await validateChangeFeedParity({
    supabaseUrl: 'https://example.invalid',
    serviceRoleKey: 'test-only',
    client: fakeClient({
      users: [{ id: 'user-secret-a' }, { id: 'user-secret-b' }],
      parityByUser: {
        'user-secret-a': [
          {
            entity_type: 'area',
            canonical_count: 1,
            feed_net_count: 1,
            is_parity: true,
          },
        ],
        'user-secret-b': [
          {
            entity_type: 'asset',
            canonical_count: 2,
            feed_net_count: 1,
            is_parity: false,
          },
        ],
      },
    }),
  });
  assert.equal(report.status, 'fail');
  assert.equal(report.accounts_checked, 2);
  assert.deepEqual(report.failures, [
    {
      account_ordinal: 2,
      entity_type: 'asset',
      canonical_count: 2,
      feed_net_count: 1,
    },
  ]);
  assert.doesNotMatch(JSON.stringify(report), /user-secret/);
});

test('RPC failures identify only an account ordinal', async () => {
  await assert.rejects(
    validateChangeFeedParity({
      supabaseUrl: 'https://example.invalid',
      serviceRoleKey: 'test-only',
      client: fakeClient({
        users: [{ id: 'user-secret-a' }],
        rpcErrorByUser: { 'user-secret-a': { code: '42501' } },
      }),
    }),
    error => {
      assert.match(error.message, /account #1 \(42501\)/);
      assert.doesNotMatch(error.message, /user-secret/);
      return true;
    },
  );
});
