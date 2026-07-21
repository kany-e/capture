import {
  CAPTURE_LIMITS,
} from "../api/recall.js";
import {
  RecallCoordinatorError,
  SYNC_INLINE_CAPTURE_MESSAGE,
  buildCaptureAttempt,
  sendCaptureAttempt,
} from "../api/messages.js";
import { INLINE_CAPTURE_ORIGINS } from "../background/inline-registration.js";
import { extractPageCapture } from "../content/capture.js";
import { createCaptureAttempt } from "./capture-attempt.js";


const pageTitle = document.querySelector("#page-title");
const pageUrl = document.querySelector("#page-url");
const preview = document.querySelector("#selection-preview");
const previewCount = document.querySelector("#preview-count");
const warning = document.querySelector("#selection-warning");
const noteInput = document.querySelector("#user-note");
const noteCount = document.querySelector("#note-count");
const retryWarning = document.querySelector("#retry-warning");
const saveButton = document.querySelector("#save-button");
const statusBox = document.querySelector("#status");
const statusTitle = document.querySelector("#status-title");
const statusDetail = document.querySelector("#status-detail");
const inlineSetting = document.querySelector(".inline-setting");
const inlineToggle = document.querySelector("#inline-capture-toggle");
const inlinePermissionStatus = document.querySelector("#inline-permission-status");

let activeTab = null;
let extractedCapture = null;
let draftKey = null;
let isSubmitting = false;

const captureAttempt = createCaptureAttempt(buildCaptureAttempt);
const SUCCESS_CLOSE_DELAY_MS = 700;


function showStatus(kind, title, detail) {
  statusBox.hidden = false;
  statusBox.dataset.kind = kind;
  statusTitle.textContent = title;
  statusDetail.textContent = detail;
}


function hideStatus() {
  statusBox.hidden = true;
  statusBox.dataset.kind = "";
  statusTitle.textContent = "";
  statusDetail.textContent = "";
}


function previewText(capture) {
  if (capture.hasSelection) {
    return capture.selectedText;
  }
  return capture.surroundingContext || capture.sourceTitle || "No page text found.";
}


function noteCharacterCount() {
  return Array.from(noteInput.value).length;
}


function updateControls() {
  const characterCount = noteCharacterCount();
  const noteIsValid = characterCount <= CAPTURE_LIMITS.userNote;
  noteCount.textContent = `${characterCount.toLocaleString()} / ${CAPTURE_LIMITS.userNote.toLocaleString()}`;
  noteInput.dataset.invalid = String(!noteIsValid);
  noteInput.disabled = isSubmitting || captureAttempt.isLocked;
  retryWarning.hidden = !captureAttempt.isLocked;
  saveButton.disabled = isSubmitting || !extractedCapture || !noteIsValid;
}


function setSubmitting(submitting) {
  isSubmitting = submitting;
  updateControls();
}


function closeAfterSuccess() {
  window.setTimeout(() => window.close(), SUCCESS_CLOSE_DELAY_MS);
}


async function restoreDraft() {
  if (!draftKey) {
    return;
  }
  const stored = await chrome.storage.local.get(draftKey);
  const draft = stored[draftKey];
  if (draft?.url === activeTab.url && typeof draft.note === "string") {
    noteInput.value = draft.note;
  }
}


async function persistDraft() {
  if (!draftKey || !activeTab) {
    return;
  }
  await chrome.storage.local.set({
    [draftKey]: {
      url: activeTab.url,
      note: noteInput.value,
    },
  });
}


async function initialize() {
  hideStatus();
  saveButton.disabled = true;

  try {
    [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!activeTab?.id || !/^https?:/i.test(activeTab.url || "")) {
      throw new Error("unsupported_page");
    }

    const [injection] = await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      func: extractPageCapture,
    });
    extractedCapture = injection?.result;
    if (!extractedCapture) {
      throw new Error("missing_capture_result");
    }

    draftKey = `recall-note-draft:${activeTab.id}`;
    try {
      await restoreDraft();
    } catch (_error) {
      // Draft storage is optional and must never block a new Capture.
    }

    pageTitle.textContent = extractedCapture.sourceTitle || "Untitled page";
    pageUrl.textContent = extractedCapture.sourceUrl;
    preview.textContent = previewText(extractedCapture);
    previewCount.textContent = `${Array.from(
      extractedCapture.selectedText,
    ).length.toLocaleString()} selected`;
    warning.hidden = extractedCapture.hasSelection;
    updateControls();
    noteInput.focus();
  } catch (_error) {
    pageTitle.textContent = "This page cannot be captured";
    preview.textContent = "Open a regular http or https page and try again.";
    showStatus(
      "error",
      "Capture unavailable.",
      "Chrome does not allow extensions to read this page.",
    );
  }
}


