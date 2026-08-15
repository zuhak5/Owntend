import assert from "node:assert/strict";
import test from "node:test";
import {
  extractTargetVersion,
  formatBuildContext,
} from "../download-site/build-status-timeline.js";

test("target version is extracted from the live build heading", () => {
  assert.equal(extractTargetVersion("Building Owntend 1.3.8"), "1.3.8");
  assert.equal(extractTargetVersion("Building Owntend APK"), "");
});

test("sticky build context stays concise and validates versions", () => {
  assert.equal(formatBuildContext("1.3.8"), "1.3.8 building");
  assert.equal(formatBuildContext("invalid"), "Build in progress");
});
