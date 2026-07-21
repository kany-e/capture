# Recall current roadmap

Last updated: 2026-07-21

Status: Active execution guide

This document tracks the product's current state and ordered next work. The
original Build Week scope remains in [`product-plan.md`](product-plan.md), while
accepted additions and contract changes remain in [`decisions.md`](decisions.md).
Historical Developer A/B labels describe how the first implementation was
split; they are no longer assignment gates.

## Current product snapshot

- `main` is the canonical runnable integration tree.
- The baseline macOS, Chrome, backend, persistence, enrichment, keyword search,
  semantic retrieval, and lifecycle flows are integrated.
- D-027 screenshot-to-text OCR is implemented and live-verified with GPT and
  Apple Vision. Its **Text note** screenshot bytes remain transient.
- D-028 CI runs backend, deterministic stress, Chrome-extension, and macOS jobs
  plus one aggregate **Required checks** result.
- D-029 opt-in inline selected-text capture passed its real unpacked-Chrome
  acceptance matrix and was merged through PR #8 at `71ec387`.
- D-030 browser context and long-detail-view hardening was merged through PR #9
  at `0c1083e`. Chrome temporarily omits surrounding context; existing stored
  context remains intact and is display-bounded in the macOS detail view.
- D-031 native global capture is merged through PR #10 at `0ab687b`. Its 68/68
  macOS tests and bounded real-UI checks pass.
- D-032 addresses the discovered Screen Recording identity failure: ad-hoc
  rebuilds receive build-specific designated requirements, so an enabled stale
  Recall entry may not authorize the current process. Stable local signing,
  app-specific reauthorization, and permission persistence across a rebuild are
  now live-verified; the macOS suite passes 70/70.
- D-033 corrects the Chrome action popup's viewport-relative self-sizing
  regression. Its explicit 344 × 510 root and internal scroller pass 68/68
  extension tests plus selected and metadata-only real-Chrome checks.
- D-034 implements explicit native Accessibility selection capture on
  `codex/native-accessibility-selection`. Its 108/108 macOS tests and the user's
  primary-path acceptance pass. WeChat's unsupported selected-text attribute
  motivated the separately gated D-035 compatibility fallback.
- D-035 extends the same draft PR with an off-by-default transactional clipboard
  compatibility mode for apps such as WeChat. It supports exact-control tickets
  and application-scoped tickets for custom-drawn apps. Its current host suite
  passes 149/149; B-016 user acceptance passed on 2026-07-21.
- D-036 starts the next capture-correctness slice. Plain text remains
  authoritative, while bounded HTML/RTF clipboard representations may restore
  line structure only when their ordered non-whitespace content is identical;
  recovered boundaries are projected onto the original plain characters.
  The existing text contract and database remain unchanged. The live Gemini
  clipboard payload restores verified HTML block boundaries from zero-newline
  plain text while retaining its TeX. The host suite passes 176/176, and
  Selection Capture remains at D-034/D-035.
- D-037 implements one-image notes: local original storage, an independent user
  note, background OCR/visual indexing within a global privacy master switch,
  ordinary search reuse, image display, and whole-Capture deletion. The user
  verified real-app image notes with AI both disabled and enabled; automated
  backend/macOS verification and file-deletion coverage pass.
- The macOS app and Chrome extension are separate clients of the loopback
  FastAPI service. The app does not yet package or start that service.

## Component ownership

| Component | Primary paths | Responsibility |
| --- | --- | --- |
| Native capture and experience | `apps/macos/` | macOS windows, menu bar, clipboard, Accessibility, screenshot capture, and native interaction |
| Browser capture | `apps/chrome-extension/` | Page selection, inline browser UI, browser permissions, page metadata, and localhost delivery |
| Memory pipeline | `services/backend/`, `contracts/` | API, persistence, OCR boundary, enrichment, embeddings, FTS, hybrid retrieval, and shared contracts |
| Product and release | `README.md`, `docs/` | Cross-component behavior, privacy, validation evidence, demo, packaging, and release readiness |

