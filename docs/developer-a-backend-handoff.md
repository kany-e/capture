# Developer A backend handoff

Status: Layer 3 macOS integration verified; Layer 4 polling and Layer 5 search contracts available

Last verified: 2026-07-18

## Local service

- Base URL: `http://127.0.0.1:8765`
- Health: `GET /health`
- Create: `POST /v1/captures`
- List: `GET /v1/captures?limit=50&offset=0`
- Detail: `GET /v1/captures/{id}`
- Retry enrichment: `POST /v1/captures/{id}/enrich`
- Search: `GET /v1/search?q={query}&limit=20`
- Shared response contract: `contracts/api.md`

Start the backend from `services/backend/`:

```bash
.venv/bin/python -m app
```

## Verified curl flow

From the repository root:

```bash
curl --header 'Content-Type: application/json' \
  --data-binary @contracts/examples/capture-request.json \
  http://127.0.0.1:8765/v1/captures
```

The verified response returned HTTP `202`, a server UUID, and status
`processing`. Use that returned UUID for detail:

```bash
curl http://127.0.0.1:8765/v1/captures/{id}
```

List the newest records:

```bash
curl 'http://127.0.0.1:8765/v1/captures?limit=50&offset=0'
```

Search raw and generated fields, or omit `q` for recent Captures:

```bash
curl --get --data-urlencode 'q=WorkingDirectory' \
  'http://127.0.0.1:8765/v1/search?limit=20'
curl 'http://127.0.0.1:8765/v1/search?limit=20'
```

The live proof created Capture `359d1c47-0190-40c4-8681-d994408860be` and
verified the same record through POST, direct SQLite inspection, detail GET,
and list GET.

The Layer 5 provider-off proof created temporary Capture
`9845ea10-da9a-4407-bd43-907f86d89557`, observed its safe `error` transition,
retrieved it through `q=WorkingDirectory`, and retrieved it again after a clean
backend restart. The disposable database was removed afterward.

## macOS behavior for this layer

- Decode list responses from the `items` array; `limit` and `offset` are
  returned beside it.
- Render source, surrounding context, and `user_note` independently.
- Show `processing` immediately after creation, then poll detail every one to
  two seconds until `ready` or `error`, with an approximately 60-second cap.
- When status becomes `ready`, render the AI interpretation separately from the
  original source and user note. When it becomes `error`, retain the raw card
  and offer retry through `POST /v1/captures/{id}/enrich`.
- Display the stable error `message`, but branch behavior on the error `code`.
- Preserve `context_truncated` in Swift request and response models.
- Decode search from `results[*].capture`. In Layer 5, `score` equals
  `keyword_score` and `semantic_score` is `null`; do not require embeddings to
  display keyword results.

## Retired integration holder

The temporary `docs/examples/macos-layer3-placeholder.swift` holder was removed
after the production Xcode target implemented the shared DTOs, networking, list,
and detail flow. The maintained client implementation now lives under
`apps/macos/Recall/`.

## Confirmation needed

Developer A confirmed on 2026-07-18:

1. Swift models decode the checked-in Capture response without invented fields.
2. The macOS list displays live records returned by the backend.
3. Detail view preserves source, surrounding context, and user-note separation.
4. Clipboard capture returns `202`, appears immediately as `processing`, and is
   read back through list and detail requests.

Evidence: the `Recall` scheme built with Xcode 26.2 and all 11 macOS contract,
network, and store tests passed; the backend's 55 tests passed; a live
API-seeded web Capture and a live macOS clipboard Capture were displayed in the
app; server logs recorded `POST /v1/captures`, list, and detail requests. The
temporary example holder was removed after this confirmation.

This closes the shared Layer 3 vertical-slice gate. Layer 4 enrichment is now
implemented by the backend: the app polls `processing` records to `ready` or
`error` and preserves raw content in either case. A real OpenAI-backed `ready`
proof still requires the untracked local API key recorded as blocker B-007;
Layer 5 backend keyword search is available and automatically replaces the
client's visible `404`-only fallback.
