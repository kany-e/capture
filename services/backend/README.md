# Recall backend

The backend is a local-only FastAPI service. It provides validated
configuration, health, transactional SQLite persistence, Capture CRUD,
Structured Output enrichment, FTS5, embeddings, and hybrid retrieval. It also
provides the D-027 one-shot GPT screenshot text-extraction boundary and D-037
persisted image notes with optional background visual indexing.

Run all commands below from `services/backend/`.

## Install

Use Python 3.10 or later. Check `python3 --version` before creating the virtual
environment; Apple's system Python may be older than this project's declared
minimum. On Apple Silicon with Homebrew, `/opt/homebrew/bin/python3` is a
typical compatible interpreter path.

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

From the repository root, the recommended one-command startup is:

```bash
./scripts/dev.sh
```

It creates `services/backend/.venv` when missing, installs dependencies when
needed, validates the environment-backed configuration, refuses to start over an
unhealthy process already using the configured port, waits up to ten seconds for
a healthy database, and prints the health and live-checklist URLs. It never
prints an API key. Press `Control-C` to stop the backend. Set `PYTHON_BIN` only
when `python3` is not the intended Python 3.10+ interpreter.

To start the already-installed backend manually from `services/backend/`:

```bash
.venv/bin/python -m app
```

In another terminal:

```bash
curl --fail --silent http://127.0.0.1:8765/health
```

Without an API key, the expected response is:

```json
{"status":"ok","database":"ok","attachments":"ok","openai_configured":false}
```

The health probe creates the configured SQLite file and attachment directory if
needed, verifies every migration, checks SQLite integrity/decodability, and
requires the attachment directory to be readable and writable.

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

Migration 003 transactionally expands `source_type` with `screenshot`, preserves
every existing Capture column, and rebuilds/backfills the same FTS table and
triggers. It does not add an image/blob column.

Migration 004 adds normalized `capture_attachments` metadata with a cascading
foreign key. Original PNG/JPEG bytes remain filesystem files under
`RECALL_ATTACHMENTS_PATH`; they are not SQLite blobs. Back up the database and
attachment directory together while the backend is stopped. Older code that
knows only migrations 001–003 will reject a database after migration 004, so a
rollback requires restoring both the pre-004 database and matching attachment
snapshot rather than checking out old code alone.

Migration 005 adds user source/organization overrides, `user_edited_at`, and AI
visibility/staleness state. It recreates and backfills the FTS triggers so
effective user-visible values take precedence while captured and AI columns
remain intact. Back up a stopped database before upgrading; a rollback requires
restoring that pre-005 database rather than checking out older code against the
new schema.

Migration 003 is forward-only for this build: older code knows only migrations
001–002 and will refuse a database that has applied 003. Before the first run of
this version against an existing `data/recall.db`, stop the backend and create a
consistent SQLite backup. A code rollback must restore that pre-003 database as
well as checkout the pre-feature tag; checking out old code alone is not a valid
rollback.

The integration backup was created while port 8765 was stopped and verified
with SQLite `integrity_check=ok` and schema versions `1,2`:

- ignored local backup: `data/backups/recall-pre-migration-003-20260720.db`
- annotated Git tag at `62d8c56`: `rollback/pre-screenshot-ocr`

To roll back after migration 003, first stop the backend completely and verify
that no `data/recall.db-wal` or `data/recall.db-shm` file is active. Preserve the
post-migration database under a new filename in `data/backups/`, copy the exact
pre-migration backup back to `data/recall.db`, and switch code to the annotated
tag. Do not overwrite either database copy. Run `PRAGMA integrity_check` and
confirm schema versions `1,2` before starting the old backend. The local backup
contains private Recall data, is mode `0600`, and must never be committed or
shared.

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

## Screenshot text extraction

`POST /v1/ocr` accepts one base64-encoded PNG or JPEG, up to 8 MiB decoded,
and uses `OPENAI_MODEL` for a single high-detail Responses API vision request.
The successful response includes extracted text plus explicit `openai`, `cloud`,
and model metadata so the macOS UI can distinguish it from Apple Vision.

The route normalizes line endings but never silently truncates text. It rejects
malformed or mismatched image data, empty/refused/incomplete provider output,
and text larger than the 12,000-character selected-source contract. A missing
key returns the stable `openai_not_configured` response and points the user to
the on-device choice. The route does not create a Capture or store the image;
after the user reviews the source text, the macOS client submits it separately
from any optional personal note through the ordinary `POST /v1/captures` flow.

## Persisted image notes

`POST /v1/image-captures` receives one multipart PNG/JPEG plus JSON metadata.
The backend validates signature, media type, byte/dimension/pixel limits, writes
the original under an application-generated UUID path, and commits one linked
Capture. V1 stores at most one attachment per Capture. Retrying the same
`client_capture_id` returns the first Capture and removes the unused retry file.

`analyze_image: false` produces a local `ready` image note without sending the
image to OpenAI. With explicit opt-in, `analyze_image: true` persists first and
then uses one background multimodal Structured Outputs request. OCR fills the
ordinary `selected_text`; visual title, summary, entities, tags, caveats, and
aliases fill the established AI fields and feed the existing FTS/embedding
pipeline. The request sets `store: false`; provider data policies still apply.
Provider failure preserves the original and user note in a retryable `error`
record.