Changes crossing these boundaries require review of every affected component,
not approval from a particular historical developer role.

## Ordered priorities

1. **Brand assets — complete on `main`.** Use the supplied AppIcon
   variants in the macOS asset catalog and the supplied Chrome sizes in the
   extension manifest. Keep the color app icon separate from a monochrome
   menu-bar template image.
2. **Browser capture reliability and privacy hardening — complete on `main`.** D-030
   temporarily sends no `surrounding_context` from either Chrome entry point,
   keeps normalized selected text unshortened through the 12,000-character
   contract limit, explicitly warns before saving a longer prefix, separates
   the inline Unicode selection count from the note count, makes long selections
   scrollable, and
   keeps the action popup usable on shorter displays. D-033 removes the
   viewport-relative sizing loop that later collapsed the real Chrome action
   popup, using an explicit 344 × 510 root with an internal scroller. Existing
   context is
   collapsed and display-bounded in macOS without altering stored data. The real
   Chrome toolbar, standalone production-script inline harness, rebuilt macOS
   app, and source review are complete. PR #9 passed all required checks and
   merged at `0c1083e`. Deterministic suites pass 68/68 for Chrome and 48/48 for
   the D-030 macOS checkpoint.
3. **Native global capture and stable Screen Recording identity — complete and
   live-verified.** D-031 registers
   configurable global screenshot and clipboard shortcuts through Carbon
   without Accessibility or Input Monitoring permission. A normal Dock app and
   its existing menu-bar extra share one application-level coordinator, so
   capture is designed to remain available after the main window closes.
   Transactional registration, draft preservation, asynchronous screenshot
   waiting/PNG reads, cancellation, and temporary-file cleanup are implemented.
   Twenty new tests bring the D-031 host-verified macOS suite to 68/68. D-032
   adds portable signing configuration, a gitignored per-developer signing
   override, verification of a signer-based designated requirement, and a clear
   diagnostic for temporary signatures. The app-specific reset,
   reauthorization, same-signer rebuild, system overlay, and cancellation now
   pass, as do all 70 macOS tests. The real-device interaction gate also passes:
   with Recall's main window closed and another app focused, the physical
   screenshot shortcut completed a non-empty region, and the clipboard shortcut
   opened Capture after text was copied. The app must be running; launch at
   login remains a separate opt-in improvement.
4. **Native Accessibility selection — implemented, compatibility fallback in
   validation.** D-034 adds configurable `Option+Shift+Command+S`. Only after
   that explicit action, Recall reads the focused external app's selected text
   and best-effort bounds off the main actor, rejects self/secure/protected/
   empty/oversized input, and opens the existing review UI near the selection.
   Bounds stay transient and the reviewed draft uses the existing clipboard-text
   contract with no surrounding context. Existing two-action shortcut settings
   migrate safely, including an external conflict fallback that preserves the
   old actions. The original 108/108 host suite passes. D-035 adds a separately
   persisted, off-by-default Clipboard Compatibility Mode. A selected-text
   failure creates a ticket for the exact frontmost PID and, when available,
   focused AX element. Recall revalidates that scope before two Copy
   attempts, accepts only matching consecutive results, and then performs a
   best-effort restore. macOS has no writer identity or atomic restore, so the
   UI and documentation disclose residual writer and delayed-Copy races. The
   expanded host suite passes 149/149. B-016 closed after the user reported no
   issue in final WeChat testing and authorized merge. Rich clipboard formats,
   password fields, races, and screen-edge cases remain release regression
   coverage.
5. **Structured-text capture fidelity — implemented; real-source acceptance
   pending.** Preserve plain non-whitespace content and remaining whitespace
   while recovering useful paragraph and line boundaries from safe, equivalent
   HTML/RTF clipboard representations in explicit Clipboard Capture. Do not
   change Selection Capture or storage until a later design proves that source
   markup is necessary.
