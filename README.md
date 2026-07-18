# capture
# Recall

Recall is a macOS personal-memory capture tool that preserves source material,
the user's reason for saving it, and an AI-generated contextual interpretation
as separate, searchable layers.

The repository contains the Layer 0–5 backend foundation plus locally verified
Layer 6 Chrome capture and Layer 7 hybrid-retrieval implementations. Their
shared manual Chrome/macOS and live OpenAI gates remain explicitly open.

The current `main` tree intentionally holds only shared documentation,
contracts, examples, and root metadata. Implementation code is separated by
layer; see [`docs/branch-layout.md`](docs/branch-layout.md) for the exact branch
map and integration consequence.

## Product baseline

The authoritative Build Week scope and execution plan is
[`docs/product-plan.md`](docs/product-plan.md). Any requirement or technical
choice introduced beyond that baseline must be highlighted in
[`docs/decisions.md`](docs/decisions.md) before implementation.

## Core workflow

```text
Capture source text and optional user note
→ persist the original Capture immediately
→ enrich it asynchronously with Structured Outputs
→ generate an embedding from the stable §12.1 text projection
→ retrieve it through keyword and semantic search
```

## Layer 0 contracts

- [`contracts/capture.schema.json`](contracts/capture.schema.json): client
  Capture creation payload.
- [`contracts/enriched_capture.schema.json`](contracts/enriched_capture.schema.json):
  model-generated enrichment payload.
- [`contracts/api.md`](contracts/api.md): localhost API, lifecycle, response,
  error, and search contracts.
- [`contracts/examples/`](contracts/examples/): handoff fixtures shared by the
  backend, macOS, and Chrome-extension owners.
- [`docs/architecture.md`](docs/architecture.md): system boundaries, ownership,
  and dependency direction.
- [`docs/decisions.md`](docs/decisions.md): accepted decisions and additions to
  the product baseline.
- [`docs/developer-b-checklist.md`](docs/developer-b-checklist.md): live build
  checklist, exit gates, validation evidence, and blocker log.
- [`docs/branch-layout.md`](docs/branch-layout.md): implementation branch tips,
  dependency relationships, and the definition of central files on `main`.

## Planned stack

- SwiftUI and AppKit macOS application
- Manifest V3 Chrome extension
- Python and FastAPI localhost backend
- SQLite with FTS5
- OpenAI Responses API with Structured Outputs
- OpenAI embeddings with local cosine-similarity search

## Environment

The backend starts without `.env` or an API key. Copy `.env.example` to `.env`
only for local overrides, and never commit `.env` or an API key. Installation,
start, health-check, test, and configuration instructions live with the backend
on the implementation branches listed in
[`docs/branch-layout.md`](docs/branch-layout.md).

While the backend is running, the live Developer B checklist is available at
[`http://127.0.0.1:8765/dev/checklist`](http://127.0.0.1:8765/dev/checklist).
It refreshes directly from the checked-in Markdown source every two seconds.

## Status

Layers 0–5 backend work is pushed. Layers 6 and 7 are implemented, verified,
and committed on local branches but are not yet pushed. The documentation-only
`main` change is also local. The unpacked-Chrome-to-macOS confirmation, real
OpenAI provider proof, and complete team integration remain open; none is
represented as complete. A validated local `integration/layers-6-7` branch
combines Developer B's Chrome and retrieval deltas but not Developer A's macOS
client. Live evidence and blockers are tracked in
[`docs/developer-b-checklist.md`](docs/developer-b-checklist.md).
