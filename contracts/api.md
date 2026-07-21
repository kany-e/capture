# Recall localhost API contract

Status: Layer 0 contract

Version: `v1`

Base URL: `http://127.0.0.1:8765`

This document is the transport contract shared by the FastAPI backend, macOS
app, and Chrome extension. Product behavior remains governed by
`docs/product-plan.md`.

## Protocol conventions

- JSON request and response bodies use `application/json`, except the image-note
  creation route, which uses `multipart/form-data`.
- API routes are prefixed with `/v1`; `/health` is intentionally unversioned.
- Identifiers are server-generated UUID strings.
- Timestamps are RFC 3339 strings. The server emits UTC timestamps with `Z`.
- Optional unknown values are represented as `null`, not empty placeholder
  strings.
- Unknown request fields are rejected.
- The backend binds only to `127.0.0.1`.
- No authentication is required for the Build Week localhost prototype.

## Capture creation contract

`POST /v1/captures` accepts
[`capture.schema.json`](capture.schema.json).

The client may omit optional fields instead of sending `null`. At least one of
`selected_text`, `surrounding_context`, or `source_title` must contain text.
`source_type` is `web`, `clipboard`, or `screenshot`. A text screenshot Capture
contains reviewed extracted text. A separately created image note has one
persisted image attachment and may begin with empty `selected_text`.

### Text limits

- `source_app`: at most 200 Unicode characters.
- `source_title`: at most 500 Unicode characters.
- `source_url`: at most 2,048 Unicode characters.
- `selected_text`: at most 12,000 Unicode characters.
- `surrounding_context`: at most 20,000 Unicode characters.
- `user_note`: at most 4,000 Unicode characters.
- If a client truncates context, it sends `context_truncated: true`.
- Navigation, cookie notices, and footer boilerplate should be removed before
  submission when practical.

### Example request

See [`examples/capture-request.json`](examples/capture-request.json).

### Creation behavior

1. Validate the request.
2. Persist the original source and user note in one database transaction.
3. Set status to `processing`.
4. Return the persisted Capture immediately.
5. Begin enrichment after the commit succeeds.

The initial response is `202 Accepted`. OpenAI failure must never roll back or
delete the original Capture.

When `client_capture_id` is present, creation is idempotent: retries return the
first persisted Capture and do not queue a second enrichment task. The field is
optional, so requests without it always create a new Capture.

## Image-note creation contract

`POST /v1/image-captures` accepts `multipart/form-data` with exactly these
parts:

- `metadata`: a JSON string containing `client_capture_id`, optional
  `source_app`, optional `user_note`, `captured_at`, and `analyze_image`;
- `image`: one `image/png` or `image/jpeg` file, at most 8 MiB, 20,000 pixels
  per dimension, and 40 megapixels total.

`analyze_image` defaults to `false` when omitted, so contract drift fails
private rather than uploading unexpectedly. The original image is validated,
written to application-owned attachment storage, and linked to its Capture in
one create operation. It is never placed
inside SQLite or an OpenAI-generated field. `client_capture_id` makes retries
idempotent and duplicate retry files are removed.

When `analyze_image` is `false`, the response is immediately `ready`, with the
original image and user note available but no generated interpretation. When it
is `true`, the response is `processing`; one background vision request extracts
visible text into `selected_text` and fills the ordinary enrichment fields.
Those derived fields improve keyword, semantic, and visual-concept retrieval,
but never replace the authoritative image. Provider failure changes the Capture
to retryable `error` and leaves the image and note intact.

## Capture representation

All Capture-returning endpoints use this complete shape:

```json
{
  "id": "4b3a30b7-55d9-4ef8-93ef-34281c826e52",
  "client_capture_id": "149f51e1-8c18-42d4-9778-3f3b062527a2",
  "created_at": "2026-07-18T19:00:00Z",
  "updated_at": "2026-07-18T19:00:02Z",
  "captured_at": "2026-07-18T12:00:00-07:00",
  "status": "ready",
  "source_type": "web",
  "source_app": "Google Chrome",
  "source_title": "How to fix example error",
  "source_url": "https://example.com/question",
  "selected_text": "The selected answer or passage.",
  "surrounding_context": "Question, nearby paragraphs, or page context.",
  "context_truncated": false,
  "user_note": "This was the only solution that worked on my VPS.",
  "ai_title": "An unexpected fix for a VPS package error",
  "ai_summary": "The saved answer describes a configuration change that resolved the user's VPS issue after common fixes failed.",
  "problem": "A deployment command failed on a Linux VPS.",
  "key_insight": "A short configuration change resolved the issue.",
  "why_saved": "The user confirmed this was the only successful fix.",
  "caveats": [
    "Verify the configuration path before applying the change."
  ],
  "tags": [
    "Linux",
    "VPS",
    "Deployment"
  ],
  "entities": [
    "Linux",
    "VPS"
  ],
  "search_aliases": [
    "unexpected VPS fix",
    "surprising Linux solution"
  ],
  "error_message": null,
  "enrichment_version": 1,
  "user_edited_at": null,
  "user_selected_text": null,
  "user_source_app": null,
  "user_source_title": null,
  "user_source_url": null,
  "user_title": null,
  "user_problem": null,
  "user_key_insight": null,
  "user_why_saved": null,
  "user_caveats": null,
  "user_tags": null,
  "ai_interpretation_hidden": false,
  "ai_content_stale": false,
  "attachments": []
}
```

