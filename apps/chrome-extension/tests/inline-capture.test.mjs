import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import vm from "node:vm";


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


function plain(value) {
  return JSON.parse(JSON.stringify(value));
}


test("state machine freezes one attempt, rejects rapid double submit, and protects success", () => {
  const core = loadCore();
  const state = core.createStateMachine();
  const originalSnapshot = { selectedText: "important context" };
  const replacementSnapshot = { selectedText: "later selection" };
  const originalAttempt = {
    clientCaptureId: "stable-id",
    capturedAt: "2026-07-20T20:00:00.000Z",
  };
  let builds = 0;

  assert.equal(state.showPill(originalSnapshot), true);
  assert.equal(state.openComposer(), true);
  const first = state.beginSubmit(() => {
    builds += 1;
    return originalAttempt;
  });
  const rapidSecond = state.beginSubmit(() => {
    builds += 1;
    return { clientCaptureId: "duplicate" };
  });

  assert.equal(first, originalAttempt);
  assert.equal(rapidSecond, null);
  assert.equal(builds, 1);
  assert.equal(state.dismiss(), false);

  assert.equal(state.fail({ retryable: true }), true);
  const retry = state.beginSubmit(() => {
    builds += 1;
    return { clientCaptureId: "replacement" };
  });
  assert.equal(retry, originalAttempt);
  assert.equal(builds, 1);

  assert.equal(state.succeed(), true);
  assert.equal(state.showPill(replacementSnapshot), false);
  assert.equal(state.state, core.STATES.success);
  assert.equal(state.snapshot, originalSnapshot);
  assert.equal(state.attempt, originalAttempt);
});


test("non-retryable errors cannot begin a second submission", () => {
  const core = loadCore();
  const state = core.createStateMachine();
  state.showPill({ selectedText: "invalid" });
  state.openComposer();
  state.beginSubmit(() => ({ clientCaptureId: "one" }));
  state.fail({ retryable: false });

  assert.equal(state.beginSubmit(() => ({ clientCaptureId: "two" })), null);
  assert.equal(state.attempt.clientCaptureId, "one");
  assert.equal(state.state, core.STATES.error);
});


test("latest task gate invalidates stale selection work", () => {
  const core = loadCore();
  const gate = core.createLatestTaskGate();
  const first = gate.next();
  const latest = gate.next();

  assert.equal(gate.isCurrent(first), false);
  assert.equal(gate.isCurrent(latest), true);
  gate.next();
  assert.equal(gate.isCurrent(latest), false);
});


test("listener registry removes every listener exactly once and remains reusable", () => {
  const core = loadCore();
  const registry = core.createListenerRegistry();
  const calls = [];
  const target = {
    addEventListener(type, listener, options) {
      calls.push(["add", type, listener, options]);
    },
    removeEventListener(type, listener, options) {
      calls.push(["remove", type, listener, options]);
    },
  };
  const firstListener = () => {};
  const secondListener = () => {};
  const capture = { capture: true };

  registry.listen(target, "pointerup", firstListener, capture);
  registry.listen(target, "keydown", secondListener, true);
  registry.clear();
  registry.clear();

  assert.deepEqual(calls, [
    ["add", "pointerup", firstListener, capture],
    ["add", "keydown", secondListener, true],
    ["remove", "keydown", secondListener, true],
    ["remove", "pointerup", firstListener, capture],
  ]);

  registry.listen(target, "blur", firstListener);
  registry.clear();
  assert.deepEqual(calls.at(-1), ["remove", "blur", firstListener, undefined]);
});


test("Unicode note limits count emoji as characters at 4,000 and 4,001", () => {
  const core = loadCore();
  const accepted = "🧠".repeat(4_000);
  const rejected = "🧠".repeat(4_001);

  assert.equal(core.unicodeLength(accepted), 4_000);
  assert.equal(core.unicodeLength(rejected), 4_001);
  const truncated = core.truncateUnicode(rejected, 4_000);
  assert.equal(core.unicodeLength(truncated.text), 4_000);
  assert.equal(truncated.text, accepted);
  assert.equal(truncated.characterCount, 4_001);
  assert.equal(truncated.truncated, true);
});


