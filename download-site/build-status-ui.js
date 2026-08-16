const REPOSITORY = "zuhak5/Owntend";
const TARGET_BUILD_CACHE_KEY = "versiondeck-target-build-v1";

const TECHNICAL_PHASES = [
  {
    id: "source",
    label: "Preparing source",
    match: /check out repository|release commit belongs to main/i,
  },
  {
    id: "configure",
    label: "Configuring production build",
    match: /set up java|set up flutter|show tool versions|prepare release metadata|create production configuration|restore android signing credentials/i,
  },
  {
    id: "build",
    label: "Building and testing APK",
    match: /build and test production apk/i,
  },
  {
    id: "verify",
    label: "Verifying APK and release",
    match: /verify apk exists|prepare release files|verify package, version, checksum, and signer/i,
  },
  {
    id: "publish",
    label: "Packaging verified build evidence",
    match: /publish and verify sentry release|upload production apk|attest production apk provenance|publish (?:github )?release/i,
  },
  {
    id: "cleanup",
    label: "Finalizing securely",
    match: /stop gradle daemons|remove temporary credentials/i,
  },
];

function cleanText(value) {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
}

export function phaseForTechnicalStep(name) {
  const normalized = cleanText(name);
  return TECHNICAL_PHASES.find((phase) => phase.match.test(normalized)) || {
    id: "other",
    label: "Processing production build",
  };
}

export function groupTechnicalSteps(steps) {
  const groups = [];
  for (const step of Array.isArray(steps) ? steps : []) {
    const phase = phaseForTechnicalStep(step?.name);
    let group = groups.find((candidate) => candidate.id === phase.id);
    if (!group) {
      group = { id: phase.id, label: phase.label, steps: [] };
      groups.push(group);
    }
    group.steps.push(step);
  }
  return groups;
}

export function parsePubspecVersion(text) {
  const match = String(text || "").match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m);
  if (!match) return null;
  return { version: match[1], build: Number(match[2]) };
}

export function shouldShowStarting(summary, percentText) {
  return /^Step 1 of \d+$/i.test(cleanText(summary)) && ["0%", "Starting"].includes(cleanText(percentText));
}

