import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const initialSchemaMigration = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260821124930_initial_schema.sql',
);
const supabaseDeploymentWorkflow = path.join(
  repositoryRoot,
  '.github',
  'workflows',
  'deploy-supabase-migrations.yml',
);

test('profile revision is canonical at initial schema creation', async () => {
  const sql = await fs.readFile(initialSchemaMigration, 'utf8');

  const profilesIndex = sql.indexOf(
    'CREATE TABLE IF NOT EXISTS "public"."profiles"',
  );
  const revisionIndex = sql.indexOf(
    '"revision" bigint DEFAULT 1 NOT NULL',
    profilesIndex,
  );
  const revisionConstraintIndex = sql.indexOf(
    'CONSTRAINT "profiles_revision_positive"',
    profilesIndex,
  );
  const changeFeedTriggerIndex = sql.indexOf(
    'CREATE OR REPLACE TRIGGER "trg_server_change_feed_profiles"',
  );

  for (const [label, index] of [
    ['profiles table', profilesIndex],
    ['revision definition', revisionIndex],
    ['positive revision constraint', revisionConstraintIndex],
    ['profile change-feed trigger', changeFeedTriggerIndex],
  ]) {
    assert.notEqual(index, -1, `${label} must remain in the baseline`);
  }

  assert.ok(
    profilesIndex < revisionIndex,
    'revision must be part of the profile table definition',
  );
  assert.ok(
    revisionIndex < revisionConstraintIndex,
    'the positive constraint must follow the non-null default definition',
  );
  assert.ok(
    revisionConstraintIndex < changeFeedTriggerIndex,
    'revision invariants must exist before change-feed logging is enabled',
  );
  assert.doesNotMatch(sql, /ALTER TABLE[^;]+profiles[^;]+ADD COLUMN[^;]+revision/is);
  assert.doesNotMatch(sql, /UPDATE public\.profiles\s+SET revision/i);
});

test('prelaunch hosted reset is explicit, exact-main, project-bound, lifecycle-gated, and non-interactive', async () => {
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
  assert.match(workflow, /npx supabase db reset --linked --no-seed --yes/);
  assert.match(workflow, /npx supabase db push --linked --dry-run/);

  const resetIndex = workflow.indexOf(
    'npx supabase db reset --linked --no-seed --yes',
  );
  const finalDryRunIndex = workflow.lastIndexOf(
    'npx supabase db push --linked --dry-run',
  );
  assert.ok(
    resetIndex >= 0 && finalDryRunIndex > resetIndex,
    'the destructive reset must be followed by a no-pending-migrations verification',
  );
});
