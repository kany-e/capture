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
| D-027 | Transient screenshot OCR into the existing Capture pipeline | Addition | Implemented and live-verified in PR #5 |
| D-028 | Layered GitHub Actions pull-request checks | Reliability safeguard | Accepted by user direction |
| D-029 | Opt-in inline browser selected-text capture | Addition | Implemented, real-Chrome verified, and merged in PR #8 |
| D-030 | Omit unsafe browser context and bound native display | Reliability/privacy safeguard | Implemented, UI-verified, and merged through PR #9 at `0c1083e` |
| D-031 | Native global capture through Carbon and one app-level coordinator | Addition | Implemented and merged through PR #10 at `0ab687b`; real-device acceptance passed |
| D-032 | Stable development code identity for TCC-protected screenshot capture | Reliability/privacy safeguard | Implemented; 70/70 tests and live TCC rebuild-persistence proof pass |
| D-033 | Deterministic Chrome action-popup dimensions | Reliability safeguard | Implemented; 68/68 tests and real-Chrome selected/metadata layouts pass |
| D-034 | User-triggered native Accessibility selection capture | Addition | Implemented; 108/108 host tests and primary-path user acceptance pass |
| D-035 | Opt-in transactional clipboard fallback for native selection | Compatibility/privacy safeguard | Implemented; 149/149 host tests and user WeChat acceptance pass |
| D-036 | Conservative structured-text line restoration | Capture-correctness addition | Merged in PR #14; live Gemini clipboard payload verified |
| D-037 | Persisted image notes with opt-in background visual indexing | Addition | Implemented; automated verification and real-app AI-disabled/AI-enabled acceptance pass |
| D-038 | Editable memories with explicit user overrides and state-driven UI | Addition | Implemented and user-accepted on `codex/note-editing-ui-polish`; 243 backend, 44/44 stress, 68/68 Chrome, and 189/189 macOS checks pass |
| D-039 | Branded Chrome settings and movable capture surfaces | Addition | Implemented and real-Chrome verified on `codex/note-editing-ui-polish`; 70/70 extension tests pass |
| D-040 | Canonical browser icon and adaptive native brand mark | UI/UX addition | Implemented and user-accepted on `codex/note-editing-ui-polish`; 70/70 extension and 189/189 host macOS tests pass |

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

D-030 later changes the current Chrome client to omit page text when there is
no selection and rely on title, URL, and optional note. D-009 remains the
cross-client contract capability for metadata- or safely bounded-context
Captures; it does not require every browser capture to populate
`surrounding_context`.

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
- Status: Implemented and live-verified; B-012 and B-013 were resolved on the
  integration Mac and the reviewed change is recorded in PR #5
- Product impact: Adds an interactive screenshot-to-note path with GPT first and
  Apple Vision as an on-device alternative
- Schedule impact: Bounded exception to the outline's deferred OCR scope

The product plan defers general OCR, image memories, and chart understanding.
This user-directed addition is intentionally narrower: the macOS app captures a
selected screen region, displays it temporarily, and extracts visible text only
after an explicit user action. The image is not written to Recall's database and
its in-memory preview is cleared when the capture draft is dismissed. The macOS
selection command uses a random OS temporary PNG that is removed after the
normal selection flow.

GPT is the default extractor through a provider-neutral localhost API boundary.
Apple Vision is the selectable local extractor for the demo, and its result
enters the exact same Capture pipeline. The UI must label cloud versus on-device
processing before extraction. Extracted text remains source content; an optional
personal user note remains a separate field. Both are saved through existing
SQLite, enrichment, FTS, and semantic retrieval; no second notes store or
image-attachment schema is introduced.

Screenshot-derived Captures use the explicit `screenshot` source type rather
than masquerading as clipboard input. Migration 003 transactionally preserves
existing rows while rebuilding the SQLite source constraint and synchronized
FTS table. No image column is added.

This decision does not authorize background screen monitoring, automatic OCR,
full screenshot persistence, image embeddings, chart understanding, or a new
navigation system. Those remain deferred.

## D-028 — Layered GitHub Actions pull-request checks

- Classification: Reliability safeguard approved by explicit user direction
- Status: Implemented
- Product impact: None; production behavior and data contracts are unchanged
- Schedule impact: Low; failures become visible before merge

Pull requests targeting `main`, pushes to `main`, and manual dispatches run four
independent jobs: backend tests, deterministic backend stress, the Chrome
extension suite, and the macOS/Xcode suite. A stable **Required checks** job
fails unless all four complete successfully, so branch protection needs only
one required context even if individual jobs evolve.

