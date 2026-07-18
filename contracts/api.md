# Recall localhost API contract

Status: Layer 0 contract

Version: `v1`

Base URL: `http://127.0.0.1:8765`

This document is the transport contract shared by the FastAPI backend, macOS
app, and Chrome extension. Product behavior remains governed by
`docs/product-plan.md`.

## Protocol conventions

- JSON request and response bodies use `application/json`.
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

### Text limits

- `selected_text`: at most 12,000 Unicode characters.
- `surrounding_context`: at most 20,000 Unicode characters.
- User notes are preserved in full for the MVP.
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
  "enrichment_version": 1
}
```

`embedding_json` is an internal persistence field and is never returned to
clients.

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

The backend sends the source fields and user note to one OpenAI Responses API
request and validates the model result against
[`enriched_capture.schema.json`](enriched_capture.schema.json) using strict
Structured Outputs.

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

## Stable embedding input — product-plan §12.1

Only a successfully enriched Capture is embedded. The exact projection is:

```text
TITLE:
{ai_title}

SUMMARY:
{ai_summary}

USER NOTE:
{user_note}

SELECTED CONTENT:
{selected_text}

PROBLEM:
{problem}

KEY INSIGHT:
{key_insight}

TAGS:
{tags}

SEARCH ALIASES:
{search_aliases}
```

Construction rules:

1. Preserve these labels, order, blank lines, and final newline.
2. Normalize line endings to LF.
3. Trim leading and trailing whitespace from each value.
4. Preserve internal whitespace in `user_note` and `selected_text`.
5. Render missing scalar values as an empty string.
6. Render `tags` and `search_aliases` by joining stored values with `, `.
7. Use the configured `OPENAI_EMBEDDING_MODEL` for both Capture and query
   embeddings.

See [`examples/embedding-input.txt`](examples/embedding-input.txt).

Changing this projection requires an `enrichment_version` increment and
regeneration of stored embeddings.

## Endpoints

### `GET /health`

Returns `200 OK` when the process and database are available. OpenAI can be
unconfigured without making the local persistence API unhealthy.

```json
{
  "status": "ok",
  "database": "ok",
  "openai_configured": false
}
```

### `POST /v1/captures`

- Body: `capture.schema.json`
- Success: `202 Accepted`
- Response: Capture with status `processing`
- Validation failure: `422 Unprocessable Entity`

### `GET /v1/captures?limit=50&offset=0`

- Success: `200 OK`
- Default order: `created_at DESC`
- `limit`: integer, default `50`, range `1...100`
- `offset`: integer, default `0`, minimum `0`

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

### `POST /v1/captures/{id}/enrich`

Queues or starts a new enrichment attempt without changing original fields.

- Success: `202 Accepted` with status `processing`
- Unknown ID: `404 Not Found`
- Already processing: `409 Conflict`
- OpenAI not configured: `503 Service Unavailable`

### Enrichment polling

After either `202 Accepted` response, clients poll
`GET /v1/captures/{id}` every one to two seconds. Polling stops when status is
`ready` or `error` and should time out after approximately 60 seconds. The P0
contract does not use WebSockets.

### `GET /v1/search?q={query}&limit=20`

- Success: `200 OK`
- `limit`: integer, default `20`, range `1...100`
- Empty or whitespace-only `q`: returns recent Captures.
- Exact technical identifiers receive higher keyword weight.
- If query embedding fails, results fall back to keyword scoring.
- Through Layer 5, `score` equals `keyword_score` and `semantic_score` is
  `null`; Layer 7 adds semantic and hybrid scoring without changing this shape.

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

- `DELETE /v1/captures/{id}` — P1
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
| 409 | `capture_already_processing` | Duplicate enrichment is in progress. |
| 422 | `validation_error` | Request does not satisfy the contract. |
| 503 | `openai_not_configured` | Enrichment cannot start without a key/model. |
| 500 | `internal_error` | Unexpected backend failure. |

## CORS

Development may allow configured localhost and unpacked-extension origins.
The submitted build must not use an unrestricted `*` origin. The final Chrome
extension origin is configured through `RECALL_CORS_ORIGINS`. The backend
rejects wildcards, public web origins, malformed extension IDs, credentials,
paths, queries, and fragments; allowed methods are limited to `GET` and `POST`.

## Official OpenAI references

- [Responses API text generation](https://developers.openai.com/api/docs/guides/text?api-mode=responses)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Vector embeddings](https://developers.openai.com/api/docs/guides/embeddings)
