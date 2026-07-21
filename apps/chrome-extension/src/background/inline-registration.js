import { DISABLE_INLINE_CAPTURE_MESSAGE } from "../api/messages.js";


export const INLINE_CAPTURE_ORIGINS = Object.freeze([
  "http://*/*",
  "https://*/*",
]);
export const INLINE_CAPTURE_SCRIPT_ID = "recall-inline-capture";
export const INLINE_CAPTURE_SCRIPT = Object.freeze({
  id: INLINE_CAPTURE_SCRIPT_ID,
  matches: INLINE_CAPTURE_ORIGINS,
  js: [
    "src/content/inline-core.js",
    "src/content/inline-capture.js",
  ],
  allFrames: false,
  runAt: "document_idle",
  persistAcrossSessions: true,
  world: "ISOLATED",
});


export async function inlineCapturePermissionEnabled(
  permissions = chrome.permissions,
) {
  return permissions.contains({ origins: [...INLINE_CAPTURE_ORIGINS] });
}


export async function syncInlineCaptureRegistration({
  permissions = chrome.permissions,
  scripting = chrome.scripting,
} = {}) {
  const enabled = await inlineCapturePermissionEnabled(permissions);
  const registered = await scripting.getRegisteredContentScripts({
    ids: [INLINE_CAPTURE_SCRIPT_ID],
  });

  if (!enabled) {
    if (registered.length > 0) {
      await scripting.unregisterContentScripts({
        ids: [INLINE_CAPTURE_SCRIPT_ID],
      });
    }
    return false;
  }

  if (registered.length === 0) {
    await scripting.registerContentScripts([{ ...INLINE_CAPTURE_SCRIPT }]);
  } else {
    await scripting.updateContentScripts([{ ...INLINE_CAPTURE_SCRIPT }]);
  }
  return true;
}


export async function disableInlineCaptureInOpenTabs(tabs = chrome.tabs) {
  const openTabs = await tabs.query({});
  const notifications = openTabs
    .filter((tab) => Number.isInteger(tab.id))
    .map((tab) => tabs.sendMessage(tab.id, {
      type: DISABLE_INLINE_CAPTURE_MESSAGE,
    }));
  await Promise.allSettled(notifications);
}
