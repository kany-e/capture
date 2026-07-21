import {
  CREATE_CAPTURE_MESSAGE,
  INLINE_CAPTURE_STATUS_MESSAGE,
  SYNC_INLINE_CAPTURE_MESSAGE,
} from "../api/messages.js";
import { coordinateCapture } from "./capture-coordinator.js";
import {
  createInlineCaptureReconciler,
  inlineCapturePermissionEnabled,
} from "./inline-registration.js";


function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}


function hasExactKeys(value, expectedKeys) {
  if (!isRecord(value)) {
    return false;
  }
  const actual = Object.keys(value).sort();
  return actual.length === expectedKeys.length
    && actual.every((key, index) => key === expectedKeys[index]);
}


function invalidMessageResponse() {
  return {
    ok: false,
    error: {
      code: "invalid_extension_message",
      title: "Couldn’t save this Capture.",
      detail: "The extension sent an invalid Capture request.",
      retryable: false,
    },
  };
}


function unexpectedMessageResponse() {
  return {
    ok: false,
    error: {
      code: "unexpected_extension_error",
      title: "Couldn’t save this Capture.",
      detail: "Try again in a moment.",
      retryable: true,
    },
  };
}


function inlineAccessRemovedResponse() {
  return {
    ok: false,
    error: {
      code: "inline_access_removed",
      title: "Inline capture is off.",
      detail: "Website access was removed. Re-enable inline capture and select the text again.",
      retryable: false,
    },
  };
}


function statusFailureResponse() {
  return {
    ok: false,
    enabled: false,
    error: "Mema could not verify inline capture access.",
  };
}


/** Build the runtime listener separately so sender and response behavior test cleanly. */
export function createServiceWorkerMessageHandler({
  extensionId = globalThis.chrome?.runtime?.id,
  coordinateCaptureImpl = coordinateCapture,
  inlineCapturePermissionEnabledImpl = () => inlineCapturePermissionEnabled(),
  reconcileInlineCapture,
} = {}) {
  return function handleMessage(message, sender, sendResponse) {
    // Pages cannot normally call runtime.sendMessage without an explicit
    // externally_connectable declaration. Still reject every sender that is not
    // this extension before inspecting or delivering its payload.
    if (!extensionId || sender?.id !== extensionId) {
      return false;
    }

    if (message?.type === CREATE_CAPTURE_MESSAGE) {
      if (!hasExactKeys(message, ["attempt", "type"])) {
        sendResponse(invalidMessageResponse());
        return false;
      }
      const deliver = async () => {
        if (sender?.tab != null) {
          try {
            if (await inlineCapturePermissionEnabledImpl() !== true) {
              return inlineAccessRemovedResponse();
            }
          } catch (_error) {
            return inlineAccessRemovedResponse();
          }
        }
        return coordinateCaptureImpl(message.attempt);
      };
      void Promise.resolve(deliver())
        .then(sendResponse)
        .catch(() => sendResponse(unexpectedMessageResponse()));
      return true;
    }

    if (message?.type === INLINE_CAPTURE_STATUS_MESSAGE) {
      if (!hasExactKeys(message, ["type"])) {
        sendResponse(statusFailureResponse());
        return false;
      }
      void Promise.resolve(inlineCapturePermissionEnabledImpl())
        .then((enabled) => sendResponse({
          ok: true,
          enabled: enabled === true,
        }))
        .catch(() => sendResponse(statusFailureResponse()));
      return true;
    }

    if (message?.type === SYNC_INLINE_CAPTURE_MESSAGE) {
      if (!hasExactKeys(message, ["type"]) || !reconcileInlineCapture) {
        sendResponse({
          ok: false,
          error: "Mema could not update inline capture access.",
        });
        return false;
      }
      void Promise.resolve(reconcileInlineCapture())
        .then((enabled) => sendResponse({ ok: true, enabled }))
        .catch(() => sendResponse({
          ok: false,
          error: "Mema could not update inline capture access.",
        }));
      return true;
    }

    return false;
  };
}


export function installServiceWorker(
  chromeApi = globalThis.chrome,
  {
    coordinateCaptureImpl = coordinateCapture,
    inlineCapturePermissionEnabledImpl = null,
    reconcileInlineCaptureImpl = null,
  } = {},
) {
  const reconcileInlineCapture = reconcileInlineCaptureImpl
    || createInlineCaptureReconciler({
      permissions: chromeApi.permissions,
      scripting: chromeApi.scripting,
      tabs: chromeApi.tabs,
    });
  const checkInlineCapturePermission = inlineCapturePermissionEnabledImpl
    || (() => inlineCapturePermissionEnabled(chromeApi.permissions));

  const reportRegistrationError = (error) => {
    console.warn(
      "Mema inline capture registration failed.",
      error?.message || error,
    );
  };
  const reconcileWithoutResponse = () => {
    void reconcileInlineCapture().catch(reportRegistrationError);
  };

  chromeApi.runtime.onInstalled.addListener(reconcileWithoutResponse);
  chromeApi.runtime.onStartup.addListener(reconcileWithoutResponse);
  chromeApi.permissions.onAdded.addListener(reconcileWithoutResponse);
  chromeApi.permissions.onRemoved.addListener(reconcileWithoutResponse);
  chromeApi.runtime.onMessage.addListener(createServiceWorkerMessageHandler({
    extensionId: chromeApi.runtime.id,
    coordinateCaptureImpl,
    inlineCapturePermissionEnabledImpl: checkInlineCapturePermission,
    reconcileInlineCapture,
  }));

  return { reconcileInlineCapture };
}


if (globalThis.chrome?.runtime?.onMessage) {
  installServiceWorker(globalThis.chrome);
}
