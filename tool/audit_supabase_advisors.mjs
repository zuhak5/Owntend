import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const allowedAdvisorTitles = new Set([
  'Leaked Password Protection Disabled',
]);

function normalizeProjectRef(projectRef, supabaseUrl) {
  const explicit = projectRef?.trim();
  if (explicit) return explicit;
  const url = supabaseUrl?.trim();
  if (!url) return '';
  try {
    return new URL(url).hostname.split('.')[0] ?? '';
  } catch {
    return '';
  }
}

function oneLine(value) {
  return typeof value === 'string'
    ? value.replace(/\s+/g, ' ').trim().slice(0, 2000)
    : '';
}

function sanitizeLint(kind, lint) {
  return {
    kind,
    level: oneLine(lint?.level).toUpperCase() || 'UNKNOWN',
    name: oneLine(lint?.name) || 'unknown',
    title: oneLine(lint?.title) || 'Untitled advisor finding',
    detail: oneLine(lint?.detail),
    remediation: oneLine(lint?.remediation),
    metadata:
      lint?.metadata && typeof lint.metadata === 'object'
        ? lint.metadata
        : null,
  };
}

export async function auditSupabaseAdvisors({
  fetchImpl = globalThis.fetch,
  accessToken,
  projectRef,
  supabaseUrl,
}) {
  const resolvedRef = normalizeProjectRef(projectRef, supabaseUrl);
  if (!accessToken?.trim()) {
    throw new Error(
      'SUPABASE_ACCESS_TOKEN is required and must grant advisors_read.',
    );
  }
  if (!resolvedRef) {
    throw new Error(
      'SUPABASE_PROJECT_REF or a valid SUPABASE_URL is required.',
    );
  }

  const findings = [];
  for (const kind of ['security', 'performance']) {
    const response = await fetchImpl(
      `https://api.supabase.com/v1/projects/${encodeURIComponent(resolvedRef)}/advisors/${kind}`,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: 'application/json',
        },
      },
    );
    if (!response.ok) {
      throw new Error(
        `Supabase ${kind} advisor request failed with HTTP ${response.status}.`,
      );
    }
    const body = await response.json();
    if (!Array.isArray(body?.lints)) {
      throw new Error(`Supabase ${kind} advisor response omitted lints.`);
    }
    findings.push(...body.lints.map((lint) => sanitizeLint(kind, lint)));
  }

  const allowed = findings.filter((finding) =>
    allowedAdvisorTitles.has(finding.title),
  );
  const informational = findings.filter(
    (finding) =>
      !allowedAdvisorTitles.has(finding.title) && finding.level === 'INFO',
  );
  const actionable = findings.filter(
    (finding) =>
      !allowedAdvisorTitles.has(finding.title) && finding.level !== 'INFO',
  );
  return {
    projectRef: resolvedRef,
    checkedAt: new Date().toISOString(),
    findingCount: findings.length,
    allowedExceptionCount: allowed.length,
    informationalCount: informational.length,
    actionableCount: actionable.length,
    allowed,
    informational,
    actionable,
  };
}

async function main() {
  const outputPath = path.resolve(
    process.env.SUPABASE_ADVISOR_REPORT ?? 'artifacts/supabase-advisors.json',
  );
  let report;
  try {
    report = await auditSupabaseAdvisors({
      accessToken: process.env.SUPABASE_ACCESS_TOKEN,
      projectRef: process.env.SUPABASE_PROJECT_REF,
      supabaseUrl: process.env.SUPABASE_URL,
    });
  } catch (error) {
    report = {
      checkedAt: new Date().toISOString(),
      auditError: error instanceof Error ? error.message : String(error),
    };
  }

  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');

  if (report.auditError) {
    console.error(`Supabase Advisors audit failed: ${report.auditError}`);
    process.exitCode = 2;
    return;
  }

  console.log(
    `Supabase Advisors: ${report.findingCount} total, ` +
      `${report.allowedExceptionCount} explicitly allowed, ` +
      `${report.informationalCount} informational, ` +
      `${report.actionableCount} actionable.`,
  );
  for (const finding of [
    ...report.actionable,
    ...report.allowed,
    ...report.informational,
  ]) {
    const disposition = allowedAdvisorTitles.has(finding.title)
      ? 'ALLOWED'
      : finding.level === 'INFO'
        ? 'INFO'
        : 'ACTION REQUIRED';
    console.log(
      `[${disposition}] [${finding.kind}] [${finding.level}] ` +
        `${finding.name}: ${finding.title}`,
    );
  }
  if (report.actionableCount > 0) process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  await main();
}
