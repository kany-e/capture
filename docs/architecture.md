# Recall architecture baseline

Status: Accepted for Build Week

Last updated: 2026-07-18

This document translates the product baseline into system boundaries and
handoffs. It does not replace [`product-plan.md`](product-plan.md).

## System shape

```text
Chrome extension ─┐
                  ├─ HTTP JSON on 127.0.0.1:8765 ─ Local FastAPI backend
macOS application ┘                              ├─ SQLite / FTS5
                                                  ├─ OpenAI Responses API
                                                  └─ OpenAI Embeddings API
macOS screenshot ── explicit choice ──────────────┬─ GPT OCR via backend
                                                  └─ Apple Vision on device
```

The backend is the only component that persists Captures, calls OpenAI, builds
the full-text index, generates embeddings, or calculates hybrid-search scores.
The macOS app and Chrome extension are API clients.

After the baseline workflow is stable, an optional Apple on-device enrichment
provider may run inside the macOS app and return the same structured enrichment
payload to the backend. This is a gated demonstration path documented in
decision D-008, not part of the P0 critical path.

Decision D-027 adds a narrower, explicit screenshot-to-note path after the
baseline became stable. Screenshot bytes exist only in the macOS draft and the
one GPT request when that extractor is selected. Apple Vision processes the
same draft entirely on device. Both paths produce editable text that enters the
existing Capture API and storage/retrieval pipeline; neither creates an image
store or a second notes database.

Decision D-028 defines the opt-in Chrome inline-capture boundary. Phase 2 now
dynamically registers an isolated content script only after optional HTTP and
HTTPS access is granted. A transient selection action and comment composer hand
one frozen capture attempt to a shared extension service worker; the toolbar and
keyboard popup use the same coordinator. B-014 retains the real unpacked-Chrome
permission, localhost delivery, macOS display, and revocation gate. Phase 3 is
still planned: an explicit browser region command may send one transient crop
to the existing GPT OCR endpoint. Chrome cannot observe arbitrary macOS
screenshots, and Apple Vision remains in the native application. See
[`browser-inline-capture-spec.md`](browser-inline-capture-spec.md).

## Ownership

### Developer A — Capture and experience

Owned paths:

- `apps/macos/`
- `docs/demo-script.md`

Responsibilities:

- SwiftUI/AppKit application and menu bar
- Clipboard capture and quick-save window
- Capture list, detail, search, and processing/error states
- Demo interaction and visual consistency

### Developer B — Intelligence and data

Owned paths:

- `services/backend/`
- `apps/chrome-extension/`
- `contracts/`

Responsibilities:

- FastAPI, SQLite, and API behavior
- OpenAI Structured Outputs and enrichment failure handling
- Embeddings, FTS5, and hybrid search
- Chrome selection/context capture and localhost delivery
- Opt-in inline-capture permission flow, extension service worker, and browser
  region capture under D-028

### Shared

- Capture and enrichment contracts
- Prompt quality and representative fixtures
- End-to-end integration, README, tests, demo, and submission materials

Contract changes require both developers to agree before implementation.

## Core data boundaries

Every Capture keeps three independent layers:

1. **Source** — selected text, surrounding context, URL, title, and source app.
2. **User note** — the user's personal reason, situation, or caution.
3. **AI interpretation** — title, summary, problem, key insight, inferred reason,
   caveats, tags, entities, and search aliases.

The AI interpretation may refer to the other layers but must never overwrite
them. The original Capture is committed before enrichment begins.

## Capture lifecycle

```text
client request
→ persist original Capture
→ processing
→ Structured Output enrichment
→ embedding generation
→ FTS synchronization
→ ready
```

Failure rules:

- A model or embedding failure never deletes the source or user note.
- Enrichment failure produces `error` plus a retryable error message.
- Startup converts processing work orphaned by a previous process exit into a
  visible, retryable `error` without changing the source or user note.
- Embedding failure may leave a text-enriched Capture searchable through FTS.
- The MVP uses polling, not WebSockets.

## Contract boundary

- Capture input: `contracts/capture.schema.json`
- AI enrichment output: `contracts/enriched_capture.schema.json`
- Transport and full response shapes: `contracts/api.md`
- Cross-client fixtures: `contracts/examples/`

The schemas reject unknown fields. Contract evolution is intentional and must
be recorded in `docs/decisions.md`.

## Embedding projection

Only `ready` Captures are embedded. The projection follows product-plan §12.1
exactly and is documented as a byte-stable construction in
`contracts/api.md`. Its order or labels must not change without incrementing
`enrichment_version`, rebuilding stored embeddings, and recording a decision.

## Build order

The baseline dependency order remains below. Delivery is currently executing
Layer 7 before Layer 6 by explicit user direction under D-016; this does not
remove the Chrome workflow or change ownership.

1. Contracts and documentation (Layer 0).
2. Backend configuration and health check.
3. SQLite persistence and Capture CRUD.
4. macOS integration for the first vertical slice.
5. Structured enrichment and FTS5.
6. Chrome capture.
7. Embeddings and hybrid retrieval.
8. Reliability, demo fixtures, and demo-readiness gate.
9. Optional Apple on-device provider experiment, only if all gates pass.
10. Final freeze, documentation, stable tag, and submission.

No P1 or P2 feature begins before the three product-plan vertical slices work.

## Explicit non-goals for the submission

- Cloud sync, accounts, or team collaboration
- External vector databases
- Redis, Celery, or a durable distributed queue
- WebSockets
- General OCR, persistent image memories, image/chart understanding, or
  full-page offline snapshots. D-027 is the bounded text-only screenshot
  exception; it does not retain the image.
- Multi-agent orchestration
- Production App Store packaging and notarization