6. **Image attachments — implemented and primary flow accepted.** D-037 adds a
   normalized attachment table and application-owned file storage rather than
   SQLite blobs. A screenshot draft chooses **Text note** or **Image note**; the
   latter saves one bounded PNG/JPEG plus an independent note. AI analysis has
   a persistent off-by-default master switch and a per-image opt-out. Background
   analysis writes
   OCR and visual meaning into the existing searchable derived fields without
   replacing the original. Library thumbnails, detail display, retry, and
   deletion are integrated. AI-disabled and AI-enabled image saves passed
   real-app acceptance. Keep visual-concept retrieval, restart, retry, and
   physical file deletion in release regression coverage.
7. **App-managed local service lifecycle.** Define how a packaged Recall app
   starts, monitors, and stops the backend without assuming a repository checkout
   or terminal command. Keep this separate from browser native messaging.
8. **Menu-bar image drop.** After image semantics are decided, add a bounded
   drop target. A click-open drop zone may precede a custom AppKit status item
   that opens when an image is dragged directly over the icon.
9. **Release readiness.** Finish licensing, screenshots, demo materials,
   packaging/notarization decisions, a stable tag, and clean-machine setup proof.

## Later product polish

- Reintroduce browser surrounding context only with a Range-centered extractor
  that excludes navigation/hidden regions and enforces both character and
  line/block limits. Falling back to no context is preferable to sending a
  broad `main` or `body` container. The backend's 20,000-character contract
  capability is not the target browser extraction size.
- Make semantic retrieval visible in the macOS results, for example by showing
  when a Capture matched by meaning rather than only by literal text.
- Group the library timeline into useful recent-date sections without changing
  the storage contract.
- Make locality and provider state legible: stored locally, OpenAI enrichment
  when configured, and keyword retrieval available without it.
- Reuse semantic retrieval to show a small related-memories strip after the
  primary capture and release paths are stable.
- Keep the demo script synchronized with the implemented Chrome → enrichment →
  natural-language retrieval flow.

## Near-term acceptance gates

### Inline browser capture — merged baseline and current hardening

- Website access is optional, explicit, revocable, and off by default.
- Merely selecting text stores and transmits nothing.
- The page does not shift, lose focus, or lose its normal keyboard behavior.
- One logical save attempt freezes its source, note, timestamp, and client ID
  across ambiguous retries.
- Toolbar capture remains a working fallback.
- Automated coverage includes Unicode notes, rapid activation, permission races,
  retry/error dismissal, current-tab injection, BFCache suspension, and a
  save-time permission gate.
- A real unpacked-Chrome run proved that enabling on an already-open page needs
  no refresh and that selected source plus a Chinese/emoji note persist exactly.
- The same run proved offline retry, normal page Escape behavior, ignored
  editable targets, immediate composer cleanup on revocation, a disabled real
  BFCache return, toolbar capture after revocation, and exact card display in
  the macOS app. PR #8 merged this D-029 baseline at `71ec387`.
- D-030 makes both current Chrome entry points send no surrounding context.
  Selection/title/URL/note follow their established normalization and limits; a
  longer selection is visibly limited to its first 12,000 characters, and a
  no-selection toolbar capture relies on title/URL/note as allowed by D-009.
- Inline UI shows a Unicode-aware selection count independent of the note count
  and exposes a keyboard-scrollable long-selection preview. Under D-033, the
  action popup has a deterministic 344 × 510 root and an internally scrollable
  shell; real Chrome verifies both selected and metadata-only layouts.
- Existing stored context is collapsed by default in the native detail view.
  Expanding it renders at most 2,000 characters and 60 lines while preserving
  the complete database/model value for retrieval and AI.
- The extension suite passes 68/68 tests. The macOS suite adds five bounded
  context-projection tests and passes 48/48; detail collapse/expansion was
  verified in the rebuilt app against the problematic long record.

The verification backend intentionally had no AI provider configured. Its later
enrichment `error` did not invalidate the successful Capture: the persist-first
pipeline retained the original source and note.

### Native global capture — complete and live-verified

- Recall remains a normal Dock app with its existing `MenuBarExtra`; it must be
  running, but the main window may be closed.
