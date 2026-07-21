import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import {
  CAPTURE_LIMITS,
  RECALL_BASE_URL,
  RecallApiError,
  RecallCaptureValidationError,
  RecallUnavailableError,
  buildCaptureRequest,
  createCapture,
} from "../src/api/recall.js";
import { createCaptureAttempt } from "../src/popup/capture-attempt.js";


const extensionRoot = fileURLToPath(new URL("..", import.meta.url));
const repositoryRoot = fileURLToPath(new URL("../../..", import.meta.url));


function extracted(overrides = {}) {
  return {
    sourceTitle: "Nginx 502 repair",
    sourceUrl: "https://example.com/repair",
    selectedText: "Set WorkingDirectory before restart.",
    surroundingContext: "The service failed only under systemd.",
    contextTruncated: false,
    hasSelection: true,
    extractionMode: "preferred-container",
    ...overrides,
  };
}


test("request builder emits only the shared Capture contract fields", async () => {
  const payload = buildCaptureRequest(extracted(), "  Keep my spacing.  ", {
    now: () => new Date("2026-07-18T20:00:00.000Z"),
    createId: () => "149f51e1-8c18-42d4-9778-3f3b062527a2",
  });
  const schema = JSON.parse(
    await readFile(`${repositoryRoot}/contracts/capture.schema.json`, "utf8"),
  );

  assert.deepEqual(Object.keys(payload).sort(), Object.keys(schema.properties).sort());
  assert.equal(payload.source_type, "web");
  assert.equal(payload.source_app, "Google Chrome");
  assert.equal(payload.user_note, "  Keep my spacing.  ");
  assert.equal(payload.captured_at, "2026-07-18T20:00:00.000Z");
  assert.equal(payload.context_truncated, false);
});


test("empty note and empty context use the contract null values", () => {
  const payload = buildCaptureRequest(
    extracted({ surroundingContext: "" }),
    "   ",
    { createId: () => "id", now: () => new Date(0) },
  );

  assert.equal(payload.user_note, null);
  assert.equal(payload.surrounding_context, null);
});


test("request builder enforces user-authored and source-content limits", () => {
  assert.throws(
    () => buildCaptureRequest(extracted(), "🧠".repeat(CAPTURE_LIMITS.userNote + 1)),
    RecallCaptureValidationError,
  );
  assert.throws(
    () => buildCaptureRequest(extracted({
      selectedText: "x".repeat(CAPTURE_LIMITS.selectedText + 1),
    }), ""),
    RecallCaptureValidationError,
  );
  assert.throws(
    () => buildCaptureRequest(extracted({
      surroundingContext: "x".repeat(CAPTURE_LIMITS.surroundingContext + 1),
    }), ""),
    RecallCaptureValidationError,
  );
});


test("request builder bounds optional page metadata without breaking capture", () => {
  const payload = buildCaptureRequest(extracted({
    sourceTitle: "🧠".repeat(CAPTURE_LIMITS.sourceTitle + 1),
    sourceUrl: `https://example.com/${"x".repeat(CAPTURE_LIMITS.sourceUrl)}`,
  }), "", {
    createId: () => "id",
    now: () => new Date(0),
  });

  assert.equal(Array.from(payload.source_title).length, CAPTURE_LIMITS.sourceTitle);
  assert.equal(payload.source_title.endsWith("🧠"), true);
  assert.equal(payload.source_url, null);
});


test("one popup attempt reuses its exact payload across retries", () => {
  let builds = 0;
  const attempt = createCaptureAttempt((source, note) => {
    builds += 1;
    return { source, note, client_capture_id: "stable-id" };
  });

  const first = attempt.request("first source", "original note");
  const retry = attempt.request("changed source", "edited note");

  assert.equal(attempt.isLocked, true);
  assert.equal(builds, 1);
  assert.equal(retry, first);
  assert.deepEqual(retry, {
    source: "first source",
    note: "original note",
    client_capture_id: "stable-id",
  });
});


