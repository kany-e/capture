import {
  MemaApiError,
  MemaCaptureValidationError,
  MemaUnavailableError,
  buildCaptureRequest,
  createCapture,
} from "../api/mema.js";


const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ATTEMPT_KEYS = Object.freeze([
  "capturedAt",
  "clientCaptureId",
  "extractedCapture",
  "userNote",
]);
const EXTRACTED_CAPTURE_KEYS = Object.freeze([
  "contextTruncated",
  "selectedText",
  "sourceTitle",
  "sourceUrl",
  "surroundingContext",
]);


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


function hasExactKeys(value, expectedKeys) {
  if (!isRecord(value)) {
    return false;
  }
  const actualKeys = Object.keys(value).sort();
  return actualKeys.length === expectedKeys.length
    && actualKeys.every((key, index) => key === expectedKeys[index]);
}


function isCanonicalTimestamp(value) {
  if (typeof value !== "string") {
    return false;
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString() === value;
}


export function validCaptureAttempt(attempt) {
  if (
    !hasExactKeys(attempt, ATTEMPT_KEYS)
    || !UUID_PATTERN.test(attempt.clientCaptureId)
    || !isCanonicalTimestamp(attempt.capturedAt)
    || typeof attempt.userNote !== "string"
    || !hasExactKeys(attempt.extractedCapture, EXTRACTED_CAPTURE_KEYS)
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


function retryableApiError(error) {
  return error.code === "invalid_response"
    || error.status === 0
    || error.status === 408
    || error.status === 429
    || error.status >= 500;
}


export function mapCaptureError(error) {
  if (error instanceof MemaUnavailableError) {
    return {
      code: "mema_unavailable",
      title: "Mema’s backend is not running.",
      detail: "Start the local Mema backend and try again.",
      retryable: true,
    };
  }
  if (error instanceof MemaCaptureValidationError) {
    return {
      code: "capture_validation_error",
      title: "This Capture cannot be saved.",
      detail: error.message,
      retryable: false,
    };
  }
  if (error instanceof MemaApiError) {
    return {
      code: error.code,
      title: "Couldn’t save this Capture.",
      detail: error.message,
      retryable: retryableApiError(error),
    };
  }
  return {
    code: "unexpected_extension_error",
    title: "Couldn’t save this Capture.",
    detail: "Try again in a moment.",
    // An unknown failure may have happened after the backend committed. A retry
    // is safe because the exact client id remains frozen and backend creation is
    // idempotent for that id.
    retryable: true,
  };
}


/** Validate and deliver a toolbar or inline attempt through one API path. */
export async function coordinateCapture(
  attempt,
  {
    createCaptureImpl = createCapture,
  } = {},
) {
  if (!validCaptureAttempt(attempt)) {
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
    return { ok: false, error: mapCaptureError(error) };
  }
}
