# Mema backend

Mema's backend is a loopback-only FastAPI service. It owns the shared Capture
contract, SQLite/FTS5 persistence, local image attachments, OpenAI enrichment,
embeddings, and hybrid retrieval.

## Requirements and install

Use Python 3.10 or later. From the repository root, the recommended setup and
startup command is:

```bash
./scripts/dev.sh
```

It creates `services/backend/.venv`, installs or refreshes dependencies,
validates configuration, refuses unsafe bind addresses, starts the service, and
waits for database health. Press `Control-C` to stop it.

Manual setup from `services/backend/`:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m mema_backend
```

Verify from another terminal:

```bash
curl --fail http://127.0.0.1:8765/health
```

The service starts without `.env` or an OpenAI key. Optional settings are read
from the ignored repository-root `.env` and then the shell environment; begin
with `.env.example` when overrides are needed.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENAI_API_KEY` | unset | Enables cloud enrichment, OCR, image understanding, and semantic retrieval |
| `OPENAI_MODEL` | `gpt-5.6` | Text enrichment, screenshot OCR, and image understanding |
| `OPENAI_EMBEDDING_MODEL` | `text-embedding-3-small` | Capture and query vectors |
| `MEMA_HOST` | `127.0.0.1` | Must be localhost or a loopback IP |
| `MEMA_PORT` | `8765` | Local service port |
| `MEMA_DATABASE_PATH` | `./data/mema.db` | SQLite file, relative to the repository root in source runs |
| `MEMA_ATTACHMENTS_PATH` | sibling `attachments/` | Application-owned PNG/JPEG directory |
| `MEMA_LOG_LEVEL` | `INFO` | Python log level |
| `MEMA_CORS_ORIGINS` | unset | Comma-separated exact Chrome-extension or loopback origins |

Public/LAN bind addresses, wildcard CORS, public web origins, malformed Chrome
IDs, overlapping database/attachment paths, and invalid ports are rejected at
startup.

## Judge API path

Create the checked-in example:

```bash
curl --header 'Content-Type: application/json' \
  --data-binary @contracts/examples/capture-request.json \
  http://127.0.0.1:8765/v1/captures
```

If running the command from `services/backend/`, use
`@../../contracts/examples/capture-request.json` instead. Use the returned ID:

```bash
curl http://127.0.0.1:8765/v1/captures/{id}
curl 'http://127.0.0.1:8765/v1/captures?limit=50&offset=0'
curl --get --data-urlencode 'q=distinctive phrase' \
  http://127.0.0.1:8765/v1/search
```

Without a key, the source is still persisted and keyword-searchable while the
asynchronous enrichment layer reports a recoverable provider error. After a
key is configured, explicitly retry with:

```bash
curl --request POST http://127.0.0.1:8765/v1/captures/{id}/enrich
```

See [`../../contracts/api.md`](../../contracts/api.md) for every route, limit,
error envelope, and lifecycle transition.

## Persistence and migrations

Numbered SQL files in `mema_backend/migrations/` run transactionally before
repository access. They create the Capture, FTS5, attachment, user-edit, and AI
state needed by the current API. A database containing unknown later migrations
is rejected instead of being opened by older code.

Database files are created as `0600`; new storage directories are `0700`.
Original PNG/JPEG bytes are application-owned files rather than SQLite blobs.
Back up the stopped database and attachment directory together. Do not copy a
live WAL-mode database in isolation.

Application code accesses records through `mema_backend.repository`. HTTP
handlers do not issue ad-hoc SQL, and AI update methods cannot overwrite
captured source or personal notes.

## OpenAI boundary

Text enrichment uses the Responses API with strict Structured Outputs from the
packaged schema in `mema_backend/schemas/`. The same boundary is reused for
opt-in image analysis. Screenshot OCR is a one-shot vision request that stores
no Capture or image by itself. Every Responses request sets `store: false`, has
a bounded timeout with SDK retries disabled, and must finish as `completed`.

Provider output is validated again for completeness, limits, generic content,
refusal, and schema conformance. Failure preserves the original Capture in a
visible retryable state. Embeddings are independent; FTS5 and bounded literal
fallback remain available without a vector provider.

`POST /v1/image-captures` persists a validated image and Capture first. Cloud
analysis occurs only when `analyze_image: true`. `DELETE /v1/captures/{id}`
removes the Capture, search metadata, attachment row, and local file. Attachment
bytes use an opaque content path and `Cache-Control: no-store`.

## Chrome extension access

After loading the unpacked extension, copy its ID and put the exact origin in
the ignored root `.env`:

```text
MEMA_CORS_ORIGINS=chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

Restart the backend. CORS permits only `GET`, `POST`, `PATCH`, and `DELETE`, the
`Content-Type` header, and no credentials. Requests carrying a disallowed
`Origin` are rejected before routing, including simple multipart writes.

## Test and stress paths

From `services/backend/`:

```bash
.venv/bin/python -m pytest
.venv/bin/python tools/stress_backend.py
.venv/bin/python -m pip check
```

The deterministic stress runner uses temporary databases and provider doubles;
it never calls OpenAI. It covers malformed/oversized payloads, concurrency,
idempotent retries, migrations, provider failures, CORS, search fallbacks, and
restart recovery. The initial hardening snapshot is preserved in
[`../../docs/backend-stress-report-2026-07-18.md`](../../docs/backend-stress-report-2026-07-18.md).

## Installed-package smoke path

The package includes a `mema-backend` console command plus its schemas and SQL
migrations:

```bash
python3 -m pip install ./services/backend
mema-backend
```

An installed build treats its launch directory as the default data/config root.
The packaging test builds a wheel, installs it into an isolated target, starts a
real `TestClient`, checks health, and verifies resource availability.
