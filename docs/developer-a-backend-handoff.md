# Developer A backend handoff

Status: Layer 3 holder pending; Layer 4 polling, Layer 6 Chrome, and Layer 7 search contracts available

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
- Chrome Captures use the same response model with `source_type=web` and
  `source_app=Google Chrome`; no browser-only field was added.
- Decode search from `results[*].capture`. `score` is the final ranking score,
  `keyword_score` is always present, and `semantic_score` is nullable. Never
  require an embedding to display a keyword-fallback result.

## Non-production integration holder

[`examples/macos-layer3-placeholder.swift`](examples/macos-layer3-placeholder.swift)
contains copy-ready `Decodable` DTOs and an async list request. It is deliberately
stored under `docs/`, outside any Xcode target, and is marked `TODO(Developer A)`.
Developer A should adapt it to the app's existing networking and state model,
then remove the holder after the real list and detail views pass.

## Confirmation needed

Developer A should confirm:

1. Swift models decode the checked-in Capture response without invented fields.
2. The macOS list displays the live record returned by the backend.
3. Detail view preserves source and user-note separation.

That confirmation closes the shared Layer 3 vertical-slice gate.

The complete Layer 6 exit gate additionally requires Developer A to confirm
that a Capture created from the unpacked Chrome extension appears in the macOS
list without a manual database edit.