An image note contains one attachment in v1:

```json
{
  "id": "4fc18b08-8896-4bc8-9526-842f3988b21f",
  "kind": "image",
  "media_type": "image/png",
  "byte_size": 482193,
  "pixel_width": 1440,
  "pixel_height": 900,
  "sha256": "b2e7e24b10a55f1a81f77088d400cf1f7d33fa46e950800da97840c5e38451bf",
  "content_path": "/v1/attachments/4fc18b08-8896-4bc8-9526-842f3988b21f/content"
}
```

`relative_path` is private persistence metadata and is never returned. Text-only
Captures always return `attachments: []`.

`embedding_json` is an internal persistence field and is never returned to
clients.

The ordinary source fields in a response are the effective display/search
values. When a user corrects captured source metadata, the original database
columns remain unchanged and the corresponding `user_selected_text` or
`user_source_*` field records the explicit override. `user_title`,
`user_problem`, `user_key_insight`, `user_why_saved`, `user_caveats`, and
`user_tags` form a separate user-organization layer; `null` means use the AI
value, while an empty string or array deliberately hides that AI field.
`user_edited_at` changes only after an explicit user edit. `updated_at` remains
the broader system revision time and can also change during AI processing.

### Field-state rules

| Status | AI fields | `error_message` |
| --- | --- | --- |
| `captured` | `null` or empty arrays | `null` |
| `processing` | `null` or empty arrays | `null` |
| `ready` | Populated | `null` |
| `error` | Previously valid values may remain | Non-empty |

`captured` exists for persistence and recovery. A normal create response is
already `processing`.

## Enrichment contract

For text Captures, the backend sends the source fields and user note to one
OpenAI Responses API request and validates the model result against
[`enriched_capture.schema.json`](enriched_capture.schema.json) using strict
Structured Outputs.

For opted-in image notes, the backend sends the persisted image plus the user
note to one multimodal Responses API request and validates OCR plus visual
memory fields against `services/backend/app/schemas/image_enrichment.schema.json`.
The raw image stays local when analysis is disabled.

The backend maps model fields as follows:

| Structured Output | Capture API field |
| --- | --- |
| `title` | `ai_title` |
| `summary` | `ai_summary` |
| `problem` | `problem` |
| `key_insight` | `key_insight` |
| `why_saved` | `why_saved` |
| `caveats` | `caveats` |
| `tags` | `tags` |
| `entities` | `entities` |
| `search_aliases` | `search_aliases` |

The model must not claim a method worked unless the user note says it worked.
When no note is supplied, `why_saved` must explicitly say that no personal
reason was provided rather than invent one.

Every provider, including a future Apple/local provider, passes through the
same provider-neutral validation boundary. Empty, `null`, structurally invalid,
generic, or oversized output is classified as `invalid_model_output`; the
Capture reaches `error` with a safe message and can never become empty-ready or
remain processing indefinitely. Enrichment scalar fields are capped at 2,000
characters (title: 200); list fields are capped at 20 items of 300 characters.

Because enrichment tasks run in-process, a backend exit can interrupt a task.
After migrations on the next startup, all Captures left in `processing` are
atomically changed to retryable `error` records. This transition changes only
status, `updated_at`, and `error_message`; source and user-note fields remain
unchanged.

## Stable embedding input — product-plan §12.1

Only a successfully enriched Capture is embedded. The exact projection is:

```text
TITLE:
{user_title ?? ai_title}

SUMMARY:
{ai_summary}

USER NOTE:
{user_note}

SELECTED CONTENT:
{user_selected_text ?? selected_text}

PROBLEM:
{user_problem ?? problem}

KEY INSIGHT:
{user_key_insight ?? key_insight}

TAGS:
{user_tags ?? tags}

SEARCH ALIASES:
{search_aliases}
```

Construction rules:

1. Preserve these labels, order, blank lines, and final newline.
2. Normalize line endings to LF.
3. Trim leading and trailing whitespace from each value.
4. Preserve internal whitespace in `user_note` and `selected_text`.
5. Render missing scalar values as an empty string.
6. Explicit user title, selected-content, problem, key-insight, and tag
   overrides take precedence over their captured/AI fallback in the projection.