function safeSessionStorage() {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

function decodeBase64Utf8(content) {
  const binary = window.atob(String(content || "").replace(/\s+/g, ""));
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

async function fetchTargetBuild() {
  const storage = safeSessionStorage();
  try {
    const cached = JSON.parse(storage?.getItem(TARGET_BUILD_CACHE_KEY) || "null");
    if (cached?.version && Number.isFinite(cached?.build)) return cached;
  } catch {
    // Continue with the network lookup.
  }

  const response = await fetch("build-info.json", {
    cache: "no-store",
    referrerPolicy: "no-referrer",
  });
  if (!response.ok) throw new Error(`Target build metadata returned ${response.status}.`);
  const payload = await response.json();
  const target = payload?.target || { version: payload?.versionName, build: payload?.versionCode };
  if (!target?.version || !Number.isFinite(target?.build)) {
    throw new Error("Target build version is unavailable.");
  }
  try {
    storage?.setItem(TARGET_BUILD_CACHE_KEY, JSON.stringify(target));
  } catch {
    // The target label remains available for the current page.
  }
  return target;
}

function phaseState(items) {
  const states = items.map((item) => item.dataset.state || "waiting");
  if (states.includes("failed")) return "failed";
  if (states.includes("active")) return "active";
  if (states.length && states.every((state) => state === "completed")) return "completed";
  return "waiting";
}

function technicalStepName(item) {
  const label = item.querySelector("span:last-child");
  return cleanText(label?.textContent);
}

function createPhaseGroup(group) {
  const item = document.createElement("li");
  item.className = "build-phase-group";

  const details = document.createElement("details");
  details.className = "build-phase-details";
  const state = phaseState(group.steps.map((step) => step.element));
  details.dataset.state = state;
  details.open = state === "active" || state === "failed";

  const summary = document.createElement("summary");
  const marker = document.createElement("span");
  marker.className = "build-phase-marker";
  marker.setAttribute("aria-hidden", "true");
  const label = document.createElement("span");
  label.className = "build-phase-label";
  label.textContent = group.label;
  const count = document.createElement("span");
  count.className = "build-phase-count";
  const completed = group.steps.filter((step) => step.element.dataset.state === "completed").length;
  count.textContent = `${completed}/${group.steps.length}`;
  summary.append(marker, label, count);

  const list = document.createElement("ol");
  list.className = "build-phase-step-list";
  for (const step of group.steps) list.append(step.element);

  details.append(summary, list);
  item.append(details);
  return item;
}

function initializeBuildStatusUi() {
  const section = document.querySelector("#build-progress-section");
  if (!section) return;

  const heading = section.querySelector("#build-progress-heading");
  const phaseName = section.querySelector("#build-progress-phase");
  const stepName = section.querySelector("#build-progress-step");
  const progressTrack = section.querySelector("#build-progress-track");
  const progressPercent = section.querySelector("#build-progress-percent");
  const progressSummary = section.querySelector("#build-progress-summary");
  const runLink = section.querySelector("#build-progress-run-link");
  const alerts = section.querySelector(".build-progress-actions");
  const details = section.querySelector(".build-progress-details");
  const detailsSummary = section.querySelector("#build-progress-details-summary");
  const stepsList = section.querySelector("#build-progress-step-list");
  const stickyLabel = document.querySelector("#sticky-download .sticky-copy small");

  if (!heading || !phaseName || !stepName || !progressTrack || !progressPercent ||
      !progressSummary || !runLink || !alerts || !details || !detailsSummary || !stepsList) return;

  if (stickyLabel && !stickyLabel.dataset.defaultText) {
    stickyLabel.dataset.defaultText = cleanText(stickyLabel.textContent) || "Current stable Owntend APK";
  }

  if (!alerts.querySelector(".build-alerts-heading")) {
    const alertsHeading = document.createElement("div");
    alertsHeading.className = "build-alerts-heading";
    const title = document.createElement("strong");
    title.textContent = "Build alerts";
    const note = document.createElement("small");
    note.textContent = "Available while VersionDeck remains open.";
    alertsHeading.append(title, note);
    alerts.prepend(alertsHeading);
  }

  let targetBuild = null;
  let targetPromise = null;
  let grouping = false;
  let frame = 0;

  function loadTarget() {
    if (targetBuild || targetPromise) return;
    targetPromise = fetchTargetBuild()
      .then((target) => {
        targetBuild = target;
        scheduleEnhancement();
      })
      .catch(() => null);
  }

  function regroupTechnicalSteps() {
    if (grouping) return;
    const flatItems = Array.from(stepsList.children).filter((child) =>
      child.classList.contains("build-step-item"),
    );
    if (!flatItems.length) return;

    grouping = true;
    const grouped = groupTechnicalSteps(flatItems.map((element) => ({
      name: technicalStepName(element),
      element,
    })));
    const fragment = document.createDocumentFragment();
    for (const group of grouped) fragment.append(createPhaseGroup(group));
    stepsList.replaceChildren(fragment);
    grouping = false;
  }

  function updateDisclosureLabel() {
    const label = details.open ? "Hide technical workflow" : "Show technical workflow";
    if (detailsSummary.textContent !== label) detailsSummary.textContent = label;
  }

  function enhance() {
    frame = 0;
    const success = !section.hidden && section.dataset.state === "success";
    if (success && phaseName.textContent !== "Verified build evidence ready") {
      phaseName.textContent = "Verified build evidence ready";
    }
    const active = !section.hidden && section.dataset.state === "active";
    if (!active) {
      progressTrack.classList.remove("is-indeterminate");
      if (stickyLabel) stickyLabel.textContent = stickyLabel.dataset.defaultText;
      updateDisclosureLabel();
      return;
    }

    loadTarget();
    const correctedPhase = phaseForTechnicalStep(stepName.textContent);
    if (correctedPhase.id !== "other" && phaseName.textContent !== correctedPhase.label) {
      phaseName.textContent = correctedPhase.label;
    }

    if (targetBuild) {
      const desiredHeading = `Building Owntend ${targetBuild.version}`;
      if (heading.textContent !== desiredHeading) heading.textContent = desiredHeading;
      let target = section.querySelector(".build-progress-target");
      if (!target) {
        target = document.createElement("p");
        target.className = "build-progress-target";
        heading.insertAdjacentElement("afterend", target);
      }
      const targetText = `Build ${targetBuild.build} · Production APK`;
      if (target.textContent !== targetText) target.textContent = targetText;
      if (stickyLabel) {
        stickyLabel.textContent = `Current stable APK · ${targetBuild.version} building`;
      }
    }

    if (!runLink.textContent.includes("↗")) runLink.textContent = `${cleanText(runLink.textContent)} ↗`;

    const starting = shouldShowStarting(progressSummary.textContent, progressPercent.textContent);
    progressTrack.classList.toggle("is-indeterminate", starting);
    if (starting) {
      progressPercent.textContent = "Starting";
      progressTrack.removeAttribute("aria-valuenow");
      const progressText = `${cleanText(progressSummary.textContent)}. Starting.`;
      if (progressTrack.getAttribute("aria-valuetext") !== progressText) {
        progressTrack.setAttribute("aria-valuetext", progressText);
      }
    }

    regroupTechnicalSteps();
    updateDisclosureLabel();
  }

  function scheduleEnhancement() {
    if (frame) return;
    frame = window.requestAnimationFrame(enhance);
  }

  details.addEventListener("toggle", updateDisclosureLabel);
  new MutationObserver(scheduleEnhancement).observe(section, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: ["hidden", "data-state", "aria-valuenow"],
  });

  scheduleEnhancement();
}

if (typeof document !== "undefined") {
  try {
    initializeBuildStatusUi();
  } catch (error) {
    console.warn("VersionDeck build-status UI enhancements are unavailable.", error);
  }
}
