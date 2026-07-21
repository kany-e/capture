# Recall current roadmap

Last updated: 2026-07-20

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
- D-027 screenshot-to-note OCR is implemented and live-verified with GPT and
  Apple Vision. Screenshot bytes remain transient and are not stored.
- D-028 CI runs backend, deterministic stress, Chrome-extension, and macOS jobs
  plus one aggregate **Required checks** result.
- D-029 opt-in inline selected-text capture passed its real unpacked-Chrome
  acceptance matrix and was merged through PR #8 at `71ec387`.
- The current `codex/inline-context-ui-fixes` branch implements D-030 browser
  context and long-detail-view hardening. Chrome temporarily omits surrounding
  context; existing stored context remains intact and is display-bounded in the
  macOS detail view.
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
2. **Browser capture reliability and privacy hardening — current.** D-030
   temporarily sends no `surrounding_context` from either Chrome entry point,
   keeps normalized selected text unshortened through the 12,000-character
   contract limit, explicitly warns before saving a longer prefix, separates
   the inline Unicode selection count from the note count, makes long selections
   scrollable, and
   keeps the action popup usable on shorter displays. Existing context is
   collapsed and display-bounded in macOS without altering stored data. The real
   Chrome toolbar, standalone production-script inline harness, rebuilt macOS
   app, and source review are complete; finish CI and merge evidence.
   Deterministic suites pass 68/68 for Chrome and 48/48 for macOS.
3. **Native global capture shortcut and menu-bar availability — next.** Add a
   configurable global screenshot shortcut that reuses the existing region
   selection and Quick Capture flow, and keep it available from the menu-bar app
   while the main window is closed. Add clipboard capture through the same
   shortcut infrastructure. The app must be running; launch-at-login is a
   separate opt-in improvement.
4. **Native Accessibility selection.** Read the focused app's selected text and
   bounds only after a user shortcut, then open capture UI near that selection.
   Keep clipboard capture as the compatibility fallback and avoid passive
   monitoring of every selection.
5. **App-managed local service lifecycle.** Define how a packaged Recall app
   starts, monitors, and stops the backend without assuming a repository checkout
   or terminal command. Keep this separate from browser native messaging.
6. **Image attachments.** Design explicit image persistence, limits, privacy,
   deletion, migrations, and detail UI before allowing an imported image to be
   saved as more than OCR-derived text.
7. **Menu-bar image drop.** After image semantics are decided, add a bounded
   drop target. A click-open drop zone may precede a custom AppKit status item
   that opens when an image is dragged directly over the icon.
8. **Release readiness.** Finish licensing, screenshots, demo materials,
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
  and exposes a keyboard-scrollable long-selection preview. The action popup is
  compact and internally scrollable.
- Existing stored context is collapsed by default in the native detail view.
  Expanding it renders at most 2,000 characters and 60 lines while preserving
  the complete database/model value for retrieval and AI.
- The extension suite passes 68/68 tests. The macOS suite adds five bounded
  context-projection tests and passes 48/48; detail collapse/expansion was
  verified in the rebuilt app against the problematic long record.

The verification backend intentionally had no AI provider configured. Its later
enrichment `error` did not invalidate the successful Capture: the persist-first
pipeline retained the original source and note.

### Native global screenshot capture

- The shortcut is configurable and registration failure is visible.
- Interactive screenshot selection does not block the app's main actor.
- Cancelling leaves no draft or temporary image behind.
- The existing GPT/on-device disclosure remains visible before extraction.
- Closing the main window does not prevent capture while Recall is still running.

## Deliberately deferred

- Browser-region screenshots are not part of the selected-text inline slice.
  The native D-027 path already handles arbitrary screen regions; a future
  browser-only crop must demonstrate distinct value such as reliable page
  metadata before it is prioritized.
- Passive system-wide selection monitoring is deferred because of privacy,
  Accessibility permission, and cross-application compatibility costs.
- A future image-drop first slice may reuse transient OCR and save only derived
  text. Persisting the image itself requires the separate attachment design
  above.

## Documentation authority

- This roadmap: current priorities and component ownership.
- `decisions.md`: accepted additions and architectural choices.
- `product-plan.md`: historical Build Week baseline and product principles.
- `developer-b-checklist.md`: detailed historical execution and validation log;
  its filename is retained because the backend checklist dashboard reads it.