The workflow grants only read access to repository contents, pins GitHub-owned
actions to immutable release commits, cancels superseded runs, and never loads
`.env` or an OpenAI key. Provider behavior, screenshot permissions, and other
interactive operating-system flows retain their documented manual gates.

## D-029 — Opt-in inline browser selected-text capture

- Classification: Addition approved by explicit user direction
- Status: Implemented, real unpacked-Chrome acceptance verified, and merged
  through PR #8 at merge commit `71ec387`
- Product impact: Reduces a selected-web-text Capture to one nearby action, an
  optional personal note, and an explicit save
- Schedule impact: Bounded Chrome-extension slice; native capture improvements
  and browser-region screenshots remain separate

After a user explicitly enables optional HTTP/HTTPS website access, the Chrome
extension may observe a completed selection locally and show a transient
**Add to Recall** action beside it. Selecting text alone must not persist, log,
or transmit source content. As originally merged, the selected source, bounded
surrounding context, page title, URL, and optional user note entered the existing
`POST /v1/captures` pipeline only after the user chose Save. D-030 hardens this
after real-site evidence by temporarily omitting browser surrounding context.

The inline surface must not change document layout, take focus merely by
appearing, suppress the page's normal keyboard behavior, interpret page text as
HTML, or leave controls behind after permission revocation. Toolbar and keyboard
capture remain supported fallbacks. All browser entry points reuse one validated
service-worker delivery path, and an ambiguous retry reuses the exact original
source, note, timestamp, and `client_capture_id`.

HTTP/HTTPS origins remain optional permissions and inline capture is off by
default. No static content script is declared. On opt-in, the service worker
dynamically registers the isolated script and injects it into eligible tabs that
are already open; on revocation, it unregisters future injection and sends an
immediate cleanup message to open tabs. Neither a page nor its content script
communicates with the localhost backend directly.

Chrome may preserve an injected document in its back-forward cache while the
user revokes access on another page. A cached document therefore suspends on
`pagehide`, performs a read-only permission check on persisted `pageshow`, and
fails closed unless access is explicitly still enabled. The service worker also
rechecks permission before accepting a content-script save. Toolbar saves are
not subject to that inline-only gate.

This decision changes no backend, database, enrichment, OCR, or retrieval
contract. It does not include browser-region screenshots, native Accessibility
capture, passive system-wide selection monitoring, Chrome native messaging, or
image attachments. The native D-027 flow remains the system screenshot path.

Deterministic coverage now includes permission initialization and revocation,
Unicode limits, rapid activation, error dismissal, stable retry identity,
already-open-tab injection, BFCache suspension, save-time permission checks, and
toolbar regression; the dependency-free suite passed 68/68 tests. A real
unpacked-Chrome run enabled inline capture on an already-open page without a
refresh and confirmed that the selected source plus a Chinese/emoji personal
note were persisted exactly. It also verified that Escape remained visible to
the page, editable targets were ignored, an offline retry retained its exact
attempt, revocation removed an open composer, a real BFCache return stayed
disabled, and toolbar capture still saved after revocation. All resulting cards
displayed with the exact source and note in the macOS app. The temporary backend
intentionally had no AI provider configured, so the resulting enrichment
`error` demonstrates the existing persist-first rule: the Capture succeeded and
retained its source and note even though enrichment did not. PR #8 completed
the pull-request checks and merged the feature into `main` at `71ec387`.

## D-030 — Omit unsafe browser context and bound native display

- Classification: Reliability and privacy safeguard approved by user direction
- Status: Implemented and UI-verified at the boundaries recorded below; 68
  extension and 48 macOS tests pass, and PR #9 merged the change into `main` at
  `0c1083e`
- Product impact: Prevents unrelated page regions from entering new Chrome
  Captures and prevents oversized stored context from stalling the native detail
  view
- Schedule impact: Browser hardening is complete; D-031 native global capture
  is current

A real Gemini Capture exposed two coupled failure modes. Its exact selected
answer was 1,530 characters, while `surrounding_context` reached 19,144
characters with 1,912 newline characters because broad `main`/`body` ancestry
also included the conversation-history sidebar. The macOS detail view eagerly
constructed one selectable SwiftUI `Text` for that value; because the newest
record is selected automatically, the cost recurred immediately after every app
restart and made the library nearly unusable.

