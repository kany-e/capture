import {
  RECALL_UNAVAILABLE_DETAIL,
  RECALL_UNAVAILABLE_TITLE,
  RecallApiError,
  RecallUnavailableError,
  buildCaptureRequest,
  createCapture,
} from "../api/recall.js";
import { extractPageCapture } from "../content/capture.js";


const pageTitle = document.querySelector("#page-title");
const pageUrl = document.querySelector("#page-url");
const preview = document.querySelector("#selection-preview");
const previewCount = document.querySelector("#preview-count");
const warning = document.querySelector("#selection-warning");
const noteInput = document.querySelector("#user-note");
const saveButton = document.querySelector("#save-button");
const statusBox = document.querySelector("#status");
const statusTitle = document.querySelector("#status-title");
const statusDetail = document.querySelector("#status-detail");

let activeTab = null;
let extractedCapture = null;
let draftKey = null;


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
    saveButton.disabled = false;
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


noteInput.addEventListener("input", () => {
  void persistDraft().catch(() => {
    // Keep the current textarea value even if draft storage is unavailable.
  });
});


saveButton.addEventListener("click", async () => {
  if (!extractedCapture) {
    return;
  }

  hideStatus();
  saveButton.disabled = true;
  saveButton.textContent = "Saving…";

  try {
    const payload = buildCaptureRequest(extractedCapture, noteInput.value);
    await createCapture(payload);
    if (draftKey) {
      try {
        await chrome.storage.local.remove(draftKey);
      } catch (_error) {
        // The backend save succeeded; draft cleanup cannot turn it into failure.
      }
    }
    showStatus("success", "Saved.", "Processing with AI…");
    saveButton.textContent = "Saved";
  } catch (error) {
    if (error instanceof RecallUnavailableError) {
      showStatus("error", RECALL_UNAVAILABLE_TITLE, RECALL_UNAVAILABLE_DETAIL);
    } else if (error instanceof RecallApiError) {
      showStatus("error", "Couldn’t save this Capture.", error.message);
    } else {
      showStatus(
        "error",
        "Couldn’t save this Capture.",
        "Try again in a moment.",
      );
    }
    saveButton.disabled = false;
    saveButton.textContent = "Try again";
  }
});


void initialize();
