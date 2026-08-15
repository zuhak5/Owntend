export function stableDownloadLabel() {
  return "Current stable APK";
}

export function buildIsActive(section) {
  return Boolean(section && !section.hidden && section.dataset.state === "active");
}

function initializeStickyDownloadFix() {
  const section = document.querySelector("#build-progress-section");
  const stickyCopy = document.querySelector("#sticky-download .sticky-copy");
  const stickyLabel = stickyCopy?.querySelector("small");
  const context = stickyCopy?.querySelector(".sticky-build-context");
  if (!section || !stickyCopy || !stickyLabel) return;

  let frame = 0;

  function render() {
    frame = 0;
    const active = buildIsActive(section);
    stickyLabel.textContent = stableDownloadLabel();

    if (!context) {
      stickyCopy.classList.remove("has-build-context");
      return;
    }

    context.hidden = !active;
    context.setAttribute("aria-hidden", String(!active));
    if (active) {
      context.style.removeProperty("display");
      stickyCopy.classList.add("has-build-context");
    } else {
      context.style.display = "none";
      context.textContent = "";
      stickyCopy.classList.remove("has-build-context");
    }
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
    initializeStickyDownloadFix();
  } catch (error) {
    console.warn("VersionDeck sticky-download fix is unavailable.", error);
  }
}
