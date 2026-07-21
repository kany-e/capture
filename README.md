# Recall

[![CI](https://github.com/CamaroW/capture/actions/workflows/ci.yml/badge.svg)](https://github.com/CamaroW/capture/actions/workflows/ci.yml)

Recall is a local-first macOS personal-memory tool. It preserves source
material, the user's reason for saving it, and an AI-generated contextual
interpretation as separate, searchable layers.

This repository now contains the complete integrated product tree:

- `apps/macos/` — SwiftUI/AppKit clipboard and screenshot-note capture,
  library, detail, lifecycle, and search client;
- `apps/chrome-extension/` — build-free Manifest V3 web capture extension;
- `services/backend/` — loopback FastAPI API, SQLite/FTS5 storage, OpenAI
  enrichment, embeddings, and hybrid retrieval;
- `contracts/` — shared request, response, and schema contracts; and
- `docs/` — product plan, architecture, decisions, handoffs, and validation
  records.

The earlier documentation-only `main` arrangement is retired by D-023.
`main` is again the canonical runnable integration target. Historical layer
branches remain useful as development checkpoints, but they are not separate
runtime dependencies.

## Product direction

The original Build Week scope and execution plan is
[`docs/product-plan.md`](docs/product-plan.md). Current priorities are tracked in
[`docs/roadmap.md`](docs/roadmap.md), and accepted additions or implementation
clarifications are recorded in [`docs/decisions.md`](docs/decisions.md).

## Core workflow

```text
Capture source text and an optional user note
→ persist the original Capture immediately
→ enrich it asynchronously with Structured Outputs
→ generate an embedding from the stable §12.1 text projection
→ retrieve it through keyword and semantic search
```

The screenshot-note addition follows the same pipeline: select a screen region,
choose the default **GPT · Cloud** extractor or **Apple Vision · On device**,
then explicitly extract source text and optionally add the personal context only
you know. Those remain separate Capture fields. Recall never writes screenshot
bytes to SQLite; the macOS selection tool uses a random OS temporary PNG that is
removed in the normal flow, and closing the draft clears its in-memory preview.

## Start the backend

The backend starts safely without an OpenAI key. From the repository root, the
recommended clean-start command creates or repairs the local environment, checks
configuration and dependencies, starts the service, waits for health, and prints
the local engineering URLs:

> **Migration 003 boundary:** the screenshot build upgrades an existing database
> on first start. Preserve a pre-upgrade database backup before starting this
> version; the matching code rollback point is
> `rollback/pre-screenshot-ocr`. See the backend README before replacing or
> moving a database.

```bash
./scripts/dev.sh
```

The equivalent manual setup is:

```bash
cd services/backend
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m app
```

Confirm it from another terminal:

```bash
curl --fail http://127.0.0.1:8765/health
```

Copy `.env.example` to the untracked root `.env` only when local overrides or
an OpenAI key are needed. Never commit or transmit `.env` or an API key.
Complete backend setup and test commands are in
[`services/backend/README.md`](services/backend/README.md).

While the backend is running, the live engineering checklist is available at
[`http://127.0.0.1:8765/dev/checklist`](http://127.0.0.1:8765/dev/checklist).

## Run the macOS app

Open [`apps/macos/Recall.xcodeproj`](apps/macos/Recall.xcodeproj) in Xcode,
select the shared **Recall** scheme and **My Mac**, then run the app. Keep the
backend running at `127.0.0.1:8765`. Detailed build commands and the manual test
matrix are in [`apps/macos/README.md`](apps/macos/README.md). Run the complete
macOS test bundle reliably from the repository root with
`./scripts/test-macos.sh`.

## Load the Chrome extension

Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**,
and select `apps/chrome-extension/`. The backend accepts only explicitly
configured Chrome-extension origins; follow
[`apps/chrome-extension/README.md`](apps/chrome-extension/README.md) to add the
generated origin to the untracked root `.env` and restart the backend.

The browser client currently saves selected text (when present), page title,
URL, and the optional personal note. It deliberately sends no surrounding page
context: broad DOM containers on conversation-style sites can mix navigation
and unrelated turns into one Capture. The shared API still supports bounded
context for other clients and future, selection-centered browser extraction.

## Contracts and architecture

- [`contracts/api.md`](contracts/api.md) defines HTTP paths, lifecycle,
  envelopes, error codes, limits, and search results.
- [`contracts/capture.schema.json`](contracts/capture.schema.json) defines
  client Capture creation input.
- [`contracts/enriched_capture.schema.json`](contracts/enriched_capture.schema.json)
  defines provider-generated enrichment output.
- [`docs/architecture.md`](docs/architecture.md) defines system boundaries and
  ownership.
- [`docs/roadmap.md`](docs/roadmap.md) defines current priorities and replaces
  historical Developer A/B roles with component ownership.
- [`docs/branch-layout.md`](docs/branch-layout.md) records how the historical
  implementation branches were integrated.
- [`docs/backend-stress-report-2026-07-18.md`](docs/backend-stress-report-2026-07-18.md)
  records the first full backend stress audit and remediation evidence.

## Continuous integration

Every pull request targeting `main` runs independent backend, deterministic
stress, Chrome-extension, and macOS/Xcode jobs. A final **Required checks** job
fails unless every layer passes. The workflow has read-only repository access,
does not receive `.env` or an OpenAI key, and never performs a real provider
call. Real GPT, Screen Recording permission, and interactive screenshot flows
remain explicit manual release gates.

## Current status

The hardened backend, Chrome extension, and macOS client have been assembled and
verified in one integration tree. Baseline counts were 190 backend tests,
all 44 deterministic stress scenarios, 16 extension tests, and 27 macOS tests.
The screenshot-note hardening tree passes 214 backend tests, 44/44 stress
scenarios, 16 extension tests, and 43 macOS tests, including the production
Apple Vision extractor.

Opt-in inline browser capture was merged through PR #8 at merge commit
`71ec387`. Its 68 extension tests cover the permission, retry, revocation, and
toolbar-fallback boundaries described below.

Real unpacked-Chrome verification covers opt-in on an already-open page, exact
Unicode source/note persistence, offline retry, Escape and editable-page
compatibility, immediate revocation, BFCache return after revocation, and the
toolbar fallback; the resulting cards were also verified in the macOS app.

The current D-030 browser-context and display hardening keeps the browser suite
at 68 tests. Inline capture now shows a separate Unicode-aware selection count
and a keyboard-scrollable selection preview, while the action popup uses a
smaller, internally scrollable layout. Both Chrome entry points temporarily
omit surrounding context. Existing stored context is neither migrated nor
deleted: the macOS detail view hides it by default and, when requested, renders
at most 2,000 characters and 60 lines while retaining the complete value for
search and AI processing. This boundary expands the macOS suite from 43 to 48
tests; the current branch passes all 48 alongside 68/68 extension tests.

Live verification covers provider-off keyword fallback, real OpenAI enrichment
and embeddings, semantic retrieval with a non-null score, and both selected-text
and no-selection Chrome Captures appearing as ready cards in the macOS app.

The shared P0 integration gates B-007, B-008, and B-009 are resolved. Layer 10
submission work such as screenshots, licensing, final tagging, and release
packaging remains intentionally separate from the runnable product integration.

Detailed current evidence and blockers are tracked in
[`docs/developer-b-checklist.md`](docs/developer-b-checklist.md).
