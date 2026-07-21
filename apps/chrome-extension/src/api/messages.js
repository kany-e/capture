export const CREATE_CAPTURE_MESSAGE = "mema:capture:create";
export const SYNC_INLINE_CAPTURE_MESSAGE = "mema:inline:sync";
export const INLINE_CAPTURE_STATUS_MESSAGE = "mema:inline:status";
export const DISABLE_INLINE_CAPTURE_MESSAGE = "mema:inline:disable";


export class MemaCoordinatorError extends Error {
  constructor(
    detail,
    {
      code = "extension_error",
      title = "Couldn’t save this Capture.",
      retryable = true,
    } = {},
  ) {
    super(detail);
    this.name = "MemaCoordinatorError";
    this.code = code;
    this.title = title;
    this.retryable = retryable;
  }
}


function captureSnapshot(extractedCapture) {
  return Object.freeze({
    sourceTitle: String(extractedCapture?.sourceTitle ?? ""),
    sourceUrl: String(extractedCapture?.sourceUrl ?? ""),
    selectedText: String(extractedCapture?.selectedText ?? ""),
    surroundingContext: String(extractedCapture?.surroundingContext ?? ""),
    contextTruncated: Boolean(extractedCapture?.contextTruncated),
  });
}


/**
 * Freeze the source, note, timestamp, and id for one logical save attempt.
 *
 * The caller should retain this object for every retry. Keeping the attempt in
 * the initiating UI, rather than extension storage, preserves the selected-text
 * privacy boundary while backend idempotency handles an ambiguous first POST.
 */
export function buildCaptureAttempt(
  extractedCapture,
  userNote,
  {
    now = () => new Date(),
    createId = () => crypto.randomUUID(),
  } = {},
) {
  return Object.freeze({
    clientCaptureId: createId(),
    capturedAt: now().toISOString(),
    extractedCapture: captureSnapshot(extractedCapture),
    userNote: String(userNote ?? ""),
  });
}


function coordinatedCapture(response) {
  const capture = response?.capture;
  if (
    response?.ok === true
    && capture
    && typeof capture === "object"
    && !Array.isArray(capture)
    && typeof capture.id === "string"
    && typeof capture.status === "string"
  ) {
    return capture;
  }
  return null;
}


/** Send one already-frozen attempt through the shared service-worker path. */
export async function sendCaptureAttempt(
  attempt,
  {
    sendMessageImpl = (message) => chrome.runtime.sendMessage(message),
  } = {},
) {
  let response;
  try {
    response = await sendMessageImpl({
      type: CREATE_CAPTURE_MESSAGE,
      attempt,
    });
  } catch (_error) {
    throw new MemaCoordinatorError(
      "Mema’s extension service is unavailable. Reload the extension and try again.",
      { code: "extension_unavailable", retryable: true },
    );
  }

  const capture = coordinatedCapture(response);
  if (capture) {
    return capture;
  }

  const error = response?.error;
  throw new MemaCoordinatorError(
    typeof error?.detail === "string"
      ? error.detail
      : "Try again in a moment.",
    {
      code: typeof error?.code === "string"
        ? error.code
        : "invalid_extension_response",
      title: typeof error?.title === "string"
        ? error.title
        : "Couldn’t save this Capture.",
      retryable: typeof error?.retryable === "boolean"
        ? error.retryable
        : true,
    },
  );
}
