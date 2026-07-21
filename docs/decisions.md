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
| D-013 | Proceed past Layer 3 with a documented macOS integration holder | Addition | Accepted; gate closed |
| D-014 | In-process enrichment tasks with an explicit retry endpoint | Clarification | Accepted |
| D-015 | Trigger-synchronized FTS5 with normalized keyword-only scoring | Clarification | Accepted |
| D-016 | Build Layer 7 before Layer 6 | Addition | Accepted by user direction |
| D-017 | Default-dimension embeddings with per-result FTS fallback | Clarification | Accepted |
| D-018 | Build-free Manifest V3 Chrome extension | Addition | Accepted |
| D-019 | Documentation-only main with stacked layer branches | Addition | Superseded by D-023 |
| D-020 | Deterministic destructive-in-temp backend stress harness | Addition | Accepted by user direction |
| D-021 | Bounded provider-neutral stress hardening | Addition | Accepted by user direction |
| D-022 | Build Week macOS runtime and narrow search fallback | Addition | Accepted |
| D-023 | Restore runnable integrated main | Addition | Accepted; deterministic verification complete |
| D-024 | Bounded literal-substring retrieval fallback | Clarification | Accepted |
| D-025 | Keyboard-first Chrome capture polish | Addition | Accepted by user direction |
| D-026 | Deterministic macOS command-line test runner | Reliability safeguard | Accepted |
| D-027 | Transient screenshot OCR into the existing Capture pipeline | Addition | Implemented; B-012 tracks live GPT proof |
| D-028 | Opt-in inline browser capture and explicit browser-region screenshots | Addition | Phase 2 implemented; B-014 pending |

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
- Status: Accepted; gate closed 2026-07-18
- Product impact: None; the temporary holder was retired after the macOS gate
  passed
- Schedule impact: Layer 4 backend work proceeds in parallel with Developer A

The product-plan build order places the first macOS list integration before AI
enrichment. At the user's direction, Developer B began Layer 4 after the Layer
3 backend was verified while Developer A completed the display gate in
parallel. A non-production Swift example under `docs/examples/` temporarily
documented the expected decoding and list request without modifying Developer
A's Xcode project or claiming the shared vertical slice was complete.

Developer A subsequently displayed live backend Captures, preserved source and
user-note separation, and replaced the holder with the maintained client under
`apps/macos/`. The placeholder was removed when the shared Layer 3 gate closed.
The current post-integration test sweep is tracked separately and does not
reopen this historical coordination gate.

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

An abrupt process exit can leave an in-process task unfinished. For demo
reliability, each successful backend startup now performs one transactional
recovery after migrations: every pre-startup `processing` row becomes `error`
with a safe interruption message. The transition preserves source and user-note
fields and uses the existing explicit retry endpoint; it does not introduce a
durable queue or automatically repeat an external model call.

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
complete. The later real embedding and semantic-search proof resolved B-008.

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
- Status: Superseded by D-023 on 2026-07-19
- Product impact: Historical exception; no longer the active repository layout
- Schedule impact: The exception ended when the complete integration tree was
  assembled

The user directed that AI, SQL, Chrome-extension, and related implementation
work be retained on separate branches while `main` contains only description
and central files. Existing commits are not rewritten. Branch refs preserve the
verified Layer 1–5 boundaries, and Layers 6 and 7 are committed as separate
sibling deltas from Layer 5. Their validated combined state is retained on
`integration/layers-6-7` because a direct sibling merge requires resolution in
the shared backend bootstrap and README. Developer A's existing macOS branch is
unchanged.

The exact branch tips and definition of central files were recorded in
[`branch-layout.md`](branch-layout.md). During this temporary exception, that
layout superseded the product-plan workflow rule that `main` stay runnable. It
did not waive the Layer 8 or final demo integration gates.

D-023 ends this exception. The branch checkpoints remain in history, while
`main` again carries the backend, Chrome extension, macOS application,
contracts, and documentation together.