test("UUID creation uses getRandomValues and sets RFC 4122 version and variant bits", () => {
  const core = loadCore();
  let calls = 0;
  const cryptoDouble = {
    randomUUID() {
      throw new Error("randomUUID must not be required by an HTTP content script");
    },
    getRandomValues(bytes) {
      calls += 1;
      for (let index = 0; index < bytes.length; index += 1) {
        bytes[index] = index;
      }
      return bytes;
    },
  };

  assert.equal(
    core.createUUID(cryptoDouble),
    "00010203-0405-4607-8809-0a0b0c0d0e0f",
  );
  assert.equal(calls, 1);
  assert.throws(() => core.createUUID({}), /secure_random_unavailable/);
});


test("keyboard selection predicate accepts only completed selection gestures", () => {
  const core = loadCore();
  const accepted = [
    { key: "ArrowLeft", shiftKey: true },
    { key: "ArrowDown", shiftKey: true },
    { key: "Home", shiftKey: true },
    { key: "End", shiftKey: true },
    { key: "PageUp", shiftKey: true },
    { key: "a", metaKey: true },
    { key: "A", ctrlKey: true },
  ];
  const rejected = [
    null,
    { key: "Escape" },
    { key: "ArrowLeft" },
    { key: "x", shiftKey: true },
    { key: "Enter", metaKey: true },
    { key: "a" },
  ];

  for (const event of accepted) {
    assert.equal(core.shouldObserveKeyboardSelection(event), true);
  }
  for (const event of rejected) {
    assert.equal(core.shouldObserveKeyboardSelection(event), false);
  }
});


test("outside pointers dismiss transient UI but preserve submission results and errors", () => {
  const core = loadCore();

  assert.equal(core.shouldDismissForOutsidePointer(core.STATES.idle), false);
  assert.equal(core.shouldDismissForOutsidePointer(core.STATES.pill), true);
  assert.equal(core.shouldDismissForOutsidePointer(core.STATES.composer), true);
  assert.equal(core.shouldDismissForOutsidePointer(core.STATES.submitting), false);
  assert.equal(core.shouldDismissForOutsidePointer(core.STATES.success), false);
  assert.equal(core.shouldDismissForOutsidePointer(core.STATES.error), false);
});


test("Escape closes Recall UI without consuming the page event", () => {
  const core = loadCore();
  const dismissibleStates = [
    core.STATES.pill,
    core.STATES.composer,
    core.STATES.error,
    core.STATES.success,
  ];

  for (const targetState of dismissibleStates) {
    const state = core.createStateMachine();
    state.showPill({ selectedText: targetState });
    if (targetState !== core.STATES.pill) {
      state.openComposer();
      if ([core.STATES.error, core.STATES.success].includes(targetState)) {
        state.beginSubmit(() => ({ clientCaptureId: targetState }));
        if (targetState === core.STATES.error) {
          state.fail({ retryable: true });
        } else {
          state.succeed();
        }
      }
    }

    const dismissCalls = [];
    const pageEvent = {
      key: "Escape",
      preventDefault() {
        assert.fail("Escape default was prevented");
      },
      stopPropagation() {
        assert.fail("Escape propagation was stopped");
      },
    };
    const handled = core.dismissOnEscape(
      pageEvent,
      state.state,
      (options) => {
        dismissCalls.push(options);
        return state.dismiss();
      },
    );

    assert.equal(handled, true);
    assert.equal(state.state, core.STATES.idle);
    assert.deepEqual(plain(dismissCalls), [{
      restoreFocus: targetState !== core.STATES.pill,
    }]);
  }

  const submitting = core.createStateMachine();
  submitting.showPill({ selectedText: "submitting" });
  submitting.openComposer();
  submitting.beginSubmit(() => ({ clientCaptureId: "submitting" }));
  assert.equal(
    core.dismissOnEscape(
      { key: "Escape" },
      submitting.state,
      () => assert.fail("submitting state was dismissed"),
    ),
    false,
  );
  assert.equal(submitting.state, core.STATES.submitting);
});


