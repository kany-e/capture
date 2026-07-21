import assert from "node:assert/strict";
import { test } from "node:test";

import {
  MemaApiError,
  MemaCaptureValidationError,
  MemaUnavailableError,
} from "../src/api/mema.js";
import {
  CREATE_CAPTURE_MESSAGE,
  DISABLE_INLINE_CAPTURE_MESSAGE,
  INLINE_CAPTURE_STATUS_MESSAGE,
  MemaCoordinatorError,
  SYNC_INLINE_CAPTURE_MESSAGE,
  buildCaptureAttempt,
  sendCaptureAttempt,
} from "../src/api/messages.js";
import {
  coordinateCapture,
  validCaptureAttempt,
} from "../src/background/capture-coordinator.js";
import {
  INLINE_CAPTURE_SCRIPT_FILES,
  INLINE_CAPTURE_SCRIPT_ID,
  LEGACY_DISABLE_INLINE_CAPTURE_MESSAGE,
  LEGACY_INLINE_CAPTURE_SCRIPT_ID,
  createInlineCaptureReconciler,
  disableInlineCaptureInOpenTabs,
  injectInlineCaptureInOpenTabs,
} from "../src/background/inline-registration.js";
import {
  createServiceWorkerMessageHandler,
  installServiceWorker,
} from "../src/background/service-worker.js";


const captureID = "149f51e1-8c18-42d4-9778-3f3b062527a2";


function extractedCapture(overrides = {}) {
  return {
    sourceTitle: "Systemd repair",
    sourceUrl: "https://example.com/repair",
    selectedText: "Set WorkingDirectory before restart.",
    surroundingContext: "The service failed only under systemd.",
    contextTruncated: false,
    ...overrides,
  };
}


function attempt(overrides = {}) {
  return {
    clientCaptureId: captureID,
    capturedAt: "2026-07-20T20:00:00.000Z",
    extractedCapture: extractedCapture(),
    userNote: "This solved the deployment issue.",
    ...overrides,
  };
}


test("attempt builder snapshots source, note, timestamp, and client id", () => {
  const source = extractedCapture({ hasSelection: true });
  const built = buildCaptureAttempt(source, "  Keep my spacing.  ", {
    now: () => new Date("2026-07-20T20:00:00.000Z"),
    createId: () => captureID,
  });
  source.selectedText = "changed after snapshot";

  assert.deepEqual(built, attempt({ userNote: "  Keep my spacing.  " }));
  assert.equal(built.extractedCapture.selectedText, "Set WorkingDirectory before restart.");
  assert.equal("hasSelection" in built.extractedCapture, false);
  assert.equal(Object.isFrozen(built), true);
  assert.equal(Object.isFrozen(built.extractedCapture), true);
});


test("message client returns coordinated captures and preserves safe error metadata", async () => {
  const saved = await sendCaptureAttempt(attempt(), {
    sendMessageImpl: async (message) => {
      assert.equal(message.type, CREATE_CAPTURE_MESSAGE);
      return {
        ok: true,
        capture: { id: "saved", status: "processing" },
      };
    },
  });
  assert.deepEqual(saved, { id: "saved", status: "processing" });

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
    (error) => error instanceof MemaCoordinatorError
      && error.code === "validation_error"
      && error.title === "Cannot save."
      && error.retryable === false,
  );

  await assert.rejects(
    sendCaptureAttempt(attempt(), {
      sendMessageImpl: async () => {
        throw new Error("worker stopped");
      },
    }),
    (error) => error instanceof MemaCoordinatorError
      && error.code === "extension_unavailable"
      && error.retryable === true,
  );
});


