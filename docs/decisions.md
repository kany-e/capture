# Recall decision log

This file records important architectural decisions and every clarification or
addition made beyond [`product-plan.md`](product-plan.md).

## Change classification

- **Baseline** — directly required by the product plan.
- **Clarification** — resolves an ambiguity without changing product scope.
- **Addition** — introduces behavior or a constraint not stated in the product
  plan. Additions must include rationale and impact.

## Decision index

| ID | Decision | Classification | Status |
| --- | --- | --- | --- |
| D-001 | Localhost monorepo architecture | Baseline | Accepted |
| D-002 | Separate request, enrichment, and transport contracts | Clarification | Accepted |
| D-003 | Persist before asynchronous enrichment | Baseline | Accepted |
| D-004 | Stable §12.1 embedding projection | Clarification | Accepted |
| D-005 | Versioned API response and error envelopes | Addition | Accepted |
| D-006 | Expose `context_truncated` in the Capture contract | Clarification | Accepted |
| D-007 | JSON Schema Draft 2020-12 for checked-in contracts | Addition | Accepted |
| D-008 | Optional Apple on-device intelligence provider | Addition | Accepted with gate |
| D-009 | Allow page-context capture without a text selection | Clarification | Accepted |
| D-010 | Standard-library virtual environment for the backend | Addition | Accepted |
| D-011 | Numbered SQL migrations with the Python standard library | Addition | Accepted |
| D-012 | Local live build-checklist dashboard | Addition | Accepted |
| D-013 | Proceed past Layer 3 with a documented macOS integration holder | Addition | Accepted with open gate |
| D-014 | In-process enrichment tasks with an explicit retry endpoint | Clarification | Accepted |
| D-015 | Trigger-synchronized FTS5 with normalized keyword-only scoring | Clarification | Accepted |
| D-016 | Build Layer 7 before Layer 6 | Addition | Accepted by user direction |
| D-017 | Default-dimension embeddings with per-result FTS fallback | Clarification | Accepted |
| D-018 | Build-free Manifest V3 Chrome extension | Addition | Accepted |
| D-019 | Documentation-only main with stacked layer branches | Addition | Accepted by user direction |

## D-001 — Localhost monorepo architecture

- Classification: Baseline
- Status: Accepted

Use a monorepo containing a SwiftUI/AppKit macOS app, a Manifest V3 Chrome
extension, and a FastAPI backend bound only to `127.0.0.1:8765`. SQLite, FTS5,
OpenAI integration, and search stay behind the backend boundary.

This supports independent work by both developers and the fastest reliable
Build Week demo path.

## D-002 — Separate request, enrichment, and transport contracts

- Classification: Clarification
- Status: Accepted

`capture.schema.json` validates client creation input.
`enriched_capture.schema.json` validates only model-generated Structured Output.
`api.md` owns HTTP envelopes and the complete persisted Capture representation.

This prevents OpenAI field names such as `title` from being confused with API
fields such as `ai_title`, and lets the backend map validated model output into
storage explicitly.

## D-003 — Persist before asynchronous enrichment

- Classification: Baseline
- Status: Accepted

`POST /v1/captures` validates and commits the original Capture before any model
request. It then returns a `processing` representation. AI failure changes
status to `error` without discarding source data or the user note.

## D-004 — Stable §12.1 embedding projection

- Classification: Clarification
- Status: Accepted

The embedding input uses the exact labels and order from product-plan §12.1.
Values are outer-trimmed, line endings are normalized to LF, list fields are
joined with `, ` in stored order, and missing values become empty strings.
Internal whitespace in source and note text is preserved.

Changing labels, order, or normalization requires an `enrichment_version`
increment and regeneration of existing embeddings.

## D-005 — Versioned API response and error envelopes

- Classification: Addition
- Status: Accepted
- Product impact: None; transport consistency only
- Schedule impact: Low

List endpoints return an object envelope rather than a bare array. Errors use a
stable `{ "error": { ... } }` envelope. Asynchronous creation and re-enrichment
return HTTP `202 Accepted`.

