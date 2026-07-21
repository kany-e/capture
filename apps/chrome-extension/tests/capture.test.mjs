import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import { extractPageCapture } from "../src/content/capture.js";


function installPage({
  selectedText = "",
  title = "Example page",
  url = "https://example.com/article",
  bodyGetter,
} = {}) {
  globalThis.window = {
    location: { href: url },
    getSelection: () => ({
      toString: () => selectedText,
    }),
  };
  globalThis.document = { title };
  if (bodyGetter) {
    Object.defineProperty(globalThis.document, "body", { get: bodyGetter });
  }
}


afterEach(() => {
  delete globalThis.window;
  delete globalThis.document;
});


test("selected-text capture does not read broad page context", () => {
  installPage({
    selectedText: "selected answer",
    title: "Gemini conversation",
    bodyGetter() {
      assert.fail("page body should not be read for surrounding context");
    },
  });

  const capture = extractPageCapture();

  assert.equal(capture.selectedText, "selected answer");
  assert.equal(capture.surroundingContext, "");
  assert.equal(capture.contextTruncated, false);
  assert.equal(capture.extractionMode, "selection-only");
  assert.equal(capture.hasSelection, true);
});


test("no selection saves metadata without reading the page body", () => {
  installPage({
    selectedText: "",
    title: "OpenAI documentation",
    url: "https://example.com/docs",
    bodyGetter() {
      assert.fail("page body should not be read for surrounding context");
    },
  });

  const capture = extractPageCapture();

  assert.equal(capture.selectedText, "");
  assert.equal(capture.surroundingContext, "");
  assert.equal(capture.contextTruncated, false);
  assert.equal(capture.extractionMode, "metadata-only");
  assert.equal(capture.hasSelection, false);
  assert.equal(capture.sourceTitle, "OpenAI documentation");
  assert.equal(capture.sourceUrl, "https://example.com/docs");
});


test("selection limits count Unicode characters without splitting emoji", () => {
  installPage({ selectedText: "🧠".repeat(12_001) });

  const capture = extractPageCapture();

  assert.equal(Array.from(capture.selectedText).length, 12_000);
  assert.equal(capture.selectedText.endsWith("🧠"), true);
  assert.equal(capture.selectionCharacterCount, 12_001);
  assert.equal(capture.selectionTruncated, true);
  assert.equal(capture.surroundingContext, "");
  assert.equal(capture.contextTruncated, false);
});


test("line endings and only outer whitespace are normalized", () => {
  installPage({
    selectedText: "  selected\r\n  code  ",
    title: "  GitHub Issue  ",
    url: "  https://github.com/example/issues/1  ",
  });

  const capture = extractPageCapture();

  assert.equal(capture.selectedText, "selected\n  code");
  assert.equal(capture.sourceTitle, "GitHub Issue");
  assert.equal(capture.sourceUrl, "https://github.com/example/issues/1");
});
