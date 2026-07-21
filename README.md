# Recall

[![CI](https://github.com/CamaroW/capture/actions/workflows/ci.yml/badge.svg)](https://github.com/CamaroW/capture/actions/workflows/ci.yml)

Recall is a local-first macOS personal-memory tool. It preserves source
material, the user's reason for saving it, and an AI-generated contextual
interpretation as separate, searchable layers.

This repository now contains the complete integrated product tree:

- `apps/macos/` — SwiftUI/AppKit Accessibility selection, clipboard, and
  screenshot-note capture, library, detail, lifecycle, and search client;
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
Capture source text or one original image, plus an optional user note
→ persist the original Capture immediately
→ optionally enrich it asynchronously with Structured Outputs
→ generate an embedding from the stable §12.1 text projection
→ retrieve it through keyword and semantic search
```

After selecting a screen region, choose **Text note** to keep the D-027 workflow:
extract with **GPT · Cloud** or **Apple Vision · On device**, review the result,
and save only text plus your separate note. Choose **Image note** to preserve the
original image and optionally add a note. Cloud image analysis has an
off-by-default master privacy control. When enabled, each new image defaults to
searchable background OCR and visual understanding, but you can turn it off for
that image before saving. When the master control is off, the per-image control
is disabled and images cannot be sent to OpenAI. SQLite stores attachment
metadata, not image blobs; original bytes live in the application-owned
attachments directory.

## Start the backend

The backend starts safely without an OpenAI key. From the repository root, the
recommended clean-start command creates or repairs the local environment, checks
configuration and dependencies, starts the service, waits for health, and prints
the local engineering URLs:

> **Migration 004 boundary:** the image-note build adds attachment metadata on
> first start. Preserve a pre-upgrade database backup before starting this
> version; migration 003's matching historical rollback point is
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

Interactive screenshot-permission testing requires a stable Apple Development
signature. Copy `apps/macos/Config/Signing.local.xcconfig.example` to the
gitignored `Signing.local.xcconfig`, enter the certificate's actual Team ID,
build normally, and verify the resulting app with
`./scripts/verify-macos-signing.sh`. Do not commit a personal Team ID.
`CODE_SIGNING_ALLOWED=NO` is reserved for deterministic automation and cannot
prove Screen Recording authorization. The macOS README documents the one-time
reset and reauthorization needed when migrating from an earlier ad-hoc build.

Recall remains a normal Dock app and also keeps its existing menu-bar extra.
While the app is running, global selection, screenshot, and clipboard capture
default to `Option+Shift+Command+S`, `Option+Shift+Command+4`, and
`Option+Shift+Command+C`; they remain available when the main window is closed.
Capture Selection reads the focused external app's selected text only after the
shortcut, then opens the existing review window near that selection. It requires
macOS Accessibility access. Carbon hotkey registration itself, clipboard
capture, and screenshot capture do not require Accessibility or Input Monitoring
permission. Configure, disable, or restore all three actions in **Settings >
Global capture shortcuts**. An off-by-default **Clipboard Compatibility Mode**
can handle custom-drawn apps such as WeChat that can copy a selection but do not
expose selected text or even a focused control to Accessibility. It temporarily
sends Copy twice to the verified frontmost application, binds to the exact AX
control when one is available, requires matching results, and makes a best-effort
restoration. Recall blocks Secure Event Input and known secure/protected controls,
but custom-drawn apps may omit per-control safety attributes. macOS exposes neither clipboard-writer identity
nor an atomic restore, so rare races or a very delayed Copy can still change the
clipboard; history tools or Universal Clipboard may also record the transient
copies.

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
remain explicit manual release gates. The physical global hotkeys and the
global screenshot path also require a final run from the stably signed app.
CI may intentionally disable code signing for deterministic tests, so a green
macOS job is not TCC acceptance evidence. The current stable build has passed
that real-device gate; future release candidates must repeat it.

## Current status

The hardened backend, Chrome extension, and macOS client have been assembled and
verified in one integration tree. Baseline counts were 190 backend tests,
all 44 deterministic stress scenarios, 16 extension tests, and 27 macOS tests.
The screenshot-note checkpoint passed 214 backend tests, 44/44 stress
scenarios, 16 extension tests, and 43 macOS tests, including the production
Apple Vision extractor.

Opt-in inline browser capture was merged through PR #8 at merge commit
`71ec387`. Its 68 extension tests cover the permission, retry, revocation, and
toolbar-fallback boundaries described below.

Real unpacked-Chrome verification covers opt-in on an already-open page, exact
Unicode source/note persistence, offline retry, Escape and editable-page
compatibility, immediate revocation, BFCache return after revocation, and the
toolbar fallback; the resulting cards were also verified in the macOS app.

The D-030 browser-context and display hardening keeps the browser suite at 68
tests. Inline capture now shows a separate Unicode-aware selection count
and a keyboard-scrollable selection preview. D-033 corrects the action popup's
self-sizing regression with an explicit 344 × 510 root and an internally
scrollable shell; selected and metadata-only states are real-Chrome verified.
Both Chrome entry points temporarily
omit surrounding context. Existing stored context is neither migrated nor
deleted: the macOS detail view hides it by default and, when requested, renders
at most 2,000 characters and 60 lines while retaining the complete value for
search and AI processing. This boundary expands the macOS suite from 43 to 48
tests. PR #9 merged D-030 into `main` at `0c1083e` after all required checks
passed.

D-031 adds configurable native global screenshot and clipboard capture without
changing the API, schemas, backend, extension, or screenshot privacy boundary.
Registration changes are transactional, failures remain visible in the menu
bar, its status icon, and Settings, and existing drafts are never silently
replaced. Screenshot process waiting and PNG reads are asynchronous; selection
cancellation and temporary-file cleanup are covered, and app termination
requests cancellation of pending work. Twenty new tests bring the host-verified
macOS suite to 68/68. Settings persistence, restore-defaults, active Carbon
registration, clipboard Quick Capture, repeated-trigger draft preservation,
and the bounded long-context view were exercised in the real app. PR #10 merged
D-031 into `main` at `0ab687b`.

D-032 records the subsequent Screen Recording diagnosis. The affected Debug
app used an ad-hoc signature with no Team ID and a CDHash-only designated
requirement. Rebuilding therefore produced a new privacy identity even though
System Settings retained an enabled same-name Recall entry from the preceding
build. Portable project signing configuration, an ignored per-developer Team ID
override, a signing verifier, and a specific temporary-signature diagnostic now
make that state explicit. The app-specific TCC reset and reauthorization now
pass on the integration Mac. A same-signer rebuild changed CDHash from
`143035…` to `5a1b00…` while retaining the Team ID and signer-based requirement;
the rebuilt app opened the system region overlay and cancelled cleanly without
a permission error. The macOS suite passes 70/70. B-014 is closed: with Recall's
main window closed and another app focused, the physical screenshot shortcut
completed a non-empty region, and the clipboard shortcut opened Capture after
text was copied.

D-034 adds user-triggered native Accessibility selection capture without
changing the backend contract or saving surrounding context. The native draft
is labeled as a selection but submits through the existing text/clipboard source
contract; selection bounds are used only to position Quick Capture and are never
persisted. The host suite passes 108/108 tests, including permission and secure-
field fail-closed behavior, exact Unicode preservation, old shortcut migration,
cancellation, oversized-source rejection, and multi-screen placement geometry.
The user accepted the primary native path and the D-035 WeChat compatibility
path on the stably signed app on 2026-07-21.

D-035 adds the opt-in transactional clipboard fallback requested after initial
real-device selection testing. It never runs for missing permission, Recall
itself, known secure/protected content, oversized text, or cancellation before
the transaction begins. The AX failure produces a ticket for the exact frontmost
application and, when available, its focused control. That scope is revalidated
immediately before each of two Copy attempts, together with Secure Event Input
and any exposed security attributes. Recall accepts only
two consecutive, matching clipboard results and attempts restoration only while
the observed change count remains unchanged. This substantially narrows races
but cannot make restoration atomic or identify the writer. The in-memory backup
is never logged, persisted, or sent to the backend. The current host suite passes
149/149 tests. The user reported no issue in final WeChat testing and authorized
merge; rich text, image, Finder-file, and race cases remain release-regression
coverage rather than an open merge gate.

D-036 begins rich-source support at the conservative intake boundary rather than
adding a rich editor prematurely. Explicit Clipboard Capture now uses a bounded
resolver: plain text owns the content, while content-equivalent HTML or RTF may
replace an existing whitespace separator with a paragraph or line boundary.
Mismatched rich data cannot remove Markdown/TeX delimiters, and no markup is
rendered, persisted, or sent. Gemini's live clipboard payload verifies that the
resolver can preserve inline/display TeX and recover safe block boundaries.
Native Accessibility selection remains unchanged and limited to what the source
app exposes.

D-037 adds persisted image notes. A screenshot draft can save one original PNG
or JPEG with a separate note, display it in library/detail views, delete it with
its local file, and—only within the global privacy master switch—run background
OCR plus visual indexing into the existing search fields. Provider errors keep
the original safe and support **Retry AI**. The user verified real-app image
notes with AI both disabled and enabled.

The integrated D-036/D-037 tree passes 235 backend tests, 44/44 stress
scenarios, 184/184 macOS tests, and
68/68 Chrome-extension tests.

Live verification covers provider-off keyword fallback, real OpenAI enrichment
and embeddings, semantic retrieval with a non-null score, and both selected-text
and no-selection Chrome Captures appearing as ready cards in the macOS app.

The shared P0 integration gates B-007, B-008, and B-009 are resolved. Layer 10
submission work such as screenshots, licensing, final tagging, and release
packaging remains intentionally separate from the runnable product integration.

Detailed current evidence and blockers are tracked in
[`docs/developer-b-checklist.md`](docs/developer-b-checklist.md).
