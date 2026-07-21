import {
  RecallApiError,
  RecallCaptureValidationError,
  RecallUnavailableError,
  buildCaptureRequest,
  createCapture,
} from "../api/recall.js";


const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;


function invalidMessage(detail = "The extension sent an invalid Capture request.") {
  return {
    ok: false,
    error: {
      code: "invalid_extension_message",
      title: "Couldn’t save this Capture.",
      detail,
      retryable: false,
    },
  };
}


function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}


function validAttempt(attempt) {
  if (!isRecord(attempt) || !UUID_PATTERN.test(attempt.clientCaptureId || "")) {
    return false;
  }
  if (
    typeof attempt.capturedAt !== "string"
    || !Number.isFinite(Date.parse(attempt.capturedAt))
    || typeof attempt.userNote !== "string"
    || !isRecord(attempt.extractedCapture)
  ) {
    return false;
  }

  const capture = attempt.extractedCapture;
  return typeof capture.sourceTitle === "string"
    && typeof capture.sourceUrl === "string"
    && typeof capture.selectedText === "string"
    && typeof capture.surroundingContext === "string"
    && typeof capture.contextTruncated === "boolean";
}


function mappedError(error) {
  if (error instanceof RecallUnavailableError) {
    return {
      code: "recall_unavailable",
      title: "REcall is not running.",
      detail: "Open the REcall app and try again.",
      retryable: true,
    };
  }
  if (error instanceof RecallCaptureValidationError) {
    return {
      code: "capture_validation_error",
      title: "This Capture cannot be saved.",
      detail: error.message,
      retryable: false,
    };
  }
  if (error instanceof RecallApiError) {
    return {
      code: error.code,
      title: "Couldn’t save this Capture.",
      detail: error.message,
      retryable: error.status === 0 || error.status >= 500,
    };
  }
  return {
    code: "unexpected_extension_error",
    title: "Couldn’t save this Capture.",
    detail: "Try again in a moment.",
    retryable: true,
  };
}


export async function coordinateCapture(
  attempt,
  {
    createCaptureImpl = createCapture,
  } = {},
) {
  if (!validAttempt(attempt)) {
    return invalidMessage();
  }

  try {
    const payload = buildCaptureRequest(
      attempt.extractedCapture,
      attempt.userNote,
      {
        now: () => new Date(attempt.capturedAt),
        createId: () => attempt.clientCaptureId,
      },
    );
    const capture = await createCaptureImpl(payload);
    return { ok: true, capture };
  } catch (error) {
    return { ok: false, error: mappedError(error) };
  }
}