7. Render effective `tags` and `search_aliases` by joining stored values with
   `, `.
8. Use the configured `OPENAI_EMBEDDING_MODEL` for both Capture and query
   embeddings.

See [`examples/embedding-input.txt`](examples/embedding-input.txt).

Changing this projection requires an `enrichment_version` increment and
regeneration of stored embeddings.

## Endpoints

### `GET /health`

Returns `200 OK` when the process and database are available. OpenAI can be
unconfigured without making the local persistence API unhealthy.

The database probe checks migration state, SQLite quick integrity, and the JSON
array columns required to decode stored Captures. Attachment storage is also
checked for local read/write availability. Either failure returns `503`.

```json
{
  "status": "ok",
  "database": "ok",
  "attachments": "ok",
  "openai_configured": false
}
```

### `POST /v1/captures`

- Body: `capture.schema.json`
- Success: `202 Accepted`
- Response: Capture with status `processing`
- Validation failure: `422 Unprocessable Entity`

### `POST /v1/image-captures`

- Body: the multipart image-note contract above
- Success: `202 Accepted`
- Response: Capture with exactly one attachment and status `ready` or
  `processing`
- Invalid or oversized image/metadata: `422 Unprocessable Entity`
- Attachment storage unavailable: `503 Service Unavailable`

### `POST /v1/ocr`

Performs one explicit GPT screenshot text-extraction request. The screenshot is
transient input and this endpoint does not create a Capture or persist image
bytes.

Request:

```json
{
  "media_type": "image/png",
  "image_base64": "iVBORw0KGgo..."
}
```

- `media_type`: exactly `image/png` or `image/jpeg`.
- `image_base64`: strict base64 whose decoded signature matches `media_type`.
- Maximum decoded image size: 8 MiB.
- The configured `OPENAI_MODEL` receives one high-detail image input.

Success is `200 OK`:

```json
{
  "text": "Exact visible text from the screenshot.",
  "provider": "openai",
  "processing_location": "cloud",
  "model": "gpt-5.6"
}
```

Text is non-empty and capped at the existing 12,000-character `selected_text`
limit. The client keeps it as reviewed source content and keeps the optional
4,000-character `user_note` independent, then saves through `POST /v1/captures`
with `source_type: "screenshot"`. Apple Vision is a macOS-local implementation
of the same user-facing extraction step and does not call this endpoint.

### `GET /v1/captures?limit=50&offset=0&sort=created_desc`

- Success: `200 OK`
- Default order: `created_at DESC`
- `limit`: integer, default `50`, range `1...100`
- `offset`: integer, default `0`, minimum `0`
- `sort`: `created_desc`, `created_asc`, `edited_desc`, or `edited_asc`.
  Edited ordering uses `COALESCE(user_edited_at, created_at)`, so an unedited
  Capture has a stable position.

```json
{
  "items": [],
  "limit": 50,
  "offset": 0
}
```

### `GET /v1/captures/{id}`

- Success: `200 OK` with one Capture
- Unknown ID: `404 Not Found`

### `PATCH /v1/captures/{id}`

Applies explicit user edits without overwriting captured or AI-generated
columns. The request may contain corrected selected content/source metadata,
the current user note, a user title, user-organized memory details and tags,
and `show_ai_interpretation`.

This is a true partial update: omitted fields retain their current user-layer
value. An explicit JSON `null` clears the corresponding override and returns to
the captured/AI fallback; an empty string or array remains an intentional
user-visible blank.

- Success: `200 OK` with the updated Capture
- Unknown ID: `404 Not Found`
- Capture currently processing: `409 Conflict` with `capture_processing`
- Source, source-metadata, or user-note changes set `ai_content_stale: true`
  and force `ai_interpretation_hidden: true`.
- Title/detail/tag-only edits do not make AI stale. User overrides remain
  separate and take display/FTS precedence.
- The edit clears the prior embedding because its searchable projection may no
  longer be current. Keyword retrieval updates in the same SQLite transaction.

```json
{
  "selected_text": "Corrected selected content",
  "user_note": "Updated personal note",
  "source_app": "Safari",
  "source_title": "Corrected source title",
  "source_url": "https://example.com/corrected",
  "user_title": "My durable title",
  "user_problem": "My framing of the problem",
  "user_key_insight": "",
  "user_why_saved": "Why I still need this",
  "user_caveats": [],
  "user_tags": ["manual", "reference"],
  "show_ai_interpretation": true
}
```

### `GET /v1/attachments/{id}/content`

