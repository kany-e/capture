# Browser inline capture development record

Date: 2026-07-20

Branch: `agent/browser-inline-capture`

Owner: Developer B

Decision: D-028

## Improvement

When a user finishes selecting ordinary webpage text, REcall offers a small,
temporary **Add to REcall** action beside the selection. Activating it opens a
compact comment composer. The source text, bounded page context, title, URL,
and optional personal comment enter the existing Capture pipeline only after
the user chooses **Save Memory**.

This addition complements the toolbar popup and keyboard shortcut. It does not
create a second notes system, change the backend schema, or start the separately
scoped browser-region screenshot phase.

## Phase 1 — interaction and privacy contract

Status: Complete in commit `d0fa028`

Phase 1 converted the initial feature idea into an implementation boundary:

- selected-text and future browser-region screenshot work became independent
  phases with separate merge gates;
- pill, composer, focus, placement, dismissal, keyboard, feedback, and retry
  behavior were specified before runtime work;
- optional website access and no-transmission-before-save were made explicit;
- unsupported page types and Chrome's inability to observe arbitrary macOS
  screenshots were documented;
- Developer B owns browser runtime work, while Apple Vision and native macOS
  screenshot UI remain native-app responsibilities; and
- existing Capture, OCR, idempotency, storage, enrichment, and retrieval
  contracts must be reused.

The accepted contract is
[`browser-inline-capture-spec.md`](browser-inline-capture-spec.md).

## Phase 2 — selected-text runtime

Status: Implemented and fixture-verified; B-014 manual Chrome gate open

### Permission lifecycle

The extension keeps its required `activeTab`, `scripting`, and `storage`
permissions. Broad HTTP and HTTPS access is optional and requested only when
the user enables **Show Add to REcall when I select text** in the popup.

Granting access dynamically registers the isolated inline content scripts.
Revoking access unregisters them and sends a disable message to open tabs so
existing controls disappear immediately. Toolbar and keyboard capture remain
available when inline capture is off.

### Page interaction

After a completed eligible selection, the content script snapshots normalized
text and bounded context and renders a fixed Shadow DOM overlay. It does not
alter document flow or focus a control. The action dismisses on timeout,
selection change, scroll, outside click, Escape, or tab blur.

Only activating the action opens the comment composer and moves focus to the
optional note. Positioning prefers space beside the selection and falls back
above or below while clamping to the viewport. Editable controls, Chrome
internal pages, built-in PDFs, cross-origin frames, and canvas/virtual text are
outside Phase 2 support.

### Delivery and failure behavior

Inline, toolbar, and keyboard saves now share one extension service-worker
coordinator. The coordinator validates runtime messages, reconstructs the
existing Capture request, and maps validation, localhost, API, and unexpected
failures to safe UI responses.

One attempt freezes its selected source, context, comment, timestamp, and
`client_capture_id`. **Try again** therefore resends the same logical Capture
instead of creating a silently different one after an ambiguous response. AI
enrichment is not promised by the save confirmation: the raw source and note
are safely stored first by the existing backend lifecycle.

### Privacy boundary

Selection and page context remain in the tab until **Save Memory**. The inline
path does not write selected source text to extension storage or send it to the
backend merely because a selection exists. Page text is assigned as text, never
interpreted as extension HTML. No backend, SQLite, enrichment, or search schema
was added or changed for this phase.

## Verification evidence

- 30 dependency-free Node extension tests pass.
- Every checked-in JavaScript file passes `node --check`.
- `manifest.json` and `package.json` parse and share version `0.3.0`.
- `git diff --check` passes.
- The browser fixture completes selection → action → comment → save
  confirmation → automatic dismissal.
- Article bounds are exactly unchanged before and after displaying the overlay,
  providing fixture evidence of no layout shift.
- The toolbar fixture still loads page context, accepts a note, uses the shared
  coordinator, and displays the safe save confirmation.

The fixture initially failed because it was served from `tests/fixtures`, which
made `/src/...` script requests return 404. Restarting from the extension root
resolved the harness error; this is recorded as E-055.

## Remaining gate

B-014 is open. The available in-app browser can validate local page behavior
but cannot install an unpacked Chrome extension. Before Phase 2 is described as
fully demo-verified or merged under D-028, run this real-browser matrix:

1. Load `apps/chrome-extension/` unpacked in Chrome.
2. Enable inline capture and approve optional website access.
3. Select text, add a comment, and save to the live localhost backend.
4. Confirm the macOS card preserves source and personal note separately.
5. Disable inline capture and confirm the control disappears from an open tab.
6. Confirm toolbar and keyboard capture still work after revocation.

Phase 3 browser-region screenshot capture has not started. It remains a
separate, independently gated improvement and must not destabilize this
selected-text path.
