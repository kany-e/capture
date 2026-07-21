# Recall architecture baseline

Status: Accepted baseline; current priorities are tracked in
[`roadmap.md`](roadmap.md)

Last updated: 2026-07-21

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
baseline became stable. Screenshot content is held by the macOS draft and sent
in the one GPT request when that extractor is selected. Apple Vision processes
the same draft entirely on device. Both paths produce reviewed source text that
enters the existing Capture API and storage/retrieval pipeline while the user's
optional personal note stays independent; neither creates an image store or a
second notes database. The macOS system selection command briefly uses a random
OS temporary PNG and removes it after success, cancellation, or failure.

## Native global capture boundary

Decision D-031 adds native global screenshot and clipboard entry points without
changing the Capture pipeline or the app's ordinary lifecycle. Recall remains a
normal Dock application with its existing `MenuBarExtra`; it must be running,
but closing the main window does not destroy the app-level capture state.

```text
main-window controls ─┐
menu-bar commands ────┼─ GlobalCaptureCoordinator ─ capture preparation
Carbon hotkeys ───────┘                         └─ presentation request
                                                       │
MenuBarExtra label ─ CapturePresentationHost ──────────┘
                                                       ↓
                                             shared Quick Capture window
```

All three entry surfaces call the app-level `GlobalCaptureCoordinator`; views
do not prepare drafts or own screenshot tasks independently. A
`CapturePresentationHost` in the `MenuBarExtra` label observes coordinator
requests and opens the Quick Capture scene, so presentation does not depend on
the main-window scene being open.

`GlobalShortcutCenter` owns configuration, persistence, active registrations,
and errors. Its Carbon `RegisterEventHotKey` registrar needs neither
Accessibility nor Input Monitoring permission. Defaults are
`Option+Shift+Command+4` for screenshots and `Option+Shift+Command+C` for the
clipboard. Settings restricts keys to A–Z and 0–9 with Command, Option, Control,
and Shift, requires at least two modifiers per action, rejects duplicate action
bindings, supports enable/disable, and restores defaults.

Applying configuration is a whole-set transaction: unregister the old set,
install the proposed set, persist only on success, and remove any partial new
set plus restore the prior set on failure. Settings, the menu, and the menu-bar
label all derive failure visibility from the same shortcut center.

The interactive screenshot `Process` is awaited asynchronously and PNG reading
also occurs off the main actor. Cancellation terminates a running selection;
success, cancellation, and failure all remove the random temporary PNG. App
termination requests cancellation before deactivating hotkeys. One coordinator
task deduplicates rapid screenshot triggers, and store-level draft guards
preserve an existing or ambiguous-retry Quick Capture rather than silently
replacing it.

This boundary changes no API, schema, backend, database, extension, enrichment,
retrieval, or image-persistence behavior. Screenshot bytes remain limited to the
active draft, and the GPT/cloud versus Apple Vision/on-device disclosure remains
unchanged.

## Browser inline capture boundary

Decision D-029, merged through PR #8 in `71ec387`, adds an opt-in selected-text
surface without changing the backend contract. The extension keeps HTTP/HTTPS
website access in `optional_host_permissions`, leaves it disabled by default,
and declares no static content script. After explicit permission, the service
worker registers the isolated content script dynamically and injects it into
eligible tabs that are already open, so users do not need to refresh them.

Selection text stays inside the page until the user chooses Save. The content
script then sends one frozen attempt to the extension service worker; toolbar
and inline capture share the same validation, retry identity, and localhost
delivery coordinator. The page script never calls the backend directly.
Revoking access unregisters future injection and immediately asks already-open
tabs to remove Recall controls and listeners.

Decision D-030, merged through PR #9 at `0c1083e`, temporarily disables
browser-generated surrounding context in both entry points. With a selection,
Chrome submits up to the shared 12,000-
character limit plus title, URL, and optional note; text within that limit uses
the existing normalization but is not shortened, and a longer selection
receives an explicit UI warning. Without a selection, the toolbar submits title,
URL, and optional note. Because no context is sent, `context_truncated` remains
`false`. This is a client policy, not a contract removal: D-009 still allows
metadata-only Captures, and the API continues to accept up to 20,000 characters
of surrounding context from clients that can produce it safely.

The immediate boundary avoids broad SPA containers such as `main` or `body`.
A real Gemini record contained a 1,530-character selection but 19,144
characters and 1,912 newline characters of context because navigation and
conversation history shared that container. Any future browser context
extractor must start from the selected DOM Range, exclude navigation and hidden
regions, and apply independent character plus line/block limits. If it cannot
prove locality, it must fall back to no surrounding context rather than the
whole page.

An injected document becomes suspended on `pagehide`. If Chrome restores it
from the back-forward cache, it sends a read-only permission-status message and
resumes only after an explicit enabled response; denial or transport failure
removes the controller. The service worker also rechecks the optional permission
before delivering any content-script save, while toolbar saves remain available
without broad page access. This closes the cached-document window in which an
off-screen page could otherwise miss the revocation broadcast.

This boundary remains text-only. It does not persist page images or add an
attachment contract. The native D-027 screenshot flow likewise stores reviewed
OCR-derived text rather than an image attachment.

## Long-context display boundary

The backend keeps the complete persisted context for enrichment and retrieval;
D-030 does not migrate or delete existing rows. The native detail view treats
that value as potentially hostile to layout performance. Context is collapsed
by default with only its character count visible. On explicit expansion,
SwiftUI receives a display-only preview capped at the first 2,000 characters
and 60 lines. The full value remains on the Capture model for search and AI.

This display limit is separate from the 20,000-character transport contract.
It prevents the newest-record auto-selection plus an eager selectable `Text`
from repeatedly laying out a page-sized, newline-heavy string at app launch.

## Component ownership

Historical Developer A/B labels are retained in the execution log as provenance,
but current work is assigned by component rather than person.

### Native capture and experience

Owned paths:

- `apps/macos/`
- `docs/demo-script.md`

Responsibilities:

- SwiftUI/AppKit application and menu bar
- Carbon global shortcuts, settings, app-level capture coordination, and
  Quick Capture presentation
- Clipboard capture and quick-save window
- Capture list, detail, search, and processing/error states
- Demo interaction and visual consistency

### Browser capture

Owned paths:

- `apps/chrome-extension/`

Responsibilities:

- Chrome page selection, context, and inline interaction
- Browser permission and content-script boundaries
- Browser-to-localhost delivery and browser-specific validation

### Memory pipeline

Owned paths:

- `services/backend/`
- `contracts/`

Responsibilities:

- FastAPI, SQLite, and API behavior
- OpenAI Structured Outputs and enrichment failure handling
- Embeddings, FTS5, and hybrid search

### Shared

- Capture and enrichment contracts
- Prompt quality and representative fixtures
- End-to-end integration, README, tests, demo, and submission materials

Contract changes require review across every affected component before
implementation.

## Core data boundaries

Every Capture keeps three independent layers:

1. **Source** — selected text, optional surrounding context, URL, title, and
   source app. Current Chrome Captures intentionally omit surrounding context;
   the field remains a cross-client contract capability.
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
- Because the original Capture is committed first, an enrichment `error` when
  AI is unconfigured is not a capture failure; the exact source and note remain
  stored.
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

The baseline dependency order remains below as implementation history. All P0
layers are now integrated on `main`; active post-baseline work is ordered in
[`roadmap.md`](roadmap.md).

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
  exception; it does not add an image store.
- Multi-agent orchestration
- Production App Store packaging and notarization
