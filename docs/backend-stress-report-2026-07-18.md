# Backend stress report — 2026-07-18

> Historical hardening snapshot. For current setup and verification commands,
> use the root README and `services/backend/README.md`.

Status: completed against the local integrated Developer B runtime

Branch: `test/backend-stress`

Base: `integration/layers-6-7` at `3389bae`, backend 0.7.0

No real OpenAI request or user data was used. Every destructive probe ran
against a temporary SQLite database that was removed by the harness.

## Executive result

The existing suite passed all 165 tests before stress. The escalated stress run
then completed 44 scenarios in 67.025 seconds:

- 28 scenarios passed;
- 16 scenarios exposed a contract, lifecycle, resilience, or performance
  break;
- 1,000 bulk API writes completed without a SQLite lock error;
- the exact Capture and FTS row counts remained synchronized at 1,000;
- `PRAGMA integrity_check` returned `ok`; and
- the bulk database remained healthy and searchable after restart.

The backend is robust for moderate local writes and exact keyword lookup. It is
not yet safe against oversized input, malformed provider implementations, NUL
search queries, extreme finite vectors, or concurrent full-dataset semantic
scans.

## Reproduction

From `services/backend/` on this branch:

```bash
<python-with-project-dependencies> tools/stress_backend.py
```

The script prints structured JSON and continues after individual HTTP 500s so a
single defect cannot hide later results. It uses deterministic local provider
doubles, 1,500+ synthetic Captures, exact contract boundaries, ambiguous cards,
hostile strings, bulk writes, concurrent searches, corrupt-row injection, and
restart checks.

## Harness execution errors

- The first direct launch failed before any scenario with
  `ModuleNotFoundError: No module named 'app'` because Python placed `tools/`,
  not the backend root, on `sys.path`. The entry point now resolves its backend
  root explicitly. The same direct command then compiled and ran successfully.
- The first completed run recorded 29 passes and 11 breaks, but its JSON echoed
  the complete 2,000-term query and made console evidence unnecessarily large.
  The harness now records query length plus an 80-character preview. The
  escalated second run added the 64-worker write phase, realistic 1,536-
  dimension vectors, stricter latency thresholds, and the stuck-processing
  assertion; it completed with the 28-pass/16-break result reported above.
- Expected application 500s emitted stack traces during the first run. The
  second run raised the harness logging threshold while retaining HTTP status
  and safe error-envelope evidence in structured output.

## Breakpoints

### ST-001 — Client metadata and request body are effectively unbounded

- Severity: High
- Reproduction: submit 250,000 characters each in `source_app`, `source_title`,
  and `source_url`, plus a 1,000,000-character `user_note`.
- Observed: HTTP `202` in 67.902 ms for approximately 1.75 MB of metadata.
- Impact: one card can inflate SQLite, response memory, enrichment prompt size,
  and later embedding input. A real provider can reject the prompt after the
  source is already stored.
- Expected hardening: add field limits and an overall request-body limit aligned
  with the Chrome and macOS clients.

### ST-002 — `client_capture_id` does not provide idempotency

- Severity: Medium
- Reproduction: POST the same valid payload twice with one UUID in
  `client_capture_id`.
- Observed: both requests returned `202` and created two unique server IDs.
- Impact: client retry, double-click, or reconnect can create duplicate cards.
- Expected hardening: decide whether this field is descriptive or idempotent;
  if idempotent, add a uniqueness rule and return the original Capture.

### ST-003 — Boolean coercion violates the checked-in JSON contract

- Severity: Medium
- Reproduction: send `context_truncated: 1` or
  `context_truncated: "false"`.
- Observed: both returned `202`; the integer became `true` and the string became
  `false`.
- Impact: the runtime accepts types rejected by `capture.schema.json`, so a
  client can pass schema validation differently from the server.
- Expected hardening: use strict boolean validation.

### ST-004 — Invalid UTF-8 bypasses the stable validation envelope

- Severity: Low
- Reproduction: send invalid UTF-8 bytes in an `application/json` body.
- Observed: HTTP `400` with FastAPI's default body instead of the versioned
  `validation_error` envelope used by malformed JSON and model validation.
- Impact: clients need a second error shape for one malformed-input class.

### ST-005 — Natural keyword fallback can return no result for a relevant card

- Severity: Medium
- Reproduction: with embeddings unavailable, store a card containing “Enable
  SQLite WAL mode” and note “fixed lock errors”, then search for
  `which sqlite setting fixed my desktop lock errors`.
- Observed: HTTP `200` with zero results.
- Cause: the FTS builder joins every query segment with `AND`; unmatched helper
  words eliminate otherwise strong keyword candidates.
- Impact: provider-off retrieval works for exact identifiers but is brittle for
  natural personal-memory questions.

### ST-006 — A NUL in `q` causes an internal server error

- Severity: High
- Reproduction: `GET /v1/search?q=ERR%00MODULE`.
- Observed: HTTP `500 internal_error`; SQLite raised `OperationalError:
  unterminated string`.