These conventions were not specified by the outline. They give the Swift and
extension clients stable parsing and error-display behavior without adding a
feature.

## D-006 — Expose `context_truncated`

- Classification: Clarification
- Status: Accepted

Product-plan §11.2 requires recording when surrounding context is truncated,
but the example request and SQL table omit the field. Layer 0 adds the optional
boolean `context_truncated` to Capture input and output, defaulting to `false`.
The persistence layer must add a matching non-null column with a false default.

This is a reconciliation of two baseline requirements, not new product scope.

## D-007 — JSON Schema Draft 2020-12

- Classification: Addition
- Status: Accepted
- Product impact: None
- Schedule impact: None

The client-input contract declares JSON Schema Draft 2020-12 and rejects
additional properties. The enrichment contract intentionally omits draft
metadata so its root object can be passed directly as the strict Structured
Output schema; it still uses only constructs valid in Draft 2020-12 and in the
subset supported by the OpenAI API. This provides precise contracts for Swift,
Python, and TypeScript consumers without requiring provider-specific wrappers
in the checked-in schema.

## D-008 — Optional Apple on-device intelligence provider

- Classification: Addition
- Status: Accepted with gate
- Product impact: Adds an optional provider demonstration; does not replace the
  OpenAI Build Week path
- Schedule impact: Medium if activated
- Ownership impact: Shared between Developers A and B

After the complete OpenAI capture, enrichment, storage, and hybrid-retrieval
workflow is stable, Recall may add an optional Apple on-device provider using
the Foundation Models framework. The provider must emit the same enrichment
contract and may not change the source or user-note fields.

Developer B owns the provider-neutral enrichment boundary, storage metadata,
OpenAI provider, and retrieval behavior. Developer A owns the Swift integration
with Apple Foundation Models, model-availability checks, and provider UI.

This path is gated by all of the following:

1. The three baseline vertical slices pass their exit gates.
2. The OpenAI contribution remains the primary judged workflow.
3. The target Mac and OS expose a usable Apple model at demo time.
4. Apple output can be mapped into `enriched_capture.schema.json` without a
   second product data model.
5. The addition does not delay demo stabilization or submission work.

Apple `NLEmbedding` may be evaluated as a separate local retrieval experiment,
but it must not replace the baseline OpenAI embedding path before the demo is
stable. Provider identity and provider/model version must be recorded with
generated data if this optional path is implemented.

## D-009 — Allow page-context capture without a text selection

- Classification: Clarification
- Status: Accepted
- Product impact: Preserves the no-selection Chrome flow in product-plan §13.3
- Schedule impact: None

The product plan permits saving a page title and limited page context when the
user has not selected text, while the database requires `selected_text` to be a
non-null string. The creation contract therefore requires `selected_text` to be
present but allows it to be empty when either `source_title` or
`surrounding_context` contains non-empty text. At least one of those three
content fields must be non-empty.

This is not a new capture mode. It reconciles the no-selection browser behavior
with the baseline data model.

## D-010 — Standard-library virtual environment for the backend

- Classification: Addition
- Status: Accepted
- Product impact: None
- Schedule impact: Low

Layer 1 uses Python's standard-library `venv`, project metadata in
`services/backend/pyproject.toml`, constrained direct dependencies, and a
single requirements entry point for development installs. This keeps the
backend isolated without requiring `uv` or a global package install on the
current development machine.

This is an implementation-tooling choice, not a new product feature. A future
toolchain change must preserve the documented start and test commands.

## D-011 — Numbered SQL migrations with the Python standard library

- Classification: Addition
- Status: Accepted
- Product impact: None; storage implementation only
- Schedule impact: Low

Layer 2 uses ordered `.sql` files plus a `schema_migrations` table and a small
Python migration runner. Migrations execute transactionally before repository
access. This gives the Build Week SQLite schema an auditable upgrade path
without adding Alembic or an ORM.

