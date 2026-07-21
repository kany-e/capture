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
| D-031 | Native global capture through Carbon and one app-level coordinator | Addition | Implemented; 68/68 macOS tests pass; signed-build manual gate pending |

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
- Status: Implemented; automated and bounded real-UI verification are complete,
  while the normally signed-build physical hotkey and real screenshot-region
  manual gate remains open
- Product impact: Makes screenshot and clipboard Quick Capture available while
  Recall is running even if its main window is closed
- Schedule impact: Current native priority; Accessibility selection remains next

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

The temporary unsigned test build did not have Screen Recording permission. It
showed the explicit permission error and the verification deliberately did not
change that permission. Therefore actual physical global key delivery from
another app and a real screenshot-region selection are not claimed as verified;
both remain an explicit user acceptance gate in the normally signed build.

## Pending decisions

Model snapshots, future dimension migrations, and the exact provider-metadata
fields remain implementation-layer decisions and must not be silently fixed
here.
