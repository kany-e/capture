(function installRecallInlineCapture(global) {
  "use strict";

  if (global.__recallInlineCaptureInstalled) {
    return;
  }
  global.__recallInlineCaptureInstalled = true;

  const core = global.RecallInlineCore;
  if (!core || !global.document || !global.chrome?.runtime) {
    return;
  }

  const CREATE_CAPTURE_MESSAGE = "recall:capture:create";
  const DISABLE_INLINE_CAPTURE_MESSAGE = "recall:inline:disable";
  const MAX_SELECTION_CHARACTERS = 12_000;
  const MAX_CONTEXT_CHARACTERS = 20_000;
  const MAX_NOTE_CHARACTERS = 4_000;
  const PILL_TIMEOUT_MS = 4_000;
  const SUCCESS_TIMEOUT_MS = 700;
  const PREFERRED_CONTEXT_SELECTOR =
    "article, [role='main'], .answer, .post-text, main";
  const NEARBY_CONTEXT_SELECTOR = "p, pre, blockquote, div, section";
  const EXCLUDED_TARGET_SELECTOR = [
    "input",
    "textarea",
    "select",
    "[contenteditable='']",
    "[contenteditable='true']",
    "[role='textbox']",
  ].join(", ");

  const machine = core.createStateMachine();
  let disabled = false;
  let pillTimer = null;
  let successTimer = null;

  const host = document.createElement("div");
  host.dataset.recallInlineRoot = "true";
  host.style.cssText = [
    "all: initial",
    "position: fixed",
    "inset: 0",
    "z-index: 2147483647",
    "pointer-events: none",
    "contain: layout style",
  ].join(";");
  const testShadowIsOpen = document.currentScript?.dataset.recallTestShadow === "open";
  const shadow = host.attachShadow({
    mode: testShadowIsOpen ? "open" : "closed",
    delegatesFocus: true,
  });

  function element(tagName, className, text) {
    const node = document.createElement(tagName);
    if (className) {
      node.className = className;
    }
    if (text !== undefined) {
      node.textContent = text;
    }
    return node;
  }

  const style = document.createElement("style");
  style.textContent = `
    :host { color-scheme: light dark; }
    * { box-sizing: border-box; }
    button, textarea { font: inherit; }
    .recall-pill {
      position: fixed;
      display: none;
      align-items: center;
      gap: 7px;
      min-height: 32px;
      border: 1px solid rgba(255,255,255,.20);
      border-radius: 999px;
      padding: 6px 11px 6px 7px;
      color: #f7fff8;
      background: #24583b;
      box-shadow: 0 8px 24px rgba(17,45,29,.24);
      cursor: pointer;
      pointer-events: auto;
      font: 700 12px/1.2 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      letter-spacing: -.01em;
    }
    .recall-pill:hover { background: #1b472f; }
    .recall-pill:focus-visible,
    .recall-button:focus-visible,
    .recall-note:focus-visible {
      outline: 3px solid rgba(90,161,113,.36);
      outline-offset: 2px;
    }
    .recall-mark {
      display: inline-grid;
      width: 20px;
      height: 20px;
      place-items: center;
      border-radius: 7px;
      color: #24583b;
      background: #f5fff6;
      font-size: 11px;
      font-weight: 800;
    }
    .recall-composer {
      position: fixed;
      display: none;
      width: min(340px, calc(100vw - 16px));
      border: 1px solid rgba(36,88,59,.18);
      border-radius: 16px;
      padding: 16px;
      color: #17211b;
      background: rgba(249,252,248,.98);
      box-shadow: 0 18px 54px rgba(20,41,28,.24);
      pointer-events: auto;
      font: 13px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .recall-header { display: flex; align-items: center; gap: 10px; }
    .recall-header .recall-mark { color: #f7fff8; background: #24583b; }
    .recall-title { margin: 0; font-size: 15px; font-weight: 760; letter-spacing: -.015em; }
    .recall-source {
      overflow: hidden;
      margin: 2px 0 0;
      color: #68756d;
      font-size: 11px;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .recall-preview {
      display: -webkit-box;
      overflow: hidden;
      margin: 12px 0;
      padding: 9px 10px;
      border: 1px solid #dce4dd;
      border-radius: 10px;
      color: #405047;
      background: #fff;
      font-size: 12px;
      line-height: 1.4;
      white-space: pre-wrap;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 2;
    }
    .recall-note-row { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
    .recall-label { color: #304b3b; font-size: 12px; font-weight: 700; }
    .recall-count { color: #718078; font-size: 10px; font-variant-numeric: tabular-nums; }
    .recall-note {
      width: 100%;
      min-height: 72px;
      margin-top: 7px;
      resize: vertical;
      border: 1px solid #cbd8ce;
      border-radius: 10px;
      outline: none;
      padding: 9px 10px;
      color: #17211b;
      background: #fff;
      line-height: 1.4;
    }
    .recall-note:focus { border-color: #4c8763; }
    .recall-privacy { margin: 8px 0 0; color: #718078; font-size: 10px; }
    .recall-status {
      display: none;
      margin-top: 10px;
      padding: 8px 9px;
      border-radius: 9px;
      color: #24583b;
      background: #e2f2e6;
      font-size: 11px;
    }
    .recall-status[data-kind="error"] { color: #7c2e29; background: #fde8e5; }
    .recall-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 12px; }
    .recall-button {
      min-height: 34px;
      border: 0;
      border-radius: 9px;
      padding: 7px 11px;
      cursor: pointer;
      color: #304b3b;
      background: #e8eee9;
      font-weight: 700;
    }
    .recall-button[data-primary="true"] { color: #fff; background: #24583b; }
    .recall-button:hover:not(:disabled) { filter: brightness(.94); }
    .recall-button:disabled, .recall-note:disabled { cursor: default; opacity: .58; }
    @media (prefers-color-scheme: dark) {
      .recall-composer { color: #edf6ef; background: rgba(28,35,30,.98); border-color: #3d5847; }
      .recall-source, .recall-count, .recall-privacy { color: #9daaa1; }
      .recall-preview, .recall-note { color: #e9f1eb; background: #222d26; border-color: #3c4c41; }
      .recall-label { color: #cbe2d1; }
      .recall-button { color: #dbe7de; background: #34433a; }
      .recall-button[data-primary="true"] { color: #fff; background: #34734f; }
    }
    @media (prefers-reduced-motion: no-preference) {
      .recall-pill, .recall-composer { animation: recall-enter 110ms ease-out; }
      @keyframes recall-enter { from { opacity: 0; transform: translateY(2px); } }
    }
  `;

  const pill = element("button", "recall-pill");
  pill.type = "button";
  pill.setAttribute("aria-label", "Add selected text to REcall");
  pill.append(element("span", "recall-mark", "R"));
  pill.append(element("span", "", "Add to REcall"));

  const composer = element("section", "recall-composer");
  composer.setAttribute("role", "dialog");
  composer.setAttribute("aria-modal", "false");
  composer.setAttribute("aria-labelledby", "recall-inline-title");

  const header = element("header", "recall-header");
  header.append(element("span", "recall-mark", "R"));
  const headingGroup = element("div");
  const heading = element("h2", "recall-title", "Add to REcall");
  heading.id = "recall-inline-title";
  const source = element("p", "recall-source");
  headingGroup.append(heading, source);
  header.append(headingGroup);

  const preview = element("p", "recall-preview");
  const noteRow = element("div", "recall-note-row");
  const noteLabel = element("label", "recall-label", "Why are you saving this?");
  noteLabel.htmlFor = "recall-inline-note";
  const noteCount = element("span", "recall-count", "0 / 4,000");
  noteRow.append(noteLabel, noteCount);
  const note = element("textarea", "recall-note");
  note.id = "recall-inline-note";
  note.rows = 3;
  note.maxLength = MAX_NOTE_CHARACTERS;
  note.placeholder = "Optional comment, situation, or caution";
  const privacy = element(
    "p",
    "recall-privacy",
    "Nothing is sent until you choose Save Memory.",
  );
  const status = element("div", "recall-status");
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const actions = element("div", "recall-actions");
  const cancelButton = element("button", "recall-button", "Cancel");
  cancelButton.type = "button";
  const saveButton = element("button", "recall-button", "Save Memory");
  saveButton.type = "button";
  saveButton.dataset.primary = "true";
  actions.append(cancelButton, saveButton);
  composer.append(header, preview, noteRow, note, privacy, status, actions);

  shadow.append(style, pill, composer);
  document.documentElement.append(host);

  function clearTimer(timer) {
    if (timer !== null) {
      global.clearTimeout(timer);
    }
  }

  function hideSurface() {
    clearTimer(pillTimer);
    clearTimer(successTimer);
    pillTimer = null;
    successTimer = null;
    pill.style.display = "none";
    composer.style.display = "none";
    status.style.display = "none";
    status.textContent = "";
    note.value = "";
  }

  function dismiss() {
    if (machine.dismiss()) {
      hideSurface();
    }
  }

  function textFrom(node) {
    return core.normalizeText(node?.innerText ?? node?.textContent ?? "");
  }

  function selectionAnchorElement(selection) {
    const node = selection?.anchorNode;
    if (!node) {
      return null;
    }
    return node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
  }

  function isEligibleTarget(elementNode) {
    if (!elementNode || host.contains(elementNode)) {
      return false;
    }
    if (elementNode.isContentEditable) {
      return false;
    }
    return !elementNode.closest?.(EXCLUDED_TARGET_SELECTOR);
  }

  function finalSelectionRect(range) {
    const rectangles = Array.from(range.getClientRects?.() ?? [])
      .filter((rect) => rect.width > 0 || rect.height > 0);
    return rectangles.at(-1) ?? range.getBoundingClientRect?.() ?? null;
  }

  function captureSelection() {
    const selection = global.getSelection?.();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return null;
    }

    const anchor = selectionAnchorElement(selection);
    if (!isEligibleTarget(anchor)) {
      return null;
    }

    const range = selection.getRangeAt(0);
    const rect = finalSelectionRect(range);
    if (!rect) {
      return null;
    }

    const selected = core.truncateUnicode(
      selection.toString(),
      MAX_SELECTION_CHARACTERS,
    );
    if (!selected.text) {
      return null;
    }

    const preferred = anchor.closest?.(PREFERRED_CONTEXT_SELECTOR);
    const nearby = anchor.closest?.(NEARBY_CONTEXT_SELECTOR);
    const contextNode = preferred || nearby || document.body;
    const context = core.truncateUnicode(
      textFrom(contextNode),
      MAX_CONTEXT_CHARACTERS,
    );

    return {
      selectedText: selected.text,
      anchorRect: {
        top: rect.top,
        right: rect.right,
        bottom: rect.bottom,
        left: rect.left,
      },
      extractedCapture: {
        sourceTitle: core.normalizeText(document.title),
        sourceUrl: core.normalizeText(global.location?.href),
        selectedText: selected.text,
        surroundingContext: context.text,
        contextTruncated: selected.truncated || context.truncated,
        hasSelection: true,
        extractionMode: preferred
          ? "preferred-container"
          : nearby
            ? "nearby-container"
            : "body",
      },
    };
  }

  function positionSurface(surface, anchorRect) {
    surface.style.visibility = "hidden";
    surface.style.display = surface === pill ? "inline-flex" : "block";
    global.requestAnimationFrame(() => {
      const bounds = surface.getBoundingClientRect();
      const position = surface === composer
        ? core.placeAdjacentOverlay(
            anchorRect,
            { width: bounds.width, height: bounds.height },
            { width: global.innerWidth, height: global.innerHeight },
          )
        : core.placeOverlay(
            anchorRect,
            { width: bounds.width, height: bounds.height },
            { width: global.innerWidth, height: global.innerHeight },
          );
      surface.style.left = `${position.left}px`;
      surface.style.top = `${position.top}px`;
      surface.dataset.placement = position.placement;
      surface.style.visibility = "visible";
    });
  }

  function armPillTimeout() {
    clearTimer(pillTimer);
    pillTimer = global.setTimeout(dismiss, PILL_TIMEOUT_MS);
  }

  function showSelectionAction() {
    if (disabled) {
      return;
    }
    if ([core.STATES.composer, core.STATES.submitting, core.STATES.error]
      .includes(machine.state)) {
      return;
    }
    const snapshot = captureSelection();
    if (!snapshot || !machine.showPill(snapshot)) {
      dismiss();
      return;
    }
    composer.style.display = "none";
    positionSurface(pill, snapshot.anchorRect);
    armPillTimeout();
  }

  function updateControls() {
    const count = Array.from(note.value).length;
    const submitting = machine.state === core.STATES.submitting;
    const locked = Boolean(machine.attempt);
    noteCount.textContent = `${count.toLocaleString()} / ${MAX_NOTE_CHARACTERS.toLocaleString()}`;
    note.disabled = submitting || locked;
    cancelButton.disabled = submitting;
    saveButton.disabled = submitting || count > MAX_NOTE_CHARACTERS;
    if (machine.state === core.STATES.error) {
      saveButton.textContent = machine.error?.retryable ? "Try again" : "Cannot retry";
      saveButton.disabled ||= machine.error?.retryable === false;
    } else {
      saveButton.textContent = submitting ? "Saving..." : "Save Memory";
    }
  }

  function openComposer() {
    if (!machine.openComposer()) {
      return;
    }
    clearTimer(pillTimer);
    pill.style.display = "none";
    const snapshot = machine.snapshot;
    preview.textContent = snapshot.selectedText;
    source.textContent = document.title || global.location?.hostname || "Current page";
    note.value = "";
    status.style.display = "none";
    status.textContent = "";
    updateControls();
    positionSurface(composer, snapshot.anchorRect);
    global.setTimeout(() => note.focus(), 0);
  }

  function attemptFor(snapshot) {
    return {
      clientCaptureId: crypto.randomUUID(),
      capturedAt: new Date().toISOString(),
      extractedCapture: snapshot.extractedCapture,
      userNote: note.value,
    };
  }

  async function submit() {
    const attempt = machine.beginSubmit(attemptFor);
    if (!attempt) {
      return;
    }
    status.style.display = "none";
    status.textContent = "";
    updateControls();

    try {
      const response = await chrome.runtime.sendMessage({
        type: CREATE_CAPTURE_MESSAGE,
        attempt,
      });
      if (response?.ok !== true) {
        throw response?.error || {
          code: "invalid_extension_response",
          title: "Couldn’t save this Capture.",
          detail: "Try again in a moment.",
          retryable: true,
        };
      }

      machine.succeed();
      status.dataset.kind = "success";
      status.textContent = "Saved to REcall ✓";
      status.style.display = "block";
      note.disabled = true;
      cancelButton.disabled = true;
      saveButton.disabled = true;
      saveButton.textContent = "Saved";
      successTimer = global.setTimeout(dismiss, SUCCESS_TIMEOUT_MS);
    } catch (caught) {
      const error = caught && typeof caught === "object"
        ? caught
        : {
            code: "extension_unavailable",
            title: "Couldn’t save this Capture.",
            detail: "REcall’s extension service is unavailable. Reload the extension and try again.",
            retryable: true,
          };
      machine.fail(error);
      status.dataset.kind = "error";
      status.textContent = `${error.title || "Couldn’t save this Capture."} ${error.detail || "Try again."}`;
      status.style.display = "block";
      updateControls();
    }
  }

  function eventIsInsideRecall(event) {
    return event.composedPath?.().includes(host) ?? false;
  }

  function disableInlineCapture() {
    disabled = true;
    if (machine.state !== core.STATES.submitting) {
      machine.dismiss();
    }
    hideSurface();
    host.remove();
    global.__recallInlineCaptureInstalled = false;
  }

  chrome.runtime.onMessage?.addListener?.((message) => {
    if (message?.type === DISABLE_INLINE_CAPTURE_MESSAGE) {
      disableInlineCapture();
    }
  });

  pill.addEventListener("mouseenter", () => clearTimer(pillTimer));
  pill.addEventListener("mouseleave", armPillTimeout);
  pill.addEventListener("click", openComposer);
  note.addEventListener("input", updateControls);
  cancelButton.addEventListener("click", dismiss);
  saveButton.addEventListener("click", () => void submit());
  note.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      void submit();
    }
  });

  document.addEventListener("pointerdown", (event) => {
    if (disabled) {
      return;
    }
    if (!eventIsInsideRecall(event) && machine.state !== core.STATES.idle) {
      dismiss();
    }
  }, true);

  document.addEventListener("pointerup", (event) => {
    if (disabled) {
      return;
    }
    if (eventIsInsideRecall(event)) {
      return;
    }
    global.setTimeout(showSelectionAction, 0);
  }, true);

  document.addEventListener("keyup", (event) => {
    if (disabled) {
      return;
    }
    if (event.key !== "Escape" && !eventIsInsideRecall(event)) {
      global.setTimeout(showSelectionAction, 0);
    }
  }, true);

  document.addEventListener("selectionchange", () => {
    if (disabled) {
      return;
    }
    if (machine.state !== core.STATES.pill) {
      return;
    }
    const current = core.truncateUnicode(
      global.getSelection?.()?.toString(),
      MAX_SELECTION_CHARACTERS,
    ).text;
    if (!current || current !== machine.snapshot?.selectedText) {
      dismiss();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (disabled) {
      return;
    }
    if (event.key === "Escape" && machine.state !== core.STATES.idle) {
      event.preventDefault();
      dismiss();
    }
  }, true);

  global.addEventListener("scroll", () => {
    if (disabled) {
      return;
    }
    if (machine.state === core.STATES.pill) {
      dismiss();
    }
  }, true);
  global.addEventListener("blur", dismiss);
})(globalThis);