## D-020 — Deterministic destructive-in-temp backend stress harness

- Classification: Addition / engineering verification
- Status: Accepted by explicit user direction
- Product impact: None; this decision adds tests and records defects only
- Schedule impact: Layer 8 now has thirteen grouped backend repair items

The backend stress audit runs from `test/backend-stress` against disposable
SQLite databases and deterministic local provider doubles. It must not use a
real OpenAI credential, personal Capture data, or the user's normal database.
One failure must not stop the remaining scenarios, and the report must preserve
every observed error, limitation, performance threshold, and untested gate.

The interaction thresholds used by the first audit—one second for one local
realistic-vector search, two seconds for the small-vector concurrent case, and
five seconds for the realistic-vector concurrent case—are provisional test
guardrails, not a public service-level agreement. The harness and results are
recorded in [`backend-stress-report-2026-07-18.md`](backend-stress-report-2026-07-18.md).

## D-021 — Bounded provider-neutral stress hardening

- Classification: Addition / reliability hardening
- Status: Accepted by explicit user direction
- Product impact: No new user-facing feature; malformed work now fails safely
- Schedule impact: Closed B-011; later integration work closed the independent live gates

The stress findings are repaired on `fix/backend-stress-hardening` without a
new external service, queue, or vector dependency. This decision supersedes the
deferred-idempotency sentence in D-011: optional `client_capture_id` now makes
create retries transactionally idempotent, while requests without it still
create distinct Captures.

All enrichment providers are validated again at the provider-neutral service
boundary. Empty, `null`, partial, generic, or oversized output has failure code
`invalid_model_output` and must store a terminal `error` with a safe message;
it may neither produce an empty `ready` Capture nor leave one in `processing`.
This is deliberately provider-neutral so the gated Apple/local path follows the
same lifecycle contract as OpenAI.

Request metadata, notes, search queries, enrichment scalars, lists, and list
items receive documented caps. Search rejects control characters, retries an
escaped any-term FTS expression only when the strict all-term expression has no
rows, and caches decoded normalized ready vectors until the SQLite file changes.
Overflow-safe normalization, stored-JSON health checks, and the stable malformed-
body envelope complete the concise remediation. These choices amend the strict
AND behavior in D-015 and the per-request full decode described in D-017.

The same deterministic harness must remain green after changes. The original
branch acceptance evidence is 181 passing backend tests and 44/44 passing
stress scenarios; the first integrated tree passed 186 backend tests. Current
`main` passes 190 backend tests and the unchanged 44/44 scenario set. Real
OpenAI enrichment and embeddings have also passed; power-loss and disk-full
behavior remain separate system evidence.

## D-022 — Build Week macOS runtime and narrow search fallback

- Classification: Addition / implementation choice
- Status: Accepted
- Product impact: Implements the product-plan macOS client without moving
  persistence or retrieval ownership out of the backend
- Schedule impact: Low

The Build Week macOS target supports macOS 14 and later, remains a normal Dock
application, and also provides a `MenuBarExtra`. It uses single-instance main
and quick-capture windows. The prototype target does not enable App Sandbox or
bundle the Python service; it permits localhost HTTP through
`NSAllowsLocalNetworking`. Production sandboxing, notarization, and backend
packaging remain outside the P0 Build Week scope.

The backend remains the only persistence and production search boundary. A
case-insensitive local filter is allowed only when the exact search route
returns HTTP `404`, so a genuinely unavailable older backend can still exercise
the search UI. Other transport and API errors remain visible and must not be
silently converted into local results. The client enforces the current Capture
and search limits before submission, and a quick-capture draft retains one
stable `client_capture_id` across retries for backend idempotency.

The macOS implementation has been included in the full integration tree and
passes all 27 current contract, networking, lifecycle, validation, idempotency,
polling-deadline, and store tests. An ambiguous create retry freezes its original
request, and foreground refreshes cannot replace an active server search with
local results.