Until a local extractor is demonstrably safe, both Chrome entry points send an
empty `surrounding_context` and `context_truncated=false`. With a selection,
they save up to the shared 12,000-character selection limit plus page title,
URL, and optional note. Text within that limit follows the existing normalization
without shortening; a longer selection shows its full count and warns that only
the first 12,000 characters will be saved. Without a selection, the toolbar
saves page title, URL, and optional note. D-009 still permits that metadata-only
Capture, and the backend's
20,000-character context field remains an available contract capability rather
than a statement of current browser behavior. No schema, database, or
enrichment contract changes are made.

Any future Chrome context implementation must be centered on the selected DOM
Range, exclude navigation and hidden regions, and enforce independent character
plus line/block limits. It must fall back to empty context rather than a broad
ancestor when locality cannot be established. This future work may improve AI
interpretation, but selected text within the shared contract limit and the
user's note remain the primary browser inputs in the meantime.

Existing context is neither migrated nor deleted. The macOS model keeps the
complete value for search and AI processing, while its detail UI starts the
section collapsed and displays only a character count. Explicit expansion
passes at most the first 2,000 characters and 60 lines to selectable `Text` and
labels the preview limit. These display limits are independent of transport and
storage limits.

The same hardening clarifies the browser surfaces: inline capture shows a
Unicode-aware selected-text count separate from the note count, its selection
preview is pointer- and keyboard-scrollable, and the action popup uses a more
compact internally scrollable layout. All 68 extension tests pass. Five macOS
tests cover the bounded context projection, and all 48 macOS tests pass; the
detail view's collapse, expansion, and responsiveness are covered by the manual
evidence below.

UI verification reloaded the unpacked extension and confirmed the toolbar
popup's complete compact layout and metadata-only Gemini result. The standalone
production content-script harness reported an 800-character selection and
allowed its preview to scroll from the top into the remaining text; because it
uses a mocked runtime and open Shadow DOM, this is not extension-injection or
CSP evidence. The rebuilt macOS app opened the problematic 19,144-character
record with context collapsed, remained responsive, and expanded only a 60-line
bounded preview while keeping the full stored value intact. No verification
Capture or database mutation was left behind.

PR #9 passed Backend tests, Backend stress, Chrome extension, macOS, and the
aggregate Required checks job before merging into `main` at `0c1083e`.

## D-031 — Native global capture through Carbon and one app-level coordinator

- Classification: Addition approved by user direction
- Status: Implemented, merged, and real-device verified; stable TCC behavior is
  verified under D-032 and B-014 is closed
- Product impact: Makes screenshot and clipboard Quick Capture available while
  Recall is running even if its main window is closed
- Schedule impact: Completed native priority; Accessibility selection remains next

Recall remains a normal Dock application and keeps its existing
`MenuBarExtra`. It does not become an agent-only or hidden menu-bar process. The
app must be running for global capture to work; launch at login is a separate
future opt-in. Closing the main window does not end the app-level capture
objects, so menu-bar and global entry points are designed to keep working.

Native hotkeys use Carbon `RegisterEventHotKey`, not an event tap. They require
neither Accessibility nor Input Monitoring permission. Screenshot capture
defaults to `Option+Shift+Command+4`, and clipboard capture defaults to
`Option+Shift+Command+C`. Settings allows A–Z or 0–9 with any combination of
Command, Option, Control, and Shift, requires at least two modifiers for each
action, and rejects a duplicate combination across the two actions. Each action
can be disabled, and **Restore Defaults** restores the defined pair.

Registration changes are transactional. Recall validates and encodes the whole
proposal, unregisters the old set, and attempts the complete new set. A failure
removes any partially installed registrations and attempts to restore the
previous working set; the new configuration is persisted only after successful
registration. The error and rollback result remain visible in Settings, the
menu, and the menu-bar status icon rather than leaving the user to infer whether
a shortcut is active.

Every capture entry point in the main window, menu, or Carbon callback routes
through the app-level `GlobalCaptureCoordinator`. Its presentation request is
observed by a `CapturePresentationHost` attached to the `MenuBarExtra` label,
which opens and activates the shared Quick Capture window independently of the
main-window scene. App termination requests cancellation of pending screenshot
preparation and deactivates the Carbon registrations.

The system screenshot `Process` is awaited asynchronously, and PNG reading is
also moved off the main actor. Task cancellation terminates a running selection;
success, cancellation, launch failure, and empty-image paths all remove the
random temporary PNG. Rapid repeated screenshot requests share one pending task
and start only one selector. If any Quick Capture draft already exists, another
trigger does not overwrite it: Recall re-presents the draft and explains that
it must be finished or cancelled first. Ambiguous-save retry protection remains
unchanged.

