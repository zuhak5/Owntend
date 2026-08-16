const REPOSITORY = "zuhak5/Owntend";
const WORKFLOW_FILE = "build-production-android.yml";
const JOB_NAME = "Build signed production APK";
const API_BASE = `https://api.github.com/repos/${REPOSITORY}`;
const ACTIVE_POLL_MS = 90_000;
const ACTIVE_HIDDEN_POLL_MS = 150_000;
const IDLE_POLL_MS = 300_000;
const IDLE_HIDDEN_POLL_MS = 600_000;
const REQUEST_TIMEOUT_MS = 12_000;
const HISTORY_SAMPLE_LIMIT = 5;
const HISTORY_TTL_MS = 24 * 60 * 60 * 1000;
const TERMINAL_VISIBLE_MS = 60_000;
const TOAST_VISIBLE_MS = 8_000;
const HISTORY_CACHE_KEY = "versiondeck-build-history-v1";
const SPEECH_PREFERENCE_KEY = "versiondeck-build-speech-v2";
const LEGACY_ALERT_PREFERENCE_KEY = "versiondeck-build-alerts-v1";
const NOTIFICATION_PREFERENCE_KEY = "versiondeck-build-notifications-v1";
const SNAPSHOT_CACHE_KEY = "versiondeck-build-snapshot-v2";
const ACTIVE_STATUSES = new Set(["queued", "in_progress", "requested", "waiting", "pending"]);
const HIDDEN_STEP_NAMES = new Set(["Set up job", "Complete job"]);
const QUEUED_STATUSES = new Set(["queued", "requested", "waiting", "pending"]);

const BUILD_PHASES = [
  {
    id: "prepare",
    label: "Preparing the build",
    match: /check out|release commit belongs|set up java|set up flutter|show tool versions|prepare release metadata|create production configuration|restore android signing/i,
  },
  {
    id: "build",
    label: "Building and testing the APK",
    match: /build and test production apk/i,
  },
  {
    id: "verify",
    label: "Verifying the release",
    match: /verify apk exists|prepare release files|verify package, version, checksum, and signer/i,
  },
  {
    id: "diagnostics",
    label: "Publishing diagnostics",
    match: /sentry release/i,
  },
  {
    id: "publish",
    label: "Packaging verified build evidence",
    match: /upload production apk|attest production apk provenance|publish (?:github )?release/i,
  },
  {
    id: "cleanup",
    label: "Finishing securely",
    match: /stop gradle daemons|remove temporary credentials/i,
  },
];

function finiteTimestamp(value) {
  const timestamp = Date.parse(value || "");
  return Number.isFinite(timestamp) ? timestamp : null;
}

function cleanText(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 240) : fallback;
}