test("API client posts one JSON request and accepts processing response", async () => {
  const payload = buildCaptureRequest(extracted(), "note", {
    createId: () => "id",
    now: () => new Date(0),
  });
  const calls = [];
  const fetchImpl = async (...args) => {
    calls.push(args);
    return {
      ok: true,
      status: 202,
      json: async () => ({ id: "capture-id", status: "processing" }),
    };
  };

  const response = await createCapture(payload, { fetchImpl });

  assert.deepEqual(response, { id: "capture-id", status: "processing" });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], `${RECALL_BASE_URL}/v1/captures`);
  assert.equal(calls[0][1].method, "POST");
  assert.deepEqual(calls[0][1].headers, { "Content-Type": "application/json" });
  assert.deepEqual(JSON.parse(calls[0][1].body), payload);
});


test("network failure becomes the explicit Recall unavailable error", async () => {
  const fetchImpl = async () => {
    throw new TypeError("connection refused");
  };

  await assert.rejects(
    createCapture({}, { fetchImpl }),
    RecallUnavailableError,
  );
});


test("backend error envelope remains visible without leaking transport details", async () => {
  const fetchImpl = async () => ({
    ok: false,
    status: 422,
    json: async () => ({
      error: {
        code: "validation_error",
        message: "Request does not satisfy the API contract.",
      },
    }),
  });

  await assert.rejects(
    createCapture({}, { fetchImpl }),
    (error) =>
      error instanceof RecallApiError
      && error.code === "validation_error"
      && error.status === 422,
  );
});


test("manifest has only the approved permissions and fixed backend access", async () => {
  const [manifest, packageMetadata] = await Promise.all([
    readFile(`${extensionRoot}/manifest.json`, "utf8").then(JSON.parse),
    readFile(`${extensionRoot}/package.json`, "utf8").then(JSON.parse),
  ]);

  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.version, "0.4.0");
  assert.equal(packageMetadata.version, manifest.version);
  assert.deepEqual(manifest.permissions.sort(), [
    "activeTab",
    "scripting",
    "storage",
  ]);
  assert.deepEqual(manifest.host_permissions, ["http://127.0.0.1:8765/*"]);
  assert.deepEqual(manifest.optional_host_permissions, [
    "http://*/*",
    "https://*/*",
  ]);
  assert.deepEqual(manifest.background, {
    service_worker: "src/background/service-worker.js",
    type: "module",
  });
  assert.equal(manifest.action.default_popup, "src/popup/popup.html");
  assert.deepEqual(manifest.options_ui, {
    page: "src/settings/settings.html",
    open_in_tab: true,
  });
  assert.deepEqual(manifest.web_accessible_resources, [{
    resources: ["assets/icons/icon32.png"],
    matches: ["http://*/*", "https://*/*"],
    use_dynamic_url: true,
  }]);
  assert.deepEqual(manifest.icons, {
    16: "assets/icons/icon16.png",
    32: "assets/icons/icon32.png",
    48: "assets/icons/icon48.png",
    128: "assets/icons/icon128.png",
  });
  assert.deepEqual(manifest.action.default_icon, manifest.icons);
  await Promise.all(
    Object.entries(manifest.icons).map(async ([expectedSize, path]) => {
      const icon = await readFile(`${extensionRoot}/${path}`);
      assert.deepEqual(
        icon.subarray(0, 8),
        Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
      );
      assert.equal(icon.readUInt32BE(16), Number(expectedSize));
      assert.equal(icon.readUInt32BE(20), Number(expectedSize));
    }),
  );
  assert.equal(
    manifest.commands._execute_action.suggested_key.mac,
    "Command+Shift+Y",
  );
  assert.equal("content_scripts" in manifest, false);
});


