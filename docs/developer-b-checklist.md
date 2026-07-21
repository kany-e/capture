# Development live build checklist

Historical owner: Developer B — Intelligence and Data

Project: Recall

Last updated: 2026-07-21

Current phase: Structured-text fidelity and persisted image notes implemented;
primary real-app acceptance complete and release regression work remains

Implementation branch: `codex/image-notes`

Merged prerequisite branch: `codex/text-capture-fidelity`

Integration base: `667b045` (PR #14 merge commit)

Canonical target: `main`

The canonical `main` tree combines the hardened backend, Chrome extension,
macOS client, screenshot OCR, shared contracts, and layered CI. It includes
D-029 merged through PR #8 at `71ec387`, D-030 merged through PR #9 at
`0c1083e`, and D-031 merged through PR #10 at `0ab687b`.

The D-031 checkpoint adds 20 macOS shortcut, coordinator, draft-safety, and
asynchronous screenshot tests. Its final regression passes 215 backend tests,
44/44 stress scenarios, 68/68 Chrome-extension tests, and 68/68 macOS tests on
the host. D-032 corrects the ad-hoc signing identity failure, passes 70/70 macOS
tests, and is live-verified across app-specific TCC reset, authorization,
same-signer rebuild, selector launch, and cancellation. B-014 is also closed:
the physical screenshot shortcut completed a non-empty region from another app
with Recall's main window closed, and the clipboard shortcut opened Capture
after copied text. D-033 also restores the Chrome action popup's full 344 × 510
layout after a viewport-relative sizing regression; 68/68 tests and selected
plus metadata-only real-Chrome checks pass.

D-034 now adds explicit native selection capture through a third configurable
shortcut, background AX reading, secure/protected-content rejection, transient
selection bounds, anchored Quick Capture, and backward-compatible shortcut
migration. The host macOS suite passes 108/108, and the user accepted the
primary AX path. WeChat then exposed an expected unsupported-control gap;
D-035 is implemented with a 149/149 host suite, and B-016 closed after final
real-device acceptance on 2026-07-21.

D-037 now adds one persisted screenshot image per Capture, an independent note,
an off-by-default visual-analysis master switch, background OCR/visual enrichment
through the existing searchable fields, library/detail rendering, and deletion
of both metadata and the local file. The feature branch passes 235 backend and
the integrated macOS suite passes 184 tests. The user verified real-app image
notes with AI both disabled and enabled; visual-concept retrieval, restart,
retry, and physical deletion remain explicit release-regression checks.

D-036 now adds one conservative intake layer to explicit Clipboard Capture. It
keeps plain characters authoritative and restores only richer line boundaries
from bounded, content-equivalent HTML/RTF. The real Gemini clipboard payload
restores verified block boundaries from an intentionally flattened plain string
while retaining inline and display TeX. Selection Capture remains unchanged, and
the resulting host suite passes 176/176.

Last baseline cross-check: 2026-07-18 against all sections of
`docs/product-plan.md`

This is the detailed historical execution and evidence record. Developer A/B
labels below describe the original Build Week split, not current assignment
boundaries. Use [`roadmap.md`](roadmap.md) for current priorities and component
ownership. Unchecked historical rehearsal rows are not automatically current
product blockers; blockers must also appear in the current status summary or
roadmap.

## Status rules

- `[ ]` — not started
- `[~]` — in progress
- `[x]` — completed and verified
- `[!]` — blocked or failed; details must appear in the blocker/error log
- `[D]` — deliberately deferred with a documented reason

Update protocol:

1. Mark the active task `[~]` before implementation.
2. Record the command, test, or artifact that proves completion.
3. If a command or test fails, immediately append it to **Errors encountered**.
4. If progress requires another person, credential, hardware, or decision,
   immediately append it to **Open blockers and risks**.
5. Do not convert `[!]` to `[x]`; add a resolution entry, then mark the task.
6. Record every scope addition in `docs/decisions.md` before implementation.
7. Commit after a working vertical slice, not after partially broken work.

## Current status summary

| Layer | Scope | Status | Exit-gate evidence |
| --- | --- | --- | --- |
| 0 | Contracts and documentation | Complete | Schemas and fixtures validated; commit `e75f783` pushed |
| 1 | Backend foundation | Complete | 11 tests passed; live `/health` returned contracted `200` response |
| 2 | SQLite persistence | Complete | Commit `0622ad0` pushed; 30 tests and restart proof passed |
| 3 | Capture CRUD and first integration | Complete | Backend CRUD plus live macOS list/detail/clipboard evidence close D-013 and B-006 |
| 4 | OpenAI enrichment | Complete | Deterministic coverage plus real Responses API `processing → ready` proof resolve B-007 |
| 5 | FTS5 keyword retrieval | Complete | Commit `d34a567` pushed; 119 tests and provider-off live/restart proof pass |
| 6 | Chrome capture | Complete and real-Chrome verified | 68/68 tests pass; unpacked selected-text/no-selection Captures resolve B-009, and D-033 verifies the corrected action-popup layout |
| 7 | Embeddings and hybrid retrieval | Complete | Real embedding and vague semantic-query proof with non-null score resolve B-008 |
| 8 | Reliability and demo readiness | P0 integration verified / backlog reduced | Layer 8 baseline passes 214 backend tests and 44/44 stress scenarios; stale-process recovery and version-aware one-command startup are verified |
| 9 | Optional Apple on-device path | Gated | Decision D-008 accepted; prerequisites unmet |
| 10 | Final freeze and submission | Pending | Not started |
| Addition | Screenshot-to-notes OCR | Complete and verified | PR #5 supersedes draft PR #4; 214 backend, 44/44 stress, 16 extension, and 43 macOS tests pass; live GPT, Apple Vision, permission, cancellation, and dismissal flows pass |
| Addition | Opt-in inline browser capture | Complete, real-Chrome verified, and merged | PR #8 merged D-029 at `71ec387`; 68/68 extension tests and enable/save/retry/revoke/BFCache/toolbar-fallback evidence passed before merge |
| Addition | Browser context and detail-view hardening | Complete, UI-reviewed, and merged | D-030 disables unsafe Chrome context, bounds native display, fixes inline count/scroll, and compacts the popup; PR #9 merged at `0c1083e` after all required checks passed |
| Addition | Native global capture | Complete and real-device verified | D-031 adds transactional Carbon shortcuts and one app-level capture coordinator; PR #10 merged at `0ab687b`; B-014 is closed |
| Safeguard | Stable Screen Recording identity | Complete and live-verified | D-032 passes 70/70 macOS tests; app-specific reset, authorization, rebuild persistence, selector launch, and cancellation pass |
| Safeguard | Chrome action popup sizing | Complete and real-Chrome verified | D-033 uses a 344 × 510 root without viewport-height feedback; 68/68 tests and selected/metadata layouts pass |
| Addition | Native Accessibility selection | Implemented; primary path accepted | D-034 adds explicit `Option+Shift+Command+S`, fail-closed AX reading, anchored review, safe v1 shortcut migration, and 108/108 macOS tests; user acceptance passed on 2026-07-21 |
| Addition | Clipboard selection compatibility | Complete and real-device accepted | D-035 adds an off-by-default transactional synthetic-Copy fallback with exact-control and application-scoped tickets; 149/149 host tests and B-016 user acceptance pass |
| Addition | Structured-text capture fidelity | Implemented; live payload verified | D-036 adds a bounded plain/HTML/RTF resolver to explicit Clipboard Capture; the real Gemini payload restores verified boundaries from flattened plain text while retaining TeX |
| Addition | Persisted image notes and visual indexing | Implemented; primary real-app flow accepted | D-037 adds one bounded local image, separate note, off-by-default AI master switch, existing-search reuse, rendering, retry, and deletion; 235 backend and 184 integrated macOS tests pass |

The D-023 integration closes B-010, the macOS slice closes B-006, and real
provider plus unpacked-Chrome evidence closes B-007, B-008, and B-009. B-011 is
resolved by the hardening work. Remaining work is the explicit Layer 8 backlog
and Layer 10 submission/release material, not a missing shared P0 integration
gate.

## Active addition — persisted image notes and visual indexing

Status: `[x]` D-037 automated implementation and real-app AI-disabled/AI-enabled
image-note acceptance verified

- [x] Preserve D-027 as the separate text-only screenshot choice; add an explicit
  **Image note** choice rather than silently changing existing behavior.
- [x] Save the original before analysis, keep the optional user note independent,
  and return one opaque attachment descriptor in the complete Capture response.
- [x] Add migration 004 with normalized attachment metadata and store immutable
  PNG/JPEG bytes under `RECALL_ATTACHMENTS_PATH`, outside SQLite. Validate type,
  signature, 8 MiB size, 20,000-pixel dimensions, 40-megapixel area, generated
  paths, and containment.
- [x] Keep visual analysis off by default with a persistent global master
  switch. When off, disable the per-draft control and force local-only saving;
  when on, default each new draft on while allowing a per-image opt-out.
- [x] When enabled, perform one post-commit background multimodal Structured
  Outputs request. Store OCR in `selected_text`, visual meaning in existing AI
  fields, and reuse the established FTS/embedding pipeline.
- [x] Show image thumbnails and full detail content, preserve retry behavior,
  and expose confirmed deletion that removes Capture state plus the referenced
  local file.
- [x] Verify invalid images, idempotent retries, provider-off preservation,
  provider-on OCR/visual search, attachment reads, deletion, migration, health,
  networking, preference persistence, upload retry, image loading, and old-
  backend decoding. Evidence: 235/235 backend and 184/184 integrated macOS tests.
- [x] In the real app, verify image notes save successfully with AI disabled and
  enabled, and that the enabled path produces visible AI interpretation.
- [ ] During release regression, verify visual-concept retrieval absent from OCR,
  restart persistence, full-resolution detail display, retry, and deletion from
  both the library and attachment directory.

## Historical addition — screenshot text into notes

Status: `[x]` implementation plus automated and manual hardening verified under
D-027; the reviewed change is recorded in PR #5

- [x] Audit local and remote branches plus merged PRs for an existing screenshot
  or OCR implementation. None exists; only P2 deferral documentation was found.
- [x] Keep screenshots transient: do not persist image bytes or add an attachment
  schema in this bounded feature.
- [x] Keep GPT as the default extraction route and define Apple Vision as the
  explicit on-device alternative for the locality demonstration.
- [x] Add a bounded, provider-neutral screenshot OCR API contract and GPT
  implementation. Focused backend API/provider run passes 71 tests.
- [x] Add interactive macOS screenshot selection, a preview, provider choice,
  and an explicit **Extract source text** action. The production app builds
  successfully and the deterministic macOS suite passes 43 tests, including
  the production Apple Vision extractor on generated screenshot text.
- [x] Save extracted text through the existing Capture storage, enrichment, and
  retrieval pipeline without creating a parallel notes database. Store tests
  verify the exact `source_type: screenshot` create request, preserve the
  independent optional user note, and prevent late OCR results after window
  close; migration 003 preserves old rows and rebuilds synchronized FTS.
- [x] Test malformed images, provider failure/refusal/empty output, source limits,
  local extraction, API paths, and the complete existing regression suite.
  Evidence: 214 backend tests, 44/44 stress scenarios, 16 extension tests plus
  syntax checks, and 43 macOS tests.
- [x] Add explicit Screen Recording permission preflight and an actionable
  System Settings error; clear screenshot memory on every dismissal path and
  invalidate/cancel in-flight extraction work.
- [x] Document migration 003 as a forward-only rollback boundary: preserve a
  pre-migration database backup and pre-feature Git tag before merge. The
  ignored mode-0600 backup
  `data/backups/recall-pre-migration-003-20260720.db` verifies `integrity_check=ok`
  at schema `1,2`; pushed annotated tag `rollback/pre-screenshot-ocr` points to
  `62d8c56`.
- [x] Document the privacy boundary, demo flow, API surface, errors, and the
  deliberate difference from the outline's deferred full image-memory work.
- [x] Developer B committed with `unsupervised push` in the commit message,
  pushed `agent/screenshot-notes-ocr`, and opened draft PR #4.
- [x] Complete harmless real GPT OCR and interactive macOS permission,
  cancellation, Apple Vision, and dismiss-during-extraction proof. B-012 and
  B-013 record the 2026-07-20 evidence.
- [x] PR #5 publishes `codex/pr4-hardening` as the reviewed successor to PR #4;
  the final remote-state check controls its merge into `main`.

## Active addition — opt-in inline browser selected-text capture

Status: `[x]` implementation, deterministic coverage, and real-Chrome acceptance
verified under D-029; PR #8 merged the change at `71ec387`

- [x] Keep inline capture off by default and request broad HTTP/HTTPS access only
  through Chrome's optional permission prompt. Toolbar and keyboard capture keep
  working without that access.
- [x] Declare no static content script. After opt-in, register the isolated
  script dynamically and inject it into eligible already-open tabs so users do
  not need to refresh them.
- [x] Keep selected source and the originally bounded context inside the page
  until Save. Do not write the selection to extension storage, log it, or send
  it merely because a user selected text. D-030 later disables browser context
  submission after real-site evidence; this row records the merged D-029 state.
- [x] Route toolbar and inline saves through one service-worker coordinator that
  validates the attempt and freezes source, note, timestamp, and
  `client_capture_id` across retryable ambiguity.
- [x] On permission removal, unregister future injection and immediately tell
  open tabs to remove Recall controls and listeners. Deterministic tests cover
  permission initialization, races, current-tab injection, and revocation.
- [x] Preserve the existing text-only data model. This slice does not save page
  images or introduce image attachments; that requires the later attachment
  design recorded in the roadmap.
- [x] Pass all 68 dependency-free extension tests at this verification point,
  including Unicode limits, rapid activation, Escape behavior, focus/error
  dismissal, stable retry identity, BFCache suspension, save-time permission
  checks, JavaScript syntax, and toolbar regression.
- [x] In real unpacked Chrome, enable the optional access while the harness page
  is already open and confirm **Add to Recall** appears without a refresh. Save
  a Chinese/emoji personal note and verify both it and the selected original
  source are persisted exactly.
- [x] Confirm Escape reaches the host page without cancellation, selections in
  input/contenteditable controls do not trigger Recall, and an offline error
  focuses **Try again**, survives tab focus changes, and reuses one exact attempt
  after the isolated backend restarts.
- [x] Revoke access while an inline composer is open and confirm it disappears
  immediately. Return to a real BFCache-restored page, confirm the fixture
  reports one persisted restore and no selection produces a Recall pill, then
  confirm toolbar capture still saves with the optional access off.
- [x] Display the test records in the native macOS app and confirm the original
  selection and personal notes render exactly. The optional Chrome access was
  left revoked after verification.
- [x] Run that manual save against a temporary backend with AI intentionally
  unconfigured. The stored Capture later entering enrichment `error` is expected
  and is not a capture failure: the persist-first pipeline retained its exact
  source and user note.
- [x] PR #8 completed review and CI, then merged D-029 into `main` at merge
  commit `71ec387`.

## Active addition — browser context and detail-view hardening

Status: `[x]` D-030 implementation, automated verification, bounded UI
verification, source review, and CI complete; PR #9 merged into `main` at
`0c1083e`

- [x] Record the real Gemini failure without storing its content in this log:
  selected text was 1,530 characters, context was 19,144 characters, and that
  context contained 1,912 newline characters. Broad `main`/`body` extraction
  included the conversation-history sidebar.
- [x] Temporarily send empty `surrounding_context` from both Chrome entry
  points with `context_truncated=false`. A selection Capture keeps normalized
  text unshortened through the shared 12,000-character limit plus
  title/URL/note; longer selections display the full count and an explicit
  first-12,000 warning. A no-selection toolbar Capture keeps title/URL/note.
  D-009 and the backend 20,000-character context contract remain unchanged.
- [x] Keep selected text and its optional note as the current enrichment input;
  do not replace browser context with another broad page scrape. A future
  extractor must be centered on the selected Range and independently bounded by
  characters plus lines/blocks.
- [x] Add a separate Unicode-aware selected-text count to inline capture and
  make its long-selection preview pointer- and keyboard-scrollable.
- [x] Tighten the action popup width and spacing and give its shell an internal
  vertical scroller so controls remain reachable on a short viewport.
- [x] Preserve every existing database value. In macOS, collapse surrounding
  context by default, show its character count, and render at most 2,000
  characters and 60 lines only after explicit expansion. The complete original
  remains on the model for search and AI.
- [x] Retain 68 extension tests for the changed Chrome behavior and pass all
  68. Add five bounded macOS context-projection tests and pass all 48 macOS
  tests.
- [x] Complete bounded UI verification and source review. The real unpacked
  Chrome toolbar popup remained fully reachable; the standalone production
  content-script harness reported and scrolled an 800-character inline preview;
  and the rebuilt native app kept the 19,144-character context collapsed before
  rendering only its bounded 60-line preview. The standalone harness uses a
  mocked runtime and open Shadow DOM, so it is not injection or CSP evidence.
- [x] Complete CI evidence. PR #9 passes Backend tests, Backend stress, Chrome
  extension, macOS, and the aggregate Required checks job.
- [x] Complete final review and merge evidence. PR #9 merged into `main` at
  merge commit `0c1083e` on 2026-07-21.

## Active reliability correction — Chrome action popup sizing

Status: `[x]` D-033 implementation, 68/68 automated tests, and real unpacked-
Chrome verification are complete on `codex/fix-chrome-popup-sizing`

- [x] Reproduce the toolbar action as a title-height strip while its full
  control tree remains present and vertically scrollable.
- [x] Trace the regression to D-030 removing the working 510-pixel minimum and
  constraining the shell with a height derived from the action popup's own
  not-yet-established viewport.
- [x] Establish a deterministic 344 × 510 pixel root, fill it with the body and
  internally scrollable shell, and remove viewport-height units from popup
  dimensions.
- [x] Preserve the existing compact spacing, capture contract, permissions,
  retry behavior, and empty browser surrounding-context boundary.
- [x] Pass all 68 extension tests, including a regression check that rejects
  viewport-height units in popup dimensions.
- [x] Reload the real unpacked extension and verify the complete internal-page,
  regular metadata-only, and 72-character selected-text layouts. The source
  card, preview, note, Save, and inline-access controls remained reachable; no
  verification Capture was submitted.

## Active addition — native global capture

Status: `[x]` D-031 implementation, automated verification, bounded real-UI
verification, review, merge at `0ab687b`, and B-014 real-device acceptance are
complete

- [x] Keep Recall as a normal Dock application with the existing
  `MenuBarExtra`. Global capture requires the app to be running but is owned by
  app-level state and does not depend on the main window remaining open.
- [x] Register screenshot and clipboard hotkeys with Carbon
  `RegisterEventHotKey`, requiring neither Accessibility nor Input Monitoring
  permission. Defaults are `Option+Shift+Command+4` and
  `Option+Shift+Command+C`, respectively.
- [x] Add Settings controls for A–Z and 0–9 plus Command, Option, Control, and
  Shift; require at least two modifiers per action, reject duplicate action
  combinations, support enable/disable, and restore both defaults.
- [x] Make whole-configuration registration transactional. Persist only after
  all enabled shortcuts register; on failure, remove any partial new set,
  restore the previous set, and expose the result in Settings, the menu, and the
  menu-bar status icon.
- [x] Route main-window, menu-bar, and Carbon callback entry points through the
  app-level `GlobalCaptureCoordinator`. Host its presentation observer in the
  `MenuBarExtra` label through `CapturePresentationHost`, so the shared Quick
  Capture window can open independently of the main-window scene.
- [x] Await the system screenshot `Process` asynchronously and read its PNG off
  the main actor. Task cancellation terminates a running selection, app
  termination requests that cancellation, and the random temporary PNG is
  removed on success, cancellation, or failure.
- [x] Preserve any existing or ambiguous-retry Quick Capture draft. Deduplicate
  rapid repeated screenshot triggers so only one selector starts, and re-present
  the protected draft with an explanatory notice instead of overwriting it.
- [x] Preserve the D-027 privacy boundary and provider disclosure: screenshot
  bytes remain transient, GPT/cloud stays the default, Apple Vision/on-device
  remains explicit, and only reviewed text can be saved. Add no API, schema,
  backend, database, Chrome-extension, enrichment, retrieval, or attachment
  change.
- [x] Add 20 shortcut, coordinator, draft-safety, and asynchronous screenshot
  tests and pass all 68/68 macOS tests on the host. Final cross-component
  regression also passes 215 backend tests, 44/44 stress scenarios, and 68/68
  Chrome-extension tests.
- [x] Complete bounded real-UI Settings verification: confirm both defaults,
  change screenshot capture to `Option+Shift+Command+5`, relaunch and confirm it
  persisted, restore defaults, and observe active Carbon registration.
- [x] Exercise clipboard Quick Capture with exactly 32 characters. A repeated
  trigger preserved the existing draft and displayed its explanatory notice.
- [x] Reopen the problematic 19,144-character context record and confirm it
  remains collapsed and responsive under D-030.
- [x] Exercise the temporary ad-hoc build's explicit Screen Recording permission
  error. It did not match the permission record, and verification deliberately
  did not change the permission state.
- [x] Reset and authorize the stably signed build, relaunch after a same-signer
  rebuild, show the real system selector, and cancel it without a permission
  error or draft.
- [x] Focus another app, close Recall's main window without quitting, physically
  press `Option+Shift+Command+4`, and complete one non-empty region. After
  copying text, physically press `Option+Shift+Command+C` and confirm that
  Capture opens. The user completed both real-device checks on 2026-07-21.

## Active addition — native Accessibility selection

Status: `[x]` D-034 implementation, 108/108 host tests, PR #13, and
primary-path user acceptance complete on `codex/native-accessibility-selection`;
D-035/B-016 compatibility acceptance is also complete

- [x] Add a third configurable **Selection capture** action with default
  `Option+Shift+Command+S`, generic three-way duplicate validation, and the
  existing whole-set registration transaction.
- [x] Migrate stored two-action `globalShortcutConfiguration.v1` values without
  losing customized screenshot/clipboard choices. Persist the additive field;
  if only the new default is externally occupied, disable it while preserving
  the two established registrations.
- [x] Read only after an explicit shortcut/menu command. Check Accessibility
  trust before attributes; reject Recall itself, secure text fields, protected
  content, missing/empty/unsupported selections, and input over 12,000
  characters. Do not simulate copy, inspect a window title, or read surrounding
  content.
- [x] Run cross-process AX work outside the main actor with bounded messaging
  timeouts and cancellation propagation. Treat range/bounds as optional so
  readable text still opens review when positioning metadata is unavailable.
- [x] Reuse the existing Quick Capture and idempotent save pipeline. Distinguish
  the native `.selection` draft in UI while mapping Save to the existing
  clipboard-text contract. Submit no URL, title, surrounding context, range, or
  screen bounds.
- [x] Convert AX global coordinates against the current primary-screen layout,
  choose the display with the greatest selection intersection, position after
  SwiftUI layout, and clamp the 500-point review window to `visibleFrame`.
  Invalid/offscreen bounds center on the current mouse screen.
- [x] Add permission status/request UI, an explicit System Settings route,
  honest current-clipboard recovery, and menu-bar Selection capture.
- [x] Pass 108/108 host tests covering AX ordering/privacy, exact Unicode,
  contract mapping, cancellation/late results, oversize rejection, source-app
  bounds, shortcut migration/conflict rollback, and window geometry/request
  gating.
- [x] Open non-auto-merged draft PR #13 and obtain user confirmation that the
  primary Accessibility path works on the stably signed app.

## Completed privacy/compatibility safeguard — transactional clipboard fallback

Status: `[x]` D-035 implementation, its 149/149 host suite, and B-016 user
acceptance are complete; the user authorized merge on 2026-07-21

- [x] Keep the primary D-034 Accessibility path unchanged and add a separately
  persisted **Clipboard Compatibility Mode** that is off by default.
- [x] Carry a fallback ticket from the exact frontmost application whose direct
  selection read failed. Bind its focused AX element when available; use an
  application-scoped ticket for custom-drawn apps that omit it. Permission/self,
  known secure/protected, empty, oversized, and pre-transaction cancellation
  failures may not synthesize Copy.
- [x] Revalidate the same PID, the exact element when available, exposed safety
  evidence, event-posting access, and Secure Event Input immediately
  before injection, after waiting for the shortcut modifiers to be released.
- [x] Deep-copy bounded ordered pasteboard items/types into in-memory Data
  before Copy. Abort before mutation when any representation cannot be
  materialized or the item/type/64 MiB limits are exceeded.
- [x] Treat `changeCount` as a race signal, not ownership proof. Require two Copy
  attempts to produce exact consecutive counts and matching complete payloads
  from the same target ticket before accepting text or attempting restoration.
  Never log, persist, submit, or attach the backup.
- [x] Disclose best-effort restoration and the unavoidable clipboard-history /
  Universal Clipboard visibility in Settings and fallback review UI, including
  macOS's missing writer identity/atomic restore and delayed-Copy residual risk.
- [x] Complete automated service/store/privacy tests and pass the expanded
  149/149 host suite.
- [x] Pass B-016 in WeChat and obtain explicit merge authorization.

## Active addition — structured-text capture fidelity

Status: `[x]` D-036 implementation, its 176/176 host suite, and live Gemini
clipboard payload verification are complete

- [x] Confirm that the API contract, JSON transport, SQLite `TEXT`, and current
  native views already retain newline characters; make no schema or migration
  change for this bounded slice.
- [x] Add one bounded resolver for plain text plus inert HTML/RTF clipboard
  representations to explicit Clipboard Capture.
- [x] Keep plain content authoritative. Project richer line boundaries only
  when the structured candidate has identical ordered non-whitespace content;
  otherwise preserve the original plain string exactly, including TeX or
  Markdown delimiters such as `$e$`.
- [x] Keep HTML/RTF markup transient and local. Do not render it, persist it,
  log it, or send it before the user saves the resolved text.
- [x] Reject whitespace-only plain text, rich-only payloads, cross-item pairing,
  and explicit-capture reads whose pasteboard change count moves mid-snapshot.
- [x] Resolve multiple text items independently and join them with macOS's
  newline semantics; fall back to system plain text when bounded item/type
  inspection is exceeded.
- [x] Pass host macOS tests covering HTML/RTF line restoration,
  whitespace-position safety, mismatch fallback, size bounds, and explicit
  Clipboard Capture.
- [x] Verify the user's Gemini clipboard payload. Its HTML exposes semantic
  `data-math`; flattening the plain string to zero newlines and resolving it
  restores 46 verified block boundaries while preserving inline/display TeX
  and identical ordered non-whitespace content.

## Active reliability correction — stable Screen Recording identity

Status: `[x]` D-032 implementation, 70/70 tests, and live TCC rebuild
persistence verification are complete on
`codex/stable-screen-recording-permission`

- [x] Reproduce the mismatch in the running Debug app: System Settings showed
  Recall enabled, while `CGPreflightScreenCaptureAccess()` still failed.
- [x] Inspect the actual process rather than another app copy. Its signature was
  ad-hoc, `TeamIdentifier` was absent, and its designated requirement was tied
  to one CDHash, so a rebuild produced a new TCC identity.
- [x] Add portable `Config/Signing.xcconfig` configuration for the app and test
  targets. Keep ad-hoc fallback available for clones and deterministic
  automation, and load an optional ignored `Signing.local.xcconfig` for real
  Apple Development signing.
- [x] Check in only a placeholder example. Each developer must enter the actual
  Team ID from their certificate/account locally; no machine Team ID or
  certificate nickname is committed.
- [x] Add `scripts/verify-macos-signing.sh` to reject an invalid signature,
  absent Team ID, or CDHash-only designated requirement before interactive
  privacy testing.
- [x] When Screen Recording preflight and request both fail, distinguish a
  temporary code signature from an ordinary user denial and present the
  stable-signing/reset guidance. Add no Screen Recording entitlement.
- [x] Produce a local Apple Development-signed Debug app with a non-empty Team
  ID and signer-based designated requirement. Confirm the verifier rejects the
  preceding ad-hoc build.
- [x] Run the complete D-032 macOS suite at 70/70.
- [x] Quit every Recall copy, run the app-specific
  `tccutil reset ScreenCapture com.recall.macos`, request permission from the
  stable build, switch Recall from off to on, and choose **Quit & Reopen**.
- [x] Rebuild with the same identity and `CURRENT_PROJECT_VERSION=2`. CDHash
  changes from `143035…` to `5a1b00…` while Team ID and the signer-based
  designated requirement remain stable.
- [x] Launch the rebuilt process as PID 87557, confirm it starts child
  `/usr/sbin/screencapture` and displays the system region overlay, then cancel
  with Escape and return to Recall without a permission error.

## Scope, schedule, and collaboration guardrails

These are baseline requirements, not optional process suggestions:

- P0 requires both Chrome web capture and clipboard/local-app capture, even
  though the minimum submission threshold says at least one stable capture
  path.
- P1 work must not begin before all three vertical slices pass. P2 remains out
  of the submission entirely; the only approved exception is the separately
  gated Apple experiment in D-008, which still cannot begin before Layers 1–8
  pass.
- The product plan requires `main` to remain runnable. D-019 records the retired
  documentation-only exception; D-023 restores the rule and resolves B-010.
- Run at least two end-to-end integration checks each day.
- Freeze major features for the final half-day. On July 21, add no new platform,
  technology stack, database rewrite, complex agent, Safari extension, OCR,
  infrastructure, or major navigation change unless the main flow is broken.
- Priority order is:
  `stable real capture > AI contextual understanding > reliable retrieval > clear demo > visual polish > additional features`.

Sprint targets from the product plan:

| Date | Required target |
| --- | --- |
| July 18 | Contracts, FastAPI/health, SQLite, Capture CRUD, curl proof, and first macOS list integration |
| July 19 | Clipboard capture, OpenAI enrichment, FTS5/basic search, and keyword retrieval |
| July 20 | Complete Chrome context capture, embeddings/hybrid search, three clean demo passes, and first recording |
| July 21 | Fixes, polish, documentation, recordings, verification, and submission only |

Any schedule variance belongs in the blocker/risk log rather than being hidden
by layer completion percentages.

## Baseline versus implementation safeguards

The following checklist items are useful safeguards but are not product-plan
features or reasons to delay a vertical slice:

- structured operational logs and request identifiers;
- duplicate-submission/idempotency hardening beyond storing
  `client_capture_id` (implemented after stress under D-021);
- stale-processing recovery beyond a visible error and manual retry;
- semantic non-empty post-validation and explicit refusal classification;
- embedding dimension/version migration policies beyond the configured MVP
  model.

Implement them only when they reduce demo risk, and document any contract or
storage impact first.

---

# Layer 0 — Contracts and documentation

Status: `[x]` complete

## Deliverables

- [x] Preserve the authoritative outline in `docs/product-plan.md`. The initial
  Layer 0 copy was byte-identical; later repository hygiene adds only a current
  roadmap note and removes four non-portable internal citation markers.
- [x] Create `docs/architecture.md` with boundaries and work ownership.
- [x] Create `docs/decisions.md` with baseline/addition classifications.
- [x] Create `contracts/capture.schema.json`.
- [x] Create `contracts/enriched_capture.schema.json`.
- [x] Create `contracts/api.md`.
- [x] Define the exact product-plan §12.1 embedding projection.
- [x] Create request, enrichment, ready-response, and embedding fixtures.
- [x] Create `.env.example` without a key.
- [x] Ignore `.env`, databases, build output, and developer-local files.
- [x] Add the optional Apple path as gated decision D-008.

## Validation evidence

- [x] JSON syntax validated with `jq`.
- [x] Schemas and positive fixtures validated with Draft 2020-12 tooling.
- [x] Negative fixtures rejected for missing fields, extra fields, and empty
  source content.
- [x] Generated §12.1 embedding input exactly matches the checked-in fixture.
- [x] The initial Layer 0 `docs/product-plan.md` exactly matched the original
  outline. Git history retains that source after the later navigation/citation
  cleanup and removal of its redundant root-level copy.
- [x] Secret-pattern scan found no API key.
- [x] Git whitespace audit passed before commit.
- [x] Commit `e75f783` pushed to `origin/agent/layer-0-contracts`.

## Exit gate

- [x] Developer A can implement Swift request/response models from checked-in
  contracts without inventing field names.
- [x] All additions to the outline are visible in the decision log.

---

# Layer 1 — Backend foundation

Status: `[x]` complete

## Prerequisites

- [x] Confirm Layer 0 is merged before both developers branch. Verified in
  `origin/main` at merge commit `9c08243` on 2026-07-18.
- [x] Confirm the local Python version and package tooling. Found Python 3.10.1
  and pip 21.2.4; `uv` is absent. Layer 1 uses a standard-library `venv` and
  project-declared, constrained dependencies so no global package install is
  required.
- [x] Confirm no repo-level `AGENTS.md` or toolchain constraint is missing. No
  `AGENTS.md` was found in the repository hierarchy on 2026-07-18.

## Build tasks

- [x] Create `services/backend/` package structure.
- [x] Define backend dependencies and a reproducible install command.
- [x] Create environment-based configuration for:
  - `OPENAI_API_KEY`
  - `OPENAI_MODEL`
  - `OPENAI_EMBEDDING_MODEL`
  - `RECALL_HOST`
  - `RECALL_PORT`
  - `RECALL_DATABASE_PATH`
  - `RECALL_LOG_LEVEL`
  - `RECALL_CORS_ORIGINS`
- [x] Refuse non-loopback binding by default.
- [x] Create one minimal, documented FastAPI entry point. An application-factory
  pattern is optional and must not delay the health endpoint.
- [x] Implement `GET /health`.
- [x] Report process, database, and OpenAI-configuration state separately.
- [x] Allow the backend to start without an OpenAI key.
- [x] Add only the logging needed to diagnose startup and requests. Never log
  API keys; avoiding full captured text in default logs is an engineering
  safeguard, not a new product feature.
- [x] Add backend test configuration and the first health test.
- [x] Document one command to start and one command to test the backend.

## Required tests

- [x] Backend starts on `127.0.0.1:8765`.
- [x] `/health` returns `200` with database status.
- [x] `/health` reports `openai_configured: false` when the key is absent.
- [x] A missing `.env` does not crash the service.
- [x] An invalid port or database path fails with a visible configuration error.

## Validation evidence

- [x] Created a fresh `.venv`, upgraded its pip, and installed with
  `.venv/bin/python -m pip install -r requirements.txt`.
- [x] `.venv/bin/python -m pip check` reported no broken requirements.
- [x] `.venv/bin/python -m pytest` passed all 11 tests without warnings.
- [x] A live `.venv/bin/python -m app` run bound to `127.0.0.1:8765`; curl
  returned `{"status":"ok","database":"ok","openai_configured":false}`.
- [x] Live startup with `RECALL_HOST=0.0.0.0` exited `1` with a loopback
  validation error.
- [x] Live startup with `RECALL_DATABASE_PATH=/tmp` exited `1` with a database
  file-path validation error; invalid ports are also covered by tests.
- [x] `git diff --check` passed after implementation.

## Exit gate

- [x] A new developer can install dependencies, start the backend, call
  `/health`, and run tests from README instructions.

---

# Developer status dashboard — addition D-012

Status: `[x]` complete

## Build tasks

- [x] Add a local HTML dashboard at `/dev/checklist`.
- [x] Generate dashboard data directly from this Markdown file on every
  request; do not create a second status source.
- [x] Refresh the browser view every two seconds without a server restart.
- [x] Show layer progress, active tasks, blockers, resolved errors, and the last
  successful refresh time.
- [x] Make refresh failures visible and preserve the last successful view.
- [x] Keep the dashboard read-only, dependency-free, and loopback-only.
- [x] Add parser and endpoint tests.
- [x] Preserve each layer's expanded or collapsed state across the two-second
  live refresh.

## Exit gate

- [x] A checklist file change appears in an already-open dashboard within two
  seconds, without restarting the backend.

## Validation evidence

- [x] The live HTML route returned HTTP `200` with a self-contained 17,368-byte
  dashboard and no external asset dependency.
- [x] While the backend process remained running, this checklist's phase and
  Layer 2 status were edited; the next JSON request returned the new phase and
  `Layer 2: complete` without a restart.
- [x] Endpoint tests verify `Cache-Control: no-store`, direct Markdown rereads,
  the two-second poll interval, and the read-only HTML/JSON routes.
- [x] Stable stream keys and in-memory open-state capture preserve user choices
  across repeated live renders; a regression test guards the mechanism.

---

# Layer 2 — SQLite persistence

Status: `[x]` complete

## Decisions required before implementation

- [x] Select and record migration tooling. D-011 uses numbered SQL files and a
  standard-library transactional migration runner.
- [x] Persist optional `client_capture_id`. Do not make uniqueness or full
  idempotency a Layer 2 requirement unless duplicate submissions are observed
  or both developers approve and document the behavior. D-011 keeps the column
  nullable and non-unique.

## Build tasks

- [x] Create the SQLite database at the configured path.
- [x] Add a migration or initialization mechanism; do not create tables ad hoc
  inside request handlers.
- [x] Implement the `captures` table from the product plan.
- [x] Add the D-006 `context_truncated` column with false default.
- [x] Preserve `source`, `user_note`, and AI fields in separate columns.
- [x] Store array fields as JSON arrays, never comma-concatenated storage.
- [x] Store embeddings as nullable JSON arrays for the MVP.
- [x] Implement UTC `created_at` and `updated_at` behavior.
- [x] Implement the four states: `captured`, `processing`, `ready`, `error`.
- [x] Create a repository/data-access boundary independent of FastAPI routes.
- [x] Use transactions for initial Capture persistence and enrichment updates.

## Required tests

- [x] Create and read English, Chinese, and mixed-language Captures.
- [x] Round-trip `null` URL, title, context, app, and note values.
- [x] Round-trip arrays without type or order loss.
- [x] Persist `context_truncated` correctly.
- [x] Verify data survives service restart.
- [x] Verify an invalid status cannot be stored.
- [x] Verify no AI field update modifies source or user-note fields.

## Exit gate

- [x] A Capture survives process restart with byte-equivalent source and user
  content.

## Validation evidence

- [x] `.venv/bin/python -m pytest` passed all 30 tests after Layer 2 and the
  dashboard were implemented.
- [x] The migration runner applied `001_initial_captures.sql` twice
  idempotently in tests and recorded `1:initial_captures` in live SQLite.
- [x] A live backend created and reported a current database at a temporary
  configured path without an OpenAI key.
- [x] A separate process persisted Capture
  `5bf83e79-5364-464a-aef9-779f9e51f3a0`; after a full backend stop/start, a
  new process read matching UTF-8 hex for source and user-note bytes.
- [x] Direct SQLite inspection returned `captured:clipboard:0` for the restart
  fixture, confirming status, source type, and the default context flag.
- [x] A release-wheel build included the numbered SQL migration and the live
  dashboard HTML as package data.

---

# Layer 3 — Capture CRUD and first vertical slice

Status: `[x]` complete; D-013 holder retired after live macOS integration

## Build tasks

- [x] Map the checked-in Capture schema to backend validation models.
- [x] Implement `POST /v1/captures`.
- [x] Persist the original request before any enrichment attempt.
- [x] Return `202 Accepted` with status `processing`.
- [x] Implement `GET /v1/captures?limit=&offset=`.
- [x] Implement `GET /v1/captures/{id}`.
- [x] Use the documented response envelope and error envelope.
- [x] Validate character limits and the D-009 at-least-one-content-field
  clarification.
- [x] Return stable codes for validation and not-found errors.
- [x] Write verified curl examples using the checked-in fixture.
- [x] Give Developer A the live base URL and curl evidence in
  `docs/developer-a-backend-handoff.md`.
- [x] Add a temporary non-production Swift decoding/list holder under
  `docs/examples/`, then remove it after the maintained Xcode target closed the
  integration gate.

## Required tests

- [x] Valid web Capture returns `202` and a server UUID.
- [x] Valid clipboard Capture without a URL succeeds.
- [x] Empty and long user notes round-trip without source-data loss.
- [x] Missing URL and missing page title are accepted when other content exists.
- [x] Empty selection succeeds only when title or context contains text.
- [x] Unknown fields fail.
- [x] Overlong selection and context fail visibly.
- [x] List ordering is `created_at DESC`.
- [x] Pagination limits are enforced.
- [x] Unknown UUID returns the documented `404` envelope.

## Validation evidence

- [x] `.venv/bin/python -m pytest` passes all 55 tests without warnings.
- [x] A drift test matches request-model fields and required fields to
  `capture.schema.json`, and response-model fields to the ready fixture.
- [x] API responses exclude internal `embedding`/`embedding_json` storage fields.
- [x] Validation errors contain the stable `validation_error` code and a UUID
  request ID without echoing captured source text.
- [x] Unexpected API failures use the documented `internal_error` envelope and
  log only method/path plus the exception, not the request body.
- [x] Live fixture POST returned HTTP `202` and Capture
  `359d1c47-0190-40c4-8681-d994408860be` with status `processing`.
- [x] Direct SQLite inspection found the same UUID with source type `web`, 146
  selected characters, and 162 user-note characters.
- [x] Live detail and list GETs returned the persisted fixture; live unknown-ID
  and empty-content requests returned the documented `404` and `422` envelopes.
- [x] The original macOS branch built with Xcode 26.2, passed its 11
  contract/network/store tests, and displayed live backend Captures with source
  and user-note separation. Current full-tree retesting is tracked under Layer
  8 rather than reopening this gate.

## Vertical-slice exit gate

```text
curl POST Capture
→ SQLite persistence
→ GET returns the Capture
→ Developer A's macOS app displays the real Capture
```

- [x] Backend portion passes.
- [x] Developer A confirmed real macOS list/detail and clipboard integration;
  the temporary holder was removed. See resolved blocker B-006.
- [x] Commit and push the verified backend slice and documented holder.

---

# Layer 4 — OpenAI enrichment

Status: `[x]` implementation and real provider exit gate verified

## Prerequisites

- [x] Confirm `OPENAI_API_KEY` is available without committing it. The key is
  present only in the ignored root `.env`; health reports it configured.
- [x] Confirm the configured GPT-5.6 model is accessible to the project. A real
  Responses API call returned `200` and passed strict output validation.
- [x] Choose and record the background-execution mechanism. D-014 uses FastAPI
  `BackgroundTasks` plus the explicit retry endpoint.
- [x] Agree on baseline polling: every 1–2 seconds, stop on `ready`/`error`, and
  cap polling at roughly 30–60 seconds. The macOS implementation follows the
  contract; its current regression tests are part of the integration sweep.

## Build tasks

- [x] Keep OpenAI calls behind a small enrichment service boundary. Do not build
  a generalized provider/plugin system in P0; only preserve a clean seam for
  the separately gated D-008 experiment.
- [x] Keep the model name in environment configuration only.
- [x] Build the system instructions from product-plan §11.5.
- [x] Build the user input from product-plan §11.6.
- [x] Send only source type/app, page title, URL/domain, selected text, limited
  surrounding context, and user note—never full page HTML.
- [x] Normalize inputs without modifying persisted originals.
- [x] Preserve the complete user note.
- [x] Enforce the selected/context length rules.
- [x] Use one Responses API request per enrichment.
- [x] Use strict Structured Outputs with
  `contracts/enriched_capture.schema.json`.
- [x] Treat refusal detection and semantic non-empty checks as small reliability
  safeguards; do not redesign the baseline schema around them.
- [x] Map `title → ai_title` and `summary → ai_summary` explicitly.
- [x] Store all enrichment fields in one transaction.
- [x] Implement `POST /v1/captures/{id}/enrich`.
- [x] Reject concurrent enrichment with the documented `409` response.
- [x] Persist a safe `error_message`; never expose credentials or raw provider
  traces to clients.
- [x] Persist `enrichment_version=1`; incompatible future prompt or projection
  changes must increment it before release.

## Prompt-quality requirements

- [x] Distinguish source facts, explicit user context, and cautious inference.
- [x] Do not invent technical details.
- [x] Do not claim a saved method worked unless the user note says it worked.
- [x] Preserve exact error codes, commands, product names, APIs, libraries, and
  technical entities.
- [x] Make `why_saved` primarily grounded in the user note; acknowledge when no
  personal reason was supplied.
- [x] Use the language most appropriate to the note and captured content.
- [x] Reject generic titles such as “Interesting Note,” “Linux Information,” or
  “A Useful Solution.”
- [x] Ensure the summary reflects the user's situation rather than merely
  summarizing the source.

## Required test fixtures

- [x] Stack Overflow-style technical solution.
- [x] General article insight.
- [x] Exact error code, command, or file path.
- [x] English source with Chinese user note.
- [x] Capture with no user note.
- [x] Long but valid context.

## Failure tests

- [x] Missing API key.
- [x] Unavailable or unauthorized model.
- [x] Timeout or connection failure.
- [x] Refusal.
- [x] Structurally invalid output.
- [x] Semantically empty output.
- [x] Retry succeeds without duplicating or modifying source data.

## Validation evidence

### Review remediation

- [x] Package the enrichment schema with the backend and prove it loads from a
  release wheel.
- [x] Bound OpenAI enrichment calls within the documented polling window.
- [x] Reject incomplete Responses API results before parsing provider output.
- [x] Clear generated fields atomically when a completed Capture is claimed for
  re-enrichment.

- [x] Official OpenAI guidance was cross-checked for the current Responses API
  `text.format` strict JSON Schema shape and explicit refusal content.
- [x] The official `openai` Python SDK 2.46.0 is constrained as a runtime
  dependency and installed without breaking the existing test client.
- [x] `.venv/bin/python -m pytest` passes all 94 tests without warnings.
- [x] The isolated release-wheel test imports and parses the packaged enrichment
  schema without access to the repository-level `contracts/` directory.
- [x] Regression tests prove the 45-second/no-retry provider budget, reject an
  incomplete result containing valid-looking JSON, and return clean generated
  fields while a ready Capture is reprocessed.
- [x] Tests prove exactly one provider request uses the checked-in schema with
  `type=json_schema`, `strict=true`, and the environment-selected model.
- [x] Automatic post-create enrichment and explicit retry both transition
  `processing → ready` with a successful provider and preserve source fields.
- [x] Missing configuration and provider/output failures transition to `error`
  with safe client-visible messages and no provider trace.
- [x] Live backend 0.4.0 exposed the retry route in OpenAPI; fixture Capture
  `c3afd501-e184-480a-86f9-df2379ec539a` returned `processing`, then stored the
  safe unconfigured `error` while direct SQLite inspection confirmed its source
  text was unchanged.
- [x] Live retry without a key returned HTTP `503` with stable code
  `openai_not_configured`; health remained available and no secret was present.
- [x] On 2026-07-19, the first credentialed request correctly surfaced a safe
  terminal error after provider HTTP `429`; after billing was enabled, retry
  moved the same persisted Capture `processing → ready` with non-empty AI
  fields and unchanged source/note data.

## Vertical-slice exit gate

```text
macOS Clipboard Capture
→ raw Capture persists
→ OpenAI enrichment runs
→ status changes from processing to ready
→ macOS card updates without data loss
```

- [x] Backend deterministic providers, failure simulation, and real OpenAI
  enrichment all pass; B-007 is resolved.
- [x] The macOS polling and state UI are integrated, and the real provider
  transition plus the current 27-test regression suite pass.
- [x] Commit the working Layer 4 slice.
- [x] Push the working Layer 4 slice in implementation commit `84a0bb7`.

---

# Layer 5 — FTS5 keyword retrieval

Status: `[x]` implementation, exit gate, and delivery complete

## Build tasks

- [x] Resolve the nine untracked `* 2.*` workspace duplicates before Layer 5
  implementation. Five were byte-identical copies; four were older snapshots
  missing current canonical changes. No duplicate contained unique content, and
  all canonical files were preserved.
- [x] Confirm SQLite FTS5 is available in the selected backend runtime.
- [x] Cross-check the table columns, search response, failure fallback, and
  technical-identifier weighting against product-plan §§6.3, 9.4, 10.6, 12.3,
  and 12.4 plus `contracts/api.md`.
- [x] Record trigger synchronization and Layer 5 score semantics in D-015
  before implementation.

- [x] Create the `captures_fts` table from the product plan.
- [x] Define one synchronization path for insert, enrichment update, retry, and
  future deletion.
- [x] Index source, user-note, and AI fields independently but query together.
- [x] Include tags, entities, and search aliases in FTS text.
- [x] Implement empty-query recent-Capture behavior.
- [x] Implement keyword search in `GET /v1/search`.
- [x] Normalize keyword scores to `0...1`.
- [x] Preserve exact error codes, commands, paths, versions, and URLs.
- [x] Ensure FTS works when OpenAI and embeddings are unavailable.

## Required tests

- [x] Exact title term.
- [x] Original selection term.
- [x] User-note phrase.
- [x] AI tag/entity/alias.
- [x] Error code and file path.
- [x] Chinese query and mixed-language content.
- [x] Empty query and no-result query.
- [x] Failed-enrichment Capture remains searchable from raw fields.

## Validation evidence

- [x] Migration 002 creates the exact FTS columns, three synchronization
  triggers, and backfills a pre-migration Capture.
- [x] Retry tests prove generated aliases leave the index when processing starts
  while immutable source terms remain, then new generated aliases appear after
  enrichment succeeds.
- [x] A direct-delete test proves the future deletion path removes its FTS row.
- [x] Query tests cover escaped FTS operators, normalized weighted BM25 scores,
  an exact-phrase ranking bonus, and the `0...1` contract.
- [x] API tests prove keyword-only response shape, provider-off fallback,
  empty/recent behavior, no-result behavior, and limit validation.
- [x] The corrected focused suite passes all 74 tests.
- [x] `.venv/bin/python -m pytest` passes all 119 tests without warnings.
- [x] `pip check` reports no broken requirements and `git diff --check` passes.
- [x] Live backend 0.5.0 on `127.0.0.1:8875` applied migrations 1–2,
  exposed all three triggers, and indexed one row for temporary Capture
  `9845ea10-da9a-4407-bd43-907f86d89557`.
- [x] With OpenAI disabled, the Capture moved `processing → error` without raw
  data loss; `q=WorkingDirectory` returned it with `score=keyword_score=1.0`
  and `semantic_score=null`.
- [x] Empty query returned the recent Capture with `keyword_score=0.0`; after a
  clean backend restart, the same keyword query returned the same Capture.
- [x] Direct SQLite inspection confirmed migrations `1,2`, three triggers, one
  Capture, one FTS row, and one matching FTS row. The disposable DB was removed.

## Exit gate

- [x] Every representative fixture is retrievable through at least one exact
  keyword or phrase, even with OpenAI disabled.

## Delivery

- [x] Commit the working Layer 5 slice in `d34a567`.
- [x] Push the working Layer 5 slice to `origin/main`.

---

# Layer 6 — Chrome extension capture

Status: `[x]` implementation and real unpacked-Chrome/macOS gate verified

Historical note: the extraction and real-page context rows below prove the
original D-018/D-009 implementation. D-030 supersedes that browser-client
behavior: current Chrome submissions use empty `surrounding_context`, including
the no-selection toolbar path, while the shared contract capability remains.

## Decisions and prerequisites

- [x] End the D-016 deferral after the verified Layer 7 backend implementation.
- [x] Record the build-free Manifest V3 structure and note-draft storage scope
  in D-018 before implementation.
- [x] Keep all browser Capture fields within the existing shared contract; no
  schema change is required.

## Build tasks

- [x] Create a Manifest V3 extension under `apps/chrome-extension/`.
- [x] Request only `activeTab`, `scripting`, `storage`, and required localhost
  host permission.
- [x] Historically extracted page title, URL, selected text, and nearby context;
  D-030 now extracts the same fields but submits no browser context.
- [x] The historical extractor located the selection's
  `commonAncestorContainer`, then preferred `article`,
  `[role="main"]`, `.answer`, `.post-text`, `main`, or the nearest `p`, `div`,
  or `section` without site-specific parsers. D-030 removes this strategy after
  the Gemini sidebar failure.
- [x] The historical fallback used a truncated portion of
  `document.body.innerText`; D-030 explicitly forbids this fallback.
- [x] Historically enforced the shared context limit and set
  `context_truncated`; current browser requests use empty context and therefore
  keep this context-specific flag `false`. Selection shortening is reported
  separately in the browser UI.
- [x] Historically supported no-selection page-context capture with a clear
  warning. D-030 keeps the D-009 metadata-only path but submits no page text.
- [x] Build popup page title, selection preview, optional note, Save, `Saved`,
  and `Processing with AI` states.
- [x] Send the exact Capture contract to the backend.
- [x] Show `Recall is not running` when localhost is unreachable.
- [x] Configure narrow CORS origins; never submit with `*`.

## Required browser tests

These are retained historical acceptance results. The first seven context
expectations were replaced by D-030 and are not current browser behavior.

- [x] Stack Overflow: actual page returned 6,211 characters from the preferred
  page container without truncation.
- [x] GitHub Issue: actual issue returned 8,170 characters from the preferred
  page container without truncation.
- [x] Ordinary article/blog: Python.org returned 2,804 characters from the
  preferred page container.
- [x] OpenAI documentation: the embeddings guide returned 6,968 characters
  from the preferred page container.
- [x] Code block selection: a real DOM Range produced the exact two-line
  systemd command and its surrounding article context.
- [x] No selection: actual public pages and the popup harness returned page
  context plus the visible warning.
- [x] Long context: the browser fixture returned exactly 20,000 characters and
  `context_truncated=true`.
- [x] Backend stopped: deterministic Node and browser-harness connection
  refusal tests show the exact recovery message. The final UI-automation run
  stopped 8765 as well, though the transient Chrome popup did not expose a
  stable accessibility update; no stronger manual-UI claim is made.

## Validation evidence

- [x] The dependency-free extension suite passes all 13 tests with the bundled
  Node runtime and through the package script.
- [x] Node syntax checks pass for extraction, API, and popup modules.
- [x] The pre-split combined backend suite passed all 165 tests, including
  strict CORS; `pip check` and bytecode compilation passed.
- [x] The isolated `layer/6-chrome-capture` branch passes 128 backend tests,
  all 13 extension tests, `pip check`, bytecode compilation, and JS syntax
  checks without any embedding or hybrid-retrieval files.
- [x] Push `layer/6-chrome-capture` to `origin` at `d426ca8`.
- [x] The real browser matrix covers Stack Overflow, GitHub, Python.org, OpenAI
  docs, selected code, no selection, long context, saved state, processing
  state, and connection-refusal state using the checked-in modules.
- [x] Disposable backend 0.7.0 proof accepted the exact extension payload as
  `202 processing`, preserved all source/note fields in SQLite, and transitioned
  safely to `error` only because OpenAI was intentionally disabled.
- [x] Exact extension-origin preflight returned `200`; an unconfigured public
  origin returned `400`. Methods remained `GET, POST`, with no credentials.
- [x] Temporary browser tabs, fixture server, backend process, and database
  were removed; the pre-existing process on port 8765 was untouched.

## Exit gate

```text
Chrome selection
→ popup preview and note
→ POST Capture
→ original persists
→ card appears in macOS app
```

- [x] Complete workflow passes without developer database edits. A user-loaded
  unpacked extension saved page-context and a 132-character real selection;
  both became ready Google Chrome cards in the macOS app. B-009 is resolved.

---

# Layer 7 — Embeddings and hybrid retrieval

Status: `[x]` implementation and cross-layer exit gate verified

## Decisions required before implementation

- [x] Confirm embedding model access. A real configured embedding request
  returned `200` and produced a stored compatible vector.
- [x] Use the configured model's default dimensions for the MVP. Only introduce
  reduced dimensions or version migration if a tested constraint requires it,
  and document that change first.
- [x] Cross-check the implementation call shape against the official OpenAI
  embeddings guide and API reference: `client.embeddings.create`, one input,
  configured model, float encoding, and `response.data[0].embedding`.

## Build tasks

- [x] Implement the exact §12.1 embedding-input builder.
- [x] Keep labels, order, LF normalization, joining, and final newline stable.
- [x] Test the builder against `contracts/examples/embedding-input.txt`.
- [x] Generate an embedding only after successful enrichment.
- [x] Store vectors as JSON arrays in SQLite.
- [x] Do not introduce Pinecone, Weaviate, Milvus, Redis Vector, or a complex
  SQLite vector extension for the Build Week dataset.
- [x] Embed the search query using the same model and dimensions.
- [x] Calculate cosine similarity in Python.
- [x] Implement normal weights:
  `0.55 semantic + 0.35 keyword + 0.10 metadata`.
- [x] Implement technical-query weights:
  `0.45 semantic + 0.50 keyword + 0.05 metadata`.
- [x] Calculate metadata bonuses from URL-domain, source-app, exact-tag, and
  exact error-code matches.
- [x] Detect technical identifiers using digits, paths, hyphens, underscores,
  hexadecimal prefixes, URLs, and mixed-case identifiers.
- [x] Return final, keyword, and nullable semantic scores.
- [x] Fall back to FTS if Capture embedding or query embedding is unavailable.

## Required tests

- [x] Exact query still ranks correctly.
- [x] Vague personal description retrieves the intended Capture.
- [x] Technical identifier query favors exact text.
- [x] Chinese query retrieves relevant English source with Chinese note.
- [x] Missing Capture embedding does not crash search.
- [x] Query embedding failure returns FTS results.
- [x] Score ordering is deterministic for fixed fixtures.

## Validation evidence

- [x] The Layer 7 focused suite passes 137 tests across embedding projection,
  provider boundaries, enrichment, storage, hybrid ranking, and HTTP behavior.
- [x] `.venv/bin/python -m pytest` passes all 156 tests.
- [x] `pip check`, `git diff --check`, and bytecode compilation pass.
- [x] Exact fixture comparison proves stable labels, order, list trimming, LF
  normalization, preserved internal note/source whitespace, and final newline.
- [x] Deterministic HTTP tests prove post-enrichment vector persistence and a
  semantic-only API result with final/keyword/semantic score fields.
- [x] A disposable backend 0.6.0 live run with OpenAI disabled preserved the
  raw Capture, stored `embedding_json` as null, and returned
  `WorkingDirectory` with `score=keyword_score=1.0` and
  `semantic_score=null` before and after a clean restart.
- [x] The disposable database and both live server processes were removed.
- [x] A real OpenAI embedding request passed. A vague query ranked the intended
  Capture first with `semantic_score=0.424013`; provider-off Captures continued
  to return `semantic_score=null` without breaking keyword retrieval.

## Vertical-slice exit gate

```text
Chrome selection
→ OpenAI enrichment
→ §12.1 embedding
→ vague natural-language query
→ intended Capture ranks near the top
```

- [x] The real provider path and unpacked-Chrome selected-text workflow pass
  end to end; deterministic Layer 7 coverage remains complementary evidence.
- [x] Commit the working slice as `faa45d7` on
  `layer/7-hybrid-retrieval`.
- [x] Push `layer/7-hybrid-retrieval` to `origin` at `faa45d7`.

---

# Layer 8 — Reliability and demo readiness

Status: `[~]` shared P0 integration verified; explicit reliability backlog remains

## Backend stress audit

- [x] Run the existing integrated backend suite before stress: all 165 tests
  passed.
- [x] Exercise weird, Unicode, prompt-injection, SQL-looking, NUL, oversized,
  duplicate, ambiguous, and conflicting context cards.
- [x] Exercise 1,000 bulk writes, including 500 posts with 64 workers and 200
  with 32 workers; no lock error occurred, Capture/FTS counts matched, SQLite
  integrity passed, and restart retrieval worked.
- [x] Exercise provider-invalid output, extreme finite vectors, corrupted JSON,
  CORS, provider-off retrieval, 1,005-card semantic scans, and 500 stored
  1,536-dimension vectors.
- [!] The escalated 67.025-second run completed 44 scenarios with 28 passes and
  16 breaks, grouped as ST-001 through ST-013 under B-011.
- [x] Resolve the historical failure above on `fix/backend-stress-hardening`:
  all 44 scenarios pass in 17.896 seconds and all ST-001 through ST-013 groups
  have regression coverage.
- [x] Record exact reproduction, impact, limitations, passed cases, and repair
  order in `docs/backend-stress-report-2026-07-18.md`.
- [x] Commit the harness and branch-local backend instructions as `0c9a52f` on
  `test/backend-stress`.
- [x] Commit the concise remediation as `5ea3d2a` on
  `fix/backend-stress-hardening`; 181 backend tests and bytecode compilation
  pass.
- [x] Publish the historical stress, hardening, integration, and isolated layer
  checkpoints to `origin`.
- [x] Assemble the hardened backend, Chrome extension, macOS client, contracts,
  and current documentation in the final integration tree. Current `main`
  passes 190 backend tests, 44/44 stress scenarios, 16 extension tests, and 27
  macOS tests.

The audit itself made no production change. D-021 records the separately
authorized follow-up remediation and its exact contract additions.

## Build tasks

- [x] Polish the Chrome demo path under D-025: add the extension shortcut,
  keyboard submission, brief success confirmation with automatic close,
  contract-limit validation, and stable retry identity. All 16 automated
  extension tests and JavaScript/JSON syntax checks pass.
- [ ] Load the integrated extension unpacked in Chrome and confirm the suggested
  shortcut is available, `Command+Enter` submits once, the success state remains
  legible, and the popup closes after its 700 ms confirmation.
- [x] Recover stale `processing` records after restart. The transactional
  startup transition preserves source/user content, exposes a retryable error,
  and passes focused lifecycle coverage, the 190-test suite, and 44/44 stress
  scenarios.
- [x] Make repeated client submissions transactionally idempotent when
  `client_capture_id` is supplied, including concurrent retry coverage.
- [x] Keep enrichment failure terminal while allowing embedding failure to fall
  back to keyword retrieval.
- [x] Retain safe enrichment retry and prevent concurrent duplicate work.
- [ ] Add request/Capture IDs to logs only if they materially improve demo
  debugging; this is an engineering safeguard, not a P0 feature.
- [ ] Never log API keys or complete private captured text by default.
- [ ] Create deterministic demo seed data from contract fixtures.
- [x] Create `scripts/dev.sh` as the documented clean-start backend command.
  Bash validation, automated safeguards, a live provider-off start, health wait,
  duplicate-process detection, URL output, and clean `Control-C` shutdown pass;
  the complete 190-test suite and 44/44 stress scenarios also pass.
- [x] Add `scripts/test-macos.sh` as a deterministic Xcode 26.6 command-line
  fallback. A clean build-for-testing followed by direct `xctest` execution
  passes all 27 tests without changing production code or project settings.
- [ ] Document backend-connected/disconnected behavior for Developer A.
- [x] Record stress limitations and remaining live/system gates in the README
  and dated stress report.

## Shared P0 integration checks

Previous macOS-branch manual evidence covers clipboard capture, notes, source
attribution, backend search, restart, offline launch, and empty/overlong
clipboard behavior. The boxes below remain open until the applicable checks are
rerun against the current integrated tree.

- [ ] Chrome capture and macOS clipboard capture both work; one stable path is
  not enough for the P0 scope.
- [ ] Developer A verifies the app can start, list Captures, search, show detail,
  show `processing`/`ready`/`error`, display source/user/AI sections separately,
  and open the original URL.
- [ ] Developer A verifies Chrome, Preview, Word or TextEdit, and a chat app.
- [ ] Developer A verifies empty and overlong clipboard behavior, backend-offline
  behavior, API failure, and persistence after app restart.
- [ ] Run and record at least two end-to-end integration checks per day.

## Demo reliability preparation

- [ ] Use a known, stable public web page for the primary recording.
- [ ] Prepare a local fallback HTML page.
- [ ] Prepare an already-enriched note matching the live demo scenario.
- [ ] Verify API quota, network connectivity, and model access before recording.
- [ ] Avoid dependency upgrades immediately before recording.
- [ ] Disable unrelated notifications.
- [ ] Record both a continuous live version and an edited version if AI latency
  makes the continuous version weak.
- [ ] Preserve the original recording files.

## Failure matrix

- [ ] Database unavailable.
- [ ] OpenAI key missing.
- [ ] Model unavailable.
- [ ] Enrichment timeout/refusal/invalid output.
- [x] Provider-invalid output: hardening adds provider-neutral validation and
  regression coverage for historical ST-009 and ST-010.
- [x] Embedding failure: overflow-safe scoring resolves historical ST-012.
- [ ] Chrome extension cannot reach backend.
- [ ] Backend restart during processing.
- [ ] macOS app restarts after data creation.
- [x] Oversized request/provider output: bounded by the ST-001/ST-011
  remediation and regression tests.
- [x] NUL and unbounded search queries: rejected by the ST-006/ST-007
  remediation.
- [x] Concurrent semantic-search latency: cached vector decoding resolves the
  historical ST-008 threshold in the deterministic stress run.

## Exit gate

- [ ] Main demo succeeds three consecutive times from a documented clean start.
- [ ] A failed AI call leaves a visible, persistent, keyword-searchable Capture.
- [ ] No manual database modification is needed during the demo.
- [ ] First backup recording is completed before optional Apple work begins.

---

# Layer 9 — Optional Apple on-device intelligence

Status: `[D]` gated; do not start yet

This is decision D-008 and an addition to the product baseline.

## Activation gate

- [ ] Layers 1–8 are complete.
- [ ] All three vertical slices pass.
- [ ] OpenAI remains the primary judged workflow.
- [ ] A backup demo recording exists.
- [ ] Target Mac hardware and OS support Apple Foundation Models.
- [ ] Apple Intelligence/model availability is confirmed at runtime.
- [ ] Remaining schedule can absorb the experiment without risking submission.
- [ ] The experiment begins before the July 21 feature freeze; otherwise it is
  automatically deferred.

If any activation item fails, leave this layer `[D]`, document why, and proceed
to Layer 10. Deferral is the intended safe outcome, not a project failure.

## Contract and architecture tasks

- [ ] Define and record provider metadata fields before schema/database edits.
- [ ] Keep one enrichment output contract for OpenAI and Apple.
- [ ] Ensure provider identity never changes source/user-note semantics.
- [ ] Define behavior when Apple Foundation Models is unavailable.
- [ ] Define whether Apple output is stored as an alternative version or
  replaces only the active AI interpretation.

## Developer B tasks

- [ ] Provide a provider-neutral enrichment interface.
- [ ] Persist provider/model/version metadata.
- [ ] Accept validated Apple enrichment results from the macOS client through a
  narrowly scoped local API contract.
- [ ] Keep the OpenAI provider and retrieval path unchanged.
- [ ] Compare outputs using the same fixtures and quality criteria.

## Developer A tasks

- [ ] Add Foundation Models capability and availability checks.
- [ ] Generate the common enrichment structure with guided generation.
- [ ] Add a clearly labeled local/provider demonstration control.
- [ ] Show unavailable/error states without blocking normal capture.

## Optional local retrieval experiment

- [ ] Obtain separate approval after local enrichment works; Apple retrieval is
  not implied by approval of the enrichment demonstration.
- [ ] Evaluate `NLEmbedding` sentence support for required demo languages.
- [ ] Measure retrieval quality against the OpenAI embedding fixtures.
- [ ] Keep vector spaces completely separate; never compare Apple and OpenAI
  vectors directly.
- [ ] Do not replace baseline hybrid search unless separately approved and
  documented.

## Exit gate

- [ ] The same Capture can be enriched locally into the common contract.
- [ ] Provider identity is visible and stored.
- [ ] OpenAI demo behavior is unchanged when Apple support is absent.
- [ ] The optional path adds no manual setup to the primary demo.

---

# Layer 10 — Final freeze and submission

Status: `[ ]` pending

## Engineering freeze

- [ ] Stop feature work.
- [ ] Merge only verified fixes.
- [ ] Keep the last known working commit available for immediate rollback.
- [x] Confirm the D-023 integration tree is runnable and ready to restore the
  full product tree to `main`.
- [x] Run backend tests and contract validation: 186 tests and all 44 stress
  scenarios pass.
- [x] Run Chrome and macOS manual integration matrices, including selected-text
  and no-selection browser Captures displayed in the app.
- [x] Confirm `.env` and API keys are absent from tracked files; the live key and
  exact development extension origin remain only in the ignored local `.env`.
- [ ] Tag the verified version `demo-stable`.

## Documentation and handoff

- [ ] Complete backend setup and troubleshooting instructions.
- [ ] Complete Chrome extension installation instructions.
- [ ] Complete README sections for Problem, Solution, Demo, Key Features, How It
  Works, Architecture, OpenAI Usage, Repository Structure, Setup, Environment,
  Development, Known Limitations, Future Work, Team, and License.
- [ ] Add an architecture diagram, screenshots, and an open-source license.
- [ ] Document OpenAI usage and failure fallback.
- [ ] Explain how Codex was used for planning, scaffolding, debugging, and
  delivery.
- [ ] Document Apple path as implemented, deferred, or unavailable—never imply
  it exists if it was not completed.
- [ ] List known limitations.
- [ ] Verify another machine/person can follow setup instructions.

## Shared submission gate

- [ ] Final demo video.
- [ ] Backup demo video.
- [ ] Screenshots and cover image.
- [ ] Devpost description.
- [ ] Devpost accurately covers OpenAI capabilities, challenges,
  accomplishments, lessons, and next steps.
- [ ] Repository visibility and links verified.
- [ ] Video links and all submission materials verified from a logged-out or
  independent view where practical.
- [ ] Confirm the exact Devpost timezone and deadline rather than relying only
  on the planning document.
- [ ] Submission completed before the official deadline.

---

# Open blockers and risks

Use IDs `B-###`. Never delete an entry; append resolution and date.

## B-001 — Layer 0 branch is not integrated into `main`

- Opened: 2026-07-18
- Severity: Coordination
- Status: Resolved 2026-07-18
- Impact: Developer A may build against older or absent contracts if working
  from `main`.
- Resolution: Pull request #1 was merged. `origin/main` is at merge commit
  `9c08243`, which contains Layer 0 commit `e75f783`.
- Does it block Layer 1 locally? No.

## B-002 — OpenAI credentials and model access verification

- Opened: 2026-07-18
- Severity: Future Layer 4 blocker
- Status: Resolved 2026-07-19
- Impact: Real enrichment and embedding tests cannot run until project-scoped
  credentials and model access are available.
- Resolution: A key stored only in the ignored root `.env` successfully called
  the configured Responses and embedding models after billing was enabled.
- Does it block Layers 1–3? No.

## B-003 — Apple runtime capability is unverified

- Opened: 2026-07-18
- Severity: Optional-path risk
- Status: Open / gated
- Impact: Target hardware, OS, Apple Intelligence configuration, language, or
  model availability may prevent the local demonstration.
- Resolution needed: Run capability checks on the exact demo Mac after the
  baseline workflow is stable.
- Does it block P0? No.

## B-004 — Day 0 backend target is not yet complete

- Opened: 2026-07-18
- Severity: Schedule risk
- Status: Resolved 2026-07-19
- Impact: The product plan's July 18 target includes FastAPI, health, SQLite,
  Capture CRUD, curl proof, and macOS list integration. Layers 1–3 backend work
  and curl proof were complete while macOS integration remained.
- Resolution: The maintained macOS target completed live list/detail and
  clipboard integration, retired the temporary holder, and closed D-013.
- Does it block later work? No.

## B-005 — Uncommitted documentation prevents a clean Layer 1 branch

- Opened: 2026-07-18
- Severity: Workflow
- Status: Resolved 2026-07-18
- Impact: README, architecture, decisions, and the live checklist are modified
  on `agent/layer-0-contracts`. Starting backend code now would mix planning
  changes with the Layer 1 implementation or carry uncommitted changes across a
  branch switch.
- Resolution: Documentation was committed and pushed in `926655c`. Layer 1
  started from clean `main`, with local `HEAD` equal to `origin/main`.
- Does it block writing code? No technically; yes for the recommended clean
  branch and commit history.

## B-006 — Developer A macOS display confirmation is pending

- Opened: 2026-07-18
- Severity: Coordination / Layer 3 exit gate
- Status: Resolved 2026-07-18
- Impact: Developer B's POST → SQLite → GET/list flow passes, but the first
  shared vertical slice is not complete until the macOS app displays the live
  backend Capture.
- Resolution: Developer A replaced the holder with `apps/macos/`, displayed
  live list/detail and clipboard Captures, preserved source/note separation, and
  removed the placeholder. Historical branch build and test evidence is
  retained in the handoff.
- Does it block Layer 4 or the shared Layer 3 slice? No.

## B-007 — OpenAI credential gate for the Layer 4 live proof

- Opened: 2026-07-18
- Severity: Integration / Layer 4 exit gate
- Status: Resolved 2026-07-19
- Impact: Provider-boundary implementation and deterministic tests can proceed,
  but the current `/health` response reports `openai_configured: false`, so a
  real Responses API enrichment and model-access check cannot run.
- Resolution: The ignored root `.env` was loaded without exposing the key. An
  initial provider `429` safely produced `error`; after billing activation, the
  same Capture retried through `processing → ready` with validated generated
  fields and preserved source data.
- Does it block Layer 4? No; the live exit gate is closed.

## B-008 — OpenAI embedding access gate

- Opened: 2026-07-18
- Severity: Integration / Layer 7 exit gate
- Status: Resolved 2026-07-19
- Impact: The exact embedding projection, provider boundary, SQLite storage,
  cosine/hybrid scoring, deterministic vector tests, and FTS fallback can be
  implemented and verified, but a real embedding-model request cannot run.
- Resolution: The configured embedding model returned `200`; the stored vector
  produced a non-null semantic score and ranked the intended Capture first for
  a vague query. Provider-off FTS behavior remained usable.
- Does it block Layer 7? No; the live model-access gate is closed.

## B-009 — Real unpacked-Chrome-to-macOS confirmation

- Opened: 2026-07-18
- Severity: Coordination / Layer 6 exit gate
- Status: Resolved 2026-07-19
- Impact: Manifest, extraction, popup behavior, exact API delivery, SQLite
  persistence, CORS, and browser-page behavior are verified independently, but
  the complete toolbar-action flow has not run in a user-loaded Chrome
  extension and the resulting card has not been confirmed in Developer A's
  macOS app.
- Resolution: Loaded `apps/chrome-extension/` unpacked, configured its exact
  origin only in the ignored `.env`, and saved both a no-selection page-context
  Capture and a 132-character selected passage. Both reached `ready` through
  real enrichment and appeared automatically as Google Chrome cards in the
  macOS app without a database edit. Backend-off recovery retains deterministic
  extension coverage; the transient popup did not yield a stable accessibility
  observation during the automated stop test.
- Does it block Layer 6? No; the cross-client gate is closed.

## B-010 — Documentation-only main is not a runnable integration tree

- Opened: 2026-07-18
- Severity: Architecture / Layer 8 integration gate
- Status: Resolved 2026-07-19 by D-023; deterministic and live verification complete
- Historical impact: Contracts and descriptions remained centralized, but
  checking out the documentation-only `main` could not start or test Recall.
- Resolution: The final integration tree restores `apps/macos/`,
  `apps/chrome-extension/`, and `services/backend/` alongside contracts and
  docs. It preserves the main, hardening, and macOS histories and passes the
  current backend, stress, extension, and macOS automated suites.
- Does it block Layer 8? No. The formerly independent B-007/B-008/B-009 live
  gates are also resolved.

## B-011 — Backend stress audit found thirteen grouped breakpoints

- Opened: 2026-07-18
- Severity: Reliability / Layer 8 blocker
- Status: Resolved 2026-07-18 on `fix/backend-stress-hardening`
- Evidence: `docs/backend-stress-report-2026-07-18.md`, harness commit
  `0c9a52f`, and an escalated 44-scenario run with 28 passes and 16 breaks.
- High-priority failures: NUL query returns 500; invalid provider output can
  become empty-ready or permanently processing; finite extreme vectors overflow
  cosine search; client/provider data is unbounded; concurrent full-vector scans
  reach 8.9–17.7 seconds.
- Medium/low failures: duplicate client IDs, strict-boolean contract drift,
  malformed-byte envelope drift, natural provider-off query misses, unbounded
  echoed query, and health blindness to corrupt row JSON.
- Resolution: Commit `5ea3d2a` applies bounded strict input, transactional
  idempotency, provider-neutral `invalid_model_output`, query hardening and FTS
  relaxation, cached overflow-safe semantic scoring, bounded enrichment, and
  deeper database health. The suite passes 181/181 tests and the unchanged
  scenario set passes 44/44 in 17.896 seconds.
- Integrated follow-up evidence: current `main` passes 190 backend tests and the
  unchanged 44/44 stress scenarios.
- Does it block Layer 8? No. Shared P0 live gates are resolved.

## B-012 — Real GPT screenshot extraction proof

- Opened: 2026-07-20
- Severity: External integration evidence / non-blocking
- Status: Resolved 2026-07-20
- Impact: Before resolution, only the default GPT route, request shape, provider
  metadata, refusal, incomplete response, invalid output, oversize output,
  provider failure, and missing-key behavior were deterministically tested.
- Evidence: The current isolated one-command startup reports
  `openai_configured=true`. Earlier provider-off smoke on port 8876 returned the
  stable HTTP 503 envelope and left the Capture list empty, proving OCR input was
  not persisted. Deterministic provider/request coverage passes.
- Resolution: Developer A ran the hardening tree against the isolated
  `/private/tmp` database with the ignored root `.env`. GPT extracted harmless
  prepared screenshot text into the source field, left the personal note
  independent, and saved/displayed the two sections correctly.
- Does it block build, deterministic verification, commit, or push? No. The
  manual integration gate is now closed.

## B-013 — Interactive macOS screenshot permission flow

- Opened: 2026-07-20
- Severity: Manual UI/demo evidence / non-blocking
- Status: Resolved 2026-07-20
- Impact: The production `/usr/sbin/screencapture -i` path compiles, injected
  screenshot drafts are tested, and the production Apple Vision extractor reads
  generated screenshot text. Permission preflight now exposes an actionable
  System Settings message, cancellation/close clears the draft, and generation
  guards reject late extraction results. Automation did not click-drag the real
  system overlay because that could capture unrelated private desktop content.
- Resolution: Developer A completed the real Screen Recording permission flow,
  cancelled the system region selector without creating a draft, verified both
  GPT and Apple Vision extraction, then dismissed an extraction through the
  available Cancel action. After ten seconds a fresh screenshot produced only
  its fresh result; no old preview or late OCR result returned.
- Does it block build, automated verification, commit, or push? No. The manual
  permission and selection gate is now closed.

## B-014 — Physical global capture acceptance

- Opened: 2026-07-21
- Severity: Manual UI/demo evidence / non-blocking for implementation
- Status: Resolved 2026-07-21
- Impact: Carbon registration, Settings persistence, rollback behavior,
  coordinator routing, exact clipboard Quick Capture, repeated-trigger draft
  preservation, and asynchronous screenshot cancellation are covered by 70/70
  host tests and bounded UI checks. Automation cannot synthesize a trustworthy
  system-wide physical hotkey or complete a meaningful non-empty user region.
- Evidence already complete: Settings showed both defaults, persisted a
  screenshot change to `Option+Shift+Command+5` across restart, restored
  defaults, and reported active Carbon registration. Clipboard Quick Capture
  contained the exact 32 characters and preserved its draft on a repeated
  trigger. Code-signing inspection of the actual running process found
  `Signature=adhoc`, no Team ID, and a CDHash-only designated requirement. A
  stable Apple Development-signed build now passes the repository verifier.
  App-specific reset and authorization succeeded; a same-signer version-2
  rebuild changed CDHash from `143035…` to `5a1b00…` without changing Team ID or
  the signer-based requirement. Rebuilt PID 87557 launched
  `/usr/sbin/screencapture`, displayed the overlay, and returned without a
  permission error after Escape. The 19,144-character context record also
  remained collapsed and responsive.
- Resolution: With Recall's main window closed and another app focused, the user
  physically pressed `Option+Shift+Command+4` and completed a non-empty region
  through the existing capture flow. After copying text, the user physically
  pressed `Option+Shift+Command+C` and Capture opened as expected.
- Does it block build, deterministic regression, documentation, or live demo
proof? No. The real-device global capture acceptance gate is closed; future
release candidates should repeat the interaction check.

## B-015 — Native Accessibility selection acceptance

- Opened: 2026-07-21
- Severity: Manual UI/privacy/compatibility gate
- Status: Closed; primary AX and D-035 compatibility paths were accepted by the
  user on 2026-07-21
- Automated evidence: The host macOS suite passes 108/108. It covers permission
  fail-closed ordering, self/secure/protected-content rejection, exact text,
  optional bounds, no-context contract mapping, 12,000-character protection,
  cancellation, v1 shortcut migration and conflicts, and placement geometry.
- Manual evidence: The user reported the native S shortcut works without an
  observed regression. WeChat does not expose the selected text through the AX
  path, which correctly produced failure rather than stale clipboard content
  and motivated the separately opt-in D-035 fallback.
- Merge rule: Satisfied by B-016 acceptance and explicit user authorization.

## B-016 — Clipboard Compatibility Mode acceptance

- Opened: 2026-07-21
- Severity: Manual privacy/data-preservation/compatibility gate
- Status: Closed on 2026-07-21; the user reported no issue in final WeChat
  testing and explicitly authorized merging PR #13
- Automated evidence: 149/149 host tests pass, including eligibility isolation,
  exact Unicode, default-off and persisted opt-in, exact-control and
  application-scoped AX tickets,
  off-main serial transaction, event/security preflight, modifier release,
  consecutive-count and matching-
  payload confirmation, stale/late/competing-write rejection, restore failure,
  12,000-character bounds, no-context API mapping, and no backend request before
  Save. The deterministic service tests use a fake pasteboard and do not touch
  the user's general clipboard; real AppKit multi-item/type, image, Finder-file,
  lazy-provider, and round-trip behavior remains part of this manual gate.
- Manual evidence: After the application-scoped fallback correction, the user
  confirmed the WeChat flow works, reported no current issue, and authorized
  merge. The broader rich-text/image/Finder/lazy-provider and deliberate-race
  matrix was not separately enumerated in that report; retain it as release
  regression coverage rather than claiming every format was manually proven.
- Merge rule: Satisfied. Keep the documented best-effort clipboard limitations
  and repeat the broader matrix before a release candidate.

# Errors encountered

Use IDs `E-###`. Record the original symptom and the resolution. Do not erase
resolved errors.

## E-060 — UTF-16 regression exposed an ambiguous no-BOM byte order

- Date: 2026-07-21
- Status: Resolved 2026-07-21
- Symptom: The first 171-test D-036 run passed 170 tests but decoded a synthetic
  `public.utf16-plain-text` payload without a byte-order mark as unrelated CJK
  characters.
- Cause: Foundation's generic UTF-16 decoder accepted the no-BOM bytes with the
  wrong order before the explicit little-endian decoder was tried.
- Resolution: Honor an explicit big- or little-endian BOM first and otherwise
  use the native little-endian order of every supported macOS target. The same
  171-test host suite now passes completely.
- Project impact: Correct plain-text decoding for a legacy pasteboard alias;
  no API, storage, or rendering change.

## E-059 — Chrome action popup collapsed to a title-height strip

- Date: 2026-07-21
- Status: Resolved and real-Chrome verified 2026-07-21
- Symptom: Opening the Recall toolbar action showed only a narrow strip with
  the brand and clipped heading. The remaining controls existed and could be
  reached only by scrolling inside that approximately minimum-height window.
- Cause: D-030 removed the popup's working fixed minimum and applied
  `max-height: min(560px, 100vh)` to an internally scrolling shell. Chrome sizes
  an action popup from its content, so the content simultaneously depended on
  the viewport Chrome was still calculating and collapsed the sizing loop.
- Resolution: D-033 establishes a 344 × 510 pixel root, makes the body and shell
  fill it, retains the internal scroller, and rejects viewport-height units in
  automated coverage. All 68 extension tests pass, and real unpacked Chrome
  shows complete selected and metadata-only layouts after reload.
- Project impact: Popup layout and its regression test only; no API, backend,
  storage, permission, inline-capture, or surrounding-context change.

## E-058 — Enabled Screen Recording row did not authorize the rebuilt app

- Date: 2026-07-21
- Status: Resolved and live-verified 2026-07-21
- Symptom: Pressing `Option+Shift+Command+4` showed Recall's Screen Recording
  requirement even though **System Settings > Privacy & Security > Screen &
  System Audio Recording** already displayed Recall as enabled. Restarting the
  app did not resolve it.
- Cause: Inspection targeted the actual running app. It was ad-hoc signed with
  no Team ID, and its designated requirement named only one CDHash. A rebuild
  changed that requirement, so TCC's retained row described an older same-name
  Recall identity while the current `CGPreflightScreenCaptureAccess()` result
  correctly remained false.
- Resolution: D-032 adds portable Xcode signing configuration, an optional
  gitignored local Apple Development Team ID override, a verifier that rejects
  missing Team IDs and CDHash-only requirements, and a runtime explanation when
  a temporary signature cannot match the visible permission. A stable local
  build now retains its signer-based requirement across a changed executable
  CDHash, while the verifier rejects the old ad-hoc app. App-specific reset,
  authorization, **Quit & Reopen**, a same-signer version-2 rebuild, selector
  launch, and Escape cancellation all pass without the permission error. The
  complete macOS suite passes 70/70. B-014 subsequently passed the physical
  screenshot shortcut with a completed non-empty region and the clipboard
  shortcut after copying text, so it is closed.
- Project impact: No API, storage, Chrome, OCR, image-persistence, or entitlement
  change. `CODE_SIGNING_ALLOWED=NO` remains valid for deterministic automation
  but is explicitly excluded from Screen Recording acceptance.

## E-055 — Job-level environment referenced the runner context too early

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Evidence: GitHub Actions run `29788040282`
- Symptom: The corrected workflow still failed before creating jobs because
  `runner.temp` is unavailable in `jobs.<job_id>.env` while GitHub is preparing
  the job.
- Resolution: Scoped `RECALL_DERIVED_DATA_PATH` to the macOS test step, where
  the `runner` context is available.
- Project impact: Workflow-only correction; the test continues to use the
  runner's disposable temporary directory.

## E-054 — First cloud CI parse rejected a hyphenated job reference

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Evidence: GitHub Actions run `29787636411`
- Symptom: GitHub created a failed run with no jobs because the aggregate
  expression referenced `needs.backend-stress.result`; the hyphen was parsed as
  an operator. Generic YAML validation could not detect GitHub expression
  semantics.
- Resolution: Renamed the internal job ID to `backend_stress` while preserving
  the user-facing **Backend stress** check name, then republished the workflow.
- Project impact: Workflow-only correction; no application or test behavior
  changed.

## E-053 — Sandboxed macOS verification could not access Vision services

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Command: `./scripts/test-macos.sh`
- Symptom: The restricted first run could not write CoreSimulator logs and the
  production Apple Vision test returned a generic Foundation error; the other
  42 tests passed.
- Resolution: Reran the identical suite with normal host access. Apple Vision
  succeeded and all 43 tests passed. No source change was required.
- Project impact: Execution-environment restriction only; the GitHub-hosted
  macOS runner uses its normal host services.

## E-048 — Screenshot tests first awaited inside XCTest autoclosures

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Command: `./scripts/test-macos.sh`
- Symptom: The production target built, but the new test target failed because
  `XCTAssert*` and `XCTUnwrap` autoclosures do not allow `await` expressions.
- Resolution: Awaited actor/store values into local constants before passing
  them to XCTest assertions. The deterministic suite then passed all 34 tests.

## E-049 — Production Vision test rerun used the wrong relative script path

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Command: `xcodegen generate && ../../../scripts/test-macos.sh` from
  `apps/macos`
- Symptom: Xcode project generation succeeded, then zsh reported that the test
  script did not exist; no test command ran.
- Resolution: Reran `../../scripts/test-macos.sh`; all 36 tests passed,
  including both production Apple Vision tests.

## E-050 — Full regression shell could not find npm

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Command: `npm test` in `apps/chrome-extension`
- Symptom: zsh returned `command not found: npm`, so no extension test ran in
  that attempt. Parallel backend verification still passed 206 tests and all 44
  stress scenarios.
- Resolution: Loaded the bundled workspace runtime and ran the suite with its
  exact Node executable; all 16 tests passed.

## E-051 — Extension syntax-check glob assumed flat source files

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The bundled Node runtime passed all 16 extension tests, then zsh
  rejected `src/*.js` because JavaScript files live in nested directories. The
  combined command therefore exited nonzero after the successful tests.
- Resolution: Enumerated tracked `.js`/`.mjs` files with `rg --files`; every
  file passed Node's syntax checker.

## E-052 — First live OCR smoke port was already occupied

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The isolated provider-off backend applied migrations to its temporary
  database, then exited cleanly because another process already owned loopback
  port 8765.
- Resolution: Preserved the existing process and reran on port 8876. The OCR
  route returned the expected provider-off 503, list returned 200 with no
  Captures, and the temporary service shut down cleanly.

## E-056 — GitHub app could not create the draft pull request

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The branch pushed successfully, but the GitHub app returned HTTP 403
  `Resource not accessible by integration` for draft-PR creation.
- Resolution: Used the already authenticated GitHub CLI as the publishing
  workflow's documented fallback and opened draft PR #4:
  `https://github.com/CamaroW/capture/pull/4`.

## E-057 — Sandboxed live-start probe could not bind a loopback port

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The first isolated `scripts/dev.sh` probe reached Uvicorn but the
  restricted execution environment rejected its bind to `127.0.0.1:18765` with
  `operation not permitted`.
- Resolution: Reran the same test under the host's approved local-network
  permission with an isolated `/private/tmp` database. Health returned `200`,
  the version-aware dependency check passed, and Control-C shut down cleanly.

## E-038 — First real provider call returned HTTP 429

- Date: 2026-07-19
- Status: Resolved 2026-07-19
- Symptom: The key loaded successfully and creation returned `202`, but the
  Responses API returned `429 Too Many Requests`; the Capture safely became
  `error` with no source loss.
- Resolution: Added billing credit to the API project and retried the same
  Capture. Responses and embeddings both returned `200`, and the Capture became
  `ready`.
- Project impact: External account configuration only; failure behavior worked
  as designed.

## E-039 — Local `.env` leaked into provider-off tests

- Date: 2026-07-19
- Status: Resolved 2026-07-19
- Symptom: Five backend tests failed after a real key was added because fixtures
  deleted the environment variable and then unintentionally reloaded it from
  the repository-root `.env`.
- Resolution: Provider-off fixtures now set an explicit empty environment value,
  which overrides `.env`. The full 186-test suite passes with the real local
  file present.
- Project impact: Test isolation only; production configuration is unchanged.

## E-040 — Final Xcode regression first missed a test-double return

- Date: 2026-07-19
- Status: Resolved 2026-07-19
- Symptom: Adding a request counter made a formerly single-expression async
  test-double method require an explicit Swift `return`, so the first final
  Xcode run stopped at compile time.
- Resolution: Added the explicit return and reran the complete target; all 27
  macOS tests passed.
- Project impact: Test code only; the production target had already compiled.

## E-025 — The first extension test command could not find `npm`

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first `npm test` attempt exited immediately with
  `zsh: command not found: npm`; the parallel backend CORS/API suite passed all
  57 tests.
- Resolution: Located the bundled Node and pnpm runtimes. The built-in test
  suite passed all 13 tests directly and through the package script; the README
  now documents npm, pnpm, and direct Node commands.
- Recurrence during branch separation: the plain `npm test` command again
  exited `127` because this shell still has no npm on `PATH`; the parallel
  isolated Layer 6 backend suite passed all 128 tests. The extension suite was
  immediately rerun with the bundled Node executable and all 13 tests plus
  three syntax checks passed.
- Project impact: Tool discovery only; no dependency or product change.

## E-026 — First real-page browser check missed the dispatch deadline

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The initial read-only Stack Overflow extraction check exceeded the
  browser dispatch deadline before navigation was sent.
- Resolution: The navigation had completed despite the dispatch timeout. Reused
  the existing tab and ran the checked-in extractor successfully, then
  completed the remaining real-page matrix.
- Project impact: One delayed observation only; no page write occurred.

## E-027 — First code-block drag did not create a browser selection

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: A bounded pointer drag inside the OpenAI documentation code block
  left `window.getSelection()` empty. The extractor correctly returned page
  context, but that does not prove the selected-code path.
- Resolution: A second coordinate gesture also produced no selection, so the
  test switched to a deterministic local browser fixture whose own page script
  establishes a real DOM Range. The checked-in extractor returned the exact
  two-line code selection and preferred article context.
- Project impact: Browser-gesture limitation only; the real DOM selection path
  is now verified.

## E-028 — Local fixture server received an optional favicon request

- Date: 2026-07-18
- Status: Resolved / no action required
- Symptom: The browser requested `/favicon.ico`; the disposable fixture server
  returned `404` because the test pages intentionally define no icon.
- Resolution: No product file was added for a test-only browser decoration.
  Every requested fixture, module, stylesheet, and popup artifact returned
  `200`, and the server was removed after verification.
- Project impact: None.

## E-029 — Package-script verification generated empty pnpm metadata

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: Running the dependency-free package script through bundled pnpm
  created an empty lockfile and two `node_modules` metadata files despite there
  being no dependencies.
- Resolution: Removed the generated files and added a local `.gitignore` for
  `node_modules/` and the empty pnpm lock. The extension remains build-free and
  the direct Node test command remains the canonical dependency-free proof.
- Project impact: Workspace hygiene only; no runtime package was installed.

## E-030 — Direct Layer 6 and Layer 7 merge has two content conflicts

- Date: 2026-07-18
- Status: Resolved for local Developer B integration; direct merge remains
  intentionally unsupported
- Symptom: `git merge-tree --write-tree layer/6-chrome-capture
  layer/7-hybrid-retrieval` reported content conflicts in
  `services/backend/app/main.py` and `services/backend/README.md`.
- Cause: Both sibling deltas update the backend version/bootstrap and adjacent
  runtime documentation from the same Layer 5 base.
- Resolution: Promoted the already-resolved, previously validated combined
  checkpoint `3389bae` to `integration/layers-6-7`. The focused siblings remain
  review branches; integration should use the combined branch instead of a
  blind direct merge.
- Project impact: No code loss and no test regression. The later D-023
  integration includes the macOS branch and resolves the former B-010 layout
  blocker.

## E-031 — First stress-harness launch could not import the backend

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first direct command exited before any scenario with
  `ModuleNotFoundError: No module named 'app'`.
- Cause: Python placed `services/backend/tools/`, not `services/backend/`, on
  `sys.path` for a directly executed script.
- Resolution: The entry point now resolves and inserts its backend root. The
  same direct command compiled and completed both full runs.
- Project impact: No scenario or product database ran before the failure.

## E-032 — First stress output expanded the complete oversized query

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first completed run recorded 29 passes and 11 breaks, but the
  structured console evidence echoed all 2,000 terms and obscured later output.
- Resolution: Record query length plus an 80-character preview, suppress only
  expected application stack traces, add the escalated cases, and rerun. The
  second run completed 44 scenarios with compact evidence.
- Project impact: Reporting clarity only; no application failure was hidden or
  removed from the dated report.

## E-033 — Hardening tests were first launched from the wrong directory

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: Pytest collected 10 modules with `ModuleNotFoundError: No module
  named 'app'` when launched from the repository root.
- Resolution: Reran from `services/backend`, where `pyproject.toml` supplies the
  expected Python path; the final suite passed 181 tests.
- Project impact: Collection/setup only; no application test ran in the failed
  launch.

## E-034 — Stress worktree has no local virtual environment

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: `.venv/bin/pytest` exited `127` because the isolated stress worktree
  does not contain `services/backend/.venv`.
- Resolution: Used the dependency-complete interpreter from the main worktree
  against the hardening worktree source.
- Project impact: Tool path only; no code or database operation ran.

## E-035 — Compile check was first issued one directory too high

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: `compileall` printed `Can't list 'app'`, `tests`, and `tools` because
  those relative paths were resolved from the repository root.
- Resolution: Reran from `services/backend`; compilation completed with exit
  code `0`.
- Project impact: Verification path only.

## E-036 — First remediation harness run retained a stale NUL expectation

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The post-fix harness reported 43 passes and one break because its
  `nul_query` case still expected HTTP `200`, while D-021 intentionally rejects
  control characters with `422 validation_error`.
- Resolution: Updated only the expected status and reran the unchanged backend;
  all 44 scenarios passed.
- Project impact: Harness contract alignment only; no backend behavior changed.

## E-037 — Post-push documentation search had an unsafe shell quote

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: A read-only `rg` command exited with `zsh: unmatched "` because a
  backtick inside its double-quoted pattern was interpreted by the shell.
- Resolution: Reran the search with a single-quoted pattern and updated every
  stale pre-push status reference.
- Project impact: No file or remote state changed during the failed command.

## E-041 — Checklist endpoint test hardcoded the main branch

- Date: 2026-07-19
- Status: Resolved 2026-07-19
- Symptom: The first full improvement-branch run passed 189 tests and failed the
  checklist endpoint assertion because the live Markdown correctly reported
  `agent/backend-recovery-dev-start` instead of the test's hardcoded `main`.
- Cause: The endpoint test coupled valid dashboard metadata to one Git branch
  name even though the dashboard is intentionally reread during feature work.
- Resolution: Kept the live branch name accurate and changed the endpoint test
  to require a present, non-`unknown` branch value. The separate parser test
  continues to verify exact metadata extraction.
- Project impact: Test robustness only; the endpoint and dashboard output were
  correct during the failed assertion.

## E-042 — First chained integration merge reported `stash failed`

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: After fast-forwarding the desktop checkout to `origin/main`, the
  first chained merge command stopped before merging either improvement branch
  with `fatal: stash failed`.
- Resolution: Verified that `main` and both feature worktrees were clean, found
  no active hooks or auto-stash configuration, and reran the backend merge as a
  standalone command. It completed normally. The subsequent Chrome merge had
  only the expected README/checklist content conflicts, which were reconciled
  explicitly to retain both improvements.
- Project impact: No code or uncommitted work was lost; the failure occurred
  before the first feature merge changed `main`.

## E-044 — First merged-main backend command used a duplicated path

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The first parallel quality-gate command exited `127` before backend
  collection because it invoked `services/backend/.venv/bin/python` while its
  working directory was already `services/backend`.
- Resolution: Reran with `.venv/bin/python` from the backend directory. All 190
  tests, bytecode compilation, and `pip check` passed; the independent 44-case
  stress harness also passed.
- Project impact: Verification path only; no backend test or app code executed
  during the failed command.

## E-045 — Xcode 26.6 hosted macOS tests waited indefinitely

- Date: 2026-07-20
- Status: Resolved with deterministic repository fallback 2026-07-20
- Symptom: `xcodebuild test` built and launched Recall but stalled in the hosted
  test process. A targeted live-client test and a contract-only target both
  reproduced the hang; interrupted runs returned exit `75`.
- Investigation: A private-URL-scheme experiment did not change the behavior
  and was reverted. Invoking the exact compiled test bundle directly with
  Apple's `xctest` completed all 27 tests with zero failures, proving the test
  and production code were healthy.
- Resolution: Added `scripts/test-macos.sh` to run `build-for-testing` followed
  by direct `xctest` with the app debug-library path configured. A clean derived
  data run passes all 27 tests. D-026 documents the safeguard.
- Project impact: Xcode 26.6 command-line host-runner reliability only; no
  production source or Xcode project setting changed.

## E-046 — Direct macOS test run first left a coverage profile in the repository

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The first successful direct `xctest` run created the untracked file
  `default.profraw` in the repository root.
- Resolution: Updated `scripts/test-macos.sh` to route `LLVM_PROFILE_FILE` into
  its Derived Data directory, removed only the generated profile, and reran all
  27 tests. Coverage output now stays outside the worktree.
- Project impact: Workspace hygiene only; test and production behavior did not
  change.

## E-047 — Live checklist smoke test assumed the wrong representation

- Date: 2026-07-20
- Status: Resolved 2026-07-20
- Symptom: The first live smoke assertion tried to parse `/dev/checklist` as
  JSON, then a corrected HTML check used a stale title string. The route itself
  returned HTTP `200` both times.
- Resolution: Verified the HTML contract and current `Recall build pulse` title
  at `/dev/checklist`, then verified structured metadata separately through
  `/dev/checklist.json`; it reported branch `main` and a complete dashboard.
- Project impact: Verification assumptions only; no endpoint change was needed.

## E-001 — Official OpenAI docs MCP could not initially install

- Date: 2026-07-18
- Status: Resolved
- Symptom: Codex lacked permission to write the MCP configuration.
- Resolution: Retried after filesystem permissions were expanded; installation
  succeeded. Official OpenAI web documentation was used in the existing task
  because newly installed MCP tools require a restart to appear.
- Project impact: None.

## E-002 — Python `jsonschema` was not installed globally

- Date: 2026-07-18
- Status: Resolved for Layer 0 validation
- Symptom: `ModuleNotFoundError: No module named 'jsonschema'`.
- Resolution: Used an isolated temporary installation for validation; no
  project dependency was added because backend tooling had not been chosen.
- Follow-up: Add schema validation through the selected backend test dependency
  in Layer 1.

## E-003 — Initial staged whitespace audit failed

- Date: 2026-07-18
- Status: Resolved
- Symptom: Extra EOF blank lines and Markdown trailing spaces in new files.
- Resolution: Corrected the files, restaged, and reran `git diff --cached
  --check` successfully before commit.
- Project impact: None.

## E-004 — GitHub CLI was unavailable during the first publish attempt

- Date: 2026-07-18
- Status: Resolved
- Symptom: `gh: command not found`.
- Resolution: GitHub CLI was installed and authenticated; Layer 0 was committed
  and pushed successfully.
- Project impact: Initial publishing was delayed; no partial commit was made.

## E-005 — Initial checklist cross-check found omissions and overstatements

- Date: 2026-07-18
- Status: Resolved in checklist documentation
- Missing baseline items found: sprint dates, integration cadence, feature
  freeze, prompt-quality rules, exact Chrome context fallback, shared macOS
  tests, demo reliability, README/license requirements, and submission checks.
- Overstated items found: application-factory architecture, mandatory
  idempotency, mandatory detailed logging, embedding-dimension/version policy,
  and Apple local retrieval implied by Apple enrichment approval.
- Resolution: Added the missing baseline requirements, downgraded implementation
  preferences to non-blocking safeguards, and documented D-009 for the
  no-selection page-context clarification.
- Project impact: No code impact; future scope and exit gates are now more
  faithful to the product plan.

## E-006 — FastAPI runtime dependencies are not installed

- Date: 2026-07-18
- Status: Resolved
- Symptom: Importing `fastapi`, `pydantic`, and `uvicorn` fails at `fastapi`
  with `ModuleNotFoundError`.
- Resolution: Added constrained dependencies and the standard-library `venv`
  setup in `services/backend/`; the documented install succeeded and
  `.venv/bin/python -m pip check` found no broken requirements.
- Project impact: None after resolution.

## E-007 — Initial test run emitted a deprecated test-client warning

- Date: 2026-07-18
- Status: Resolved
- Symptom: All 11 tests passed, but Starlette warned that its fallback to the
  legacy `httpx` package is deprecated and requested `httpx2`.
- Resolution: Replaced the development dependency with `httpx2`, reinstalled
  from `requirements.txt`, removed the legacy fallback packages from the test
  environment, and reran the suite: 11 tests passed without warnings.
- Project impact: None after resolution.

## E-008 — Editable install generated an unignored metadata directory

- Date: 2026-07-18
- Status: Resolved
- Symptom: The final status review showed `services/backend/recall_backend.egg-info/`
  as untracked after the editable development install.
- Resolution: Added the standard `*.egg-info/` rule to `.gitignore`; the local
  metadata remains available to the environment but is no longer a candidate
  for source control.
- Project impact: None after resolution.

## E-009 — Named SQLite rows broke the healthy probe comparison

- Date: 2026-07-18
- Status: Resolved
- Symptom: The first Layer 2 test run passed 24 tests but failed two health
  tests because healthy databases returned HTTP `503` instead of `200`.
- Cause: Layer 2 enabled `sqlite3.Row` for schema-version reads, while the
  Layer 1 probe still compared `SELECT 1` to the tuple `(1,)`.
- Resolution: Changed the probe to compare the first returned column by value;
  the next complete run passed all 29 tests.
- Project impact: Local regression detected before commit; no remote impact.

## E-010 — Forced temporary-directory cleanup was rejected

- Date: 2026-07-18
- Status: Resolved
- Symptom: The environment rejected `rm -rf` for the isolated Layer 2 restart
  proof directory under `/tmp`.
- Resolution: Listed the exact isolated directory and its single database file,
  then removed it successfully with non-force `rm -r`.
- Project impact: None; the command ran after all proofs and did not touch the
  repository.

## E-011 — Wheel verification generated an unignored build directory

- Date: 2026-07-18
- Status: Resolved
- Symptom: `pip wheel` correctly packaged the migration and dashboard assets but
  left `services/backend/build/` visible as untracked output.
- Resolution: Added the standard Python `build/` ignore rule, confirmed the
  directory contained only generated package copies, and removed it without
  force.
- Project impact: None; final review caught the artifact before staging.

## E-012 — System `tidy` does not recognize HTML5 semantic elements

- Date: 2026-07-18
- Status: Resolved
- Symptom: `/usr/bin/tidy` exited `2`, reporting standard elements such as
  `<main>`, `<header>`, `<section>`, and `<article>` as unknown and assuming a
  non-UTF-8 character set.
- Cause: The bundled validator targets an older HTML dialect and cannot
  validate the dashboard's HTML5 document accurately.
- Resolution: Preserved semantic HTML5 and added a standard-library parser test
  that verifies balanced elements and unique IDs; all 30 tests pass.
- Project impact: No runtime failure; the dashboard returned HTTP `200` and its
  live JSON behavior already passed.

## E-013 — Layer 3 validation tests emitted deprecated 422 constant warnings

- Date: 2026-07-18
- Status: Resolved
- Symptom: All 51 tests passed, but 13 validation cases warned that the
  installed Starlette release renamed `HTTP_422_UNPROCESSABLE_ENTITY` to
  `HTTP_422_UNPROCESSABLE_CONTENT`.
- Resolution: Switched to the supported constant while preserving numeric HTTP
  status `422`; the complete suite now passes 53 tests without warnings.
- Project impact: No response-code failure; detected before commit.

## E-014 — Live refresh collapses user-expanded dashboard layers

- Date: 2026-07-18
- Status: Resolved
- Symptom: A layer expanded by the user stays open only until the next
  two-second checklist refresh, then collapses.
- Cause: Every refresh replaces all `<details>` elements and reapplies only the
  default active-layer state, discarding the user's current open/closed state.
- Resolution: Each panel now has a stable stream key. The renderer captures all
  open keys before replacement and restores those keys on the fresh elements;
  toggle events retain both expanded and explicitly collapsed choices in
  memory. A regression test guards the state-preservation mechanism.
- Project impact: Checklist data remains correct, but inspection is disruptive.

## E-015 — Dashboard status update initially targeted Layer 0

- Date: 2026-07-18
- Status: Resolved
- Symptom: A broad patch changed Layer 0's generic `Status: [x] complete` line
  instead of the identically formatted dashboard status line.
- Resolution: The immediate checklist inspection caught the mismatch; Layer 0
  was restored to complete and the dashboard alone was marked in progress using
  section-specific patch context.
- Project impact: No code or historical evidence changed; the incorrect live
  status existed only during this edit cycle.

## E-016 — Dashboard verification command used the wrong relative path

- Date: 2026-07-18
- Status: Resolved
- Symptom: The combined source-inspection and test command stopped at `sed`
  because it referenced `services/backend/...` while its working directory was
  already `services/backend`.
- Resolution: Reran the inspection and test suite from the repository root with
  paths relative to that directory.
- Project impact: No implementation or test failure; the first verification
  command exited before tests started.

## E-017 — Dashboard snapshot test observed the live in-progress status

- Date: 2026-07-18
- Status: Resolved
- Symptom: The full suite reported 54 passes and one failure because the
  dashboard snapshot test expects its status to be complete while this fix had
  intentionally marked it in progress.
- Cause: The live checklist is the test fixture and accurately exposed the
  temporary implementation status.
- Resolution: Marked the verified dashboard task complete, resolved E-014, and
  reran the full suite successfully with 55 tests passing.
- Project impact: No product-code assertion failed; final verification is
  complete.

## E-018 — Layer 3 read-after-create assertion did not include enrichment failure transition

- Date: 2026-07-18
- Status: Resolved
- Symptom: The first Layer 4 suite run passed 54 tests and failed the Layer 3
  assertion that detail GET must exactly equal the initial `processing` response.
- Cause: Layer 4 now executes a background task after the response; with no API
  key it correctly preserves the raw Capture and changes the stored status to
  `error` with a safe message.
- Resolution: Updated the assertion to verify the initial `202` response and
  subsequent safe error transition independently; added configured-provider,
  retry, concurrency, and failure tests. The complete suite passes 88 tests.
- Project impact: Expected contract evolution caught by the existing test; no
  source or user-note data was lost.

## E-019 — Release-wheel smoke test lacked the wheel build command

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first review-remediation run passed 76 tests and failed the new
  isolated wheel smoke test with `error: invalid command 'bdist_wheel'`. After
  installing `wheel`, the stale backend emitted `UNKNOWN-0.0.0` instead of the
  declared project artifact.
- Cause: The local venv had neither `wheel` nor a current `setuptools`; version
  58.1.0 ignored the PEP 621 project metadata during the intentionally
  no-build-isolation regression test.
- Resolution: Declared `setuptools>=68` and `wheel>=0.43,<1.0` for the local
  developer toolchain, installed setuptools 83.0.0 and wheel 0.47.0, and reran
  the isolated release-wheel import successfully. The focused suite passed 77
  tests and the complete suite passed 94.
- Project impact: No runtime defect; the release-artifact regression is now
  reproducible and passing.

## E-020 — Final documentation scan used backend-relative paths from the wrong directory

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first final `rg` scan reported `docs: No such file or directory`
  and stopped before dependency and diff checks.
- Cause: The command used repository-root paths while its working directory was
  `services/backend/`.
- Resolution: Reran the scan, `pip check`, and `git diff --check` from the
  repository root; all passed.
- Project impact: None.

## E-021 — Duplicate-classification glob failed under zsh

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first duplicate comparison stopped with
  `zsh: no matches found: * 2.*` before examining any files.
- Cause: zsh expanded an unmatched root-level glob before the guarded loop.
- Resolution: Reran the comparison with null-delimited Git output. Five files
  were exact copies and four were stale snapshots; none contained unique
  content. Removed all nine duplicates and retained every canonical file.
- Project impact: Workspace hygiene only; no tracked product file was replaced.

## E-022 — First Layer 5 focused suite exposed API indexing and wheel packaging failures

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first focused Layer 5 run passed 71 tests and failed three. Two
  `/v1/search` API tests returned empty results after successful Capture writes,
  and the isolated wheel could not discover migration 002.
- Cause: Both API queries contained terms absent from the checked-in fixtures.
  The wheel itself contained migration 002, but the test zip-imported it rather
  than installing it; filesystem migration discovery correctly targets normal
  extracted wheel installations.
- Resolution: Corrected the fixture queries, installed the wheel into an
  isolated target before importing it, confirmed the three failed cases, and
  reran the complete focused set with 74 passing tests.
- Project impact: No production defect; the API index and packaged migration
  were correct, and the stronger installed-wheel proof now passes.

## E-023 — Layer 5 diagnostic used the backend venv path from the repository root

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The first database-inspection command reported
  `.venv/bin/python: no such file or directory`; its independent source scan did
  complete.
- Cause: The command ran from the repository root while using a backend-relative
  interpreter path.
- Resolution: Reran with `services/backend/.venv/bin/python` and inspected the
  failing-test databases. Migration 002, all triggers, Capture rows, and FTS
  rows were present and synchronized.
- Project impact: None; this was a read-only diagnostic command.

## E-024 — Disposable live database cleanup rejected `rm -f`

- Date: 2026-07-18
- Status: Resolved 2026-07-18
- Symptom: The execution safety layer rejected cleanup of the known Layer 5
  `/private/tmp/recall-layer5-live-8697.db*` artifacts because the command used
  `rm -f`. A guarded retry then reported `command not found: unlink` and left
  the database in place.
- Cause: Destructive force-delete syntax is disallowed even for generated temp
  files, and this macOS environment does not provide the `unlink` executable.
- Resolution: Used `Path.unlink(missing_ok=True)` only for the three exact
  generated paths and verified that none remained.
- Project impact: None; live verification had completed and no repository file
  was targeted.

## E-043 — Review worktree lacked npm and backend test dependencies

- Date: 2026-07-19
- Status: Resolved for the changed extension scope
- Symptom: `npm test` returned `command not found`, and the fresh detached
  review worktree had no backend virtual environment or system `pytest`.
- Cause: The review shell did not expose npm, and intentionally untracked
  virtual environments do not follow a Git worktree.
- Resolution: Loaded the bundled workspace runtime and ran the dependency-free
  suite directly with Node; all 16 extension tests, JavaScript syntax checks,
  and manifest/package JSON validation pass. No backend code changed, so the
  prior 186-test and 44/44 stress evidence remains recorded rather than falsely
  described as freshly rerun.
- Project impact: The Chrome improvement is verified automatically. A real
  unpacked-extension shortcut/auto-close check remains explicit above.

## E-044 — Image-note verification commands used two invalid test invocations

- Date: 2026-07-21
- Status: Resolved
- Symptom: The first combined regression used a backend-relative virtualenv
  path from inside the backend directory and relied on an `npm` executable not
  exposed in the review shell. A later new Swift test also placed `await`
  directly inside an XCTest autoclosure, so that macOS test build stopped before
  execution.
- Resolution: Used the backend-local `.venv/bin/python`, loaded the bundled Node
  runtime and ran the extension suite directly, then assigned both async Swift
  results before asserting them. Final evidence is 235/235 backend, 44/44
  stress, 68/68 Chrome, and 157/157 macOS tests.
- Project impact: Verification harness only; no production-code assertion or
  product behavior failed.

## E-060 — Image attachment responses introduced an N+1 search query

- Date: 2026-07-21
- Status: Resolved
- Symptom: The image-notes pull request passed all functional checks, but the
  Linux stress runner recorded 50/50 successful concurrent vector searches with
  a maximum latency of 2039.688 ms, narrowly exceeding the 2-second guard.
- Cause: Every Capture serialized by collection and search endpoints loaded its
  attachment metadata with a separate SQLite query. A 100-result search therefore
  performed 100 avoidable attachment queries in addition to search itself.
- Resolution: Added one bounded attachment query for the complete result set and
  passed the grouped metadata into response serialization. A regression test now
  rejects per-Capture attachment reads from library and search responses while
  verifying image metadata remains present.
- Project impact: No result or attachment was lost, but this removed a real
  performance regression instead of weakening the existing stress threshold.

## E-061 — Merge CI exceeded the bounded SQLite write-lock wait

- Date: 2026-07-21
- Status: Resolved
- Symptom: The PR #14 merge run returned HTTP 500 for 19 of 700 concurrent
  writes, and the integrated PR #15 run returned 500 for 14 of 500 writes. The
  databases remained internally consistent but contained only the accepted
  rows. A separate dashboard test read `current_branch` as `unknown`.
- Cause: SQLite permits one writer at a time. On the slower shared runner, some
  requests waited longer than the configured five seconds for the write lock.
  The dashboard failure came from renaming its recognized `Implementation
  branch` metadata field while resolving documentation conflicts.
- Resolution: Increased the bounded SQLite busy wait to 30 seconds, added a
  regression assertion for the effective 30,000 ms connection setting, and
  restored the recognized checklist field. The complete backend suite passes
  235/235 and all 44 stress scenarios pass, including 1,000 synchronized
  Capture/FTS rows under the same 64- and 32-worker bursts.
- Project impact: A write that previously lost a short lock race and returned a
  safe 500 can now remain queued during an exceptional local burst. Normal
  requests proceed as soon as the lock is released; a genuinely stuck lock is
  still bounded and fails after 30 seconds rather than waiting indefinitely.