D-031 does not persist screenshot images. The existing GPT/cloud and Apple
Vision/on-device disclosure and extraction choices remain visible, and only
reviewed text enters the Capture pipeline. There is no API, schema, backend,
database, Chrome-extension, enrichment, retrieval, or image-attachment change.

Twenty new shortcut, coordinator, draft-safety, and screenshot-process tests
bring the host-verified macOS suite from 48 to 68/68. Real UI verification
confirmed both defaults, a change to `Option+Shift+Command+5`, persistence after
restart, restore-defaults, and active Carbon registration. Clipboard Quick
Capture opened with the exact 32 characters; a repeated trigger kept that draft
and showed the explanatory notice. The previously problematic
19,144-character context record still opened collapsed and remained responsive.

The temporary ad-hoc test build did not match the Screen Recording permission
record. It showed the explicit permission error and the verification
deliberately did not change that permission. D-032 later verified the stable TCC
identity, authorization, same-signer rebuild persistence, and selector
cancellation. B-014 later passed the physical screenshot shortcut with Recall's
main window closed and another app focused, completed a non-empty region, and
confirmed that the clipboard shortcut opened Capture after text was copied.

## D-032 — Stable development code identity for TCC-protected screenshot capture

- Classification: Reliability and privacy safeguard approved by user direction
- Status: Implemented and live-verified; the independent B-014 physical-input
  gate also passed and is closed
- Product impact: Makes Screen Recording authorization reliably refer to the
  current development build and explains temporary-signature failures
- Schedule impact: Bounded correction to the D-031 manual acceptance gate

macOS privacy authorization matches an application's designated code
requirement, not only its display name or `com.recall.macos` bundle identifier.
The affected Debug app was ad-hoc signed with no Team ID and a designated
requirement tied only to that build's CDHash. Rebuilding changed the CDHash and
therefore its privacy identity. System Settings could retain an enabled Recall
row for the preceding build while `CGPreflightScreenCaptureAccess()` returned
false for the currently running process.

The Xcode project now uses a tracked, portable `Config/Signing.xcconfig` for
both app and test targets. It has an ad-hoc fallback so cloning and deterministic
automation remain available without a developer account, and it optionally
includes a gitignored `Signing.local.xcconfig`. Each developer who performs
interactive privacy testing copies the checked-in example and supplies the
actual Team ID for their own Apple Development identity. No personal Team ID,
certificate label, or machine-specific path belongs in version control.

A local signing verifier rejects an invalid app signature, a missing
`TeamIdentifier`, or a CDHash-only designated requirement. The runtime
permission path also distinguishes a temporary code identity from an ordinary
denial when both Screen Recording preflight and request fail. This gives the
developer a direct stable-signing and one-time-reset instruction instead of
implying that an enabled stale System Settings row authorizes the current
process. No Screen Recording entitlement is added.

Live verification quit every Recall process, reset only `ScreenCapture` for
`com.recall.macos`, requested permission from the stable build, changed Recall's
System Settings switch from off to on, and used **Quit & Reopen**. After
authorization, a same-signer build with `CURRENT_PROJECT_VERSION=2` changed the
executable CDHash from `143035…` to `5a1b00…` while retaining its Team ID and
signer-based designated requirement. The rebuilt process launched
`/usr/sbin/screencapture`, displayed the region overlay, and returned to Recall
without a permission error after Escape. The verifier also rejects the old
ad-hoc build, and the complete macOS suite passes 70/70.

`CODE_SIGNING_ALLOWED=NO` remains appropriate for the deterministic macOS test
runner and CI, but such a build cannot prove TCC authorization. Interactive
acceptance must use the stably signed app. Migration from an existing ad-hoc
entry is deliberately explicit: quit every Recall process, verify the intended
app bundle, run `tccutil reset ScreenCapture com.recall.macos`, launch that exact
build, authorize it once, quit, relaunch, and then exercise completed plus
cancelled region selections. Rebuild persistence is accepted only when the new
executable CDHash changes while its signer-based designated requirement and
authorization remain effective. D-032 now satisfies that identity and
cancelled-selector proof. B-014 separately passed physical screenshot delivery,
one completed non-empty region, and clipboard Quick Capture after copying text.

This follows Apple's explanation that privacy controls use code-signing
requirements to identify an app and Apple's documented Screen & System Audio
Recording authorization flow:

