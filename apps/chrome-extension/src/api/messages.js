export const CREATE_CAPTURE_MESSAGE = "recall:capture:create";
export const SYNC_INLINE_CAPTURE_MESSAGE = "recall:inline:sync";
export const DISABLE_INLINE_CAPTURE_MESSAGE = "recall:inline:disable";


export class RecallCoordinatorError extends Error {
  constructor(
    detail,
    {
      code = "extension_error",
      title = "Couldn’t save this Capture.",
      retryable = true,
    } = {},
  ) {
    super(detail);
    this.name = "RecallCoordinatorError";
    this.code = code;
    this.title = title;
    this.retryable = retryable;
  }
}


export function buildCaptureAttempt(
  extractedCapture,
  userNote,
  {
    now = () => new Date(),
    createId = () => crypto.randomUUID(),
  } = {},
) {
  return {
    clientCaptureId: createId(),
    capturedAt: now().toISOString(),
    extractedCapture,
    userNote: String(userNote ?? ""),
  };
}


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
    throw new RecallCoordinatorError(
      "REcall’s extension service is unavailable. Reload the extension and try again.",
      { code: "extension_unavailable" },
    );
  }

  if (response?.ok === true && response.capture) {
    return response.capture;
  }

  const error = response?.error;
  throw new RecallCoordinatorError(
    error?.detail || "Try again in a moment.",
    {
      code: error?.code || "invalid_extension_response",
      title: error?.title || "Couldn’t save this Capture.",
      retryable: error?.retryable !== false,
    },
  );
}
