import {
  CREATE_CAPTURE_MESSAGE,
  SYNC_INLINE_CAPTURE_MESSAGE,
} from "../api/messages.js";
import { coordinateCapture } from "./capture-coordinator.js";
import {
  disableInlineCaptureInOpenTabs,
  syncInlineCaptureRegistration,
} from "./inline-registration.js";


function reportRegistrationError(error) {
  console.warn("REcall inline capture registration failed.", error?.message || error);
}


function synchronizeInlineCapture() {
  return syncInlineCaptureRegistration().catch((error) => {
    reportRegistrationError(error);
    throw error;
  });
}


async function applyInlineCaptureState() {
  const enabled = await synchronizeInlineCapture();
  if (!enabled) {
    await disableInlineCaptureInOpenTabs();
  }
  return enabled;
}


chrome.runtime.onInstalled.addListener(() => {
  void applyInlineCaptureState().catch(() => {});
});

chrome.runtime.onStartup.addListener(() => {
  void applyInlineCaptureState().catch(() => {});
});

chrome.permissions.onAdded.addListener(() => {
  void applyInlineCaptureState().catch(() => {});
});

chrome.permissions.onRemoved.addListener(() => {
  void applyInlineCaptureState().catch(() => {});
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id) {
    return false;
  }

  if (message?.type === CREATE_CAPTURE_MESSAGE) {
    void coordinateCapture(message.attempt).then(sendResponse);
    return true;
  }

  if (message?.type === SYNC_INLINE_CAPTURE_MESSAGE) {
    void applyInlineCaptureState()
      .then((enabled) => sendResponse({ ok: true, enabled }))
      .catch(() => sendResponse({
        ok: false,
        error: "REcall could not update inline capture access.",
      }));
    return true;
  }

  return false;
});

void applyInlineCaptureState().catch(() => {});
