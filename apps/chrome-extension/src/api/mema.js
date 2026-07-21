export const MEMA_BASE_URL = "http://127.0.0.1:8765";
export const MEMA_UNAVAILABLE_TITLE = "Mema’s backend is not running.";
export const MEMA_UNAVAILABLE_DETAIL = "Start the local Mema backend and try again.";
export const CAPTURE_LIMITS = Object.freeze({
  sourceTitle: 500,
  sourceUrl: 2_048,
  selectedText: 12_000,
  surroundingContext: 20_000,
  userNote: 4_000,
});


export class MemaUnavailableError extends Error {
  constructor() {
    super(MEMA_UNAVAILABLE_TITLE);
    this.name = "MemaUnavailableError";
  }
}


export class MemaApiError extends Error {
  constructor(message, { code = "api_error", status = 0 } = {}) {
    super(message);
    this.name = "MemaApiError";
    this.code = code;
    this.status = status;
  }
}


export class MemaCaptureValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "MemaCaptureValidationError";
  }
}


function unicodeLength(value) {
  return Array.from(String(value ?? "")).length;
}


function requireWithinLimit(value, fieldName, maximum) {
  const length = unicodeLength(value);
  if (length > maximum) {
    throw new MemaCaptureValidationError(
      `${fieldName} can use up to ${maximum.toLocaleString()} characters; this value has ${length.toLocaleString()}.`,
    );
  }
}


export function buildCaptureRequest(
  extracted,
  userNote,
  {
    now = () => new Date(),
    createId = () => crypto.randomUUID(),
  } = {},
) {
  const note = String(userNote ?? "");
  requireWithinLimit(note, "Your note", CAPTURE_LIMITS.userNote);
  requireWithinLimit(
    extracted.selectedText,
    "The selected text",
    CAPTURE_LIMITS.selectedText,
  );
  requireWithinLimit(
    extracted.surroundingContext,
    "The surrounding context",
    CAPTURE_LIMITS.surroundingContext,
  );

  const sourceTitle = String(extracted.sourceTitle ?? "");
  const sourceUrl = String(extracted.sourceUrl ?? "");
  requireWithinLimit(sourceTitle, "The page title", CAPTURE_LIMITS.sourceTitle);
  requireWithinLimit(sourceUrl, "The page URL", CAPTURE_LIMITS.sourceUrl);
  return {
    client_capture_id: createId(),
    source_type: "web",
    source_app: "Google Chrome",
    source_title: sourceTitle || null,
    source_url: sourceUrl || null,
    selected_text: extracted.selectedText,
    surrounding_context: extracted.surroundingContext || null,
    context_truncated: Boolean(extracted.contextTruncated),
    user_note: note.trim() ? note : null,
    captured_at: now().toISOString(),
  };
}


export async function createCapture(
  payload,
  {
    fetchImpl = globalThis.fetch,
    timeoutMs = 6_000,
    baseUrl = MEMA_BASE_URL,
  } = {},
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    let response;
    try {
      response = await fetchImpl(`${baseUrl}/v1/captures`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
    } catch (_error) {
      throw new MemaUnavailableError();
    }

    let body = null;
    try {
      body = await response.json();
    } catch (_error) {
      body = null;
    }

    if (!response.ok) {
      const apiError = body?.error;
      throw new MemaApiError(
        apiError?.message || "Mema could not save this Capture.",
        {
          code: apiError?.code || "api_error",
          status: response.status,
        },
      );
    }

    if (!body || typeof body.id !== "string" || typeof body.status !== "string") {
      throw new MemaApiError("Mema returned an invalid response.", {
        code: "invalid_response",
        status: response.status,
      });
    }
    return body;
  } finally {
    clearTimeout(timeout);
  }
}
