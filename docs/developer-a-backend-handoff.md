# macOS and backend integration handoff

Status: Layer 3 gate closed; hardened backend, Chrome, and macOS code integrated;
deterministic and shared live verification complete

Last updated: 2026-07-19

## Local service

- Base URL: `http://127.0.0.1:8765`
- Health: `GET /health`
- Create: `POST /v1/captures`
- List: `GET /v1/captures?limit=50&offset=0`
- Detail: `GET /v1/captures/{id}`
- Retry enrichment: `POST /v1/captures/{id}/enrich`
- Search: `GET /v1/search?q={query}&limit=20`
- Shared response contract: [`contracts/api.md`](../contracts/api.md)

Start the backend from `services/backend/`:

```bash
.venv/bin/python -m app
```

The service starts without an OpenAI key. In that mode, capture persistence and
FTS search still work, enrichment reaches a safe terminal error, and search
results may have `semantic_score=null`.

## macOS contract behavior

- Decode list responses from `items`; `limit` and `offset` are returned beside
  the array.
- Decode search from `results[*].capture`. `score` is the final ranking score,
  `keyword_score` is always present, and `semantic_score` is nullable. A result
  never requires an embedding to be displayed.
- Render source text, surrounding context, `user_note`, and generated AI fields
  as separate information layers.
- Show `processing` immediately after creation, poll detail about every two
  seconds, stop on `ready` or `error`, and stop after approximately 60 seconds.
- Preserve raw source and note data when enrichment fails, and offer
  `POST /v1/captures/{id}/enrich` where retry is appropriate.
- Display an error's stable message, but branch behavior on its stable code and
  HTTP status.
- Preserve `context_truncated` in request and response models.
- Reuse the draft's `client_capture_id` and `captured_at` when a user retries
  the same failed create request; a new draft receives a new identity.
- Use the local substring search fallback only when the exact search route
  returns `404`. Do not hide validation, server, or connectivity errors behind
  local results.

Chrome Captures use the same response model with `source_type=web` and normally
`source_app=Google Chrome`; there is no browser-only Capture response type.

## Current input limits

The macOS client and backend share these relevant caps:

| Field | Maximum Unicode scalars |
| --- | ---: |
| `source_app` | 200 |
| `source_title` | 500 |
| `source_url` | 2,048 |
| `selected_text` | 12,000 |
| `surrounding_context` | 20,000 |
| `user_note` | 4,000 |
| search query `q` | 512 |

Search also rejects ASCII control characters. Oversized clipboard text, notes,
and queries should remain visible to the user with a local validation message;
the client must not silently truncate private content before submission. Source
application metadata may be safely bounded to its contract cap.

## Layer 3 gate closure

The temporary `docs/examples/macos-layer3-placeholder.swift` holder was removed
after the production target implemented the shared DTOs, networking, list, and
detail flow. On the original macOS branch, the app built with Xcode 26.2, its 11
contract/network/store tests passed, and live backend Captures were displayed
with source and user-note separation. Subsequent manual checks also exercised
clipboard capture, notes, source attribution, backend search, restart recovery,
offline behavior, and empty/overlong clipboard handling.

That evidence closes D-013 and B-006. The current integrated target now passes
all 27 macOS tests alongside 186 backend tests, 44 stress scenarios, and 13
extension tests.

## Shared live-gate result

- **B-007 resolved:** a real Responses API retry moved a persisted Capture from
  `processing` to `ready` with non-empty generated fields.
- **B-008 resolved:** a real embedding was stored and a vague query ranked the
  intended Capture first with a non-null semantic score; provider-off FTS still
  returns usable results with `semantic_score=null`.
- **B-009 resolved:** an unpacked extension using an exact local CORS origin
  saved both page-context and 132-character selected-text Captures; the macOS
  app displayed the resulting ready Google Chrome cards without database edits.

Never send an API key through Git, GitHub, chat, screenshots, or test fixtures.
