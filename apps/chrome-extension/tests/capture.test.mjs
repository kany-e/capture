import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import { extractPageCapture } from "../src/content/capture.js";


function element({ innerText = "", preferred = null, nearby = null } = {}) {
  return {
    nodeType: 1,
    innerText,
    textContent: innerText,
    closest(selector) {
      return selector.includes("article") ? preferred : nearby;
    },
  };
}


function installPage({
  selectedText = "",
  anchor = null,
  pageContainer = null,
  bodyText = "Body fallback",
  title = "Example page",
  url = "https://example.com/article",
} = {}) {
  const commonAncestorContainer = anchor
    ? { nodeType: 3, parentElement: anchor }
    : null;
  globalThis.window = {
    location: { href: url },
    getSelection() {
      return {
        rangeCount: commonAncestorContainer ? 1 : 0,
        anchorNode: commonAncestorContainer,
        toString: () => selectedText,
        getRangeAt: () => ({ commonAncestorContainer }),
      };
    },
  };
  globalThis.document = {
    title,
    body: element({ innerText: bodyText }),
    querySelector: () => pageContainer,
  };
}


afterEach(() => {
  delete globalThis.window;
  delete globalThis.document;
});


test("preferred article context wins over the nearest generic element", () => {
  const article = element({ innerText: "Question and selected answer context" });
  const paragraph = element({ innerText: "Only the selected paragraph" });
  const anchor = element({ preferred: article, nearby: paragraph });
  installPage({
    selectedText: "selected answer",
    anchor,
    title: "Stack Overflow question",
    url: "https://stackoverflow.com/questions/123/example",
  });

  const capture = extractPageCapture();

  assert.equal(capture.selectedText, "selected answer");
  assert.equal(capture.surroundingContext, article.innerText);
  assert.equal(capture.extractionMode, "preferred-container");
  assert.equal(capture.hasSelection, true);
});


test("nearest paragraph, div, or section is used when no preferred container exists", () => {
  const codeContainer = element({
    innerText: "npm test\nERR_MODULE_NOT_FOUND\ncheck package exports",
  });
  const anchor = element({ nearby: codeContainer });
  installPage({ selectedText: "ERR_MODULE_NOT_FOUND", anchor });

  const capture = extractPageCapture();

  assert.equal(capture.extractionMode, "nearby-container");
  assert.match(capture.surroundingContext, /npm test/);
  assert.equal(capture.contextTruncated, false);
});


test("no selection saves a preferred page container and reports the warning state", () => {
  const main = element({ innerText: "OpenAI documentation page context" });
  installPage({ selectedText: "", pageContainer: main });

  const capture = extractPageCapture();

  assert.equal(capture.selectedText, "");
  assert.equal(capture.hasSelection, false);
  assert.equal(capture.surroundingContext, main.innerText);
  assert.equal(capture.extractionMode, "page-container");
});


test("body fallback truncates long context and marks it explicitly", () => {
  const anchor = element();
  installPage({
    selectedText: "small selection",
    anchor,
    bodyText: "x".repeat(20_050),
  });

  const capture = extractPageCapture();

  assert.equal(Array.from(capture.surroundingContext).length, 20_000);
  assert.equal(capture.contextTruncated, true);
  assert.equal(capture.extractionMode, "body");
});


test("selection limits count Unicode characters without splitting emoji", () => {
  const container = element({ innerText: "short context" });
  const anchor = element({ preferred: container });
  installPage({ selectedText: "🧠".repeat(12_001), anchor });

  const capture = extractPageCapture();

  assert.equal(Array.from(capture.selectedText).length, 12_000);
  assert.equal(capture.selectedText.endsWith("🧠"), true);
  assert.equal(capture.contextTruncated, true);
});


test("line endings and only outer whitespace are normalized", () => {
  const container = element({ innerText: "  first\r\n  indented\rline  " });
  const anchor = element({ preferred: container });
  installPage({
    selectedText: "  selected\r\n  code  ",
    anchor,
    title: "  GitHub Issue  ",
  });

  const capture = extractPageCapture();

  assert.equal(capture.selectedText, "selected\n  code");
  assert.equal(capture.surroundingContext, "first\n  indented\nline");
  assert.equal(capture.sourceTitle, "GitHub Issue");
});
