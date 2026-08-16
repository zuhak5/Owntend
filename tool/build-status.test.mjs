import assert from "node:assert/strict";
import test from "node:test";
import {
  buildHistoricalModel,
  createBuildSnapshot,
  createStepPreview,
  detectBuildTransition,
  formatElapsedTime,
  formatEtaRange,
  formatRemainingTime,
  isVisibleBuildStep,
  median,
  phaseForStepName,
  selectActiveRun,
} from "../download-site/build-status.js";
import { parseVersionDeckTarget } from "./build_versiondeck_site.mjs";

const START = Date.parse("2026-08-04T12:00:00Z");

function step(name, offset, duration, status = "completed", conclusion = null) {
  return {
    name,
    status,
    conclusion: conclusion ?? (status === "completed" ? "success" : null),
    started_at: new Date(START + offset * 1000).toISOString(),
    completed_at: status === "completed"
      ? new Date(START + (offset + duration) * 1000).toISOString()
      : null,
  };
}

function successfulJob(multiplier = 1) {
  return {
    name: "Build signed production APK",
    status: "completed",
    conclusion: "success",
    steps: [
      step("Set up job", 0, 1),
      step("Check out repository", 1, 10 * multiplier),
      step("Build and test production APK", 11, 300 * multiplier),
      step("Verify package, version, checksum, and signer", 311, 60 * multiplier),
      step("Upload production APK handoff", 371, 30 * multiplier),
      step("Post Check out repository", 401, 1),
      step("Complete job", 402, 1),
    ],
  };
}

test("median is outlier resistant", () => {
  assert.equal(median([10, 11, 12, 1000, 13]), 12);
});

test("hidden Actions housekeeping steps are excluded", () => {
  assert.equal(isVisibleBuildStep({ name: "Set up job" }), false);
  assert.equal(isVisibleBuildStep({ name: "Post Check out repository" }), false);
  assert.equal(isVisibleBuildStep({ name: "Build and test production APK" }), true);
});

test("history model calculates per-step, total medians, and timing quartiles", () => {
  const model = buildHistoricalModel([
    successfulJob(1),
    successfulJob(1.1),
    successfulJob(0.9),
    successfulJob(1.2),
    successfulJob(0.8),
  ]);
  assert.equal(model.sampleCount, 5);
  assert.equal(model.stepOrder.length, 4);
  assert.ok(model.stepMedians["Build and test production APK"] >= 299);
  assert.ok(model.totalMedianSeconds > 390);
  assert.ok(model.totalLowSeconds < model.totalMedianSeconds);
  assert.ok(model.totalHighSeconds > model.totalMedianSeconds);
});

test("active run selection prefers a running build over a newer queued build", () => {
  const run = selectActiveRun([
    { id: 2, status: "queued", head_branch: "main", event: "workflow_dispatch", created_at: "2026-08-04T12:05:00Z" },
    { id: 1, status: "in_progress", head_branch: "main", event: "workflow_dispatch", created_at: "2026-08-04T12:00:00Z" },
  ]);
  assert.equal(run.id, 1);
});

test("workflow steps are grouped into readable phases", () => {
  assert.equal(phaseForStepName("Check out repository").label, "Preparing the build");
  assert.equal(phaseForStepName("Build and test production APK").label, "Building and testing the APK");
  assert.equal(phaseForStepName("Verify package, version, checksum, and signer").label, "Verifying the release");
  assert.equal(phaseForStepName("Upload production APK handoff").label, "Packaging verified build evidence");
  assert.equal(phaseForStepName("Remove temporary credentials").label, "Finishing securely");
});

test("three-step preview shows previous, current, and next context", () => {
  const steps = [
    { name: "A", status: "completed", conclusion: "success" },
    { name: "B", status: "in_progress", conclusion: "" },
    { name: "C", status: "queued", conclusion: "" },
    { name: "D", status: "queued", conclusion: "" },
  ];
  const preview = createStepPreview(steps, 1);
  assert.deepEqual(preview.map((item) => item.role), ["Previous", "Current", "Next"]);
  assert.deepEqual(preview.map((item) => item.name), ["A", "B", "C"]);
  assert.equal(preview[1].state, "active");
});

test("snapshot reports step position, readable phase, context, and a history-based ETA range", () => {
  const history = buildHistoricalModel([
    successfulJob(0.8),
    successfulJob(0.9),
    successfulJob(1),
    successfulJob(1.1),
    successfulJob(1.2),
  ]);
  const run = {
    id: 42,
    run_number: 17,
    run_attempt: 1,
    status: "in_progress",
    head_branch: "main",
    event: "workflow_dispatch",
    html_url: "https://github.com/zuhak5/Owntend/actions/runs/42",
    created_at: new Date(START).toISOString(),
  };
  const job = {
    name: "Build signed production APK",
    status: "in_progress",
    started_at: new Date(START).toISOString(),
    steps: [
      step("Check out repository", 0, 10),
      step("Build and test production APK", 10, 0, "in_progress"),
      { name: "Verify package, version, checksum, and signer", status: "queued", conclusion: null, started_at: null, completed_at: null },
      { name: "Upload production APK handoff", status: "queued", conclusion: null, started_at: null, completed_at: null },
    ],
  };
  const snapshot = createBuildSnapshot(run, job, history, { now: START + 70_000 });
  assert.equal(snapshot.completedCount, 1);
  assert.equal(snapshot.currentStepNumber, 2);
  assert.equal(snapshot.remainingAfterCurrent, 2);
  assert.equal(snapshot.currentStepName, "Build and test production APK");
  assert.equal(snapshot.currentPhaseName, "Building and testing the APK");
  assert.equal(snapshot.stepPreview.length, 3);
  assert.ok(snapshot.estimatedSeconds > 200);
  assert.ok(snapshot.estimatedLowSeconds < snapshot.estimatedSeconds);
  assert.ok(snapshot.estimatedHighSeconds > snapshot.estimatedSeconds);
  assert.equal(snapshot.estimateConfidence, "high");
});