The initial migration implements the product-plan `captures` table plus the
D-006 `context_truncated` column and database checks for the four accepted
statuses. `client_capture_id` remains nullable and non-unique; stronger
idempotency is deliberately deferred unless duplicate submissions become a
demonstrated problem. A non-unique `created_at` index is included to support
the contract's required newest-first list ordering in Layer 3; it introduces no
new data constraint.

## D-012 — Local live build-checklist dashboard

- Classification: Addition
- Status: Accepted
- Product impact: None; developer visibility only
- Schedule impact: Low

The loopback backend exposes a developer-only HTML dashboard at
`/dev/checklist` and a read-only JSON view at `/dev/checklist.json`. The JSON is
regenerated from `docs/developer-b-checklist.md` on every request, and the page
polls it every two seconds. Markdown remains the single source of truth, so
there is no second checklist to drift out of date.

The dashboard has no write endpoint, remote deployment, browser persistence,
or external JavaScript dependency. It stays behind the existing localhost-only
backend boundary and may be removed from a submission build without affecting
Recall product behavior.

## D-013 — Proceed past Layer 3 with a documented macOS integration holder

- Classification: Addition / workflow exception
- Status: Accepted with open gate
- Product impact: None; no macOS behavior is claimed as implemented
- Schedule impact: Layer 4 backend work proceeds in parallel with Developer A

The product-plan build order places the first macOS list integration before AI
enrichment. At the user's direction, Developer B may begin Layer 4 after the
Layer 3 backend is verified and pushed, while Developer A's display confirmation
remains open. A non-production Swift example under `docs/examples/` documents
the expected decoding and list request without modifying Developer A's Xcode
project or pretending the shared vertical slice is complete.

The placeholder is not an exit-gate substitute. Developer A must still display
the live Capture, preserve source/user-note separation, and remove or supersede
the holder before the shared Layer 3 gate can be marked complete.

## D-014 — In-process enrichment tasks with an explicit retry endpoint

- Classification: Clarification / implementation choice
- Status: Accepted
- Product impact: Implements the baseline asynchronous enrichment lifecycle
- Schedule impact: Low

Layer 4 uses FastAPI `BackgroundTasks` after the original Capture transaction
commits. `POST /v1/captures` still returns the required `processing` response;
the background task stores either the validated AI interpretation or a safe
`error` state without modifying the source or user note.

`POST /v1/captures/{id}/enrich` provides explicit retry behavior. The repository
claims retries with a transactional status comparison so two requests cannot
start enrichment for the same Capture concurrently. Clients poll the detail
endpoint every one to two seconds, stop on `ready` or `error`, and cap polling
at approximately 60 seconds. No WebSocket, Redis, Celery, or durable queue is
added for P0.

An abrupt process exit can still leave an in-process task unfinished. Automatic
stale-processing recovery remains a documented post-MVP safeguard unless it
becomes necessary for demo reliability.

## D-015 — Trigger-synchronized FTS5 with normalized keyword-only scoring

- Classification: Clarification / implementation choice
- Status: Accepted
- Product impact: Implements the baseline Layer 5 keyword-retrieval path
- Schedule impact: Low

Layer 5 creates the exact product-plan `captures_fts` columns. One set of SQLite
`AFTER INSERT`, `AFTER UPDATE`, and `AFTER DELETE` triggers owns synchronization
for raw creation, enrichment success or failure, retry clearing, future
deletion, and any other repository write. Migration 002 also backfills every
existing Capture, avoiding an application-only second indexing path.

Non-empty queries are split on whitespace and each segment is escaped as an FTS
phrase joined with `AND`, so FTS operators supplied by a client are data rather
than query syntax. Weighted BM25 prioritizes titles, exact source content,
user notes, tags, entities, and aliases. Scores are normalized relative to the
candidate set with a small exact-phrase bonus and clamped to `0...1`.

In Layer 5, `score` equals `keyword_score` and `semantic_score` is `null`. Empty
queries return recent Captures with zero keyword scores. Layer 7 may combine
these stable keyword results with embeddings and metadata bonuses without
changing FTS synchronization.

## D-016 — Build Layer 7 before Layer 6

