# Recall backend

The backend is a local-only FastAPI service. Layers 1–2 provide validated
configuration, `GET /health`, numbered SQLite migrations, and transactional
Capture persistence. HTTP Capture CRUD routes begin in Layer 3.

Run all commands below from `services/backend/`.

## Install

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

The service reads optional configuration from the repository-root `.env` and
then from the shell environment. It starts safely without `.env` or an OpenAI
key. Copy `.env.example` to `.env` only when local overrides are needed.

`RECALL_HOST` must be `localhost` or a loopback IP address. The default is
`127.0.0.1`; public or LAN binding is rejected.

## Start

```bash
.venv/bin/python -m app
```

In another terminal:

```bash
curl --fail --silent http://127.0.0.1:8765/health
```

Without an API key, the expected response is:

```json
{"status":"ok","database":"ok","openai_configured":false}
```

The health probe creates the configured SQLite file if needed and checks it
with `SELECT 1` and verifies that every known migration is applied.

## Live build checklist

Open [http://127.0.0.1:8765/dev/checklist](http://127.0.0.1:8765/dev/checklist)
while the backend is running. The page rereads
`docs/developer-b-checklist.md` every two seconds, so saved checklist edits
appear without a service restart. The dashboard is read-only and local-only.

## SQLite persistence

Numbered SQL files live in `app/migrations/` and run transactionally during
backend startup and before repository access. Migrations create the product-plan
`captures` and `captures_fts` tables. SQLite triggers synchronize every insert,
update, retry, and future deletion in the same transaction; migration 002
backfills records created by older builds.

Application code accesses Capture records through `app.repository` rather than
issuing SQL from HTTP handlers. Source fields and the user note are not accepted
by the enrichment-update method, preventing an AI update from overwriting them.

## Capture API

Layer 3 exposes create, newest-first list, and detail routes. From
`services/backend/`, create the checked-in example with:

```bash
curl --header 'Content-Type: application/json' \
  --data-binary @../../contracts/examples/capture-request.json \
  http://127.0.0.1:8765/v1/captures
```

The response is HTTP `202` with status `processing`. The background enrichment
task then moves the stored Capture to `ready` or a source-preserving `error`.

Use the returned `id` in the detail route and list the newest Captures with:

```bash
curl http://127.0.0.1:8765/v1/captures/{id}
curl 'http://127.0.0.1:8765/v1/captures?limit=50&offset=0'
```

Validation failures and unknown Capture IDs use the versioned error envelope
in `contracts/api.md`.

## AI enrichment

Layer 4 starts one in-process enrichment task after a Capture is committed.
The task uses the configured `OPENAI_MODEL`, sends the product-plan §11.5/§11.6
prompts through the Responses API, and requests strict Structured Outputs using
the contract in `contracts/enriched_capture.schema.json`. An identical packaged
copy under `app/schemas/` keeps wheel installations self-contained; an automated
wheel smoke test prevents the two checked-in copies from drifting.

Provider calls use a 45-second timeout with SDK retries disabled so one attempt
cannot outlive the approximately 60-second client polling window. Responses
must report `completed`; incomplete results are stored as a safe retryable
provider error rather than accepted as ready data.

If OpenAI is not configured, creation still returns the persisted `processing`
representation and the background task moves the stored Capture to a visible
`error` state without changing source content. After configuring the untracked
root `.env`, retry a failed Capture with:

```bash
curl --request POST http://127.0.0.1:8765/v1/captures/{id}/enrich
```

The retry response is HTTP `202`. Poll the detail route every one to two seconds
until status becomes `ready` or `error`, stopping after approximately 60 seconds.
Concurrent attempts return the stable `capture_already_processing` error.

The P0 runner is deliberately in-process. It does not add Redis, Celery,
WebSockets, or a durable queue; see decision D-014.

## Chrome extension CORS

Layer 6 accepts cross-origin requests only from exact origins listed in
`RECALL_CORS_ORIGINS`. Wildcards and public web origins are rejected. After
loading the unpacked extension, copy its ID and configure the untracked root
`.env`, then restart the backend:

```text
RECALL_CORS_ORIGINS=chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

For a local browser harness, loopback origins such as
`http://127.0.0.1:3000` are also accepted. CORS permits only `GET`, `POST`, and
the `Content-Type` header, without credentials.

## Keyword search

Layer 5 exposes provider-independent FTS5 retrieval:

```bash
curl --get --data-urlencode 'q=WorkingDirectory' \
  --data-urlencode 'limit=20' \
  http://127.0.0.1:8765/v1/search
```

The response follows `contracts/api.md`. Through Layer 5, `score` equals the
normalized `keyword_score` and `semantic_score` is `null`. Empty or omitted `q`
returns recent Captures. Source text and user notes remain searchable when
OpenAI is absent or enrichment fails. Client input is escaped as FTS data, so
quotes and operators cannot become query syntax; see decision D-015.

## Test

```bash
.venv/bin/python -m pytest
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENAI_API_KEY` | unset | Enables later OpenAI layers when non-empty |
| `OPENAI_MODEL` | `gpt-5.6` | Later enrichment model |
| `OPENAI_EMBEDDING_MODEL` | `text-embedding-3-small` | Later embedding model |
| `RECALL_HOST` | `127.0.0.1` | Loopback-only bind host |
| `RECALL_PORT` | `8765` | Backend port, from 1 through 65535 |
| `RECALL_DATABASE_PATH` | `./data/recall.db` | SQLite file, relative to repository root |
| `RECALL_LOG_LEVEL` | `INFO` | Python logging level |
| `RECALL_CORS_ORIGINS` | unset | Comma-separated allowed origins for a later client layer |
