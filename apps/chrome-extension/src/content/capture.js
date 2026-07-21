/**
 * Extract a contract-safe web Capture from the active page.
 *
 * Keep this function self-contained: Chrome serializes it for
 * `scripting.executeScript`, so it cannot depend on module-scope bindings.
 *
 * Browser surrounding context is intentionally disabled for now. Broad DOM
 * containers on SPA sites can mix navigation, hidden panels, and unrelated
 * conversations into one Capture. A future context extractor must be centered
 * on the selected Range and independently bounded by characters and lines.
 */
export function extractPageCapture() {
  const MAX_SELECTION_CHARS = 12_000;

  const normalize = (value) =>
    String(value ?? "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .trim();

  const truncate = (value, maximum) => {
    const characters = Array.from(normalize(value));
    return {
      text: characters.slice(0, maximum).join(""),
      characterCount: characters.length,
      truncated: characters.length > maximum,
    };
  };

  const selection = window.getSelection?.() ?? null;
  const selected = truncate(selection?.toString?.() ?? "", MAX_SELECTION_CHARS);

  return {
    sourceTitle: normalize(document.title),
    sourceUrl: normalize(window.location?.href),
    selectedText: selected.text,
    selectionCharacterCount: selected.characterCount,
    selectionTruncated: selected.truncated,
    surroundingContext: "",
    contextTruncated: false,
    hasSelection: Boolean(selected.text),
    extractionMode: selected.text ? "selection-only" : "metadata-only",
  };
}