test("failed snapshots retain the failed technical step and phase", () => {
  const run = {
    id: 43,
    run_number: 18,
    status: "completed",
    conclusion: "failure",
    head_branch: "main",
    event: "workflow_dispatch",
    html_url: "https://github.com/zuhak5/Owntend/actions/runs/43",
  };
  const job = {
    status: "completed",
    conclusion: "failure",
    steps: [
      step("Check out repository", 0, 10),
      step("Verify package, version, checksum, and signer", 10, 20, "completed", "failure"),
      { name: "Upload production APK handoff", status: "completed", conclusion: "skipped", started_at: null, completed_at: null },
    ],
  };
  const snapshot = createBuildSnapshot(run, job, null, { now: START + 60_000 });
  assert.equal(snapshot.failedStepName, "Verify package, version, checksum, and signer");
  assert.equal(snapshot.currentPhaseName, "Verifying the release");
});

test("transition announces a completed step and next readable phase", () => {
  const previous = {
    runId: 42,
    runAttempt: 1,
    runNumber: 17,
    status: "in_progress",
    currentPhaseName: "Preparing the build",
    currentStepName: "Check out repository",
    completedStepNames: [],
    totalSteps: 3,
    remainingAfterCurrent: 2,
    estimatedSeconds: 400,
    estimatedLowSeconds: 340,
    estimatedHighSeconds: 470,
  };
  const current = {
    ...previous,
    currentPhaseName: "Building and testing the APK",
    currentStepName: "Build and test production APK",
    completedStepNames: ["Check out repository"],
    remainingAfterCurrent: 1,
    estimatedSeconds: 330,
    estimatedLowSeconds: 280,
    estimatedHighSeconds: 390,
  };
  const transition = detectBuildTransition(previous, current);
  assert.match(transition.message, /Completed Check out repository/);
  assert.match(transition.message, /Building and testing the APK/);
  assert.match(transition.message, /1 step follows/);
});

test("ETA range and elapsed formatting avoid false precision", () => {
  assert.equal(formatEtaRange(9 * 60, 15 * 60, 12 * 60), "9–15 min");
  assert.equal(formatEtaRange(11 * 60, 13 * 60, 12 * 60), "About 12 min");
  assert.equal(formatElapsedTime(30), "Started less than a minute ago");
  assert.equal(formatElapsedTime(5 * 60), "Running for 5 minutes");
});

test("remaining time formatting remains concise for announcements", () => {
  assert.equal(formatRemainingTime(30), "Less than a minute");
  assert.equal(formatRemainingTime(600), "About 10 minutes");
  assert.equal(formatRemainingTime(5_400), "About 1 hr 30 min");
});

test("live build status uses the GitHub REST API origin", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = await readFile(
    new URL("../download-site/build-status.js", import.meta.url),
    "utf8",
  );

  assert.match(
    source,
    /const API_BASE = `https:\/\/api\.github\.com\/repos\/\$\{REPOSITORY\}`;/,
  );
  assert.doesNotMatch(source, /const API_BASE = "";/);
  assert.doesNotMatch(source, /Â·/);
});

test("VersionDeck page permits and exposes live GitHub build status", async () => {
  const { readFile } = await import("node:fs/promises");
  const html = await readFile(
    new URL("../download-site/index.html", import.meta.url),
    "utf8",
  );
  assert.match(html, /id="build-progress-run-link"/);
  assert.match(html, /connect-src 'self' https:\/\/api\.github\.com/);
  assert.match(
    html,
    /href="https:\/\/github\.com\/zuhak5\/Owntend\/actions\/workflows\/build-production-android\.yml"/,
  );
});

test("VersionDeck target metadata uses the canonical pubspec version", () => {
  assert.deepEqual(parseVersionDeckTarget("name: owntend\nversion: 1.0.0+1\n"), {
    version: "1.0.0",
    build: 1,
  });
  assert.throws(
    () => parseVersionDeckTarget("version: 1.0.0"),
    /X\.Y\.Z\+N/,
  );
});


test("live polling calls the exported production-job fetcher", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = await readFile(
    new URL("../download-site/build-status.js", import.meta.url),
    "utf8",
  );
  assert.doesNotMatch(source, /\bfetchRunJob\s*\(/);
  assert.match(source, /fetchLiveBuildRunJobs\(currentRun\.id/);
  assert.match(source, /fetchLiveBuildRunJobs\(activeRun\.id/);
});
