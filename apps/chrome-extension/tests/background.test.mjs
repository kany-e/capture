import assert from "node:assert/strict";
import { test } from "node:test";

import {
  RecallCaptureValidationError,
  RecallUnavailableError,
} from "../src/api/recall.js";
import {
  RecallCoordinatorError,
  sendCaptureAttempt,
} from "../src/api/messages.js";
import { coordinateCapture } from "../src/background/capture-coordinator.js";
import {
  disableInlineCaptureInOpenTabs,
  INLINE_CAPTURE_SCRIPT_ID,
  syncInlineCaptureRegistration,
} from "../src/background/inline-registration.js";


const captureID = "149f51e1-8c18-42d4-9778-3f3b062527a2";


function attempt(overrides = {}) {
  return {
    clientCaptureId: captureID,
    capturedAt: "2026-07-20T20:00:00.000Z",
    extractedCapture: {
      sourceTitle: "Systemd repair",
      sourceUrl: "https://example.com/repair",
      selectedText: "Set WorkingDirectory before restart.",
      surroundingContext: "The service failed only under systemd.",
      contextTruncated: false,
      hasSelection: true,
      extractionMode: "preferred-container",
    },
    userNote: "This solved the deployment issue.",
    ...overrides,
  };
}


test("coordinator builds the existing Capture contract with stable retry identity", async () => {
  const calls = [];
  const response = await coordinateCapture(attempt(), {
    createCaptureImpl: async (payload) => {
      calls.push(payload);
      return { id: "saved-capture", status: "processing" };
    },
  });

  assert.deepEqual(response, {
    ok: true,
    capture: { id: "saved-capture", status: "processing" },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].client_capture_id, captureID);
  assert.equal(calls[0].captured_at, "2026-07-20T20:00:00.000Z");
  assert.equal(calls[0].selected_text, "Set WorkingDirectory before restart.");
  assert.equal(calls[0].user_note, "This solved the deployment issue.");
});


test("coordinator rejects an untrusted malformed message before transport", async () => {
  let called = false;
  const response = await coordinateCapture(attempt({ clientCaptureId: "not-a-uuid" }), {
    createCaptureImpl: async () => {
      called = true;
    },
  });

  assert.equal(called, false);
  assert.equal(response.ok, false);
  assert.equal(response.error.code, "invalid_extension_message");
  assert.equal(response.error.retryable, false);
});


test("coordinator maps ambiguous localhost failure to a retryable safe response", async () => {
  const response = await coordinateCapture(attempt(), {
    createCaptureImpl: async () => {
      throw new RecallUnavailableError();
    },
  });

  assert.equal(response.ok, false);
  assert.equal(response.error.code, "recall_unavailable");
  assert.equal(response.error.title, "REcall is not running.");
  assert.equal(response.error.retryable, true);
});


test("coordinator maps local contract errors without offering a useless retry", async () => {
  const response = await coordinateCapture(attempt(), {
    createCaptureImpl: async () => {
      throw new RecallCaptureValidationError("Your note is too long.");
    },
  });

  assert.equal(response.ok, false);
  assert.equal(response.error.code, "capture_validation_error");
  assert.equal(response.error.detail, "Your note is too long.");
  assert.equal(response.error.retryable, false);
});


test("message client returns a coordinated Capture and preserves error metadata", async () => {
  const saved = await sendCaptureAttempt(attempt(), {
    sendMessageImpl: async () => ({
      ok: true,
      capture: { id: "saved", status: "processing" },
    }),
  });
  assert.equal(saved.id, "saved");

  await assert.rejects(
    sendCaptureAttempt(attempt(), {
      sendMessageImpl: async () => ({
        ok: false,
        error: {
          code: "validation_error",
          title: "Cannot save.",
          detail: "The note is too long.",
          retryable: false,
        },
      }),
    }),
    (error) => error instanceof RecallCoordinatorError
      && error.code === "validation_error"
      && error.title === "Cannot save."
      && error.retryable === false,
  );
});


function scriptingDouble(registered = []) {
  const calls = [];
  return {
    calls,
    getRegisteredContentScripts: async () => registered,
    registerContentScripts: async (scripts) => calls.push(["register", scripts]),
    updateContentScripts: async (scripts) => calls.push(["update", scripts]),
    unregisterContentScripts: async (details) => calls.push(["unregister", details]),
  };
}


test("inline registration is added only after optional website access", async () => {
  const scripting = scriptingDouble();
  const enabled = await syncInlineCaptureRegistration({
    permissions: { contains: async () => true },
    scripting,
  });

  assert.equal(enabled, true);
  assert.equal(scripting.calls.length, 1);
  assert.equal(scripting.calls[0][0], "register");
  assert.equal(scripting.calls[0][1][0].id, INLINE_CAPTURE_SCRIPT_ID);
  assert.deepEqual(scripting.calls[0][1][0].js, [
    "src/content/inline-core.js",
    "src/content/inline-capture.js",
  ]);
});


test("inline registration updates an installed script and removes it after revocation", async () => {
  const existing = [{ id: INLINE_CAPTURE_SCRIPT_ID }];
  const enabledScripting = scriptingDouble(existing);
  assert.equal(await syncInlineCaptureRegistration({
    permissions: { contains: async () => true },
    scripting: enabledScripting,
  }), true);
  assert.equal(enabledScripting.calls[0][0], "update");

  const disabledScripting = scriptingDouble(existing);
  assert.equal(await syncInlineCaptureRegistration({
    permissions: { contains: async () => false },
    scripting: disabledScripting,
  }), false);
  assert.deepEqual(disabledScripting.calls, [[
    "unregister",
    { ids: [INLINE_CAPTURE_SCRIPT_ID] },
  ]]);
});


test("revocation disables already-injected controls without requiring a reload", async () => {
  const messages = [];
  await disableInlineCaptureInOpenTabs({
    query: async () => [{ id: 3 }, { id: 7 }, { id: undefined }],
    sendMessage: async (tabID, message) => messages.push([tabID, message]),
  });

  assert.deepEqual(messages, [
    [3, { type: "recall:inline:disable" }],
    [7, { type: "recall:inline:disable" }],
  ]);
});