test("save errors focus Try again or Cancel according to retryability", () => {
  const core = loadCore();
  const focusCalls = [];
  const retryButton = {
    focus(options) {
      focusCalls.push(["retry", options]);
    },
  };
  const cancelButton = {
    focus(options) {
      focusCalls.push(["cancel", options]);
    },
  };

  assert.equal(
    core.focusErrorAction({ retryable: true }, retryButton, cancelButton),
    retryButton,
  );
  assert.equal(
    core.focusErrorAction({ retryable: false }, retryButton, cancelButton),
    cancelButton,
  );
  assert.deepEqual(plain(focusCalls), [
    ["retry", { preventScroll: true }],
    ["cancel", { preventScroll: true }],
  ]);
});


test("page lifecycle reset leaves the state machine reusable after BFCache restore", () => {
  const core = loadCore();
  const state = core.createStateMachine();
  state.showPill({ selectedText: "before navigation" });
  state.openComposer();
  state.beginSubmit(() => ({ clientCaptureId: "before-navigation" }));

  state.reset();
  assert.equal(state.state, core.STATES.idle);
  assert.equal(state.snapshot, null);
  assert.equal(state.attempt, null);
  assert.equal(
    state.showPill({ selectedText: "after BFCache restore" }),
    true,
  );
  assert.equal(state.state, core.STATES.pill);
});


test("suspension gate resumes only the latest cache entry with explicit access", () => {
  const core = loadCore();
  const gate = core.createSuspensionGate();
  assert.equal(gate.suspended, false);

  const first = gate.suspend();
  assert.equal(gate.suspended, true);
  assert.equal(gate.resume(first, false), false);
  assert.equal(gate.suspended, true);

  const latest = gate.suspend();
  assert.equal(gate.resume(first, true), false);
  assert.equal(gate.suspended, true);
  assert.equal(gate.resume(latest, true), true);
  assert.equal(gate.suspended, false);

  const invalidated = gate.suspend();
  gate.invalidate();
  assert.equal(gate.resume(invalidated, true), false);
  assert.equal(gate.suspended, true);
});


test("overlay positioning avoids selections and clamps at viewport edges", () => {
  const core = loadCore();
  const below = plain(core.placeOverlay(
    { top: 40, right: 180, bottom: 60, left: 100 },
    { width: 110, height: 32 },
    { width: 320, height: 240 },
  ));
  assert.deepEqual(below, { left: 70, top: 68, placement: "below" });

  const above = plain(core.placeOverlay(
    { top: 210, right: 315, bottom: 230, left: 280 },
    { width: 110, height: 40 },
    { width: 320, height: 240 },
  ));
  assert.deepEqual(above, { left: 202, top: 162, placement: "above" });

  const right = plain(core.placeAdjacentOverlay(
    { top: 160, right: 820, bottom: 182, left: 400 },
    { width: 340, height: 280 },
    { width: 1_280, height: 720 },
  ));
  assert.deepEqual(right, { left: 828, top: 160, placement: "right" });

  const left = plain(core.placeAdjacentOverlay(
    { top: 80, right: 1_160, bottom: 102, left: 920 },
    { width: 340, height: 280 },
    { width: 1_280, height: 720 },
  ));
  assert.deepEqual(left, { left: 572, top: 80, placement: "left" });

  const narrow = plain(core.placeOverlay(
    { top: 1, right: 2, bottom: 3, left: 1 },
    { width: 340, height: 280 },
    { width: 300, height: 240 },
  ));
  assert.equal(narrow.left, 8);
  assert.equal(narrow.top, 8);
});


test("content source keeps selection private until explicit submit", () => {
  const submitStart = captureSource.indexOf("async function submit()");
  const sendStart = captureSource.indexOf("chrome.runtime.sendMessage");

  assert.ok(submitStart >= 0);
  assert.ok(sendStart > submitStart);
  assert.equal(
    [...captureSource.matchAll(/chrome\.runtime\.sendMessage/g)].length,
    2,
  );
  assert.match(captureSource, /Nothing is sent until Save\./);
  assert.doesNotMatch(captureSource, /\.innerHTML\s*=/);
  assert.doesNotMatch(captureSource, /chrome\.storage/);
  assert.doesNotMatch(captureSource, /console\.(?:log|info|debug)/);
});