test("coordinator builds the existing Capture contract with exact retry identity", async () => {
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


test("coordinator strictly rejects malformed or expanded messages before transport", async () => {
  const invalidAttempts = [
    attempt({ clientCaptureId: "not-a-uuid" }),
    attempt({ capturedAt: "2026-07-20 20:00:00" }),
    attempt({ extra: true }),
    attempt({ extractedCapture: extractedCapture({ extra: true }) }),
    attempt({ extractedCapture: extractedCapture({ contextTruncated: "false" }) }),
  ];

  for (const invalid of invalidAttempts) {
    let called = false;
    const response = await coordinateCapture(invalid, {
      createCaptureImpl: async () => {
        called = true;
      },
    });
    assert.equal(validCaptureAttempt(invalid), false);
    assert.equal(called, false);
    assert.equal(response.ok, false);
    assert.equal(response.error.code, "invalid_extension_message");
    assert.equal(response.error.retryable, false);
  }
});


test("coordinator exposes only safe retry choices for transport and API failures", async (t) => {
  const cases = [
    ["network or timeout", new MemaUnavailableError(), true],
    ["invalid success response", new MemaApiError("Invalid response.", {
      code: "invalid_response",
      status: 202,
    }), true],
    ["request timeout", new MemaApiError("Timed out.", {
      code: "request_timeout",
      status: 408,
    }), true],
    ["rate limited", new MemaApiError("Slow down.", {
      code: "rate_limited",
      status: 429,
    }), true],
    ["server failure", new MemaApiError("Unavailable.", {
      code: "server_error",
      status: 503,
    }), true],
    ["ordinary client error", new MemaApiError("Conflict.", {
      code: "conflict",
      status: 409,
    }), false],
    ["backend validation", new MemaApiError("Invalid.", {
      code: "validation_error",
      status: 422,
    }), false],
    ["local contract validation", new MemaCaptureValidationError("Too long."), false],
  ];

  for (const [name, error, retryable] of cases) {
    await t.test(name, async () => {
      const response = await coordinateCapture(attempt(), {
        createCaptureImpl: async () => {
          throw error;
        },
      });
      assert.equal(response.ok, false);
      assert.equal(response.error.retryable, retryable);
    });
  }
});


function scriptingDouble(registered = []) {
  let current = [...registered];
  const calls = [];
  return {
    calls,
    getRegisteredContentScripts: async ({ ids } = {}) => current.filter(
      ({ id }) => !ids || ids.includes(id),
    ),
    registerContentScripts: async (scripts) => {
      calls.push(["register", scripts]);
      current = scripts;
    },
    updateContentScripts: async (scripts) => {
      calls.push(["update", scripts]);
      current = scripts;
    },
    unregisterContentScripts: async (details) => {
      calls.push(["unregister", details]);
      current = current.filter(({ id }) => !details.ids.includes(id));
    },
    executeScript: async (details) => {
      calls.push(["inject", details]);
    },
  };
}


test("enabling registers inline capture and injects every already-open web tab", async () => {
  const scripting = scriptingDouble();
  const enabled = await createInlineCaptureReconciler({
    permissions: { contains: async () => true },
    scripting,
    tabs: { query: async () => [{ id: 3 }, { id: 7 }, { id: undefined }] },
  })();

  assert.equal(enabled, true);
  assert.equal(scripting.calls[0][0], "register");
  assert.equal(scripting.calls[0][1][0].id, INLINE_CAPTURE_SCRIPT_ID);
  assert.deepEqual(scripting.calls[0][1][0].js, INLINE_CAPTURE_SCRIPT_FILES);
  assert.deepEqual(
    scripting.calls.filter(([kind]) => kind === "inject").map(([, details]) => details),
    [
      { target: { tabId: 3 }, files: [...INLINE_CAPTURE_SCRIPT_FILES] },
      { target: { tabId: 7 }, files: [...INLINE_CAPTURE_SCRIPT_FILES] },
    ],
  );
});


test("upgrade removes the legacy dynamic registration before enabling Mema", async () => {
  const scripting = scriptingDouble([{ id: LEGACY_INLINE_CAPTURE_SCRIPT_ID }]);

  const enabled = await createInlineCaptureReconciler({
    permissions: { contains: async () => true },
    scripting,
    tabs: { query: async () => [] },
  })();

  assert.equal(enabled, true);
  assert.deepEqual(scripting.calls[0], [
    "unregister",
    { ids: [LEGACY_INLINE_CAPTURE_SCRIPT_ID] },
  ]);
  assert.equal(scripting.calls[1][0], "register");
  assert.equal(scripting.calls[1][1][0].id, INLINE_CAPTURE_SCRIPT_ID);
});


test("one tab injection failure does not block other already-open pages", async () => {
  const result = await injectInlineCaptureInOpenTabs({
    tabs: { query: async () => [{ id: 1 }, { id: 2 }, { id: 3 }] },
    scripting: {
      executeScript: async ({ target }) => {
        if (target.tabId === 2) {
          throw new Error("restricted page");
        }
      },
    },
  });

  assert.deepEqual(result, { attempted: 3, succeeded: 2, failed: 1 });
});


test("permission reconciliation is serialized across event and popup requests", async () => {
  let activeChecks = 0;
  let maximumActiveChecks = 0;
  const scripting = scriptingDouble();
  const reconcile = createInlineCaptureReconciler({
    permissions: {
      contains: async () => {
        activeChecks += 1;
        maximumActiveChecks = Math.max(maximumActiveChecks, activeChecks);
        await new Promise((resolve) => setTimeout(resolve, 5));
        activeChecks -= 1;
        return true;
      },
    },
    scripting,
    tabs: { query: async () => [] },
  });

  assert.deepEqual(await Promise.all([reconcile(), reconcile()]), [true, true]);
  assert.equal(maximumActiveChecks, 1);
  assert.equal(
    scripting.calls.filter(([kind]) => kind === "register").length,
    1,
  );
});


test("revocation unregisters behavior and notifies all injected tabs", async () => {
  const scripting = scriptingDouble([{ id: INLINE_CAPTURE_SCRIPT_ID }]);
  const messages = [];
  const tabs = {
    query: async () => [{ id: 3 }, { id: 7 }, { id: undefined }],
    sendMessage: async (tabID, message) => {
      messages.push([tabID, message]);
      if (tabID === 7) {
        throw new Error("no receiver");
      }
    },
  };

  const enabled = await createInlineCaptureReconciler({
    permissions: { contains: async () => false },
    scripting,
    tabs,
  })();
  assert.equal(enabled, false);
  assert.deepEqual(scripting.calls, [[
    "unregister",
    { ids: [INLINE_CAPTURE_SCRIPT_ID] },
  ]]);
  assert.deepEqual(messages, [
    [3, { type: DISABLE_INLINE_CAPTURE_MESSAGE }],
    [3, { type: LEGACY_DISABLE_INLINE_CAPTURE_MESSAGE }],
    [7, { type: DISABLE_INLINE_CAPTURE_MESSAGE }],
    [7, { type: LEGACY_DISABLE_INLINE_CAPTURE_MESSAGE }],
  ]);

  const result = await disableInlineCaptureInOpenTabs(tabs);
  assert.deepEqual(result, { attempted: 4, succeeded: 2, failed: 2 });
});


function invokeAsyncHandler(handler, message, sender) {
  return new Promise((resolve, reject) => {
    const keepChannelOpen = handler(message, sender, resolve);
    if (keepChannelOpen !== true) {
      reject(new Error("message channel was not kept open"));
    }
  });
}


test("service-worker handler rejects foreign senders before delivery", () => {
  let called = false;
  const handler = createServiceWorkerMessageHandler({
    extensionId: "trusted-extension",
    coordinateCaptureImpl: async () => {
      called = true;
    },
    reconcileInlineCapture: async () => true,
  });

  const handled = handler(
    { type: CREATE_CAPTURE_MESSAGE, attempt: attempt() },
    { id: "foreign-extension" },
    () => assert.fail("foreign sender received a response"),
  );
  assert.equal(handled, false);
  assert.equal(called, false);
});


test(
  "service-worker handler delivers valid messages and strictly rejects envelope extras",
  async () => {
    const delivered = [];
    const handler = createServiceWorkerMessageHandler({
      extensionId: "trusted-extension",
      coordinateCaptureImpl: async (value) => {
        delivered.push(value);
        return { ok: true, capture: { id: "saved", status: "processing" } };
      },
      reconcileInlineCapture: async () => true,
    });

    const response = await invokeAsyncHandler(
      handler,
      { type: CREATE_CAPTURE_MESSAGE, attempt: attempt() },
      { id: "trusted-extension" },
    );
    assert.equal(response.ok, true);
    assert.deepEqual(delivered, [attempt()]);

    let invalidResponse = null;
    const keepOpen = handler(
      { type: CREATE_CAPTURE_MESSAGE, attempt: attempt(), extra: true },
      { id: "trusted-extension" },
      (value) => {
        invalidResponse = value;
      },
    );
    assert.equal(keepOpen, false);
    assert.equal(invalidResponse.error.code, "invalid_extension_message");
    assert.equal(delivered.length, 1);

    const syncResponse = await invokeAsyncHandler(
      handler,
      { type: SYNC_INLINE_CAPTURE_MESSAGE },
      { id: "trusted-extension" },
    );
    assert.deepEqual(syncResponse, { ok: true, enabled: true });
  },
);


test("read-only inline status messages report permission without reconciling tabs", async () => {
  let permissionState = true;
  let reconciled = false;
  const handler = createServiceWorkerMessageHandler({
    extensionId: "trusted-extension",
    inlineCapturePermissionEnabledImpl: async () => {
      if (permissionState === "error") {
        throw new Error("permission API unavailable");
      }
      return permissionState;
    },
    reconcileInlineCapture: async () => {
      reconciled = true;
      return true;
    },
  });
  const sender = { id: "trusted-extension", tab: { id: 3 } };

  assert.deepEqual(
    await invokeAsyncHandler(
      handler,
      { type: INLINE_CAPTURE_STATUS_MESSAGE },
      sender,
    ),
    { ok: true, enabled: true },
  );
  permissionState = false;
  assert.deepEqual(
    await invokeAsyncHandler(
      handler,
      { type: INLINE_CAPTURE_STATUS_MESSAGE },
      sender,
    ),
    { ok: true, enabled: false },
  );
  permissionState = "error";
  assert.deepEqual(
    await invokeAsyncHandler(
      handler,
      { type: INLINE_CAPTURE_STATUS_MESSAGE },
      sender,
    ),
    {
      ok: false,
      enabled: false,
      error: "Mema could not verify inline capture access.",
    },
  );
  assert.equal(reconciled, false);

  let invalidResponse = null;
  assert.equal(handler(
    { type: INLINE_CAPTURE_STATUS_MESSAGE, extra: true },
    sender,
    (response) => {
      invalidResponse = response;
    },
  ), false);
  assert.equal(invalidResponse.ok, false);
  assert.equal(invalidResponse.enabled, false);
});


test("content-script saves recheck inline access while popup saves remain independent", async () => {
  let permissionState = true;
  let permissionChecks = 0;
  let deliveries = 0;
  const handler = createServiceWorkerMessageHandler({
    extensionId: "trusted-extension",
    inlineCapturePermissionEnabledImpl: async () => {
      permissionChecks += 1;
      if (permissionState === "error") {
        throw new Error("permission API unavailable");
      }
      return permissionState;
    },
    coordinateCaptureImpl: async () => {
      deliveries += 1;
      return { ok: true, capture: { id: "saved", status: "processing" } };
    },
    reconcileInlineCapture: async () => true,
  });
  const message = { type: CREATE_CAPTURE_MESSAGE, attempt: attempt() };
  const contentSender = { id: "trusted-extension", tab: { id: 3 } };
  const popupSender = { id: "trusted-extension" };

  assert.equal(
    (await invokeAsyncHandler(handler, message, contentSender)).ok,
    true,
  );
  assert.equal(permissionChecks, 1);
  assert.equal(deliveries, 1);

  permissionState = false;
  const removed = await invokeAsyncHandler(handler, message, contentSender);
  assert.equal(removed.ok, false);
  assert.equal(removed.error.code, "inline_access_removed");
  assert.equal(removed.error.retryable, false);
  assert.equal(deliveries, 1);

  permissionState = "error";
  const unavailable = await invokeAsyncHandler(handler, message, contentSender);
  assert.equal(unavailable.error.code, "inline_access_removed");
  assert.equal(unavailable.error.retryable, false);
  assert.equal(deliveries, 1);

  const checksBeforePopup = permissionChecks;
  assert.equal(
    (await invokeAsyncHandler(handler, message, popupSender)).ok,
    true,
  );
  assert.equal(permissionChecks, checksBeforePopup);
  assert.equal(deliveries, 2);
});


function chromeEvent() {
  const listeners = [];
  return {
    listeners,
    addListener(listener) {
      listeners.push(listener);
    },
  };
}


test(
  "service worker keeps status reads side-effect free and reconciles lifecycle events",
  async () => {
    const onInstalled = chromeEvent();
    const onStartup = chromeEvent();
    const onAdded = chromeEvent();
    const onRemoved = chromeEvent();
    const onMessage = chromeEvent();
    const chromeApi = {
      runtime: {
        id: "trusted-extension",
        onInstalled,
        onStartup,
        onMessage,
      },
      permissions: { onAdded, onRemoved },
    };
    let reconciliations = 0;
    const reconcile = async () => {
      reconciliations += 1;
      return true;
    };

    installServiceWorker(chromeApi, {
      inlineCapturePermissionEnabledImpl: async () => true,
      reconcileInlineCaptureImpl: reconcile,
    });
    await Promise.resolve();
    assert.equal(reconciliations, 0);
    assert.equal(onMessage.listeners.length, 1);
    assert.deepEqual(
      await invokeAsyncHandler(
        onMessage.listeners[0],
        { type: INLINE_CAPTURE_STATUS_MESSAGE },
        { id: "trusted-extension", tab: { id: 3 } },
      ),
      { ok: true, enabled: true },
    );
    assert.equal(reconciliations, 0);

    for (const event of [onInstalled, onStartup, onAdded, onRemoved]) {
      assert.equal(event.listeners.length, 1);
      event.listeners[0]();
    }
    await Promise.resolve();
    assert.equal(reconciliations, 4);
  },
);