- Impact: one client-controlled query can crash an individual search request.
- Expected hardening: reject or normalize control characters before building
  the FTS expression and map SQLite query errors to a stable client error.

### ST-007 — Search query length is unbounded and echoed back

- Severity: Medium
- Reproduction: send 2,000 terms totaling 34,889 characters.
- Observed: HTTP `200`, zero results, 68.279 ms; the complete query was included
  again in the response.
- Impact: request and response amplification plus unnecessary FTS parsing and
  provider-embedding cost.
- Expected hardening: set a documented `q` limit before FTS or embedding work.

### ST-008 — Full-dataset semantic scans collapse under concurrency

- Severity: High
- Four-dimensional stress set: 1,005 ready vectors searched 50 times with 16
  workers. All requests returned `200`, but median latency was 6,841.723 ms and
  maximum latency was 8,886.450 ms.
- Default-size-like stress set: after adding 500 vectors with 1,536 dimensions,
  one search over 1,505 cards took 1,674.017 ms. Twelve searches with eight
  workers reached 14,261.557 ms median and 17,705.718 ms maximum.
- Impact: search remains correct but becomes unusable for an interactive local
  UI under overlapping requests or a growing card collection.
- Cause: every semantic query loads and validates every ready Capture and its
  JSON vector, then calculates cosine similarity in Python.
- Expected hardening: coalesce/cancel overlapping UI searches immediately and
  bound semantic candidates; evaluate cached vectors or a small local vector
  index only if the measured dataset requires it.

### ST-009 — Provider-neutral enrichment accepts empty invalid output as ready

- Severity: High
- Reproduction: inject a provider that returns an `EnrichmentPayload` with
  empty scalar strings and empty-string list items.
- Observed: the Capture became `ready` with an empty AI title.
- Cause: normalization is performed inside `OpenAIEnrichmentProvider`, not at
  the provider-neutral `EnrichmentService` boundary.
- Impact: the planned Apple/local provider can bypass the same quality rules
  that protect OpenAI output.

### ST-010 — A provider returning `None` leaves the card stuck processing

- Severity: High
- Reproduction: inject a provider whose `enrich` method returns `None`.
- Observed: POST returned `202`; background processing raised `AttributeError`;
  the persisted card remained `processing` indefinitely.
- Impact: polling clients never reach `ready` or `error`.
- Expected hardening: validate every provider result inside the service and wrap
  result normalization/storage in the same failure-to-error lifecycle guard.

### ST-011 — Enrichment output size and list counts are unbounded

- Severity: High
- Reproduction: return five large scalar fields and four arrays of 1,000
  approximately 200-character values.
- Observed: the Capture became `ready`; one enrichment grew SQLite by 3,407,872
  bytes.
- Impact: a provider can cause database, FTS, response, and embedding-input
  amplification even when client input is small.

### ST-012 — Extreme finite vectors crash cosine similarity

- Severity: High
- Reproduction: store and query with `[1e308, 1e308]`.
- Observed: HTTP `500`; squaring a finite component raised `OverflowError`.
- Impact: an extreme provider vector or corrupted vector can break search for
  otherwise readable cards.
- Expected hardening: validate vector magnitude/dimension at the service
  boundary and use an overflow-safe norm calculation.

### ST-013 — Health reports OK when persisted rows are unreadable

- Severity: Medium
- Reproduction: corrupt one persisted `tags_json` value, then request the card
  and `/health`.
- Observed: the card returned `500`; `/health` returned `200` with database
  status `ok`.
- Impact: the process looks healthy to clients while list/detail/search may fail
  when they encounter the damaged row.
- Expected hardening: expose a deeper diagnostic or periodic integrity check;
  the lightweight liveness probe can remain cheap if its scope is documented.

## Passed resilience cases

- Exact 12,000-character selection and 20,000-character context boundaries were
  accepted; one extra character was rejected with the stable envelope.
- Whitespace-only source content, unknown fields, malformed JSON, and invalid
  timestamps were rejected.
- Unicode, right-to-left markers, combining characters, CJK, emoji, code fences,
  SQL text, prompt-injection text, and embedded NUL source content persisted
  without executing as instructions or SQL.
- Text after an accepted NUL in source content remained searchable.
- 300 sequential writes completed at 125.42 requests/second.
- 500 writes at 64 workers completed at 119.80 requests/second; another 200 at
  32 workers completed at 115.97 requests/second.
- All 1,000 bulk cards had unique server IDs, one synchronized FTS row each,
  and a clean SQLite integrity check.
- Restart preserved health, newest-first listing, and exact FTS retrieval.
- Exact `ERR_MODULE_NOT_FOUND` lookup worked with embeddings disabled.
- Semantic retrieval returned both deliberately conflicting WAL cards and kept
  both similar local-AI/cloud-AI cards available.
- FTS operator-like input, punctuation-only input, and emoji-only input did not
  become executable FTS syntax.