test("inline capture sends no broad surrounding page context", () => {
  const captureStart = captureSource.indexOf("function captureSelection(originTarget)");
  const captureEnd = captureSource.indexOf("function positionSurface", captureStart);
  const captureBlock = captureSource.slice(captureStart, captureEnd);

  assert.match(captureBlock, /surroundingContext: ""/);
  assert.match(captureBlock, /selectionCharacterCount: selected\.characterCount/);
  assert.match(captureBlock, /selectionTruncated: selected\.truncated/);
  assert.match(captureBlock, /contextTruncated: false/);
  assert.doesNotMatch(captureBlock, /document\.body/);
  assert.doesNotMatch(captureBlock, /innerText/);
  assert.doesNotMatch(captureSource, /PREFERRED_CONTEXT_SELECTOR/);
  assert.doesNotMatch(captureSource, /MAX_CONTEXT_CHARACTERS/);
});


test("content source enforces Unicode note limits without the UTF-16 maxlength trap", () => {
  assert.match(captureSource, /core\.unicodeLength\(note\.value\)/);
  assert.match(captureSource, /count > MAX_NOTE_CHARACTERS/);
  assert.doesNotMatch(captureSource, /note\.maxLength\s*=/);
  assert.doesNotMatch(captureSource, /setAttribute\(["']maxlength["']/i);
});


test("inline composer distinguishes selection and note counts with a scrollable preview", () => {
  assert.match(
    captureSource,
    /core\.unicodeLength\(snapshot\.selectedText\)/,
  );
  assert.match(captureSource, /characters?" : "characters/);
  assert.match(captureSource, /first \$\{savedCharacterCount\.toLocaleString\(\)\} will be saved/);
  assert.match(captureSource, /Note: \$\{count\.toLocaleString\(\)\}/);
  assert.match(captureSource, /preview\.tabIndex = 0/);
  assert.match(captureSource, /preview\.setAttribute\("role", "region"\)/);
  assert.match(captureSource, /\.recall-preview \{[\s\S]*overflow: auto;/);
  assert.match(captureSource, /\.recall-preview \{[\s\S]*max-height: 128px;/);
  assert.match(captureSource, /\.recall-composer \{[\s\S]*overflow: auto;/);
  assert.match(
    captureSource,
    /\.recall-composer \{[\s\S]*max-height: calc\(100vh - 16px\);/,
  );
  assert.doesNotMatch(captureSource, /-webkit-line-clamp: 2/);
});


test("selection eligibility checks both endpoints against editable content", () => {
  const captureStart = captureSource.indexOf("function captureSelection(originTarget)");
  const captureEnd = captureSource.indexOf("function positionSurface", captureStart);
  const captureBlock = captureSource.slice(captureStart, captureEnd);

  assert.match(
    captureBlock,
    /const anchorElement = elementForNode\(selection\.anchorNode\)/,
  );
  assert.match(
    captureBlock,
    /const focusElement = elementForNode\(selection\.focusNode\)/,
  );
  assert.match(captureBlock, /!isEligibleTarget\(anchorElement\)/);
  assert.match(captureBlock, /!isEligibleTarget\(focusElement\)/);
});


test("every hidden-surface path clears captured preview and source text", () => {
  const hideStart = captureSource.indexOf("function hideSurface(");
  const hideEnd = captureSource.indexOf("function dismiss(", hideStart);
  const hideBlock = captureSource.slice(hideStart, hideEnd);

  assert.match(hideBlock, /preview\.textContent = ""/);
  assert.match(hideBlock, /source\.textContent = ""/);
  assert.match(hideBlock, /note\.value = ""/);
});


test("revocation performs complete controller, listener, message, and host cleanup", () => {
  const disableStart = captureSource.indexOf("function disableInlineCapture()");
  const disableEnd = captureSource.indexOf("function runtimeMessageListener", disableStart);
  const disableBlock = captureSource.slice(disableStart, disableEnd);

  assert.match(disableBlock, /selectionGate\.next\(\)/);
  assert.match(disableBlock, /machine\.reset\(\)/);
  assert.match(disableBlock, /listeners\.clear\(\)/);
  assert.match(disableBlock, /onMessage\?\.removeListener\?\./);
  assert.match(disableBlock, /host\.remove\(\)/);
  assert.match(disableBlock, /__recallInlineCaptureController = null/);
});


test("pagehide suspends UI and persisted pageshow performs a read-only access check", () => {
  const suspendStart = captureSource.indexOf("function suspendInlineCapture()");
  const suspendEnd = captureSource.indexOf(
    "async function resumeInlineCaptureFromPageCache",
    suspendStart,
  );
  const suspendBlock = captureSource.slice(suspendStart, suspendEnd);
  const resumeStart = suspendEnd;
  const resumeEnd = captureSource.indexOf("function disableInlineCapture()", resumeStart);
  const resumeBlock = captureSource.slice(resumeStart, resumeEnd);

  assert.match(suspendBlock, /pageCacheToken = suspensionGate\.suspend\(\)/);
  assert.match(suspendBlock, /selectionGate\.next\(\)/);
  assert.match(suspendBlock, /machine\.reset\(\)/);
  assert.match(suspendBlock, /hideSurface\(\)/);
  assert.doesNotMatch(suspendBlock, /listeners\.clear\(\)/);
  assert.doesNotMatch(suspendBlock, /host\.remove\(\)/);
  assert.doesNotMatch(suspendBlock, /__recallInlineCaptureController = null/);
  assert.match(
    captureSource,
    /listeners\.listen\(global, "pagehide", suspendInlineCapture\)/,
  );
  assert.match(captureSource, /listeners\.listen\(global, "pageshow"/);
  assert.match(resumeBlock, /event\?\.persisted !== true/);
  assert.match(resumeBlock, /type: INLINE_CAPTURE_STATUS_MESSAGE/);
  assert.match(resumeBlock, /response\?\.ok === true/);
  assert.match(resumeBlock, /response\.enabled === true/);
  assert.match(resumeBlock, /suspensionGate\.resume\(expectedToken, true\)/);
  assert.match(resumeBlock, /disableInlineCapture\(\)/);
  assert.doesNotMatch(resumeBlock, /SYNC_INLINE_CAPTURE/);
  assert.match(captureSource, /machine\.state !== core\.STATES\.submitting/);
});


test("suspended controller fails closed for selection and submit entry points", () => {
  const inactiveStart = captureSource.indexOf("function inlineCaptureInactive()");
  const inactiveEnd = captureSource.indexOf("const host", inactiveStart);
  const inactiveBlock = captureSource.slice(inactiveStart, inactiveEnd);
  assert.match(inactiveBlock, /disabled \|\| suspensionGate\.suspended/);

  for (const functionName of [
    "showSelectionAction",
    "scheduleSelectionAction",
    "openComposer",
    "submit",
  ]) {
    const start = captureSource.indexOf(`function ${functionName}`);
    const nextFunction = captureSource.indexOf("\n  function ", start + 1);
    const block = captureSource.slice(
      start,
      nextFunction === -1 ? captureSource.length : nextFunction,
    );
    assert.match(block, /inlineCaptureInactive\(\)/, functionName);
  }
});


test("Escape never prevents the page default while the explicit save shortcut does", () => {
  const escapeStart = captureSource.lastIndexOf(
    "listeners.listen(document, \"keydown\", (event) => {",
  );
  const escapeEnd = captureSource.indexOf("\n  }, true);", escapeStart);
  const escapeBlock = captureSource.slice(escapeStart, escapeEnd);
  assert.match(escapeBlock, /core\.dismissOnEscape\(event, machine\.state, dismiss\)/);
  assert.doesNotMatch(escapeBlock, /preventDefault/);
  assert.doesNotMatch(escapeBlock, /stopPropagation/);

  const shortcutStart = captureSource.indexOf(
    "listeners.listen(note, \"keydown\", (event) => {",
  );
  const shortcutEnd = captureSource.indexOf("\n  });", shortcutStart);
  const shortcutBlock = captureSource.slice(shortcutStart, shortcutEnd);
  assert.match(shortcutBlock, /event\.key === "Enter"/);
  assert.match(shortcutBlock, /event\.metaKey \|\| event\.ctrlKey/);
  assert.match(shortcutBlock, /event\.preventDefault\(\)/);
});


test("content error path schedules a reachable retry or cancel action", () => {
  assert.match(
    captureSource,
    /core\.focusErrorAction\(expectedError, saveButton, cancelButton\)/,
  );
  assert.match(captureSource, /machine\.state === core\.STATES\.error/);
});