test("popup preserves toolbar capture with branded, stable, scrollable controls", async () => {
  const [html, popupSource, popupStyles] = await Promise.all([
    readFile(`${extensionRoot}/src/popup/popup.html`, "utf8"),
    readFile(`${extensionRoot}/src/popup/popup.js`, "utf8"),
    readFile(`${extensionRoot}/src/popup/popup.css`, "utf8"),
  ]);

  assert.match(
    html,
    /No text selected; saving the page title, URL, and optional note only\./,
  );
  assert.match(html, /Ctrl\/⌘/);
  assert.match(html, /aria-describedby="note-count save-hint retry-warning"/);
  assert.match(html, /Retry uses the original source and note\./);
  assert.match(html, /src="\.\.\/\.\.\/assets\/icons\/icon32\.png"/);
  assert.match(html, /id="settings-button"/);
  assert.match(html, /class="source-content"[\s\S]*tabindex="0"/);
  assert.doesNotMatch(html, /Show Add to Recall when I select text/);
  assert.match(popupSource, /"Saved\."/);
  assert.match(popupSource, /"Your source and note are safely stored\."/);
  assert.match(popupSource, /sendCaptureAttempt\(attempt\)/);
  assert.match(popupSource, /chrome\.runtime\.openOptionsPage\(\)/);
  assert.doesNotMatch(popupSource, /createInlinePermissionController/);
  assert.match(popupSource, /chrome\.storage\.local\.remove/);
  assert.match(popupSource, /event\.metaKey \|\| event\.ctrlKey/);
  assert.match(popupSource, /setAttribute\("aria-invalid"/);
  assert.match(popupSource, /window\.close\(\)/);
  assert.match(popupSource, /characters?" : "characters/);
  assert.match(popupSource, /Note: \$\{characterCount\.toLocaleString\(\)\}/);
  assert.match(popupStyles, /:root \{[^}]*width: 380px;/);
  assert.match(popupStyles, /:root \{[^}]*height: 560px;/);
  assert.match(popupStyles, /body \{[^}]*width: 100%;/);
  assert.match(popupStyles, /body \{[^}]*height: 100%;/);
  assert.match(popupStyles, /\.popup-shell \{[^}]*height: 100%;/);
  assert.match(popupStyles, /\.popup-shell \{[^}]*overflow-y: auto;/);
  assert.match(popupStyles, /\.popup-shell \{[^}]*display: flex;/);
  assert.match(popupStyles, /\.selection-preview \{[^}]*overflow: auto;/);
  assert.match(popupStyles, /\.selection-preview \{[^}]*resize: vertical;/);
  assert.match(popupStyles, /\.source-content \{[^}]*overflow: auto;/);
  assert.match(popupStyles, /\.source-content \{[^}]*max-height: 82px;/);
  assert.match(popupStyles, /\.source-card h2 \{[^}]*white-space: normal;/);
  assert.match(popupStyles, /\.page-url \{[^}]*white-space: normal;/);
  assert.doesNotMatch(popupStyles, /\.source-card h2 \{[^}]*text-overflow: ellipsis;/);
  assert.doesNotMatch(popupStyles, /-webkit-line-clamp/);
  assert.match(popupStyles, /#save-button \{[^}]*height: 40px;/);
  assert.match(popupStyles, /#save-button \{[^}]*flex: 0 0 40px;/);
  assert.doesNotMatch(
    popupStyles,
    /(?:width|height|min-height|max-height):[^;]*(?:vh|dvh|svh|lvh)/,
    "an auto-sized extension popup cannot bootstrap its dimensions from its own viewport",
  );
});


test("settings owns inline access and links to Chrome shortcut management", async () => {
  const [html, settingsSource, settingsStyles, popupSource] = await Promise.all([
    readFile(`${extensionRoot}/src/settings/settings.html`, "utf8"),
    readFile(`${extensionRoot}/src/settings/settings.js`, "utf8"),
    readFile(`${extensionRoot}/src/settings/settings.css`, "utf8"),
    readFile(`${extensionRoot}/src/popup/popup.js`, "utf8"),
  ]);

  assert.match(html, /Show Add to Recall when I select text/);
  assert.match(html, /id="inline-capture-toggle"[\s\S]*disabled/);
  assert.match(html, /src="\.\.\/\.\.\/assets\/icons\/icon128\.png"/);
  assert.match(settingsSource, /createInlinePermissionController\(\)/);
  assert.match(settingsSource, /chrome\.commands\.getAll\(\)/);
  assert.match(settingsSource, /chrome:\/\/extensions\/shortcuts/);
  assert.match(settingsSource, /chrome\.tabs\.create/);
  assert.match(settingsStyles, /#c92f63/);
  assert.doesNotMatch(popupSource, /inline-capture-toggle/);
});