## D-023 — Restore runnable integrated main

- Classification: Addition / repository workflow restoration
- Status: Accepted 2026-07-19; deterministic and live verification complete
- Product impact: `main` again contains the complete runnable Recall product
- Schedule impact: Removes the repository-layout blocker before final demo work

The temporary D-019 documentation-only arrangement is retired. The canonical
integration tree combines the stress-hardened backend and Chrome extension from
`fix/backend-stress-hardening`, the macOS client from `codex/macos-client`, and
the current shared contracts and documentation. Merge commits preserve the
relevant development histories; no published commit is rewritten.

This tree is the source for future feature branches and the final demo. Prior
branch test results remain useful component evidence, but they do not replace
the backend, extension, Xcode, and manual checks being run against the assembled
tree. The first assembled tree passed 186 backend tests, 44/44 stress scenarios,
13 extension tests, and 27 macOS tests. After the reliability and keyboard-first
improvements, current `main` passes 190 backend tests, the same 44/44 stress
scenarios, 16 extension tests, and 27 macOS tests. Real OpenAI enrichment and
embeddings, semantic search, unpacked-Chrome capture, and macOS display resolve
B-007, B-008, and B-009.

## D-024 — Bounded literal-substring retrieval fallback

- Classification: Clarification / retrieval robustness
- Status: Accepted
- Product impact: Partial identifiers and short CJK fragments remain findable
  when FTS5 tokenization cannot represent the user's literal query
- Schedule impact: Low

FTS5 remains the primary keyword retrieval and ranking path. Search first runs
the strict all-term expression and then the D-021 any-term expression when
needed. A bounded, parameterized literal-substring scan across the same indexed
Capture fields is merged with tokenized candidates so a valid FTS hit cannot
hide a partial identifier elsewhere. Rows are deduped under the existing
candidate cap; FTS-ranked rows retain priority. The pass never interprets
punctuation as SQL or FTS syntax.

This closes the observed cases where `RecallSearchSmokeTest` could not be found
with `Recall`, or a Chinese memory could not be found with a literal character
fragment. Semantic retrieval remains independent and may add candidates when a
real embedding provider is configured.

## D-025 — Keyboard-first Chrome capture polish

- Classification: Addition
- Status: Accepted by user direction
- Product impact: Reduces the primary Chrome capture path to a shortcut, an
  optional note, and one keyboard submission
- Schedule impact: Low

The Chrome extension declares an `_execute_action` command with a suggested
`Command+Shift+Y` shortcut on macOS. The existing popup remains the only capture
UI and preserves the product-plan separation between source material and the
optional user note. `Command+Enter` or `Control+Enter` submits the Capture,
success remains visible briefly, and the popup then closes automatically.

The popup enforces the shared contract limits before sending. Uneditable page
titles are safely bounded and overlong optional URLs are omitted rather than
submitted as invalid or misleading truncated links. Once a valid request begins,
the open popup freezes and reuses that exact payload and `client_capture_id` for
all retries. This complements backend idempotency without caching selected
private source content in extension storage.

## D-026 — Deterministic macOS command-line test runner

- Classification: Reliability safeguard
- Status: Accepted during final `main` reconciliation
- Product impact: None; production code and the Xcode project remain unchanged
- Schedule impact: Low

Xcode 26.6 can build and launch the hosted macOS unit-test target but leave the
host process waiting indefinitely. The compiled test bundle itself remains
healthy and passes all 27 tests when invoked with Apple's `xctest` executable.
The repository therefore provides `scripts/test-macos.sh`, which runs
`xcodebuild build-for-testing` and then invokes that exact bundle with the app's
debug-library directory available to the dynamic loader.

This is a test-infrastructure fallback, not a substitute for manual app checks
or a change to the product runtime. The conventional Xcode `Command-U` and
`xcodebuild test` paths remain documented for environments where the hosted
runner completes normally.

## D-027 — Transient screenshot OCR into the existing Capture pipeline

