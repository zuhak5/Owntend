import {
  VERSIONDECK_PRIMARY_ABI,
  VERSIONDECK_SPLIT_ABIS,
  VersionDeckManifestState,
  classifyVersionDeckManifest,
} from "./manifest-schema.js";

const ABI_LABELS = Object.freeze({
  "arm64-v8a": "ARM64 — most modern Android phones",
  "armeabi-v7a": "ARMv7 — older 32-bit ARM devices",
  "x86_64": "x86_64 — emulators and x86 devices",
});

function controlledLink(label, variant, className) {
  const link = document.createElement("a");
  link.className = className;
  link.textContent = label;
  link.href = variant.apk.url;
  link.dataset.downloadLink = "true";
  link.dataset.downloadHref = variant.apk.url;
  link.dataset.apkAbi = variant.abi;
  link.title = `${variant.apk.name} · ${formatBytes(variant.apk.size)}`;
  return link;
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 1) return "unknown size";
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function variantFor(release, abi) {
  return release.apkVariants?.find((variant) => variant.abi === abi) || null;
}

function appendVariantChooser(container, release, { compact = false } = {}) {
  if (!container || release.distributionMode !== "abi") return;
  if (container.querySelector("[data-abi-chooser]")) return;

  const chooser = document.createElement("div");
  chooser.dataset.abiChooser = "true";
  chooser.className = compact ? "release-links" : "latest-actions";

  if (!compact) {
    const note = document.createElement("p");
    note.className = "exact-date";
    note.textContent =
      "Choose your Android CPU. VersionDeck does not guess device architecture from the browser.";
    container.parentElement?.insertBefore(note, container);
  }

  for (const abi of VERSIONDECK_SPLIT_ABIS) {
    const variant = variantFor(release, abi);
    if (!variant) continue;
    const suffix = abi === VERSIONDECK_PRIMARY_ABI ? " (recommended default)" : "";
    chooser.append(
      controlledLink(
        `${ABI_LABELS[abi]} · ${formatBytes(variant.apk.size)}${suffix}`,
        variant,
        compact ? "button button-secondary" : "button button-primary",
      ),
    );
  }
  container.append(chooser);
}

function enhanceLatest(release) {
  if (release?.distributionMode !== "abi") return;
  const actions = document.querySelector("#latest-card .latest-actions");
  if (!actions) return;
  const existing = actions.querySelector("[data-download-link]");
  if (existing) {
    existing.textContent = `Download ARM64 · ${formatBytes(release.apk.size)}`;
    existing.title = `${release.apk.name} · ${ABI_LABELS[VERSIONDECK_PRIMARY_ABI]}`;
  }
  appendVariantChooser(actions, release);
  const sticky = document.querySelector("#sticky-download-link");
  if (sticky) sticky.textContent = "Download ARM64 APK";
}

function releaseCardFor(release) {
  return [...document.querySelectorAll("#release-list .release-card")].find((card) => {
    const title = card.querySelector(".release-title")?.textContent;
    const meta = card.querySelector(".release-meta")?.textContent || "";
    return title === `Owntend ${release.version}` && meta.includes(`Build ${release.build}`);
  });
}

function enhanceArchive(release) {
  if (release?.distributionMode !== "abi") return;
  const card = releaseCardFor(release);
  if (!card) return;
  const primary = card.querySelector(".archive-download");
  if (primary) {
    primary.textContent = "Download ARM64";
    primary.title = ABI_LABELS[VERSIONDECK_PRIMARY_ABI];
  }
  const links = card.querySelector(".release-links");
  if (links) appendVariantChooser(links, release, { compact: true });
}

async function waitForReleaseRender(manifest) {
  const expectedCards = manifest.releases.length;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const latestReady = !document.querySelector("#latest-card.loading-card");
    const cards = document.querySelectorAll("#release-list .release-card:not(.loading-card)").length;
    if (latestReady && cards >= expectedCards) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

export async function enhanceAbiDownloads(manifest) {
  const classification = classifyVersionDeckManifest(manifest);
  if (classification.state !== VersionDeckManifestState.ACTIVE) return;
  if (!manifest.releases.some((release) => release.distributionMode === "abi")) return;
  await waitForReleaseRender(manifest);
  const latest = manifest.releases.find((release) => release.id === manifest.latestStableReleaseId);
  enhanceLatest(latest);
  for (const release of manifest.releases) enhanceArchive(release);
}

async function main() {
  const response = await fetch("./releases.json", {
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  if (!response.ok) return;
  const manifest = await response.json();
  await enhanceAbiDownloads(manifest);
}

if (typeof window !== "undefined" && typeof document !== "undefined") {
  window.addEventListener("DOMContentLoaded", () => {
    main().catch(() => {});
  }, { once: true });
}
