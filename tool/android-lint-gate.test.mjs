import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

async function read(relPath) {
  return fs.readFile(path.join(repositoryRoot, relPath), 'utf8');
}

export function validateLintConfig(gradleContent) {
  const errors = [];
  const lintMatch = gradleContent.match(/lint\s*\{([\s\S]*?)\n\s*\}/);
  if (!lintMatch) {
    errors.push('Missing lint configuration block in android/app/build.gradle.kts');
    return { valid: false, errors };
  }

  const lintBlock = lintMatch[1];
  if (!/checkReleaseBuilds\s*=\s*true/.test(lintBlock)) {
    errors.push('lint block must set checkReleaseBuilds = true');
  }
  if (!/abortOnError\s*=\s*true/.test(lintBlock)) {
    errors.push('lint block must set abortOnError = true');
  }
  if (!/htmlReport\s*=\s*true/.test(lintBlock)) {
    errors.push('lint block must enable htmlReport = true');
  }
  if (!/xmlReport\s*=\s*true/.test(lintBlock)) {
    errors.push('lint block must enable xmlReport = true');
  }
  if (!/sarifReport\s*=\s*true/.test(lintBlock)) {
    errors.push('lint block must enable sarifReport = true');
  }
  if (!/textReport\s*=\s*true/.test(lintBlock)) {
    errors.push('lint block must enable textReport = true');
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

test('Android app build.gradle.kts enforces blocking release lint and all reports', async () => {
  const gradleContent = await read('android/app/build.gradle.kts');
  const result = validateLintConfig(gradleContent);
  assert.equal(result.valid, true, `Lint config validation failed: ${result.errors.join('; ')}`);
  assert.equal(result.errors.length, 0);

  assert.match(gradleContent, /htmlOutput\s*=\s*file\("build\/reports\/lint-results-prodRelease\.html"\)/);
  assert.match(gradleContent, /xmlOutput\s*=\s*file\("build\/reports\/lint-results-prodRelease\.xml"\)/);
  assert.match(gradleContent, /sarifOutput\s*=\s*file\("build\/reports\/lint-results-prodRelease\.sarif"\)/);
  assert.match(gradleContent, /textOutput\s*=\s*file\("build\/reports\/lint-results-prodRelease\.txt"\)/);
});

test('Lint validator detects and rejects disabled or permissive lint configurations', () => {
  const disabledConfig = `
    android {
        lint {
            checkReleaseBuilds = false
        }
    }
  `;
  const resDisabled = validateLintConfig(disabledConfig);
  assert.equal(resDisabled.valid, false);
  assert.ok(resDisabled.errors.some(e => e.includes('checkReleaseBuilds = true')));

  const permissiveConfig = `
    android {
        lint {
            checkReleaseBuilds = true
            abortOnError = false
        }
    }
  `;
  const resPermissive = validateLintConfig(permissiveConfig);
  assert.equal(resPermissive.valid, false);
  assert.ok(resPermissive.errors.some(e => e.includes('abortOnError = true')));
});

test('Release evidence collector archives and binds Android lint reports into summary', async () => {
  const collector = await read('tool/collect_android_release_evidence.ps1');
  assert.match(collector, /lint-results-prodRelease\.html/);
  assert.match(collector, /lint-results-prodRelease\.xml/);
  assert.match(collector, /lint_html_report_file\s*=/);
  assert.match(collector, /lint_html_report_sha256\s*=/);
  assert.match(collector, /lint_xml_report_file\s*=/);
  assert.match(collector, /lint_xml_report_sha256\s*=/);
  assert.match(collector, /android_lint_verified\s*=\s*\$true/);
});

test('Production build scripts execute release builds where lint is enforced', async () => {
  const buildProd = await read('tool/build_prod.ps1');
  assert.match(buildProd, /build', 'apk', '--flavor', 'prod', '--release/);

  const buildPlay = await read('tool/build_play_prod.ps1');
  assert.match(buildPlay, /build', 'appbundle', '--flavor', 'prod', '--release/);
});