- An unconfigured Chrome-extension origin was rejected by CORS.

## Additional observations not counted as breaks

- `source_url` accepts a syntactically valid `javascript:` URI because the
  contract currently allows any URI. A client rendering this field as a link
  must never execute non-HTTP schemes; narrowing the API to expected schemes is
  safer.
- The deterministic semantic fixtures intentionally create many close vectors,
  so several ambiguous searches filled the 100-result limit. This is a useful
  worst case, not a claim about real embedding quality.
- The bulk write result shows the current five-second SQLite timeout is adequate
  for this in-process local load; it does not prove multi-process or disk-full
  behavior.

## Test limitations and remaining gates

- B-007 and B-008 remain open: no real Responses API or embeddings request ran.
- The harness uses FastAPI's in-process `TestClient`, not a separate Uvicorn
  process over a real socket.
- Power loss, process kill during transaction commit, disk-full behavior,
  read-only filesystem behavior, and multi-process writers were not simulated.
- Chrome-to-backend-to-macOS confirmation remains B-009/B-006.
- The performance thresholds are interaction-oriented guardrails, not a formal
  service-level agreement: one second for a single local search, two seconds
  for the small-vector concurrent set, and five seconds for the realistic-vector
  concurrent set.

## Recommended repair order

1. Reject control characters and cap `q`; prevent NUL-triggered 500s.
2. Validate and normalize every provider result in `EnrichmentService`; ensure
   all post-provider exceptions store `error` instead of leaving `processing`.
3. Validate vector dimensions/magnitude and make cosine norms overflow-safe.
4. Bound client metadata, request size, enrichment strings, and array counts.
5. Decide and enforce `client_capture_id` idempotency.
6. Improve provider-off query relaxation and bound/cancel semantic scans before
   adding a more complex vector dependency.
7. Align strict boolean and malformed-byte errors with the checked-in contract.
8. Add an explicit deep-database diagnostic for corrupt rows.

This report records defects only. No production behavior was changed during the
stress-test task.

## Remediation run — `fix/backend-stress-hardening`

The follow-up hardening branch resolves all 13 breakpoint groups without adding
an external service or vector dependency. The original observations above are
retained as the pre-fix baseline.

Verification after the fixes:

- Python regression suite: **181 passed, 0 failed**;
- adversarial harness: **44 passed, 0 breaks** in 17.896 seconds;
- 1,000 Capture/FTS rows remained synchronized with SQLite integrity `ok`;
- the 1,505-card / 500 realistic-vector single scan completed in 826.369 ms;
- 12 concurrent realistic-vector scans completed with 2,473.740 ms median and
  3,024.309 ms maximum latency; and
- bytecode compilation completed successfully for `app`, `tests`, and `tools`.

| Finding | Resolution |
| --- | --- |
| ST-001 | Added explicit app/title/URL/note limits matching the checked-in request schema. |
| ST-002 | `client_capture_id` is now transactionally idempotent, including concurrent retries. |
| ST-003 | `context_truncated` now requires a JSON boolean. |
| ST-004 | Invalid UTF-8 now returns the stable `422 validation_error` envelope. |
| ST-005 | FTS retries with escaped `OR` terms only when the strict `AND` pass is empty. |
| ST-006/ST-007 | Search rejects control characters and caps `q` at 512 characters. |
| ST-008 | Ready vectors are decoded and overflow-safely normalized once per database write revision. |
| ST-009/ST-010 | Provider-neutral validation maps empty, `null`, partial, or generic output to terminal `error` with failure code `invalid_model_output`. |
| ST-011 | Enrichment strings, arrays, and array items have checked-in limits. |
| ST-012 | Cosine normalization uses `math.hypot` and rejects unusable vectors. |
| ST-013 | Health runs SQLite quick integrity plus stored JSON-array checks. |

### Hardening-run execution errors

These setup errors did not execute application tests and are recorded rather
than hidden:

- A pytest launch from the repository root produced 10 collection errors with
  `ModuleNotFoundError: No module named 'app'`. It was rerun from
  `services/backend`, where the configured Python path applies.
- `.venv/bin/pytest` was then attempted inside the stress worktree, which does
  not contain its own virtual environment, and exited `127`. Verification used
  the dependency-complete interpreter from the main worktree against the stress
  worktree source.
- The first compile-only command was issued one directory too high and printed
  `Can't list 'app'`, `tests`, and `tools`. It was rerun from
  `services/backend` and completed with exit code `0`.
- The first post-fix harness run reported 43 passes and one apparent break
  because the harness still expected NUL queries to return `200`. The contract
  intentionally rejects them with `422`; after correcting that stale expected
  value, the unchanged backend passed 44/44.

Remaining gates are unchanged: no real Responses API or embedding request was
made, and power-loss, disk-full, read-only-filesystem, multi-process writer, and
real-socket Uvicorn behavior remain outside this deterministic local harness.
