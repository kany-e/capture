import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import {
  RECALL_BASE_URL,
  RecallApiError,
  RecallUnavailableError,
  buildCaptureRequest,
  createCapture,
} from "../src/api/recall.js";


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
  const manifest = JSON.parse(
    await readFile(`${extensionRoot}/manifest.json`, "utf8"),
  );

  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions.sort(), [
    "activeTab",
    "scripting",
    "storage",
  ]);
  assert.deepEqual(manifest.host_permissions, ["http://127.0.0.1:8765/*"]);
  assert.equal(manifest.action.default_popup, "src/popup/popup.html");
  assert.equal("content_scripts" in manifest, false);
});


test("popup includes no-selection, saved, processing, and offline states", async () => {
  const [html, popupSource] = await Promise.all([
    readFile(`${extensionRoot}/src/popup/popup.html`, "utf8"),
    readFile(`${extensionRoot}/src/popup/popup.js`, "utf8"),
  ]);

  assert.match(html, /No text selected; saving page context\./);
  assert.match(popupSource, /"Saved\."/);
  assert.match(popupSource, /"Processing with AI…"/);
  assert.match(popupSource, /RECALL_UNAVAILABLE_TITLE/);
  assert.match(popupSource, /chrome\.storage\.local\.remove/);
});