Clients fetch bytes from the opaque `content_path` returned in `attachments`.
`DELETE /v1/captures/{id}` removes Capture/FTS/embedding/attachment metadata and
then its referenced local files. Filesystem paths are never accepted from or
returned to clients.

## Editable memories

`PATCH /v1/captures/{id}` stores explicit user corrections separately from
captured and model-generated columns. Source/note changes mark the previous AI
layer stale and hidden; title/detail/tag-only organization stays current and
takes display/FTS precedence. Every edit updates `user_edited_at`, clears the
potentially stale embedding, and leaves trigger-synchronized keyword search
ready immediately. Editing is rejected while a Capture is processing.

`GET /v1/captures` accepts `created_desc`, `created_asc`, `edited_desc`, and
`edited_asc`. An explicit `POST /v1/captures/{id}/enrich` uses the corrected
effective source, replaces only AI fields, and retains user organization
overrides; no edit automatically calls a provider.

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

Every provider result is revalidated at the service boundary. Empty, `null`,
partial, generic, or oversized model output is classified as
`invalid_model_output` and moves the Capture to a terminal `error` state with a
safe message; it cannot produce an empty `ready` Capture or leave one stuck in
`processing`. This same rule applies to a future Apple/local provider.

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

If the process exits during enrichment, the next successful backend startup
atomically changes every orphaned `processing` Capture to `error` with a safe
restart message. Source text and the user note remain unchanged and searchable;
use the existing enrichment endpoint or **Retry AI** in the macOS app to continue.

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
`DELETE` plus the `Content-Type` header, without credentials.

## Embeddings and hybrid search

Layer 5 provides provider-independent FTS5 retrieval, and Layer 7 adds
embeddings and in-memory hybrid ranking:

```bash
curl --get --data-urlencode 'q=WorkingDirectory' \
  --data-urlencode 'limit=20' \
  http://127.0.0.1:8765/v1/search
```

After enrichment validates, the backend builds the exact §12.1 projection and
stores one vector as an internal SQLite JSON array. Search embeds a non-empty
query with the same configured model, calculates cosine similarity using a
write-invalidated normalized-vector cache, and combines semantic, normalized
keyword, and metadata scores. Normal queries use `0.55 / 0.35 / 0.10`;
technical identifiers use `0.45 / 0.50 / 0.05`.

The response follows `contracts/api.md`. Empty or omitted `q` returns recent
Captures. If OpenAI, the query vector, or a Capture vector is unavailable,
Layer 5 FTS behavior remains available and `semantic_score` is `null` for the
affected result. Client input is escaped as FTS data, so quotes and operators
cannot become query syntax. Search queries are capped at 512 characters and
control characters are rejected. If strict all-term FTS produces no rows, a
relaxed any-term pass keeps provider-off natural-language retrieval usable. A
bounded literal-substring pass is merged with tokenized candidates to recover
partial identifiers and CJK fragments that FTS may omit. Results are deduped
under the existing candidate cap and FTS-ranked rows retain priority; see
decisions D-015, D-021, and D-024.

## Test

```bash
.venv/bin/python -m pytest
```

## Destructive-in-temp stress test

The deterministic stress harness uses only temporary SQLite databases and
local provider doubles; it never calls OpenAI:

```bash
.venv/bin/python tools/stress_backend.py
```

It exercises malformed and oversized payloads, duplicate and ambiguous cards,
bulk and concurrent writes, FTS edge cases, provider failures, realistic vector
dimensions, corrupt rows, CORS, and restart durability. The dated findings and
known limitations are recorded in
`../../docs/backend-stress-report-2026-07-18.md`.

The harness prints every observation before exiting. It returns a nonzero status
when no observations ran or any outcome is not `pass`, so CI cannot report a
false green result after a recorded break.

The post-hardening scenarios still pass 44/44 after startup-recovery and clean-
start work. The integrated baseline had 190 passing Python tests; the current
feature-branch count is recorded in `docs/developer-b-checklist.md` after every
full-suite run. Counts 181 and 186 remain historical hardening/integration
checkpoints.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENAI_API_KEY` | unset | Enables OpenAI enrichment, GPT screenshot extraction, and embeddings when non-empty |
| `OPENAI_MODEL` | `gpt-5.6` | Enrichment and GPT screenshot-extraction model |
| `OPENAI_EMBEDDING_MODEL` | `text-embedding-3-small` | Capture and query embedding model |
| `RECALL_HOST` | `127.0.0.1` | Loopback-only bind host |
| `RECALL_PORT` | `8765` | Backend port, from 1 through 65535 |
| `RECALL_DATABASE_PATH` | `./data/recall.db` | SQLite file, relative to repository root |
| `RECALL_ATTACHMENTS_PATH` | database sibling `attachments/` | Application-owned original image directory; must not contain or be contained by the database path |
| `RECALL_LOG_LEVEL` | `INFO` | Python logging level |
| `RECALL_CORS_ORIGINS` | unset | Comma-separated exact origins allowed for the Chrome client |
