import assert from "node:assert/strict";
import test from "node:test";
import {
  groupTechnicalSteps,
  parsePubspecVersion,
  phaseForTechnicalStep,
  shouldShowStarting,
} from "../download-site/build-status-ui.js";

test("technical steps map to distinct user-readable phases", () => {
  assert.equal(phaseForTechnicalStep("Check out repository").label, "Preparing source");
  assert.equal(phaseForTechnicalStep("Set up Flutter").label, "Configuring production build");
  assert.equal(phaseForTechnicalStep("Build and test production APK").label, "Building and testing APK");
  assert.equal(phaseForTechnicalStep("Verify package, version, checksum, and signer").label, "Verifying APK and release");
  assert.equal(phaseForTechnicalStep("Publish GitHub Release").label, "Publishing release");
  assert.equal(phaseForTechnicalStep("Remove temporary credentials").label, "Finalizing securely");
});

test("technical steps are grouped without changing source order", () => {
  const groups = groupTechnicalSteps([
    { name: "Check out repository" },
    { name: "Set up Java 17" },
    { name: "Set up Flutter" },
    { name: "Build and test production APK" },
    { name: "Publish GitHub Release" },
  ]);
  assert.deepEqual(groups.map((group) => group.id), ["source", "configure", "build", "publish"]);
  assert.deepEqual(groups[1].steps.map((step) => step.name), ["Set up Java 17", "Set up Flutter"]);
});

test("pubspec version parsing returns release and build numbers", () => {
  assert.deepEqual(parsePubspecVersion("name: owntend\nversion: 1.3.7+22\n"), {
    version: "1.3.7",
    build: 22,
  });
  assert.equal(parsePubspecVersion("version: invalid"), null);
});

test("zero percent on the first active step is presented as starting", () => {
  assert.equal(shouldShowStarting("Step 1 of 18", "0%"), true);
  assert.equal(shouldShowStarting("Step 1 of 18", "Starting"), true);
  assert.equal(shouldShowStarting("Step 2 of 18", "0%"), false);
  assert.equal(shouldShowStarting("Step 1 of 18", "4%"), false);
});
