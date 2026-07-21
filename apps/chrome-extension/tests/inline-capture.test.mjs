import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import { test } from "node:test";


const coreSource = await readFile(
  new URL("../src/content/inline-core.js", import.meta.url),
  "utf8",
);
const captureSource = await readFile(
  new URL("../src/content/inline-capture.js", import.meta.url),
  "utf8",
);


function loadCore() {
  const context = { globalThis: null };
  context.globalThis = context;
  vm.runInNewContext(coreSource, context, { filename: "inline-core.js" });
  return context.RecallInlineCore;
}


test("inline state machine freezes one attempt across an ambiguous retry", () => {
  const core = loadCore();
  const state = core.createStateMachine();
  const snapshot = { selectedText: "important context" };
  const originalAttempt = { clientCaptureId: "stable" };
  let builds = 0;

  assert.equal(state.showPill(snapshot), true);
  assert.equal(state.state, "pill");
  assert.equal(state.openComposer(), true);
  const first = state.beginSubmit(() => {
    builds += 1;
    return originalAttempt;
  });
  assert.equal(first, originalAttempt);
  assert.equal(state.dismiss(), false);
  assert.equal(state.fail({ retryable: true }), true);
  const retry = state.beginSubmit(() => {
    builds += 1;
    return { clientCaptureId: "different" };
  });

  assert.equal(retry, originalAttempt);
  assert.equal(builds, 1);
  assert.equal(state.succeed(), true);
  assert.equal(state.dismiss(), true);
  assert.equal(state.state, "idle");
});


test("inline positioning avoids the selection and clamps to viewport edges", () => {
  const core = loadCore();
  const below = core.placeOverlay(
    { top: 40, right: 180, bottom: 60, left: 100 },
    { width: 110, height: 32 },
    { width: 320, height: 240 },
  );
  assert.equal(below.placement, "below");
  assert.equal(below.top, 68);
  assert.equal(below.left, 70);

  const above = core.placeOverlay(
    { top: 210, right: 315, bottom: 230, left: 280 },
    { width: 110, height: 40 },
    { width: 320, height: 240 },
  );
  assert.equal(above.placement, "above");
  assert.equal(above.top, 162);
  assert.equal(above.left, 202);

  const right = core.placeAdjacentOverlay(
    { top: 160, right: 820, bottom: 182, left: 400 },
    { width: 340, height: 280 },
    { width: 1_280, height: 720 },
  );
  assert.equal(right.placement, "right");
  assert.equal(right.left, 828);
  assert.equal(right.top, 160);

  const left = core.placeAdjacentOverlay(
    { top: 80, right: 1_160, bottom: 102, left: 920 },
    { width: 340, height: 280 },
    { width: 1_280, height: 720 },
  );
  assert.equal(left.placement, "left");
  assert.equal(left.left, 572);
});


test("inline normalization respects Unicode limits without splitting emoji", () => {
  const core = loadCore();
  assert.equal(core.normalizeText("  first\r\n second  "), "first\n second");
  const truncated = core.truncateUnicode("🧠".repeat(5), 3);
  assert.equal(truncated.text, "🧠🧠🧠");
  assert.equal(truncated.truncated, true);
});


test("content script is transient, isolated, and transmits only from submit", () => {
  assert.match(captureSource, /testShadowIsOpen \? "open" : "closed"/);
  assert.match(captureSource, /document\.currentScript\?\.dataset\.recallTestShadow/);
  assert.match(captureSource, /position: fixed/);
  assert.match(captureSource, /PILL_TIMEOUT_MS = 4_000/);
  assert.match(captureSource, /pointerup/);
  assert.match(captureSource, /selectionchange/);
  assert.match(captureSource, /addEventListener\("scroll"/);
  assert.match(captureSource, /addEventListener\("blur"/);
  assert.match(captureSource, /DISABLE_INLINE_CAPTURE_MESSAGE/);
  assert.match(captureSource, /host\.remove\(\)/);
  assert.match(captureSource, /Nothing is sent until you choose Save Memory\./);
  assert.doesNotMatch(captureSource, /\.innerHTML\s*=/);
  assert.doesNotMatch(captureSource, /chrome\.storage/);

  const submitStart = captureSource.indexOf("async function submit()");
  const sendStart = captureSource.indexOf("chrome.runtime.sendMessage");
  assert.ok(submitStart >= 0);
  assert.ok(sendStart > submitStart);
});


test("content script exposes required accessibility and unsupported-input guards", () => {
  assert.match(captureSource, /aria-label", "Add selected text to REcall/);
  assert.match(captureSource, /aria-modal", "false"/);
  assert.match(captureSource, /aria-live", "polite"/);
  assert.match(captureSource, /prefers-reduced-motion/);
  assert.match(captureSource, /contenteditable/);
  assert.match(captureSource, /role='textbox'/);
  assert.match(captureSource, /event\.key === "Escape"/);
  assert.match(captureSource, /event\.metaKey \|\| event\.ctrlKey/);
});