function showInlinePermissionStatus(message, kind = "information") {
  inlinePermissionStatus.hidden = !message;
  inlinePermissionStatus.textContent = message;
  inlinePermissionStatus.dataset.kind = kind;
}


async function inlinePermissionEnabled() {
  return chrome.permissions.contains({ origins: [...INLINE_CAPTURE_ORIGINS] });
}


async function synchronizeInlinePermission() {
  const response = await chrome.runtime.sendMessage({
    type: SYNC_INLINE_CAPTURE_MESSAGE,
  });
  if (response?.ok !== true) {
    throw new Error("inline_registration_failed");
  }

  if (
    response.enabled
    && activeTab?.id
    && /^https?:/i.test(activeTab.url || "")
  ) {
    await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      files: [
        "src/content/inline-core.js",
        "src/content/inline-capture.js",
      ],
    });
  }
  return response.enabled;
}


async function initializeInlinePermission() {
  if (!chrome.permissions?.contains || !chrome.runtime?.sendMessage) {
    inlineSetting.hidden = true;
    return;
  }
  inlineToggle.disabled = true;
  try {
    inlineToggle.checked = await inlinePermissionEnabled();
  } catch (_error) {
    showInlinePermissionStatus("Inline capture access could not be checked.", "error");
  } finally {
    inlineToggle.disabled = false;
  }
}


async function setInlinePermission(enabled) {
  inlineToggle.disabled = true;
  showInlinePermissionStatus("");
  try {
    const changed = enabled
      ? await chrome.permissions.request({ origins: [...INLINE_CAPTURE_ORIGINS] })
      : await chrome.permissions.remove({ origins: [...INLINE_CAPTURE_ORIGINS] });

    if (enabled && !changed) {
      inlineToggle.checked = false;
      showInlinePermissionStatus("Website access was not granted.", "error");
      return;
    }

    const active = await synchronizeInlinePermission();
    inlineToggle.checked = active;
    showInlinePermissionStatus(
      active
        ? "Enabled. Select text on this page to try it."
        : "Inline capture is off; toolbar capture still works.",
    );
  } catch (_error) {
    inlineToggle.checked = await inlinePermissionEnabled().catch(() => !enabled);
    showInlinePermissionStatus("REcall could not update website access.", "error");
  } finally {
    inlineToggle.disabled = false;
  }
}


noteInput.addEventListener("input", () => {
  updateControls();
  void persistDraft().catch(() => {
    // Keep the current textarea value even if draft storage is unavailable.
  });
});


async function submitCapture() {
  if (!extractedCapture) {
    return;
  }

  hideStatus();
  setSubmitting(true);
  saveButton.textContent = "Saving…";

  try {
    const attempt = captureAttempt.request(extractedCapture, noteInput.value);
    await sendCaptureAttempt(attempt);
    if (draftKey) {
      try {
        await chrome.storage.local.remove(draftKey);
      } catch (_error) {
        // The backend save succeeded; draft cleanup cannot turn it into failure.
      }
    }
    showStatus("success", "Saved.", "Your source and note are safely stored.");
    saveButton.textContent = "Saved";
    closeAfterSuccess();
  } catch (error) {
    if (error instanceof RecallCoordinatorError) {
      showStatus("error", error.title, error.message);
    } else {
      showStatus(
        "error",
        "Couldn’t save this Capture.",
        "Try again in a moment.",
      );
    }
    setSubmitting(false);
    saveButton.textContent = "Try again";
  }
}


saveButton.addEventListener("click", () => {
  void submitCapture();
});

inlineToggle.addEventListener("change", () => {
  void setInlinePermission(inlineToggle.checked);
});


document.addEventListener("keydown", (event) => {
  if (
    event.key === "Enter"
    && (event.metaKey || event.ctrlKey)
    && !saveButton.disabled
  ) {
    event.preventDefault();
    void submitCapture();
  }
});


void Promise.all([initialize(), initializeInlinePermission()]);
