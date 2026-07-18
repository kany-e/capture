/**
 * Extract a contract-safe web Capture from the active page.
 *
 * Keep this function self-contained: Chrome serializes it for
 * `scripting.executeScript`, so it cannot depend on module-scope bindings.
 */
export function extractPageCapture() {
  const MAX_SELECTION_CHARS = 12_000;
  const MAX_CONTEXT_CHARS = 20_000;
  const preferredSelector =
    "article, [role='main'], .answer, .post-text, main";
  const nearbySelector = "p, div, section";

  const normalize = (value) =>
    String(value ?? "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .trim();

  const truncate = (value, maximum) => {
    const characters = Array.from(normalize(value));
    return {
      text: characters.slice(0, maximum).join(""),
      truncated: characters.length > maximum,
    };
  };

  const textFrom = (element) =>
    normalize(element?.innerText ?? element?.textContent ?? "");

  const selection = window.getSelection?.() ?? null;
  const selected = truncate(selection?.toString?.() ?? "", MAX_SELECTION_CHARS);
  let anchor = null;

  if (selection && selection.rangeCount > 0) {
    const commonAncestor = selection.getRangeAt(0).commonAncestorContainer;
    anchor =
      commonAncestor?.nodeType === 3
        ? commonAncestor.parentElement
        : commonAncestor;
  } else if (selection?.anchorNode) {
    anchor =
      selection.anchorNode.nodeType === 3
        ? selection.anchorNode.parentElement
        : selection.anchorNode;
  }

  let container = null;
  let extractionMode = "body";
  if (selected.text) {
    container = anchor?.closest?.(preferredSelector) ?? null;
    if (container) {
      extractionMode = "preferred-container";
    } else {
      container = anchor?.closest?.(nearbySelector) ?? null;
      if (container) {
        extractionMode = "nearby-container";
      }
    }
  } else {
    container = document.querySelector?.(preferredSelector) ?? null;
    if (container) {
      extractionMode = "page-container";
    }
  }

  let contextSource = textFrom(container);
  if (!contextSource) {
    contextSource = textFrom(document.body);
    extractionMode = "body";
  }
  const context = truncate(contextSource, MAX_CONTEXT_CHARS);

  return {
    sourceTitle: normalize(document.title),
    sourceUrl: normalize(window.location?.href),
    selectedText: selected.text,
    surroundingContext: context.text,
    contextTruncated: selected.truncated || context.truncated,
    hasSelection: Boolean(selected.text),
    extractionMode,
  };
}