- Classification: Addition / schedule change
- Status: Accepted by explicit user direction
- Product impact: None; both baseline layers remain required
- Schedule impact: Layer 6 is deferred until Layer 7 is delivered

The product plan orders Chrome capture before embeddings and hybrid retrieval.
At the user's direction, Developer B will implement Layer 7 first and will not
start or claim any Chrome-extension work as part of this slice. Layer 7 remains
a backend-only change built against the existing Capture API and deterministic
fixtures.

This reordering does not change ownership, remove the Layer 6 browser workflow,
or satisfy the final Chrome-to-search vertical-slice gate. The Apple on-device
experiment in D-008 also remains gated until the baseline workflow is stable.

The temporary deferral ended on 2026-07-18 when the user requested Layer 6
after the Layer 7 backend implementation and deterministic verification were
complete. Layer 7's live provider gate remains independently blocked by B-008.

## D-017 — Default-dimension embeddings with per-result FTS fallback

- Classification: Clarification / implementation choice
- Status: Accepted
- Product impact: Implements product-plan §12 without a storage migration
- Schedule impact: Low

Layer 7 calls the configured `OPENAI_EMBEDDING_MODEL` without a reduced
`dimensions` argument for both Capture and query inputs. A Capture vector is
generated only after enrichment output has passed validation; an embedding
failure still stores that Capture as `ready` with `embedding_json` empty.

Search reads every `ready` Capture and calculates cosine similarity in Python.
Cosine values are clamped to the public `0...1` score range. Hybrid candidates
are the union of keyword matches and ready Captures with compatible vectors.
When the query vector is unavailable, the complete response preserves Layer 5
FTS ordering and scores. When only one Capture vector is unavailable or
incompatible, that result retains its keyword score and a null semantic score
instead of failing the search.

The implementation stores no second vector index and adds no embedding-model
metadata column. A future model change still requires the regeneration policy
from D-004; provider metadata remains a pending post-MVP decision.

## D-018 — Build-free Manifest V3 Chrome extension

- Classification: Addition / implementation choice
- Status: Accepted
- Product impact: Implements the baseline Chrome Capture workflow
- Schedule impact: Low

Layer 6 uses browser-native ES modules and a Manifest V3 action popup under
`apps/chrome-extension/`. The unpacked extension requires no bundler or runtime
framework: its package script runs deterministic tests with Node's built-in
test runner, while Chrome executes the checked-in source directly.

The popup injects a self-contained, testable extraction function only after an
explicit toolbar action. It requests exactly `activeTab`, `scripting`, and
`storage`, plus the fixed `http://127.0.0.1:8765/*` host permission. `storage`
holds only a per-tab note draft plus its page-URL identity and removes the draft
after a successful save; selected text and surrounding context are not cached
by the extension.

The backend CORS allowlist remains environment-configured. Wildcards, public
web origins, malformed extension origins, credentials, and broad methods or
headers are rejected; no unpacked extension ID is hard-coded into the shared
repository.

## D-019 — Documentation-only main with stacked layer branches

- Classification: Addition / repository workflow change
- Status: Accepted by explicit user direction
- Product impact: `main` is no longer a runnable integrated product tree
- Schedule impact: A runnable integration branch is required before Layer 8

The user directed that AI, SQL, Chrome-extension, and related implementation
work be retained on separate branches while `main` contains only description
and central files. Existing commits are not rewritten. Branch refs preserve the
verified Layer 1–5 boundaries, and Layers 6 and 7 are committed as separate
sibling deltas from Layer 5. Their validated combined state is retained on
`integration/layers-6-7` because a direct sibling merge requires resolution in
the shared backend bootstrap and README. Developer A's existing macOS branch is
unchanged.

The exact branch tips and definition of central files are recorded in
[`branch-layout.md`](branch-layout.md). This intentionally supersedes the
product-plan workflow rule that `main` stay runnable. It does not waive the
Layer 8 and final demo integration gates: the team must agree on a runnable
integration location before those gates can close.

## Pending decisions

Model snapshots, future dimension migrations, and the exact provider-metadata
fields remain implementation-layer decisions and must not be silently fixed
here.