- Classification: Addition approved by explicit user direction
- Status: Implemented, verified, and published in draft PR #4; live GPT proof
  remains tracked by B-012
- Product impact: Adds an interactive screenshot-to-note path with GPT first and
  Apple Vision as an on-device alternative
- Schedule impact: Bounded exception to the outline's deferred OCR scope

The product plan defers general OCR, image memories, and chart understanding.
This user-directed addition is intentionally narrower: the macOS app captures a
selected screen region, displays it temporarily, and extracts visible text only
after an explicit user action. The image is not written to Recall's database or
retained after the capture draft is dismissed.

GPT is the default extractor through a provider-neutral localhost API boundary.
Apple Vision is the selectable local extractor for the demo, and its result
enters the exact same note and Capture pipeline. The UI must label cloud versus
on-device processing before extraction. Extracted text is editable and is saved
through existing SQLite, enrichment, FTS, and semantic retrieval; no second
notes store or image-attachment schema is introduced.

Screenshot-derived Captures use the explicit `screenshot` source type rather
than masquerading as clipboard input. Migration 003 transactionally preserves
existing rows while rebuilding the SQLite source constraint and synchronized
FTS table. No image column is added.

This decision does not authorize background screen monitoring, automatic OCR,
full screenshot persistence, image embeddings, chart understanding, or a new
navigation system. Those remain deferred.

## D-028 — Opt-in inline browser capture and explicit browser-region screenshots

- Classification: Addition approved by explicit user direction
- Status: Phase 2 selected-text runtime implemented; B-014 pending; Phase 3
  not started
- Product impact: Adds a transient capture action beside completed webpage
  selections and scopes a matching REcall-initiated browser screenshot flow
- Schedule impact: Phase 2 text selection is medium; Phase 3 screenshot capture
  is independently gated and must not destabilize the selection path

The existing Chrome toolbar and keyboard capture remain supported. After the
user explicitly grants optional HTTP and HTTPS site access, a lightweight
content script may observe a completed selection locally and display a
transient **Add to REcall** action. Merely selecting text must not transmit,
store, or log the selection, change page layout, steal focus, or interfere with
normal page behavior. The exact states and dismissal rules are defined in
[`browser-inline-capture-spec.md`](browser-inline-capture-spec.md).

The inline composer preserves the existing separation among source material,
the optional personal comment, and AI interpretation. It delivers through a
shared extension service-worker boundary and the existing `POST /v1/captures`
contract. Toolbar, shortcut, and inline entry points must reuse validation,
idempotency, error mapping, and localhost behavior rather than create parallel
request implementations.

Chrome cannot detect arbitrary macOS screenshots. The browser screenshot path
therefore begins only from an explicit REcall **Capture Region** action, captures
a region of the visible tab, and uses the existing GPT `/v1/ocr` boundary before
saving extracted text as `source_type: screenshot`. Cloud processing must be
disclosed before upload, screenshot bytes remain transient, and page title and
URL remain source metadata. Apple Vision continues to belong to the native
macOS flow; the browser UI must not claim that GPT browser OCR is on-device.

Phase 2 selected-text capture may ship independently. Phase 3 browser screenshot
capture cannot block it and does not authorize passive screenshot monitoring,
full-page snapshots, persistent image memories, image embeddings, or general
image understanding.

Phase 2 implementation evidence: optional website permission controls dynamic
content-script registration and revocation; the isolated action/composer sends
one explicitly saved, identity-frozen request through the shared service-worker
coordinator. Toolbar and keyboard capture now use the same coordinator. No API,
database, enrichment, or search schema changed. Thirty extension tests and the
complete browser-fixture interaction pass. B-014 remains open because a real
unpacked Chrome permission/backend/macOS/revocation run was not available in
the browser fixture environment.

## Pending decisions

Model snapshots, future dimension migrations, and the exact provider-metadata
fields remain implementation-layer decisions and must not be silently fixed
here.