- Carbon `RegisterEventHotKey` supplies screenshot
  `Option+Shift+Command+4` and clipboard `Option+Shift+Command+C` defaults
  without Accessibility or Input Monitoring permission.
- Settings accepts A–Z and 0–9 plus Command, Option, Control, and Shift; each
  action requires at least two modifiers, and the actions cannot share one
  shortcut. Either can be disabled, and both can be restored to defaults.
- A configuration change replaces registrations transactionally. Failure rolls
  back to the prior working set and remains visible in Settings, the menu, and
  the menu-bar status icon.
- Main-window, menu-bar, and hotkey entry points converge on the app-level
  `GlobalCaptureCoordinator`; a presentation host in the `MenuBarExtra` label
  opens the shared Quick Capture window independently of the main-window scene.
- Interactive screenshot process waiting and PNG reading are asynchronous.
  Task cancellation terminates pending work, app termination requests that
  cancellation, and completed success, cancellation, and failure paths remove
  the random temporary PNG.
- Existing drafts are not overwritten. Rapid repeated screenshot triggers start
  only one selector, while another trigger against an open draft re-presents it
  with an explanatory notice.
- Screenshot bytes remain transient, and the existing GPT/cloud versus Apple
  Vision/on-device disclosure is unchanged. D-031 adds no API, schema, backend,
  extension, database, or image-persistence change.
- All 70 D-032 macOS tests pass on the host, including the D-031 shortcut,
  coordinator, draft-safety, and asynchronous screenshot coverage plus the new
  signing-identity diagnostics.
- Real UI checks confirmed the default settings, a persisted change to
  `Option+Shift+Command+5`, restart persistence, restore-defaults, active Carbon
  registration, an exact 32-character clipboard Quick Capture, repeated-trigger
  draft preservation, and a responsive collapsed 19,144-character context
  record. The earlier ad-hoc test build showed the explicit Screen Recording
  error even while System Settings retained an enabled Recall entry. Inspection
  found no Team ID and a build-specific CDHash-only designated requirement;
  this is the D-032 identity failure, not evidence that the user omitted the
  permission.
- D-032 keeps the repository portable: the tracked configuration has an ad-hoc
  fallback, while each developer may supply an ignored local Apple Development
  Team ID. No machine Team ID is committed, and no Screen Recording entitlement
  is added. `CODE_SIGNING_ALLOWED=NO` remains automation-only and cannot satisfy
  this gate.
- Live verification quit all Recall copies, reset only the app-specific TCC
  record, authorized the stable build, and chose **Quit & Reopen**. A same-signer
  version-2 rebuild changed CDHash from `143035…` to `5a1b00…` while retaining
  the Team ID and signer-based requirement. The rebuilt process launched
  `/usr/sbin/screencapture`, displayed the system overlay, and cancelled with
  Escape without a permission error.
- B-014 is closed. From another app with Recall's main window closed, the
  physical `Option+Shift+Command+4` shortcut completed a non-empty region.
  After copying text, `Option+Shift+Command+C` opened Capture as expected.

## Deliberately deferred

- Browser-region screenshots are not part of the selected-text inline slice.
  The native D-027 path already handles arbitrary screen regions; a future
  browser-only crop must demonstrate distinct value such as reliable page
  metadata before it is prioritized.
- The Chrome-like automatic native selection pill is deferred to a separate
  opt-in slice after D-034 compatibility evidence. It should observe only the
  current foreground app, reject secure content, keep candidates in memory,
  debounce and deduplicate AX notifications, and use a non-activating pill;
  explicit Capture Selection remains the reliable fallback.
- Menu-bar image drop remains deferred until the signed D-037 screenshot-image
  flow is accepted. It should reuse the same one-image contract instead of
  inventing another persistence route.

## Documentation authority

- This roadmap: current priorities and component ownership.
- `decisions.md`: accepted additions and architectural choices.
- `product-plan.md`: historical Build Week baseline and product principles.
- `developer-b-checklist.md`: detailed historical execution and validation log;
  its filename is retained because the backend checklist dashboard reads it.