- [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Apple DTS: Screen Recording authorization across ad-hoc rebuilds](https://developer.apple.com/forums/thread/819406)
- [Control access to screen and system audio recording on Mac](https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac)

## D-033 — Deterministic Chrome action-popup dimensions

- Classification: Reliability safeguard approved by user direction
- Status: Implemented and real-Chrome verified
- Product impact: Restores the complete toolbar capture UI instead of a
  scrollable title-height strip
- Schedule impact: Bounded correction before native Accessibility selection

D-030 compacted the toolbar action but removed its working 510-pixel minimum
height and constrained the new shell with `min(560px, 100vh)`. Chrome determines
an action popup's viewport from that popup's content. Making the content height
depend on the not-yet-established viewport created a sizing feedback loop, and
the real popup collapsed to approximately Chrome's minimum window height even
though every control still existed in its accessibility tree.

The popup now establishes a 344 × 510 pixel root before Chrome measures it.
The body and shell fill that root, the shell retains its internal vertical
scroller, and no popup dimension depends on viewport-height units. This changes
no permissions, capture fields, surrounding-context policy, retry identity,
backend request, or persistence behavior.

All 68 extension tests pass, including a regression assertion that rejects
viewport-height units in popup dimensions. After reloading the unpacked
extension, real Chrome displayed the complete popup on an internal page, a
regular metadata-only page, and a 72-character selected-text state. The source
card, preview, note field, Save button, and inline-access setting remained
visible and reachable; verification did not submit a Capture.

## D-034 — User-triggered native Accessibility selection capture

- Classification: Addition approved by user direction
- Status: Implemented on `codex/native-accessibility-selection`; 108/108 host
  tests and primary-path user acceptance pass
- Product impact: Reduces native selected-text capture to one explicit shortcut
  and opens the existing review UI near the selection
- Schedule impact: Primary-path and D-035/B-016 compatibility gates closed

Recall will add a third configurable global action, **Capture Selection**, with
`Option+Shift+Command+S` as its default. Only after the user invokes that action
does Recall ask macOS Accessibility for the focused external application's
selected text, selected range, and—when the application supports it—the range's
screen bounds. It reads no window title or surrounding context, never simulates
copy, and does not modify the clipboard. Bounds are transient presentation data
and are not submitted, logged, or persisted.

The exact selected text within the 12,000-character limit and source application
enter the existing Quick Capture review, idempotency, and save pipeline. A
native selection has its own draft and UI label, but it continues to submit as the existing
`source_type: clipboard`; this addition therefore changes no API, schema,
database, extension, enrichment, or retrieval contract. Unsupported bounds fall
back to centering the window on the target screen without turning a valid text
selection into a failure. Missing permission, secure fields, empty selections,
unresponsive targets, and unsupported applications fail closed and offer an
explicit clipboard action rather than silently saving stale clipboard content.

Adding the third action must preserve existing `globalShortcutConfiguration.v1`
values through backward-compatible decoding. All enabled actions participate in
duplicate validation and whole-set registration rollback.

Passive selection observation is a separate, later addition. The intended
future shape is an explicit opt-in setting and a non-activating pill that keeps
candidate text only in memory, rejects secure fields, debounces and deduplicates
Accessibility notifications, and opens the existing composer only after a user
click. Splitting it from this decision keeps permission, one-shot reading,
cross-application compatibility, and anchored-window behavior independently
testable while retaining the explicit shortcut as the reliable fallback.

## D-035 — Opt-in transactional clipboard fallback for native selection

- Classification: Compatibility and privacy safeguard approved by user direction
- Status: Implemented on `codex/native-accessibility-selection`; 149/149 host
  tests pass and B-016 user acceptance closed on 2026-07-21
- Product impact: Lets the explicit Capture Selection shortcut work in apps
  such as WeChat that can copy a selection but do not expose its text through AX
- Schedule impact: B-016 real-device acceptance passed; user authorized merge

D-034 remains the primary path and continues to read selected text directly
without touching the clipboard. D-035 adds a separately persisted **Clipboard
Compatibility Mode** that is off by default. When the user explicitly enables
it and invokes Capture Selection, the AX reader may issue a fallback ticket for
the exact frontmost application whose selected-text lookup failed. A stable AX
focused element is retained when available with complete safety evidence; a
custom-drawn app that omits that element uses an application-scoped ticket.
Missing permission, Recall itself, known secure/protected content, whitespace,
and oversized input never enter this fallback.

The transaction waits for the global shortcut modifiers to be released and
deep-copies every pasteboard item/type into bounded in-memory Data before event
injection. Any unmaterializable item, more than 100 items, more than 128 types
per item, more than 64 MiB total data, or an observed pasteboard race aborts.
The full AX/pasteboard transaction runs on a serial actor outside `MainActor`,
so lazy-provider materialization and bounded cross-process AX waits do not block
the app UI. Immediately before each event sequence, Recall revalidates the ticket's
frontmost PID, exact AX focused element when available, all exposed safety
attributes, event-posting access, and Secure Event Input. The backup is never logged, persisted, attached to a
draft, or sent to the backend.

One `NSPasteboard.changeCount` advance cannot identify who wrote the clipboard.
Recall therefore sends Copy twice and accepts text only when both attempts
produce the exact next counts, the same complete materialized payload, the same
text, and the same verified focus ticket. It attempts restoration from newly
constructed pasteboard items only after that confirmation and only while the
last count remains unchanged. Detected ambiguity, timeout, focus change, or
payload mismatch creates no draft and attempts no restore. A confirmed fallback
draft remains a native selection, carries no bounds or surrounding context, and
saves through the existing clipboard-text API contract.

This mode cannot guarantee restoration or invisibility. macOS exposes neither
pasteboard-writer identity nor an atomic compare-and-restore operation, so a
sufficiently narrow external-writer race can still be overwritten and a source
app that processes Copy after Recall's bounded wait can still replace the prior
clipboard. A crash, lazy representation that cannot be materialized, or write
failure can also prevent full restoration. Clipboard history applications,
Universal Clipboard, or other observers may record either temporary Copy.
Settings and fallback review UI disclose this best-effort boundary; it must not
be described as lossless, guaranteed, or private from clipboard observers.
Application-scoped fallback also cannot prove per-control safety when a
custom-drawn app omits those attributes; it remains opt-in and equivalent to the
user explicitly asking Recall to perform Copy in that verified frontmost app.

## D-037 — Persisted image notes with opt-in background visual indexing

- Classification: Addition approved by user direction
- Status: Implemented; automated verification and real-app AI-disabled and
  AI-enabled image-note acceptance pass
- Product impact: A screenshot can now remain an image memory with an optional
  note instead of existing only as transient OCR input
- Schedule impact: Crosses macOS, API, persistence, enrichment, search,
  migration, deletion, and privacy boundaries

D-027 remains the explicit **Text note** path: its temporary screenshot is
discarded after GPT or Apple Vision extraction, and the user reviews text before
saving. D-037 adds a separate **Image note** choice to the same screenshot
review. Its original PNG is saved immediately as the authoritative source and
its optional user note remains an independent field. V1 accepts exactly one PNG
or JPEG per Capture, up to 8 MiB, 20,000 pixels per dimension, and 40
megapixels. Attachment metadata lives in a normalized
`capture_attachments` table while immutable bytes live under a configurable,
application-owned directory beside the database by default; SQLite stores no
image blob or user-controlled filesystem path.

Image analysis is opt-in and off by default. A persisted global master switch is
the privacy boundary: while it is off, the image-note draft cannot enable AI and
the upload contract is forced to `analyze_image: false`. When the master switch
is on, each new image draft defaults to analysis on but can be turned off for
that image before saving. An analyzed image is first committed locally and then
uses one background multimodal Structured Outputs request. OCR is
stored in the existing `selected_text` field; visual title, summary, concepts,
entities, tags, caveats, and search aliases use the existing AI fields. This
preserves original/user/AI separation and lets FTS and semantic retrieval index
both visible words and non-text visual meaning without a second search system.
AI output is derived metadata only and never replaces the image. The Responses
request explicitly uses `store: false`; this avoids Recall creating reusable
server-side response state but does not supersede the provider's data policies.

The attachment API returns an opaque loopback content path, never a filesystem
path. Upload type/signature, dimensions, and byte bounds are validated before
storage; random UUID filenames, path-containment checks, restrictive file modes,
idempotent client IDs, and cleanup on failed or duplicate creation prevent user
paths and retry files from leaking into persistence. Deleting a Capture removes
its database/FTS/embedding state and referenced local image. Provider failure or
backend restart leaves the original and note intact as a visible, retryable
error. The first implementation deliberately reuses the existing in-process
background-task boundary rather than introducing a queue service.

D-036 remains a separate capture-correctness decision and was merged through PR
#14 before D-037 integration. The image-note model does not change its bounded
structured-clipboard resolver.

## D-038 — Editable memories with explicit user overrides and state-driven UI

- Classification: Addition approved by user direction
- Status: Implemented, automated-verified, and user-accepted on
  `codex/note-editing-ui-polish`
- Product impact: Users can correct and organize saved memories without making
  user-authored changes indistinguishable from captured or AI-generated data
- Schedule impact: Crosses migration, API, FTS, embedding invalidation, macOS
  editing, sorting, notification lifecycle, Settings, and detail/list UI

Migration 005 adds a user-edit layer rather than repurposing captured or AI
columns. Corrected selected text and source metadata are stored as explicit
overrides; the captured database values remain intact. A user title, problem,
key insight, why-it-mattered value, caveats, and tags similarly take display and
FTS precedence without replacing `ai_*`, `problem`, `tags_json`, or other model
output. Empty user strings/arrays deliberately hide an inapplicable generated
field, while `NULL` continues to mean “use the AI value.” The ordinary user note
is user-owned and may be updated directly.

`user_edited_at` records explicit edits only. Existing `updated_at` remains a
broader system revision timestamp because AI state transitions also update it.
Library ordering can use creation or user-edit time in either direction;
unedited memories fall back to their creation time. Search results retain
relevance order. Static minute-level list timestamps replace continuously
updating relative seconds.

Changing effective selected content, source metadata, or the user note marks
the current AI interpretation stale and hides it. Recall does not silently call
the provider after an edit: that would spend quota, transmit changed content,
and replace context without a new explicit user action. The detail view instead
offers **Refresh AI**, which uses the effective corrected source and current note,
replaces only the AI layer, and preserves user organization overrides. Any edit
invalidates the old embedding while trigger-synchronized FTS immediately indexes
the effective user-visible values.

Application notices now declare either a bounded lifetime or the state that
resolves them. Clipboard warnings expire and clear on a later successful
capture; connection errors clear after a successful health/list/search probe;
processing notices become a short ready/error result when polling observes the
terminal state. Settings separates shortcut registration from automatically
saved privacy/features, and the screenshot image-note composer reserves fixed
preview, description, and switch geometry so the AI toggle cannot resize or
shift nearby content.

The completed automated gate passes 243 backend tests, all 44 deterministic
stress scenarios, all 68 Chrome-extension tests, and 189/189 host macOS tests,
including production Apple Vision OCR. User acceptance on 2026-07-21 covered
editing, sort ordering, notice resolution, Settings tabs, and stable image-
composer geometry.

## D-036 — Conservative structured-text line restoration

- Classification: Capture-correctness addition approved by user direction
- Status: Merged through PR #14; 176/176 host tests and the live Gemini payload
  verification pass
- Product impact: Preserves useful paragraph and line boundaries when a source
  application supplies plain text together with HTML or RTF clipboard data
- Schedule impact: Bounded first slice before image attachments or a full rich-
  text viewer

Recall's current Capture contract, JSON transport, SQLite `TEXT` column, and
SwiftUI `Text` views already preserve newline characters. The first observed
loss therefore belongs at the native intake boundary: Clipboard Capture
currently asks `NSPasteboard` only for `.string`, while some rich source
applications expose better paragraph boundaries in HTML or RTF.

The native clients require plain text and may also decode bounded HTML or RTF
representations into inert text. Plain text remains authoritative for its
content and leading/trailing whitespace. A structured candidate may project a
richer boundary only onto an existing internal plain-text whitespace separator.
Ordered visible anchors must match. Supported paired Markdown presentation
delimiters, headings, and list bullets may occupy a plain gap because rendered
HTML omits those literal characters, but every delimiter remains unchanged in
the returned text; unpaired operators remain anchors and reject a mismatch.
Gemini math nodes may contribute their bounded `data-math` value only when their
class identifies an inline or block formula, and the resulting `$...$` or
`$$...$$` is still verified against the authoritative plain characters. A
candidate cannot move a boundary where plain text has no separator. HTML/RTF
without a matching plain representation is rejected.

The resolver is limited to explicit Clipboard Capture. Selection Capture and its
opt-in compatibility fallback remain at the D-034/D-035 behavior. No clipboard
representation is logged, persisted as markup, sent before Save, or added to a
draft beyond the resolved text.

Multiple pasteboard items are resolved independently and joined with newlines,
matching macOS's plain-text behavior without allowing one item's HTML/RTF to
reshape another item's text. If the explicit clipboard exceeds its bounded item
or type inspection limits, Recall falls back to the system plain-text value
rather than partially returning rich data.

Accessibility selection remains an explicitly weaker source. Recall can retain
the exact string or attributed string returned by `AXSelectedText`, but rendered
MathJax/KaTeX and other custom content may omit original Markdown or TeX syntax
from the Accessibility tree. Recall must not reverse-engineer or invent source
markup that the target application did not expose. Clipboard capture and the
browser client remain the honest compatibility paths for those sources.

D-036 changes no API, schema, migration, enrichment, FTS, or embedding
projection. Persisting original HTML/RTF/Markdown, declaring a source-format
field, or rendering Markdown/LaTeX requires a later reviewed contract and
privacy decision. Image attachments remain a separate storage design.

## D-039 — Branded Chrome settings and movable capture surfaces

- Classification: UI/UX addition approved by user direction
- Status: Implemented and real-Chrome verified on
  `codex/note-editing-ui-polish`; 70/70 extension tests pass
- Product impact: Makes browser capture visually consistent with Recall, moves
  browser preferences out of the transient popup, and keeps long content usable
- Schedule impact: Bounded Chrome-extension slice; no backend or data migration

The toolbar popup, inline selection pill, and inline composer reuse Recall's
checked-in pink icon and palette. The toolbar popup retains D-033's deterministic
root-sizing rule at a roomier 380 × 560 pixels: its selected-text preview is
vertically scrollable and resizable, while the Save button has a fixed 40-pixel
height and cannot stretch with the note field.

A dedicated Manifest V3 options page owns browser preferences. It shows the
currently assigned `_execute_action` shortcut and links to Chrome's extension
shortcut manager because the browser does not permit an extension to rewrite
its command binding programmatically. The existing **Show Add to Recall when I
select text** control moves from the popup to this page without changing its
optional-permission, revocation, or off-by-default behavior.

The inline composer's source title now wraps within two visible lines rather
than widening the surface. Its branded header is a mouse/pointer drag handle;
movement is clamped to the current viewport and a resize re-clamps an open
composer. Dragging does not alter the host document layout or change submission,
retry, BFCache, focus, or privacy state. The only new page-readable extension
resource is the existing 32-pixel icon, scoped to HTTP/HTTPS origins; no new
required permission is introduced.

Real Chrome verified the popup, options page, current shortcut display, branded
selection pill, wrapped long source title, and a composer dragged to the viewport
edge. The user's inline-access preference remained off throughout this visual
check; the isolated production-script harness exercised the inline UI without
changing that permission.

## D-040 — Canonical browser icon and adaptive native brand mark

- Classification: UI/UX addition approved by user direction
- Status: Implemented and user-accepted on `codex/note-editing-ui-polish`;
  70/70 extension and 189/189 host macOS tests pass
- Product impact: Keeps browser and native capture surfaces recognizable while
  preserving platform-appropriate rendering and long Page metadata
- Schedule impact: Bounded asset and presentation change; no API, storage, or
  migration work

The checked-in 128-pixel Chrome image is the canonical browser logo. Chrome's
16-, 32-, and 48-pixel files remain because the manifest benefits from real
native-size raster assets, but they are derived from that master rather than
maintained as separate artwork. The action popup's Page title and URL no longer
use ellipsis: they wrap within a bounded, keyboard-focusable region that scrolls
independently when either value is unusually long.

The macOS asset catalog adds one transparent vector `RecallMarkTemplate` that
uses the Recall logo's ring, satellite circle, and center dot as monochrome
geometry. `MenuBarExtra` renders it as a template so macOS supplies the correct
light/dark and selected-state color. The shared Quick Capture header uses the
same vector with Recall's accent color, including the screenshot-note save
window. The colored square AppIcon remains the application and Dock icon.

Xcode compiled the vector asset and the host suite passed all 189 tests,
including production Apple Vision OCR. The dependency-free extension suite
passed all 70 tests, including new regressions for Page wrapping, independent
scrolling, and removal of title ellipsis. Live screen inspection was unavailable
in the verification environment because macOS ScreenCaptureKit could not start;
asset rendering, compilation, and automated layout evidence remain complete.
The user subsequently accepted the popup Page metadata, menu-bar logo, and
Quick Capture logo in the running products on 2026-07-21.

## Pending decisions

Model snapshots, future dimension migrations, and the exact provider-metadata
fields remain implementation-layer decisions and must not be silently fixed
here.
