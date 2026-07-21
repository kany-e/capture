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
import {
  buildCaptureAttempt,
} from "../src/api/messages.js";
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


test("capture attempt preserves one client identity and timestamp", () => {
  const attempt = buildCaptureAttempt(extracted(), "remember this", {
    createId: () => "149f51e1-8c18-42d4-9778-3f3b062527a2",
    now: () => new Date("2026-07-20T20:00:00.000Z"),
  });

  assert.equal(attempt.clientCaptureId, "149f51e1-8c18-42d4-9778-3f3b062527a2");
  assert.equal(attempt.capturedAt, "2026-07-20T20:00:00.000Z");
  assert.equal(attempt.extractedCapture.selectedText, "Set WorkingDirectory before restart.");
  assert.equal(attempt.userNote, "remember this");
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
  assert.equal(manifest.version, packageMetadata.version);
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
  assert.equal(
    manifest.commands._execute_action.suggested_key.mac,
    "Command+Shift+Y",
  );
  assert.equal("content_scripts" in manifest, false);
});


test("popup preserves toolbar capture and exposes the opt-in inline setting", async () => {
  const [html, popupSource] = await Promise.all([
    readFile(`${extensionRoot}/src/popup/popup.html`, "utf8"),
    readFile(`${extensionRoot}/src/popup/popup.js`, "utf8"),
  ]);

  assert.match(html, /No text selected; saving page context\./);
  assert.match(html, /⌘/);
  assert.match(html, /Retry uses the original source and note\./);
  assert.match(html, /Show Add to REcall when I select text/);
  assert.match(html, /nothing is sent until you save/);
  assert.match(popupSource, /"Saved\."/);
  assert.match(popupSource, /"Your source and note are safely stored\."/);
  assert.match(popupSource, /sendCaptureAttempt/);
  assert.match(popupSource, /chrome\.permissions\.request/);
  assert.match(popupSource, /SYNC_INLINE_CAPTURE_MESSAGE/);
  assert.match(popupSource, /chrome\.storage\.local\.remove/);
  assert.match(popupSource, /event\.metaKey \|\| event\.ctrlKey/);
  assert.match(popupSource, /window\.close\(\)/);
});
