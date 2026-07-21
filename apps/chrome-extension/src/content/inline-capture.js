(function installRecallInlineCapture(global) {
  "use strict";

  if (global.__recallInlineCaptureController?.enabled) {
    return;
  }

  const core = global.RecallInlineCore;
  if (
    !core
    || !global.document
    || !global.chrome?.runtime
    || !/^https?:$/i.test(global.location?.protocol || "")
  ) {
    return;
  }

  const CREATE_CAPTURE_MESSAGE = "recall:capture:create";
  const INLINE_CAPTURE_STATUS_MESSAGE = "recall:inline:status";
  const DISABLE_INLINE_CAPTURE_MESSAGE = "recall:inline:disable";
  const MAX_SELECTION_CHARACTERS = 12_000;
  const MAX_NOTE_CHARACTERS = 4_000;
  const PILL_TIMEOUT_MS = 4_000;
  const SUCCESS_TIMEOUT_MS = 700;
  const EXCLUDED_TARGET_SELECTOR = [
    "input",
    "textarea",
    "select",
    "[contenteditable='']",
    "[contenteditable='true']",
    "[role='textbox']",
  ].join(", ");

  const machine = core.createStateMachine();
  const selectionGate = core.createLatestTaskGate();
  const suspensionGate = core.createSuspensionGate();
  const listeners = core.createListenerRegistry();
  let disabled = false;
  let pageCacheToken = null;
  let pillTimer = null;
  let successTimer = null;
  let positionGeneration = 0;
  let previousFocus = null;

  function inlineCaptureInactive() {
    return disabled || suspensionGate.suspended;
  }

  const host = document.createElement("div");
  host.dataset.recallInlineRoot = "true";
  host.style.cssText = [
    "all: initial !important",
    "position: fixed !important",
    "inset: 0 !important",
    "z-index: 2147483647 !important",
    "display: block !important",
    "pointer-events: none !important",
    "contain: layout style !important",
  ].join(";");
  const shadow = host.attachShadow({
    mode: global.__RECALL_INLINE_TEST__ === true ? "open" : "closed",
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
      border: 1px solid rgba(255,255,255,.22);
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
    .recall-pill:focus { animation: none; }
    .recall-pill:focus-visible,
    .recall-button:focus-visible,
    .recall-note:focus-visible {
      outline: 3px solid rgba(90,161,113,.42);
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
      overflow: auto;
      width: min(340px, calc(100vw - 16px));
      max-height: calc(100vh - 16px);
      border: 1px solid rgba(36,88,59,.18);
      border-radius: 16px;
      padding: 16px;
      color: #17211b;
      background: rgba(249,252,248,.98);
      box-shadow: 0 18px 54px rgba(20,41,28,.24);
      pointer-events: auto;
      overscroll-behavior: contain;
      scrollbar-gutter: stable;
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
    .recall-selection-row,
    .recall-note-row {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 8px;
    }
    .recall-selection-row { margin-top: 12px; }
    .recall-preview {
      overflow: auto;
      min-height: 48px;
      max-height: 128px;
      margin: 6px 0 12px;
      padding: 9px 10px;
      border: 1px solid #dce4dd;
      border-radius: 10px;
      color: #405047;
      background: #fff;
      font-size: 12px;
      line-height: 1.4;
      overflow-wrap: anywhere;
      overscroll-behavior: contain;
      scrollbar-gutter: stable;
      white-space: pre-wrap;
    }
    .recall-preview:focus-visible {
      outline: 3px solid rgba(90,161,113,.42);
      outline-offset: 2px;
    }
    .recall-label { color: #304b3b; font-size: 12px; font-weight: 700; }
    .recall-count {
      min-width: 0;
      color: #718078;
      font-size: 10px;
      font-variant-numeric: tabular-nums;
      overflow-wrap: anywhere;
      text-align: right;
    }
    .recall-count[data-invalid="true"] { color: #a13d35; font-weight: 700; }
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
    .recall-note[aria-invalid="true"] { border-color: #bd5148; }
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
  pill.setAttribute("aria-label", "Add selected text to Recall");
  pill.append(element("span", "recall-mark", "R"));
  pill.append(element("span", "", "Add to Recall"));

  const composer = element("section", "recall-composer");
  composer.setAttribute("role", "dialog");
  composer.setAttribute("aria-modal", "false");
  composer.setAttribute("aria-labelledby", "recall-inline-title");

  const header = element("header", "recall-header");
  header.append(element("span", "recall-mark", "R"));
  const headingGroup = element("div");
  const heading = element("h2", "recall-title", "Add to Recall");
  heading.id = "recall-inline-title";
  const source = element("p", "recall-source");
  headingGroup.append(heading, source);
  header.append(headingGroup);

  const selectionRow = element("div", "recall-selection-row");
  const selectionLabel = element("span", "recall-label", "Selected text");
  selectionLabel.id = "recall-inline-selection-label";
  const selectionCount = element(
    "span",
    "recall-count",
    "0 characters selected",
  );
  selectionCount.id = "recall-inline-selection-count";
  selectionRow.append(selectionLabel, selectionCount);
  const preview = element("p", "recall-preview");
  preview.tabIndex = 0;
  preview.setAttribute("role", "region");
  preview.setAttribute("aria-labelledby", selectionLabel.id);
  preview.setAttribute("aria-describedby", selectionCount.id);
  const noteRow = element("div", "recall-note-row");
  const noteLabel = element("label", "recall-label", "Why are you saving this?");
  noteLabel.htmlFor = "recall-inline-note";
  const noteCount = element(
    "span",
    "recall-count",
    "Note: 0 / 4,000 characters",
  );
  noteCount.id = "recall-inline-note-count";
  noteRow.append(noteLabel, noteCount);
  const note = element("textarea", "recall-note");
  note.id = "recall-inline-note";
  note.rows = 3;
  note.placeholder = "Optional note, situation, or caution";
  note.setAttribute("aria-describedby", "recall-inline-note-count recall-inline-privacy recall-inline-status");
  const privacy = element(
    "p",
    "recall-privacy",
    "Nothing is sent until Save. Recall then sends this selection, page title and URL, and your note to its local service; configured AI enrichment follows Recall settings.",
  );
  privacy.id = "recall-inline-privacy";
  const status = element("div", "recall-status");
  status.id = "recall-inline-status";
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const actions = element("div", "recall-actions");
  const cancelButton = element("button", "recall-button", "Cancel");
  cancelButton.type = "button";
  const saveButton = element("button", "recall-button", "Save");
  saveButton.type = "button";
  saveButton.dataset.primary = "true";
  actions.append(cancelButton, saveButton);
  composer.append(
    header,
    selectionRow,
    preview,
    noteRow,
    note,
    privacy,
    status,
    actions,
  );

  shadow.append(style, pill, composer);
  document.documentElement.append(host);

  function clearTimer(timer) {
    if (timer !== null) {
      global.clearTimeout(timer);
    }
  }

  function hideSurface({ restoreFocus = false } = {}) {
    clearTimer(pillTimer);
    clearTimer(successTimer);
    pillTimer = null;
    successTimer = null;
    positionGeneration += 1;
    pill.style.display = "none";
    pill.style.visibility = "hidden";
    composer.style.display = "none";
    composer.style.visibility = "hidden";
    status.style.display = "none";
    status.textContent = "";
    preview.textContent = "";
    selectionCount.textContent = "0 characters selected";
    source.textContent = "";
    note.value = "";
    note.removeAttribute("aria-invalid");
    if (restoreFocus && previousFocus?.isConnected && previousFocus.focus) {
      previousFocus.focus({ preventScroll: true });
    }
    previousFocus = null;
  }

  function dismiss({ restoreFocus = false } = {}) {
    selectionGate.next();
    if (machine.dismiss()) {
      hideSurface({ restoreFocus });
      return true;
    }
    return false;
  }

  function elementForNode(node) {
    if (!node) {
      return null;
    }
    return node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
  }

  function isEligibleTarget(elementNode) {
    if (!elementNode || host.contains(elementNode) || elementNode.isContentEditable) {
      return false;
    }
    return !elementNode.closest?.(EXCLUDED_TARGET_SELECTOR);
  }

  function focusEndpointRect(selection) {
    if (!selection?.focusNode || !document.createRange) {
      return null;
    }
    try {
      const focusRange = document.createRange();
      focusRange.setStart(selection.focusNode, selection.focusOffset);
      focusRange.collapse(true);
      const rect = focusRange.getBoundingClientRect?.();
      return rect && rect.height > 0 ? rect : null;
    } catch (_error) {
      return null;
    }
  }

  function finalSelectionRect(range) {
    const rectangles = Array.from(range.getClientRects?.() ?? [])
      .filter((rect) => rect.width > 0 || rect.height > 0);
    return rectangles.at(-1) ?? range.getBoundingClientRect?.() ?? null;
  }

  function captureSelection(originTarget) {
    const selection = global.getSelection?.();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return null;
    }

    const range = selection.getRangeAt(0);
    const contextAnchor = elementForNode(range.commonAncestorContainer)
      || elementForNode(selection.anchorNode);
    const anchorElement = elementForNode(selection.anchorNode);
    const focusElement = elementForNode(selection.focusNode);
    if (
      !isEligibleTarget(elementForNode(originTarget))
      || !isEligibleTarget(contextAnchor)
      || !isEligibleTarget(anchorElement)
      || !isEligibleTarget(focusElement)
    ) {
      return null;
    }

    const rect = focusEndpointRect(selection) || finalSelectionRect(range);
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

    return {
      selectedText: selected.text,
      selectionCharacterCount: selected.characterCount,
      selectionTruncated: selected.truncated,
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
        surroundingContext: "",
        contextTruncated: false,
      },
    };
  }

  function positionSurface(surface, anchorRect, expectedState) {
    positionGeneration += 1;
    const generation = positionGeneration;
    surface.style.visibility = "hidden";
    surface.style.display = surface === pill ? "inline-flex" : "block";
    global.requestAnimationFrame(() => {
      if (
        inlineCaptureInactive()
        || generation !== positionGeneration
        || machine.state !== expectedState
        || !host.isConnected
      ) {
        return;
      }
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
    pillTimer = machine.state === core.STATES.pill
      ? global.setTimeout(() => dismiss(), PILL_TIMEOUT_MS)
      : null;
  }

  function showSelectionAction(generation, originTarget) {
    if (inlineCaptureInactive() || !selectionGate.isCurrent(generation)) {
      return;
    }
    if ([
      core.STATES.composer,
      core.STATES.submitting,
      core.STATES.success,
      core.STATES.error,
    ].includes(machine.state)) {
      return;
    }
    const snapshot = captureSelection(originTarget);
    if (!snapshot) {
      if (machine.state === core.STATES.pill) {
        dismiss();
      }
      return;
    }
    if (!machine.showPill(snapshot)) {
      return;
    }
    previousFocus = document.activeElement === host ? null : document.activeElement;
    composer.style.display = "none";
    positionSurface(pill, snapshot.anchorRect, core.STATES.pill);
    armPillTimeout();
  }

  function scheduleSelectionAction(originTarget) {
    if (inlineCaptureInactive()) {
      return;
    }
    const generation = selectionGate.next();
    global.setTimeout(() => showSelectionAction(generation, originTarget), 0);
  }

  function showStatus(kind, message) {
    status.dataset.kind = kind;
    status.textContent = message;
    status.style.display = "block";
  }

  function updateControls() {
    const count = core.unicodeLength(note.value);
    const invalid = count > MAX_NOTE_CHARACTERS;
    const submitting = machine.state === core.STATES.submitting;
    const succeeded = machine.state === core.STATES.success;
    const locked = Boolean(machine.attempt);
    noteCount.textContent = `Note: ${count.toLocaleString()} / ${MAX_NOTE_CHARACTERS.toLocaleString()} characters`;
    noteCount.dataset.invalid = String(invalid);
    note.setAttribute("aria-invalid", String(invalid));
    note.disabled = submitting || succeeded || locked;
    cancelButton.disabled = submitting || succeeded;
    saveButton.disabled = submitting || succeeded || invalid;
    if (machine.state === core.STATES.error) {
      const retryable = machine.error?.retryable !== false;
      saveButton.textContent = retryable ? "Try again" : "Cannot retry";
      if (!retryable) {
        saveButton.disabled = true;
      }
    } else if (succeeded) {
      saveButton.textContent = "Saved";
    } else {
      saveButton.textContent = submitting ? "Saving…" : "Save";
    }
  }

  function openComposer() {
    if (inlineCaptureInactive() || !machine.openComposer()) {
      return;
    }
    clearTimer(pillTimer);
    pillTimer = null;
    pill.style.display = "none";
    const snapshot = machine.snapshot;
    preview.textContent = snapshot.selectedText;
    const savedCharacterCount = core.unicodeLength(snapshot.selectedText);
    const selectedCharacterCount = snapshot.selectionCharacterCount
      ?? savedCharacterCount;
    selectionCount.textContent = snapshot.selectionTruncated
      ? `${selectedCharacterCount.toLocaleString()} characters selected · first ${savedCharacterCount.toLocaleString()} will be saved`
      : `${selectedCharacterCount.toLocaleString()} ${selectedCharacterCount === 1 ? "character" : "characters"} selected`;
    source.textContent = snapshot.extractedCapture.sourceTitle
      || global.location?.hostname
      || "Current page";
    note.value = "";
    status.style.display = "none";
    status.textContent = "";
    updateControls();
    positionSurface(composer, snapshot.anchorRect, core.STATES.composer);
    global.setTimeout(() => {
      if (!inlineCaptureInactive() && machine.state === core.STATES.composer) {
        note.focus({ preventScroll: true });
      }
    }, 0);
  }

  function attemptFor(snapshot) {
    return {
      clientCaptureId: core.createUUID(global.crypto),
      capturedAt: new Date().toISOString(),
      extractedCapture: snapshot.extractedCapture,
      userNote: note.value,
    };
  }

  async function submit() {
    if (inlineCaptureInactive()) {
      return;
    }
    let attempt;
    try {
      attempt = machine.beginSubmit(attemptFor);
    } catch (_error) {
      showStatus(
        "error",
        "Recall could not create a secure Capture request. Reload the page and try again.",
      );
      return;
    }
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
      if (
        inlineCaptureInactive()
        || machine.state !== core.STATES.submitting
        || machine.attempt !== attempt
      ) {
        return;
      }
      if (response?.ok !== true) {
        throw response?.error || {
          code: "invalid_extension_response",
          title: "Couldn’t save this Capture.",
          detail: "Try again with the same Capture.",
          retryable: true,
        };
      }

      machine.succeed();
      showStatus("success", "Saved to Recall ✓");
      updateControls();
      successTimer = global.setTimeout(() => dismiss(), SUCCESS_TIMEOUT_MS);
    } catch (caught) {
      if (
        inlineCaptureInactive()
        || machine.state !== core.STATES.submitting
        || machine.attempt !== attempt
      ) {
        return;
      }
      const error = caught && typeof caught === "object"
        ? caught
        : {
            code: "extension_unavailable",
            title: "Couldn’t save this Capture.",
            detail: "Recall’s extension service is unavailable. Reload the extension and try again.",
            retryable: true,
          };
      machine.fail(error);
      showStatus(
        "error",
        `${error.title || "Couldn’t save this Capture."} ${error.detail || "Try again."}`,
      );
      updateControls();
      const expectedError = machine.error;
      global.setTimeout(() => {
        if (
          !inlineCaptureInactive()
          && machine.state === core.STATES.error
          && machine.error === expectedError
        ) {
          core.focusErrorAction(expectedError, saveButton, cancelButton);
        }
      }, 0);
    }
  }

  function eventIsInsideRecall(event) {
    return event.composedPath?.().includes(host) ?? false;
  }

  function suspendInlineCapture() {
    if (disabled) {
      return;
    }
    pageCacheToken = suspensionGate.suspend();
    selectionGate.next();
    machine.reset();
    hideSurface();
  }

  async function resumeInlineCaptureFromPageCache(event) {
    if (
      disabled
      || event?.persisted !== true
      || !suspensionGate.suspended
      || pageCacheToken === null
    ) {
      return;
    }

    const expectedToken = pageCacheToken;
    let response;
    try {
      response = await chrome.runtime.sendMessage({
        type: INLINE_CAPTURE_STATUS_MESSAGE,
      });
    } catch (_error) {
      if (!disabled && expectedToken === pageCacheToken) {
        disableInlineCapture();
      }
      return;
    }

    if (disabled || expectedToken !== pageCacheToken) {
      return;
    }
    if (
      response?.ok === true
      && response.enabled === true
      && suspensionGate.resume(expectedToken, true)
    ) {
      pageCacheToken = null;
      return;
    }
    disableInlineCapture();
  }

  function disableInlineCapture() {
    if (disabled) {
      return;
    }
    disabled = true;
    suspensionGate.invalidate();
    pageCacheToken = null;
    selectionGate.next();
    machine.reset();
    hideSurface();
    listeners.clear();
    chrome.runtime.onMessage?.removeListener?.(runtimeMessageListener);
    host.remove();
    if (global.__recallInlineCaptureController === controller) {
      global.__recallInlineCaptureController = null;
    }
  }

  function runtimeMessageListener(message) {
    if (message?.type === DISABLE_INLINE_CAPTURE_MESSAGE) {
      disableInlineCapture();
    }
  }

  const controller = Object.freeze({
    get enabled() {
      return !disabled;
    },
    get suspended() {
      return !disabled && suspensionGate.suspended;
    },
    disable: disableInlineCapture,
  });
  global.__recallInlineCaptureController = controller;
  chrome.runtime.onMessage.addListener(runtimeMessageListener);

  listeners.listen(pill, "mouseenter", () => clearTimer(pillTimer));
  listeners.listen(pill, "mouseleave", armPillTimeout);
  listeners.listen(pill, "focus", () => clearTimer(pillTimer));
  listeners.listen(pill, "blur", armPillTimeout);
  listeners.listen(pill, "click", openComposer);
  listeners.listen(note, "input", updateControls);
  listeners.listen(cancelButton, "click", () => dismiss({ restoreFocus: true }));
  listeners.listen(saveButton, "click", () => void submit());
  listeners.listen(note, "keydown", (event) => {
    if (
      !inlineCaptureInactive()
      && event.key === "Enter"
      && (event.metaKey || event.ctrlKey)
    ) {
      event.preventDefault();
      void submit();
    }
  });

  listeners.listen(document, "pointerdown", (event) => {
    if (
      inlineCaptureInactive()
      || eventIsInsideRecall(event)
      || !core.shouldDismissForOutsidePointer(machine.state)
    ) {
      return;
    }
    dismiss();
  }, true);

  listeners.listen(document, "pointerup", (event) => {
    if (inlineCaptureInactive() || eventIsInsideRecall(event)) {
      return;
    }
    scheduleSelectionAction(event.target);
  }, true);

  listeners.listen(document, "keyup", (event) => {
    if (
      inlineCaptureInactive()
      || eventIsInsideRecall(event)
      || !core.shouldObserveKeyboardSelection(event)
    ) {
      return;
    }
    scheduleSelectionAction(document.activeElement);
  }, true);

  listeners.listen(document, "selectionchange", () => {
    if (inlineCaptureInactive() || machine.state !== core.STATES.pill) {
      return;
    }
    const current = core.truncateUnicode(
      global.getSelection?.()?.toString(),
      MAX_SELECTION_CHARACTERS,
    );
    if (
      !current.text
      || current.text !== machine.snapshot?.selectedText
      || current.characterCount !== machine.snapshot?.selectionCharacterCount
    ) {
      dismiss();
    }
  });

  listeners.listen(document, "keydown", (event) => {
    if (inlineCaptureInactive()) {
      return;
    }
    core.dismissOnEscape(event, machine.state, dismiss);
  }, true);

  listeners.listen(global, "scroll", () => {
    if (!inlineCaptureInactive() && machine.state === core.STATES.pill) {
      dismiss();
    }
  }, true);
  listeners.listen(global, "blur", () => {
    if (!inlineCaptureInactive() && machine.state === core.STATES.pill) {
      dismiss();
    }
  });
  listeners.listen(document, "visibilitychange", () => {
    if (
      !inlineCaptureInactive()
      && document.hidden
      && machine.state === core.STATES.pill
    ) {
      dismiss();
    }
  });
  listeners.listen(global, "pagehide", suspendInlineCapture);
  listeners.listen(global, "pageshow", (event) => {
    void resumeInlineCaptureFromPageCache(event);
  });
})(globalThis);