- Success: `200 OK` with the immutable PNG/JPEG bytes and `nosniff`
- Unknown attachment or missing backing file: `404 Not Found`
- The route is loopback-only like the rest of the API; clients use the
  attachment's returned `content_path` rather than constructing a filesystem
  path.

### `DELETE /v1/captures/{id}`

- Success: `204 No Content`
- Unknown ID: `404 Not Found`
- The Capture, FTS/embedding metadata, attachment rows, and referenced local
  image files are removed. Deleting a text Capture uses the same route.

### `POST /v1/captures/{id}/enrich`

Queues or starts a new enrichment attempt without changing original fields.

- Success: `202 Accepted` with status `processing`
- Unknown ID: `404 Not Found`
- Already processing: `409 Conflict`
- OpenAI not configured: `503 Service Unavailable`

An explicit refresh uses the effective corrected source and current user note.
It replaces only the AI layer, clears the stale/hidden flags when the attempt
finishes, and keeps user title/detail/tag overrides intact. Recall never queues
this refresh automatically after an edit.

### Enrichment polling

After either `202 Accepted` response, clients poll
`GET /v1/captures/{id}` every one to two seconds. Polling stops when status is
`ready` or `error` and should time out after approximately 60 seconds. The P0
contract does not use WebSockets.

### `GET /v1/search?q={query}&limit=20`

- Success: `200 OK`
- `limit`: integer, default `20`, range `1...100`
- `q`: at most 512 Unicode characters; ASCII control characters are rejected
  with `422 validation_error`.
- Empty or whitespace-only `q`: returns recent Captures.
- Keyword retrieval first requires all terms, then retries with any term only
  when the strict pass returns no rows.
- A bounded literal-substring pass is merged with tokenized candidates to
  recover partial identifiers and CJK fragments that FTS may omit. Candidates
  are deduped under the existing cap, and FTS-ranked rows retain priority.
  Query punctuation is never interpreted as search syntax.
- Exact technical identifiers receive higher keyword weight.
- If query embedding fails, results fall back to keyword scoring.
- With a compatible Capture and query vector, `score` combines semantic,
  keyword, and metadata signals. On provider or vector fallback, `score`
  preserves the keyword score and `semantic_score` is `null` for the affected
  result.

```json
{
  "query": "unexpected linux fix",
  "results": [
    {
      "capture": {},
      "score": 0.91,
      "keyword_score": 0.68,
      "semantic_score": 0.93
    }
  ]
}
```

`semantic_score` is `null` when semantic scoring is unavailable for that
result. Scores are normalized to `0...1`.

### Deferred endpoints

- `POST /v1/chat` — P1

They are deliberately excluded from the Layer 0 P0 implementation contract.

## Error envelope

All non-2xx API responses use:

```json
{
  "error": {
    "code": "capture_not_found",
    "message": "Capture was not found.",
    "details": null,
    "request_id": "8a12890b-6c51-4cb9-896a-78659ef08758"
  }
}
```

Clients may display `message`. They must not branch on message text; stable
behavior uses `code` and HTTP status.

Initial error codes:

| HTTP | Code | Meaning |
| --- | --- | --- |
| 404 | `capture_not_found` | No Capture exists for the ID. |
| 404 | `attachment_not_found` | No attachment metadata exists for the ID. |
| 404 | `attachment_file_missing` | Attachment metadata exists but its local file is unavailable. |
| 409 | `capture_already_processing` | Duplicate enrichment is in progress. |
| 422 | `validation_error` | Request does not satisfy the contract. |
| 422 | `invalid_image` | Uploaded image type, bytes, size, or dimensions are invalid. |
| 502 | `ocr_provider_unavailable` | GPT screenshot extraction failed safely. |
| 502 | `ocr_refused` | GPT refused the screenshot request. |
| 502 | `invalid_ocr_output` | GPT returned no usable screenshot text. |
| 502 | `ocr_text_too_long` | Extracted text exceeds the selected-source contract. |
| 503 | `openai_not_configured` | Enrichment or GPT screenshot extraction cannot start without a key/model. |
| 503 | `attachment_storage_unavailable` | The local attachment directory cannot store the image. |
| 500 | `internal_error` | Unexpected backend failure. |

## CORS

Development may allow configured localhost and unpacked-extension origins.
The submitted build must not use an unrestricted `*` origin. The final Chrome
extension origin is configured through `RECALL_CORS_ORIGINS`. The backend
rejects wildcards, public web origins, malformed extension IDs, credentials,
paths, queries, and fragments; allowed methods are limited to `GET`, `POST`, and
`DELETE`.

## Official OpenAI references

- [Responses API text generation](https://developers.openai.com/api/docs/guides/text?api-mode=responses)
- [Images and vision](https://developers.openai.com/api/docs/guides/images-vision)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Vector embeddings](https://developers.openai.com/api/docs/guides/embeddings)
