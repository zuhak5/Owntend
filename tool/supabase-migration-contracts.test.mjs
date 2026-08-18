import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const profileRevisionMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260815000006_profile_revision.sql',
);
const supabaseDeploymentWorkflow = path.join(
  repositoryRoot,
  '.github',
  'workflows',
  'deploy-supabase-migrations.yml',
);

test('profile revision baseline protects NULL initialization from metadata trigger', async () => {
  const sql = await fs.readFile(profileRevisionMigration, 'utf8');

  const beginIndex = sql.indexOf('BEGIN;');
  const addColumnIndex = sql.indexOf(
    'ADD COLUMN IF NOT EXISTS revision BIGINT;',
  );
  const disableIndex = sql.indexOf('DISABLE TRIGGER set_row_metadata;');
  const backfillIndex = sql.indexOf('UPDATE public.profiles');
  const enableIndex = sql.indexOf('ENABLE TRIGGER set_row_metadata;');
  const notNullIndex = sql.indexOf('ALTER COLUMN revision SET NOT NULL;');
  const changeFeedTriggerIndex = sql.indexOf(
    'CREATE TRIGGER trg_server_change_feed_profiles',
  );
  const commitIndex = sql.lastIndexOf('COMMIT;');

  for (const [label, index] of [
    ['BEGIN', beginIndex],
    ['revision column addition', addColumnIndex],
    ['metadata trigger disable', disableIndex],
    ['profile revision initialization', backfillIndex],
    ['metadata trigger enable', enableIndex],
    ['revision NOT NULL constraint', notNullIndex],
    ['profile change-feed trigger', changeFeedTriggerIndex],
    ['COMMIT', commitIndex],
  ]) {
    assert.notEqual(index, -1, `${label} must remain in the baseline`);
  }

  assert.ok(beginIndex < addColumnIndex, 'baseline must add revision after BEGIN');
  assert.ok(
    addColumnIndex < disableIndex,
    'revision must exist before disabling the profile metadata trigger',
  );
  assert.ok(
    disableIndex < backfillIndex,
    'metadata trigger must be disabled before initializing profile revisions',
  );
  assert.ok(
    backfillIndex < enableIndex,
    'metadata trigger must be restored after profile revision initialization',
  );
  assert.ok(
    enableIndex < notNullIndex,
    'metadata trigger must be restored before steady-state constraints are enforced',
  );
  assert.ok(
    notNullIndex < changeFeedTriggerIndex,
    'revision constraints must be established before enabling profile change-feed logging',
  );
  assert.ok(
    changeFeedTriggerIndex < commitIndex,
    'all profile sync changes must remain inside the baseline transaction',
  );

  assert.match(
    sql,
    /UPDATE public\.profiles\s+SET revision = 1\s+WHERE revision IS NULL;/,
    'profiles must be initialized to revision 1',
  );
});

test('prelaunch hosted reset is explicit, exact-main, project-bound, and lifecycle-gated', async () => {
  const workflow = await fs.readFile(supabaseDeploymentWorkflow, 'utf8');

  assert.match(workflow, /reset-prelaunch-database/);
  assert.match(workflow, /reset-prelaunch-zero-user/);
  assert.match(
    workflow,
    /grep -Fqx -- '- \[ \] Project is published and has active users' AGENTS\.md/,
  );
  assert.match(workflow, /test "\$source_sha" = "\$INPUT_SOURCE_SHA"/);
  assert.match(workflow, /test "\$source_sha" = "\$GITHUB_SHA"/);
  assert.match(workflow, /test "\$source_sha" = "\$remote_sha"/);
  assert.match(workflow, /test "\$INPUT_PROJECT_REF" = "\$expected_ref"/);
  assert.match(workflow, /environment: production-supabase-migrations/);
  assert.match(workflow, /npx supabase db reset --linked --no-seed/);
  assert.match(workflow, /npx supabase db push --linked --dry-run/);

  const resetIndex = workflow.indexOf('npx supabase db reset --linked --no-seed');
  const finalDryRunIndex = workflow.lastIndexOf(
    'npx supabase db push --linked --dry-run',
  );
  assert.ok(
    resetIndex >= 0 && finalDryRunIndex > resetIndex,
    'the destructive reset must be followed by a no-pending-migrations verification',
  );
});