export function median(values) {
  const sorted = values.filter(Number.isFinite).sort((left, right) => left - right);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

function quantile(values, percentile) {
  const sorted = values.filter(Number.isFinite).sort((left, right) => left - right);
  if (!sorted.length) return null;
  const index = (sorted.length - 1) * percentile;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
}

export function isVisibleBuildStep(step) {
  const name = cleanText(step?.name);
  return Boolean(name) && !HIDDEN_STEP_NAMES.has(name) && !name.startsWith("Post ");
}

function stepDurationSeconds(step) {
  const startedAt = finiteTimestamp(step?.started_at);
  const completedAt = finiteTimestamp(step?.completed_at);
  if (startedAt === null || completedAt === null || completedAt < startedAt) return null;
  return Math.max(1, (completedAt - startedAt) / 1000);
}

function visibleSteps(job) {
  return Array.isArray(job?.steps) ? job.steps.filter(isVisibleBuildStep) : [];
}

export function phaseForStepName(name) {
  const normalized = cleanText(name);
  return BUILD_PHASES.find((phase) => phase.match.test(normalized)) || {
    id: "other",
    label: "Processing the release",
  };
}

function orderedPhaseIds(steps) {
  const ids = [];
  for (const step of steps) {
    const id = phaseForStepName(step.name).id;
    if (!ids.includes(id)) ids.push(id);
  }
  return ids;
}

export function buildHistoricalModel(jobs, { generatedAt = Date.now() } = {}) {
  const successfulJobs = (Array.isArray(jobs) ? jobs : []).filter(
    (job) => job?.status === "completed" && job?.conclusion === "success",
  );
  const stepSamples = new Map();
  const totalSamples = [];
  const allDurations = [];
  let stepOrder = [];

  for (const job of successfulJobs) {
    const steps = visibleSteps(job);
    if (!stepOrder.length && steps.length) stepOrder = steps.map((step) => cleanText(step.name));
    let total = 0;
    let hasDuration = false;
    for (const step of steps) {
      const duration = stepDurationSeconds(step);
      if (!Number.isFinite(duration)) continue;
      const name = cleanText(step.name);
      if (!stepSamples.has(name)) stepSamples.set(name, []);
      stepSamples.get(name).push(duration);
      allDurations.push(duration);
      total += duration;
      hasDuration = true;
    }
    if (hasDuration) totalSamples.push(total);
  }

  const stepMedians = {};
  for (const [name, samples] of stepSamples.entries()) {
    const value = median(samples);
    if (Number.isFinite(value)) stepMedians[name] = value;
  }

  return {
    schemaVersion: 1,
    generatedAt: new Date(generatedAt).toISOString(),
    sampleCount: successfulJobs.length,
    stepOrder,
    stepMedians,
    defaultStepSeconds: median(allDurations) || 60,
    totalMedianSeconds: median(totalSamples),
    totalLowSeconds: quantile(totalSamples, 0.25),
    totalHighSeconds: quantile(totalSamples, 0.75),
  };
}

function statusPriority(status) {
  return {
    in_progress: 0,
    waiting: 1,
    pending: 2,
    requested: 3,
    queued: 4,
  }[status] ?? 99;
}

export function selectActiveRun(runs) {
  return (Array.isArray(runs) ? runs : [])
    .filter((run) =>
      ACTIVE_STATUSES.has(run?.status) &&
      run?.head_branch === "main" &&
      run?.event === "workflow_dispatch",
    )
    .sort((left, right) => {
      const priority = statusPriority(left.status) - statusPriority(right.status);
      if (priority) return priority;
      return (finiteTimestamp(right.created_at) || 0) - (finiteTimestamp(left.created_at) || 0);
    })[0] || null;
}

function safeRunUrl(run) {
  const fallback = `https://github.com/${REPOSITORY}/actions/runs/${Number(run?.id) || 0}`;
  try {
    const url = new URL(run?.html_url || fallback);
    return url.protocol === "https:" && url.hostname === "github.com" ? url.href : fallback;
  } catch {
    return fallback;
  }
}

function etaBounds(seconds, history) {
  if (!Number.isFinite(seconds) || !Number.isFinite(history?.totalMedianSeconds)) {
    return { lowSeconds: null, highSeconds: null };
  }
  const lowRatio = Number.isFinite(history.totalLowSeconds)
    ? Math.max(0.5, Math.min(1, history.totalLowSeconds / history.totalMedianSeconds))
    : 0.82;
  const highRatio = Number.isFinite(history.totalHighSeconds)
    ? Math.max(1, Math.min(1.8, history.totalHighSeconds / history.totalMedianSeconds))
    : 1.22;
  return {
    lowSeconds: Math.max(0, seconds * lowRatio),
    highSeconds: Math.max(seconds, seconds * highRatio),
  };
}

function estimateRemainingSeconds(steps, currentStep, job, history, now) {
  if (!history?.sampleCount || !Number.isFinite(history.totalMedianSeconds)) {
    return {
      seconds: null,
      lowSeconds: null,
      highSeconds: null,
      coverage: 0,
      confidence: "unavailable",
    };
  }

  const status = job?.status;
  if (QUEUED_STATUSES.has(status)) {
    return {
      seconds: history.totalMedianSeconds,
      lowSeconds: history.totalLowSeconds,
      highSeconds: history.totalHighSeconds,
      coverage: 1,
      confidence: history.sampleCount >= 5 ? "high" : history.sampleCount >= 3 ? "medium" : "low",
    };
  }

  const unfinished = steps.filter((step) => step.status !== "completed");
  let stepEstimate = 0;
  let known = 0;
  for (const step of unfinished) {
    const expected = history.stepMedians?.[step.name] || history.defaultStepSeconds || 60;
    if (history.stepMedians?.[step.name]) known += 1;
    if (currentStep && step.name === currentStep.name) {
      const startedAt = finiteTimestamp(step.started_at);
      const elapsed = startedAt === null ? 0 : Math.max(0, (now - startedAt) / 1000);
      stepEstimate += Math.max(30, expected * 0.2, expected - elapsed);
    } else {
      stepEstimate += expected;
    }
  }

  const coverage = unfinished.length ? known / unfinished.length : 1;
  const jobStartedAt = finiteTimestamp(job?.started_at);
  const totalEstimate = jobStartedAt === null
    ? null
    : Math.max(30, history.totalMedianSeconds - Math.max(0, (now - jobStartedAt) / 1000));
  let seconds = stepEstimate;
  if (Number.isFinite(totalEstimate)) {
    seconds = coverage >= 0.5
      ? stepEstimate * 0.75 + totalEstimate * 0.25
      : totalEstimate;
  }

  const confidence = history.sampleCount >= 5 && coverage >= 0.8
    ? "high"
    : history.sampleCount >= 3 && coverage >= 0.5
      ? "medium"
      : "low";
  const bounds = etaBounds(Math.max(0, seconds), history);
  return {
    seconds: Math.max(0, seconds),
    ...bounds,
    coverage,
    confidence,
  };
}

function expectedSteps(currentSteps, history) {
  if (currentSteps.length) {
    return currentSteps.map((step) => ({
      name: cleanText(step.name, "Build step"),
      status: cleanText(step.status, "queued"),
      conclusion: cleanText(step.conclusion),
      started_at: step.started_at || null,
      completed_at: step.completed_at || null,
    }));
  }
  return (history?.stepOrder || []).map((name) => ({
    name,
    status: "queued",
    conclusion: "",
    started_at: null,
    completed_at: null,
  }));
}

function stepState(step) {
  if (!step) return "waiting";
  if (step.status === "completed") {
    return step.conclusion === "success" || step.conclusion === "skipped"
      ? "completed"
      : "failed";
  }
  return step.status === "in_progress" ? "active" : "waiting";
}

export function createStepPreview(steps, currentIndex) {
  if (!Array.isArray(steps) || !steps.length) return [];
  const boundedCurrent = Math.max(0, Math.min(steps.length - 1, currentIndex));
  const items = [];
  if (boundedCurrent > 0) {
    items.push({ role: "Previous", ...steps[boundedCurrent - 1], state: stepState(steps[boundedCurrent - 1]) });
  }
  items.push({ role: "Current", ...steps[boundedCurrent], state: stepState(steps[boundedCurrent]) });
  if (boundedCurrent < steps.length - 1) {
    items.push({ role: "Next", ...steps[boundedCurrent + 1], state: stepState(steps[boundedCurrent + 1]) });
  }
  return items;
}

export function createBuildSnapshot(run, job, history, { now = Date.now() } = {}) {
  if (!run || !Number.isFinite(Number(run.id))) return null;
  const steps = expectedSteps(visibleSteps(job), history);
  const completedSteps = steps.filter((step) => step.status === "completed");
  const currentStep = steps.find((step) => step.status === "in_progress") || null;
  const failedStep = steps.find((step) =>
    step.status === "completed" &&
    !["", "success", "skipped"].includes(step.conclusion),
  ) || null;
  const status = cleanText(job?.status || run.status, "queued");
  const conclusion = cleanText(job?.conclusion || run.conclusion);
  const totalSteps = steps.length;
  const completedCount = completedSteps.length;
  const currentIndex = currentStep
    ? steps.indexOf(currentStep)
    : failedStep
      ? steps.indexOf(failedStep)
      : status === "completed"
        ? Math.max(0, totalSteps - 1)
        : Math.min(completedCount, Math.max(0, totalSteps - 1));
  const currentStepNumber = totalSteps ? currentIndex + 1 : 0;
  const remainingCount = Math.max(0, totalSteps - completedCount);
  const remainingAfterCurrent = currentStep
    ? Math.max(0, totalSteps - currentStepNumber)
    : status === "completed"
      ? 0
      : Math.max(0, totalSteps - currentStepNumber);
  const estimate = estimateRemainingSeconds(steps, currentStep, { ...job, status }, history, now);

  let progress = totalSteps ? completedCount / totalSteps : 0;
  if (currentStep && totalSteps) {
    const expected = history?.stepMedians?.[currentStep.name] || history?.defaultStepSeconds || 60;
    const startedAt = finiteTimestamp(currentStep.started_at);
    const elapsed = startedAt === null ? 0 : Math.max(0, (now - startedAt) / 1000);
    progress = Math.min(0.98, (completedCount + Math.min(0.9, elapsed / expected)) / totalSteps);
  } else if (status === "completed" && conclusion === "success") {
    progress = 1;
  }

  const effectiveStepName = currentStep?.name || failedStep?.name || (
    status === "waiting" ? "Waiting for production approval" :
    QUEUED_STATUSES.has(status) ? "Waiting for a build runner" :
    status === "completed" && conclusion === "success" ? "Build completed successfully" :
    status === "completed" ? "The production build stopped" :
    "Preparing production build"
  );
  const effectivePhase = status === "completed" && conclusion === "success"
    ? { id: "published", label: "Release published" }
    : phaseForStepName(effectiveStepName);
  const phaseIds = orderedPhaseIds(steps);
  const phasePosition = Math.max(0, phaseIds.indexOf(effectivePhase.id));

  const startedAt = job?.started_at || run.run_started_at || run.created_at || null;
  const startedTimestamp = finiteTimestamp(startedAt);
  return {
    runId: Number(run.id),
    runNumber: Number(run.run_number) || null,
    runAttempt: Number(run.run_attempt) || 1,
    runUrl: safeRunUrl(run),
    status,
    conclusion,
    startedAt,
    updatedAt: new Date(now).toISOString(),
    elapsedSeconds: startedTimestamp === null ? null : Math.max(0, (now - startedTimestamp) / 1000),
    currentStepName: effectiveStepName,
    failedStepName: failedStep?.name || "",
    currentPhaseId: effectivePhase.id,
    currentPhaseName: effectivePhase.label,
    phaseNumber: phasePosition >= 0 ? phasePosition + 1 : 1,
    totalPhases: Math.max(phaseIds.length, BUILD_PHASES.length),
    completedStepNames: completedSteps.map((step) => step.name),
    completedCount,
    currentStepNumber,
    remainingCount,
    remainingAfterCurrent,
    totalSteps,
    progress,
    estimatedSeconds: estimate.seconds,
    estimatedLowSeconds: estimate.lowSeconds,
    estimatedHighSeconds: estimate.highSeconds,
    estimateCoverage: estimate.coverage,
    estimateConfidence: estimate.confidence,
    historySampleCount: history?.sampleCount || 0,
    stepPreview: createStepPreview(steps, currentIndex),
    steps,
  };
}

function durationParts(seconds) {
  if (!Number.isFinite(seconds)) return null;
  if (seconds < 60) return { value: 1, unit: "min" };
  const minutes = Math.max(1, Math.round(seconds / 60));
  if (minutes < 60) return { value: minutes, unit: "min" };
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return { value: remainder ? `${hours} hr ${remainder} min` : `${hours} hr`, unit: "" };
}

export function formatRemainingTime(seconds) {
  if (!Number.isFinite(seconds)) return "Calculating…";
  if (seconds < 60) return "Less than a minute";
  const minutes = Math.max(1, Math.round(seconds / 60));
  if (minutes < 60) return `About ${minutes} ${minutes === 1 ? "minute" : "minutes"}`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder
    ? `About ${hours} hr ${remainder} min`
    : `About ${hours} ${hours === 1 ? "hour" : "hours"}`;
}

export function formatEtaRange(lowSeconds, highSeconds, fallbackSeconds) {
  if (!Number.isFinite(fallbackSeconds)) return "Calculating…";
  const low = durationParts(Number.isFinite(lowSeconds) ? lowSeconds : fallbackSeconds * 0.82);
  const high = durationParts(Number.isFinite(highSeconds) ? highSeconds : fallbackSeconds * 1.22);
  if (!low || !high) return formatRemainingTime(fallbackSeconds);
  if (low.unit === "min" && high.unit === "min") {
    if (Math.abs(Number(high.value) - Number(low.value)) <= 2) {
      return `About ${Math.max(1, Math.round(fallbackSeconds / 60))} min`;
    }
    return `${low.value}–${high.value} min`;
  }
  return `${low.value}${low.unit ? ` ${low.unit}` : ""}–${high.value}${high.unit ? ` ${high.unit}` : ""}`;
}

export function formatElapsedTime(seconds) {
  if (!Number.isFinite(seconds)) return "Start time unavailable";
  if (seconds < 60) return "Started less than a minute ago";
  const minutes = Math.max(1, Math.floor(seconds / 60));
  if (minutes < 60) return `Running for ${minutes} ${minutes === 1 ? "minute" : "minutes"}`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder
    ? `Running for ${hours} hr ${remainder} min`
    : `Running for ${hours} ${hours === 1 ? "hour" : "hours"}`;
}

function remainingPhrase(snapshot) {
  if (!snapshot.totalSteps) return "Step count is loading.";
  return `${snapshot.remainingAfterCurrent} ${
    snapshot.remainingAfterCurrent === 1 ? "step follows" : "steps follow"
  } the current step.`;
}

export function detectBuildTransition(previous, current) {
  if (!current) return null;
  const estimate = Number.isFinite(current.estimatedSeconds)
    ? `${formatEtaRange(current.estimatedLowSeconds, current.estimatedHighSeconds, current.estimatedSeconds)} remaining.`
    : "The remaining time is still being calculated.";

  if (!previous || previous.runId !== current.runId || previous.runAttempt !== current.runAttempt) {
    return {
      kind: "started",
      message: `Owntend production build ${current.runNumber || ""} is active. ${current.currentPhaseName}. Current task: ${current.currentStepName}. ${remainingPhrase(current)} ${estimate}`.replace(/\s+/g, " ").trim(),
    };
  }

  if (current.status === "completed" && previous.status !== "completed") {
    const result = current.conclusion === "success"
      ? "completed successfully"
      : `finished with ${current.conclusion || "an unknown result"}`;
    return {
      kind: current.conclusion === "success" ? "success" : "error",
      message: `Owntend production build ${current.runNumber || ""} ${result}.`.replace(/\s+/g, " ").trim(),
    };
  }

  const previousCompleted = new Set(previous.completedStepNames || []);
  const newlyCompleted = (current.completedStepNames || []).filter((name) => !previousCompleted.has(name));
  const stepChanged = previous.currentStepName !== current.currentStepName;
  if (!newlyCompleted.length && !stepChanged) return null;

  const completedPhrase = newlyCompleted.length === 1
    ? `Completed ${newlyCompleted[0]}.`
    : newlyCompleted.length > 1
      ? `Completed ${newlyCompleted.length} build steps.`
      : "";
  return {
    kind: "step",
    message: `${completedPhrase} ${current.currentPhaseName}. Current task: ${current.currentStepName}. ${remainingPhrase(current)} ${estimate}`.replace(/\s+/g, " ").trim(),
  };
}

function browserStorage() {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function readJsonStorage(storage, key) {
  try {
    return storage ? JSON.parse(storage.getItem(key)) : null;
  } catch {
    return null;
  }
}

function writeJsonStorage(storage, key, value) {
  try {
    storage?.setItem(key, JSON.stringify(value));
  } catch {
    // Status remains usable when storage is unavailable.
  }
}

function readStringStorage(storage, key) {
  try {
    return storage?.getItem(key) || "";
  } catch {
    return "";
  }
}

function writeStringStorage(storage, key, value) {
  try {
    storage?.setItem(key, value);
  } catch {
    // Preferences remain session-only when storage is unavailable.
  }
}

function isHistoryCacheUsable(record, runIds, now = Date.now()) {
  const fetchedAt = finiteTimestamp(record?.fetchedAt);
  return record?.schemaVersion === 1 &&
    fetchedAt !== null &&
    now - fetchedAt <= HISTORY_TTL_MS &&
    Array.isArray(record.runIds) &&
    record.runIds.join(",") === runIds.join(",") &&
    record.model?.schemaVersion === 1;
}

async function fetchStatusJson(path, { signal } = {}) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const abort = () => controller.abort();
  signal?.addEventListener("abort", abort, { once: true });
  try {
    const response = await fetch(`${API_BASE}${path}`, {
      cache: "no-store",
      headers: { Accept: "application/json" },
      referrerPolicy: "no-referrer",
      signal: controller.signal,
    });
    if (!response.ok) {
      const error = new Error(`Build status returned ${response.status}.`);
      error.status = response.status;
      error.rateLimitReset = Number(response.headers.get("x-ratelimit-reset")) || null;
      throw error;
    }
    return response.json();
  } finally {
    window.clearTimeout(timeout);
    signal?.removeEventListener("abort", abort);
  }
}

function productionJob(jobs) {
  return (Array.isArray(jobs) ? jobs : []).find((job) => job?.name === JOB_NAME) || null;
}

export async function fetchLiveBuildRunJobs(runId, options = {}) {
  const payload = await fetchStatusJson(`/actions/runs/${runId}/jobs?filter=latest&per_page=100`, options);
  return productionJob(payload?.jobs);
}

async function loadHistoricalModel(successfulRuns, options) {
  const candidates = successfulRuns.slice(0, HISTORY_SAMPLE_LIMIT);
  const runIds = candidates
    .map((run) => `${Number(run.id)}:${Number(run.run_attempt) || 1}`)
    .filter((value) => !value.startsWith("NaN:"));
  const cached = readJsonStorage(browserStorage(), HISTORY_CACHE_KEY);
  if (isHistoryCacheUsable(cached, runIds)) return cached.model;

  const jobs = [];
  for (const run of candidates) {
    try {
      const job = await fetchRunJob(run.id, options);
      if (job) jobs.push(job);
    } catch {
      // A partial history still produces a conservative estimate.
    }
  }
  const model = buildHistoricalModel(jobs);
  writeJsonStorage(browserStorage(), HISTORY_CACHE_KEY, {
    schemaVersion: 1,
    fetchedAt: new Date().toISOString(),
    runIds,
    model,
  });
  return model;
}

function requiredElement(selector) {
  const element = document.querySelector(selector);
  if (!element) throw new Error(`Missing VersionDeck build-status element: ${selector}`);
  return element;
}

function initializeBuildStatus() {
  const section = requiredElement("#build-progress-section");
  const heading = requiredElement("#build-progress-heading");
  const statusLabel = requiredElement("#build-progress-status-label");
  const runLink = requiredElement("#build-progress-run-link");
  const runMeta = requiredElement("#build-progress-meta");
  const phaseName = requiredElement("#build-progress-phase");
  const stepName = requiredElement("#build-progress-step");
  const progressTrack = requiredElement("#build-progress-track");
  const progressBar = requiredElement("#build-progress-bar");
  const progressPercent = requiredElement("#build-progress-percent");
  const progressSummary = requiredElement("#build-progress-summary");
  const progressRemaining = requiredElement("#build-progress-remaining");
  const eta = requiredElement("#build-progress-eta");
  const etaBasis = requiredElement("#build-progress-basis");
  const elapsed = requiredElement("#build-progress-elapsed");
  const speechButton = requiredElement("#build-progress-alerts");
  const speechState = requiredElement("#build-progress-alerts-state");
  const notificationButton = requiredElement("#build-progress-notifications");
  const notificationState = requiredElement("#build-progress-notifications-state");
  const previewList = requiredElement("#build-progress-preview");
  const stepsList = requiredElement("#build-progress-step-list");
  const detailsSummary = requiredElement("#build-progress-details-summary");
  const announcer = requiredElement("#build-announcer");
  const toast = requiredElement("#build-toast");
  const toastMessage = requiredElement("#build-toast-message");
  const toastDismiss = requiredElement("#build-toast-dismiss");

  const storage = browserStorage();
  const legacyAlertEnabled = readStringStorage(storage, LEGACY_ALERT_PREFERENCE_KEY) === "true";
  let currentRun = null;
  let currentSnapshot = readJsonStorage(storage, SNAPSHOT_CACHE_KEY);
  let history = null;
  let timer = null;
  let controller = null;
  let toastTimer = null;
  let terminalUntil = 0;
  let consecutiveFailures = 0;
  let backoffUntil = 0;
  let speechEnabled = readStringStorage(storage, SPEECH_PREFERENCE_KEY) === "true" || legacyAlertEnabled;
  let notificationsEnabled = readStringStorage(storage, NOTIFICATION_PREFERENCE_KEY) === "true";

  function setSpeechButton() {
    const supported = "speechSynthesis" in window && typeof SpeechSynthesisUtterance !== "undefined";
    speechButton.disabled = !supported;
    speechButton.setAttribute("aria-pressed", String(supported && speechEnabled));
    speechState.textContent = supported ? (speechEnabled ? "On" : "Off") : "Unavailable";
  }

  function setNotificationButton() {
    const supported = "Notification" in window;
    const blocked = supported && Notification.permission === "denied";
    if (!supported || blocked) notificationsEnabled = false;
    notificationButton.disabled = !supported || blocked;
    notificationButton.setAttribute("aria-pressed", String(supported && !blocked && notificationsEnabled));
    notificationState.textContent = !supported
      ? "Unavailable"
      : blocked
        ? "Blocked"
        : notificationsEnabled
          ? "On"
          : "Off";
  }

  function dismissToast() {
    window.clearTimeout(toastTimer);
    toast.classList.remove("visible");
    toast.setAttribute("aria-hidden", "true");
  }

  function showToast(message, kind = "info") {
    toastMessage.textContent = message;
    toast.dataset.kind = kind;
    toast.setAttribute("aria-hidden", "false");
    toast.classList.add("visible");
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(dismissToast, TOAST_VISIBLE_MS);
  }

  function speak(message) {
    if (!speechEnabled || !("speechSynthesis" in window) || typeof SpeechSynthesisUtterance === "undefined") return;
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(message);
    utterance.lang = document.documentElement.lang || "en";
    utterance.rate = 1;
    utterance.pitch = 1;
    window.speechSynthesis.speak(utterance);
  }

  function notify(message, snapshot, kind = "info") {
    announcer.textContent = "";
    window.requestAnimationFrame(() => { announcer.textContent = message; });
    showToast(message, kind);
    speak(message);
    if (notificationsEnabled && document.hidden && "Notification" in window && Notification.permission === "granted") {
      try {
        new Notification("Owntend production build", {
          body: message,
          icon: "assets/versiondeck-192.png",
          tag: `versiondeck-build-${snapshot?.runId || "status"}`,
        });
      } catch {
        // Spoken and in-page alerts remain available.
      }
    }
  }

  function renderStepItem(step, { preview = false } = {}) {
    const item = document.createElement("li");
    item.className = preview ? "build-preview-item" : "build-step-item";
    item.dataset.state = step.state || stepState(step);

    const marker = document.createElement("span");
    marker.className = "build-step-marker";
    marker.setAttribute("aria-hidden", "true");

    if (preview) {
      const role = document.createElement("span");
      role.className = "build-preview-role";
      role.textContent = step.role;
      const label = document.createElement("span");
      label.className = "build-preview-label";
      label.textContent = step.name;
      item.append(marker, role, label);
    } else {
      const label = document.createElement("span");
      label.textContent = step.name;
      item.append(marker, label);
    }
    return item;
  }

  function renderSteps(snapshot) {
    const previewFragment = document.createDocumentFragment();
    for (const step of snapshot.stepPreview) {
      previewFragment.append(renderStepItem(step, { preview: true }));
    }
    previewList.replaceChildren(previewFragment);

    const fragment = document.createDocumentFragment();
    for (const step of snapshot.steps) fragment.append(renderStepItem(step));
    stepsList.replaceChildren(fragment);
    detailsSummary.textContent = snapshot.totalSteps
      ? `View all ${snapshot.totalSteps} technical steps`
      : "View technical steps";
  }

  function terminalState(snapshot) {
    if (snapshot.status !== "completed") return "active";
    return snapshot.conclusion === "success" ? "success" : "error";
  }

  function render(snapshot) {
    const state = terminalState(snapshot);
    section.hidden = false;
    section.dataset.state = state;

    heading.textContent = state === "success"
      ? "Production build completed"
      : state === "error"
        ? "Production build failed"
        : "Building Owntend APK";
    statusLabel.textContent = snapshot.status === "waiting"
      ? "Approval required"
      : QUEUED_STATUSES.has(snapshot.status)
        ? "Waiting to start"
        : state === "success"
          ? "Build completed successfully"
          : state === "error"
            ? "Build stopped"
            : "Production build in progress";

    runLink.href = snapshot.runUrl;
    runLink.textContent = snapshot.runNumber ? `Run #${snapshot.runNumber}` : "Workflow run";
    runMeta.textContent = `${formatElapsedTime(snapshot.elapsedSeconds)} · Updated just now`;
    phaseName.textContent = snapshot.currentPhaseName;
    stepName.textContent = snapshot.currentStepName;

    const percent = Math.max(0, Math.min(100, Math.round(snapshot.progress * 100)));
    progressBar.style.width = `${percent}%`;
    progressPercent.textContent = `${percent}%`;
    progressSummary.textContent = snapshot.totalSteps
      ? `Step ${snapshot.currentStepNumber} of ${snapshot.totalSteps}`
      : "Preparing step list";
    progressRemaining.textContent = snapshot.totalSteps
      ? snapshot.remainingAfterCurrent === 0
        ? "Final step"
        : `${snapshot.remainingAfterCurrent} ${
            snapshot.remainingAfterCurrent === 1 ? "step" : "steps"
          } after this`
      : "Step count is loading";
    progressTrack.setAttribute("aria-valuenow", String(percent));
    progressTrack.setAttribute(
      "aria-valuetext",
      `${progressSummary.textContent}. ${progressRemaining.textContent}.`,
    );

    eta.textContent = state === "success"
      ? "Complete"
      : state === "error"
        ? "Stopped"
        : formatEtaRange(
            snapshot.estimatedLowSeconds,
            snapshot.estimatedHighSeconds,
            snapshot.estimatedSeconds,
          );
    const basis = snapshot.historySampleCount
      ? `${snapshot.historySampleCount} recent successful ${
          snapshot.historySampleCount === 1 ? "build" : "builds"
        } · ${snapshot.estimateConfidence} confidence`
      : "Estimate improves after more successful builds";
    etaBasis.textContent = QUEUED_STATUSES.has(snapshot.status)
      ? `Typical duration after approval and runner start · ${basis}`
      : basis;
    elapsed.textContent = formatElapsedTime(snapshot.elapsedSeconds);
    renderSteps(snapshot);
  }

  function hide() {
    section.hidden = true;
    section.dataset.state = "inactive";
    currentRun = null;
  }

  function schedule(delay) {
    window.clearTimeout(timer);
    const effectiveDelay = Math.max(delay, backoffUntil - Date.now());
    timer = window.setTimeout(() => {
      if (currentRun) pollCurrentRun();
      else discoverRun();
    }, Math.max(1000, effectiveDelay));
  }

  function handleFailure(error) {
    consecutiveFailures += 1;
    if (error?.status === 403 || error?.status === 429) {
      backoffUntil = error.rateLimitReset
        ? Math.max(Date.now() + 60_000, error.rateLimitReset * 1000)
        : Date.now() + 15 * 60_000;
    }
    if (consecutiveFailures >= 3 && Date.now() >= terminalUntil) hide();
    schedule(currentRun ? ACTIVE_HIDDEN_POLL_MS : IDLE_POLL_MS);
  }

  function commitSnapshot(snapshot, { announceInitial = false } = {}) {
    const previous = currentSnapshot?.runId === snapshot.runId &&
      currentSnapshot?.runAttempt === snapshot.runAttempt
      ? currentSnapshot
      : null;
    render(snapshot);
    const transition = detectBuildTransition(previous, snapshot);
    const shouldAnnounce = transition && (previous || announceInitial || speechEnabled || notificationsEnabled);
    if (shouldAnnounce) notify(transition.message, snapshot, transition.kind);
    currentSnapshot = snapshot;
    writeJsonStorage(storage, SNAPSHOT_CACHE_KEY, snapshot);
  }

  async function pollCurrentRun() {
    controller?.abort();
    controller = new AbortController();
    try {
      const job = await fetchRunJob(currentRun.id, { signal: controller.signal });
      consecutiveFailures = 0;
      if (!job) {
        currentRun = null;
        schedule(10_000);
        return;
      }
      const snapshot = createBuildSnapshot(currentRun, job, history);
      if (!snapshot) throw new Error("Production build status is invalid.");
      commitSnapshot(snapshot);
      if (snapshot.status === "completed") {
        terminalUntil = Date.now() + TERMINAL_VISIBLE_MS;
        currentRun = null;
        schedule(15_000);
        return;
      }
      schedule(document.hidden ? ACTIVE_HIDDEN_POLL_MS : ACTIVE_POLL_MS);
    } catch (error) {
      if (error?.name !== "AbortError") handleFailure(error);
    }
  }

  async function discoverRun() {
    controller?.abort();
    controller = new AbortController();
    try {
      const payload = await fetchStatusJson(
        `/actions/workflows/${WORKFLOW_FILE}/runs?branch=main&event=workflow_dispatch&per_page=50`,
        { signal: controller.signal },
      );
      consecutiveFailures = 0;
      const runs = Array.isArray(payload?.workflow_runs) ? payload.workflow_runs : [];
      const activeRun = selectActiveRun(runs);
      if (!activeRun) {
        if (Date.now() < terminalUntil) {
          schedule(Math.min(15_000, terminalUntil - Date.now()));
          return;
        }
        hide();
        schedule(document.hidden ? IDLE_HIDDEN_POLL_MS : IDLE_POLL_MS);
        return;
      }

      terminalUntil = 0;
      currentRun = activeRun;
      const successfulRuns = runs.filter(
        (run) => run?.status === "completed" && run?.conclusion === "success" && run?.head_branch === "main",
      );
      const job = await fetchRunJob(activeRun.id, { signal: controller.signal });
      const initialSnapshot = createBuildSnapshot(
        activeRun,
        job || { status: activeRun.status, steps: [] },
        history,
      );
      commitSnapshot(initialSnapshot, { announceInitial: true });

      loadHistoricalModel(successfulRuns, { signal: controller.signal })
        .then((loadedHistory) => {
          if (currentRun?.id !== activeRun.id) return;
          history = loadedHistory;
          const enrichedSnapshot = createBuildSnapshot(
            activeRun,
            job || { status: activeRun.status, steps: [] },
            history,
          );
          commitSnapshot(enrichedSnapshot);
        })
        .catch(() => {
          // Live step data remains useful when historical timing data is unavailable.
        });
      schedule(document.hidden ? ACTIVE_HIDDEN_POLL_MS : ACTIVE_POLL_MS);
    } catch (error) {
      if (error?.name !== "AbortError") handleFailure(error);
    }
  }

  speechButton.addEventListener("click", () => {
    speechEnabled = !speechEnabled;
    writeStringStorage(storage, SPEECH_PREFERENCE_KEY, String(speechEnabled));
    setSpeechButton();
    if (speechEnabled) {
      const message = "Spoken Owntend build updates are on.";
      showToast(message, "success");
      speak(message);
    } else {
      window.speechSynthesis?.cancel();
      showToast("Spoken Owntend build updates are off.", "info");
    }
  });

  notificationButton.addEventListener("click", async () => {
    if (!("Notification" in window)) return;
    if (Notification.permission === "default") {
      try {
        const permission = await Notification.requestPermission();
        notificationsEnabled = permission === "granted";
      } catch {
        notificationsEnabled = false;
      }
    } else {
      notificationsEnabled = Notification.permission === "granted" && !notificationsEnabled;
    }
    writeStringStorage(storage, NOTIFICATION_PREFERENCE_KEY, String(notificationsEnabled));
    setNotificationButton();
    showToast(
      notificationsEnabled
        ? "Desktop build notifications are on while VersionDeck remains open."
        : Notification.permission === "denied"
          ? "Desktop notifications are blocked in browser settings."
          : "Desktop build notifications are off.",
      notificationsEnabled ? "success" : "info",
    );
  });

  toastDismiss.addEventListener("click", dismissToast);
  document.addEventListener("visibilitychange", () => schedule(document.hidden ? 30_000 : 1000));
  window.addEventListener("online", () => schedule(1000));
  window.addEventListener("offline", () => {
    controller?.abort();
    if (Date.now() >= terminalUntil) hide();
  });
  window.addEventListener("pagehide", () => controller?.abort());

  setSpeechButton();
  setNotificationButton();
  discoverRun();
}

if (typeof document !== "undefined") {
  try {
    initializeBuildStatus();
  } catch (error) {
    console.warn("VersionDeck live build status is unavailable.", error);
  }
}
