export function extractTargetVersion(headingText) {
  const match = String(headingText || "").match(/Building Owntend\s+(\d+\.\d+\.\d+)/i);
  return match ? match[1] : "";
}

export function formatBuildContext(version) {
  const normalized = String(version || "").trim();
  return /^\d+\.\d+\.\d+$/.test(normalized) ? `${normalized} building` : "Build in progress";
}

function initializeTimelineRefinement() {
  const section = document.querySelector("#build-progress-section");
  const heading = document.querySelector("#build-progress-heading");
  const stickyCopy = document.querySelector("#sticky-download .sticky-copy");
  const stickyLabel = stickyCopy?.querySelector("small");

  if (!section || !heading || !stickyCopy || !stickyLabel) return;

  const defaultLabel = stickyLabel.dataset.defaultText || stickyLabel.textContent.trim() || "Current stable Owntend APK";
  stickyLabel.dataset.defaultText = defaultLabel;

  let context = stickyCopy.querySelector(".sticky-build-context");
  if (!context) {
    context = document.createElement("span");
    context.className = "sticky-build-context";
    context.hidden = true;
    stickyCopy.append(context);
  }

  let frame = 0;

  function render() {
    frame = 0;
    const active = !section.hidden && section.dataset.state === "active";
    const version = extractTargetVersion(heading.textContent);

    if (active) {
      stickyCopy.classList.add("has-build-context");
      stickyLabel.textContent = "Current stable APK";
      context.textContent = formatBuildContext(version);
      context.hidden = false;
      return;
    }

    stickyCopy.classList.remove("has-build-context");
    stickyLabel.textContent = defaultLabel;
    context.hidden = true;
    context.textContent = "";
  }

  function scheduleRender() {
    if (frame) return;
    frame = window.requestAnimationFrame(render);
  }

  new MutationObserver(scheduleRender).observe(section, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: ["hidden", "data-state"],
  });

  scheduleRender();
}

if (typeof document !== "undefined") {
  try {
    initializeTimelineRefinement();
  } catch (error) {
    console.warn("VersionDeck timeline refinement is unavailable.", error);
  }
}
