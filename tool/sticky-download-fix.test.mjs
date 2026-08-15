import test from "node:test";
import assert from "node:assert/strict";
import { buildIsActive, stableDownloadLabel } from "../download-site/sticky-download-fix.js";

test("uses a compact stable-download label", () => {
  assert.equal(stableDownloadLabel(), "Current stable APK");
});

test("requires a visible active build for build context", () => {
  assert.equal(buildIsActive({ hidden: false, dataset: { state: "active" } }), true);
  assert.equal(buildIsActive({ hidden: true, dataset: { state: "active" } }), false);
  assert.equal(buildIsActive({ hidden: false, dataset: { state: "inactive" } }), false);
});
