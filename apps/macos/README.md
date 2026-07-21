# Recall for macOS

This directory contains Recall's SwiftUI/AppKit client. It talks to the
loopback backend at `http://127.0.0.1:8765`; normal runs do not use an in-process
database or mock API client.

The macOS client, hardened backend, and Chrome extension now live in the same
integration tree. The current D-034 branch passes all 108 Accessibility,
contract, networking, Vision, global-shortcut, lifecycle, validation,
idempotency, store, window-placement, and code-signing identity tests.

## Requirements

- Xcode 26.x. The project was previously built with Xcode 26.2.
- macOS 14.0 or later.
- Python 3.10 or later and backend dependencies installed as described in
  [`services/backend/README.md`](../../services/backend/README.md).
- XcodeGen 2.45 or later only when regenerating the project. The checked-in
  `Recall.xcodeproj` opens without XcodeGen.
- An Apple Development signing identity for interactive screenshot-permission
  acceptance. Unsigned and ad-hoc builds remain sufficient for deterministic
  automation that does not exercise macOS privacy authorization.

## Configure stable local signing

macOS Screen Recording authorization is associated with the app's code-signing
identity, not only its display name or bundle identifier. An ad-hoc Debug build
has a build-specific designated requirement, so System Settings can show an old
**Recall** entry as enabled while a newly rebuilt process still fails the
permission preflight.

Before interactive screenshot testing, create the ignored local override from
the checked-in example:

```bash
cp -n apps/macos/Config/Signing.local.xcconfig.example \
  apps/macos/Config/Signing.local.xcconfig
```

Replace `YOUR_TEAM_ID` in the local file with the actual Team ID for the Apple
Development certificate or team selected in Xcode. Use the certificate subject
organizational-unit value or the Team ID shown by the Apple Developer account;
do not assume a parenthesized certificate nickname is the Team ID. Never commit
the local file or place a personal Team ID in `project.yml`.

`Config/Signing.xcconfig` is the portable project default. It allows an ad-hoc
fallback when no developer identity is available and optionally includes the
ignored `Signing.local.xcconfig`. XcodeGen preserves this arrangement because
`project.yml`, not the generated project file, declares the configuration.

## Run the app

Install the backend once from the repository root:

```bash
cd services/backend
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

Check `python3 --version` first. On Apple Silicon with Homebrew,
`/opt/homebrew/bin/python3` is a typical compatible interpreter when Apple's
system Python is too old.

Keep the backend running in its own terminal:

```bash
cd services/backend
.venv/bin/python -m app
```

Confirm the local service is ready:

```bash
curl --fail http://127.0.0.1:8765/health
```

No OpenAI key is required for storage and keyword retrieval. A healthy
provider-off response reports `"openai_configured": false`. Real enrichment,
embedding, and semantic-search integration has also been verified with a key
stored only in the untracked root `.env`.

Open `apps/macos/Recall.xcodeproj` in Xcode, select the shared **Recall** scheme
and **My Mac**, then run with **Product > Run** (`Command-R`). The app shows a
green **Connected** indicator after it reaches a healthy local service. For
Screen Recording acceptance, use this stably signed run after configuring the
local override above.

The equivalent stable command-line build is:

```bash
xcodebuild \
  -project apps/macos/Recall.xcodeproj \
  -scheme Recall \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/recall-signed-derived-data \
  build

./scripts/verify-macos-signing.sh \
  /tmp/recall-signed-derived-data/Build/Products/Debug/Recall.app
```

The verifier requires a valid app signature, a non-empty `TeamIdentifier`, and
a signer-based designated requirement instead of a build-specific CDHash-only
requirement. It rejects the preceding ad-hoc build as intended.

The `/tmp/recall-signed-derived-data` output is a disposable verification
artifact, not an installed app. Do not pin it to the Dock. Xcode **Run** uses a
different bundle under Xcode's DerivedData directory; although both copies have
the same `com.recall.macos` identifier, macOS can launch each explicit path.
Quit every other Recall copy before debugging so only one process owns the
global shortcuts, menu-bar item, and capture coordinator. A future packaging
slice must establish one canonical Applications-directory install.

### One-time Screen Recording migration

If an earlier ad-hoc Recall entry is already enabled in System Settings, migrate
once after producing and verifying the stable build:

1. Quit every running copy of Recall.
2. Verify the exact app bundle you intend to launch with
   `scripts/verify-macos-signing.sh`.
3. Reset only Recall's stale Screen Recording record:
   `tccutil reset ScreenCapture com.recall.macos`.
4. Launch that verified build, start a screenshot capture, and allow Recall in
   **System Settings > Privacy & Security > Screen & System Audio Recording**.
5. Quit and relaunch the same stably signed app, then complete and cancel a real
   region selection. A later rebuild signed by the same identity should retain
   authorization even though its executable CDHash changes.

The reset removes Recall's existing authorization and therefore requires one
fresh approval. It does not reset other applications. No Screen Recording
entitlement should be added; the stable code identity and the normal macOS user
authorization are the relevant boundaries.

This migration is verified on the integration Mac. After authorizing the stable
build at CDHash `143035…`, rebuilding with the same signer and
`CURRENT_PROJECT_VERSION=2` produced CDHash `5a1b00…` with the same Team ID and
signer-based requirement. The rebuilt process launched `/usr/sbin/screencapture`,
showed the region overlay, and returned without a permission error after Escape.

### Accessibility permission for Capture Selection

Accessibility is independent of Screen Recording. Recall requests it only when
the user chooses **Request Access** in Settings or invokes Capture Selection
without authorization. Enable the exact Recall build under **System Settings >
Privacy & Security > Accessibility**, return to the source app, select the text
again, and retry the shortcut; the initial permission call cannot read the
selection retroactively. Clipboard and screenshot capture continue to work when
Accessibility is disabled. Use one stably signed Recall copy during acceptance
so the permission row, running process, and shortcut owner all refer to the same
application identity.

### Clipboard Compatibility Mode

Some applications can copy selected text but do not expose it through the
Accessibility selected-text attribute. **Settings > Selection access >
Clipboard Compatibility Mode** is an off-by-default fallback for those apps.
Permission failure, Recall itself, known secure/protected controls, oversized
input, and cancellation before the transaction never synthesize Copy.
The Settings permission row always shows current Accessibility status. When
access is granted it offers **Manage Access…**, because macOS owns revocation and
Recall cannot implement a real in-app on/off switch for that system permission.

When enabled, Recall retains a ticket for the exact frontmost application whose
selected-text lookup failed. It also binds the exact AX focused control when the
app exposes one with complete safety evidence. Custom-drawn apps such as WeChat
may expose neither a focused control nor per-control safety attributes; their
ticket remains application-scoped, while Secure Event Input and any attributes
that do become available are still checked before Copy.
It waits for the shortcut modifiers to be released, deep-copies bounded ordered
pasteboard items and types into memory, and revalidates that same control
or frontmost application immediately before each of two Copy attempts. It accepts text only when both
attempts produce consecutive change counts and matching complete clipboard
payloads. It then attempts restoration only while the last observed count is
unchanged. The AX and pasteboard transaction runs on its own serial actor rather
than `MainActor`, so a slow source app or lazy pasteboard provider does not block
Recall's UI. The backup is not logged, persisted, or sent to the backend.

Restoration cannot be guaranteed or made invisible. macOS exposes neither the
writer behind a change count nor an atomic compare-and-restore operation. The
two matching Copy results reject common competing-writer races, but a sufficiently
narrow race, a source app that processes Copy after Recall's timeout, a crash, or
a pasteboard write failure can still change the clipboard. Clipboard history
apps, Universal Clipboard, and other observers may record either temporary copy.
Keep the mode disabled if that tradeoff is not acceptable; the explicit
clipboard shortcut remains available.

## Build and test from the command line

Run from the repository root. The explicit Derived Data path keeps generated
output outside the source tree. The repository test command builds the app and
test bundle, then invokes the bundle directly so Xcode 26.6 cannot leave the
host application waiting indefinitely before test completion:

```bash
./scripts/test-macos.sh
```

The commands below are unsigned deterministic automation variants. They are
useful for compilation and unit-test diagnosis, but `CODE_SIGNING_ALLOWED=NO`
must never be used to accept or verify Screen Recording permission:

```bash
xcodebuild \
  -project apps/macos/Recall.xcodeproj \
  -scheme Recall \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/recall-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```bash
xcodebuild \
  -project apps/macos/Recall.xcodeproj \
  -scheme Recall \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/recall-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Normal signed build and test actions are available in Xcode with `Command-B`
and `Command-U` after the local signing override is configured. If
`xcodebuild test` launches Recall but never finishes, stop that run and use
`./scripts/test-macos.sh`; D-026 and E-045 record the verified Xcode 26.6
workaround. That fallback intentionally proves deterministic code behavior, not
TCC authorization.

## Regenerate the Xcode project

`project.yml` is the source of truth for targets, build settings, sources, and
the shared scheme. Regeneration overwrites project-file-only edits, so change
the YAML first and commit it with the generated project.

```bash
cd apps/macos
xcodegen generate
git diff -- project.yml Recall.xcodeproj
```

Run the build and tests again after regeneration.

## Current client behavior

- Run as a normal Dock app with the existing `MenuBarExtra`. Closing the main
  window does not quit Recall, so menu-bar and global capture remain available
  while the app is running.
- Register native global selection, screenshot, and clipboard shortcuts with
  Carbon `RegisterEventHotKey`. Defaults are `Option+Shift+Command+S`,
  `Option+Shift+Command+4`, and `Option+Shift+Command+C`, respectively. Carbon
  registration itself, screenshot capture, and clipboard capture need no
  Accessibility or Input Monitoring permission; reading another app's selected
  text requires Accessibility access.
- Configure any action in Settings with an A–Z or 0–9 key plus Command, Option,
  Control, and/or Shift; each shortcut requires at least two modifiers, and no
  enabled actions can share a combination. Any action can be disabled, and
  **Restore Defaults** restores all three defaults. Existing two-action settings
  migrate without losing custom values; if the new selection shortcut cannot be
  registered, the two established actions remain active.
- Apply shortcut changes transactionally. If any new registration fails, Recall
  restores the previous working registrations and shows the failure in
  Settings, the menu, and the menu-bar status icon.
- Route main-window, menu-bar, and hotkey capture through one app-level
  `GlobalCaptureCoordinator`. Its presentation request is hosted by the
  `MenuBarExtra` label so Quick Capture can open without relying on the main
  window's lifetime.
- Check backend and database health and distinguish connected, degraded, and
  disconnected states.
- Load the newest durable Captures and show list and detail views from live API
  responses.
- Capture non-empty clipboard text, optional notes, and best-effort source-app
  metadata through `POST /v1/captures`.
- After the explicit selection shortcut, ask the focused external app for its
  Accessibility selected text and best-effort range bounds. Reject Recall itself,
  secure/protected fields, empty selections, unresponsive or unsupported
  controls, and selections over 12,000 characters without reading the clipboard
  or silently truncating. Open the existing Quick Capture near valid bounds or
  centered on the current screen when bounds are unavailable. Bounds never leave
  memory; only reviewed text, source app, and optional note can be saved.
- Select a screenshot region, preview it, and explicitly extract visible text
  as reviewed source content. GPT/cloud is the default; Apple Vision/on-device
  uses the same UI and subsequent Capture pipeline without calling the backend
  OCR route. The optional personal note remains an independent field.
- Keep screenshot bytes only for the active draft. Cancel, window close, or
  successful save clears the in-memory preview and invalidates any late OCR
  result; SQLite stores the extracted source text and optional note, not the
  image. Waiting for the system screenshot process and reading its PNG are
  asynchronous. Task cancellation terminates pending selection, app termination
  requests that cancellation, and the random temporary PNG is removed on
  success, cancellation, or failure.
- Keep source, surrounding context, user note, and generated interpretation
  visually separate. Surrounding context is collapsed by default with its
  character count visible; expanding it renders at most the first 2,000
  characters and 60 lines so an overly broad web capture cannot stall the
  detail view. The complete stored context remains available to search and AI
  processing.
- Show `processing`, `ready`, `error`, and captured lifecycle states; poll
  processing records about every two seconds for approximately 60 seconds.
- Retry enrichment without losing the raw Capture.
- Search through the backend's keyword/hybrid endpoint and display results with
  nullable semantic scores.
- Use a visible local substring fallback only when the exact search route
  returns `404`; other API and connection errors remain visible.
- Validate the 12,000-character clipboard, 4,000-character note, and
  512-character search-query limits before sending a request.
- Reuse one `client_capture_id` when the same quick-capture draft is retried, so
  backend idempotency can return the original record instead of creating a
  duplicate. After an ambiguous network failure, freeze that request and require
  a new draft before edited content can be submitted, preventing silent note
  loss on an idempotent replay.
- Preserve an existing Quick Capture draft when another global trigger arrives,
  and show why the new request was not started. Rapid repeated screenshot
  triggers launch only one region selector.
- Render valid web source URLs and Chrome-created Captures through the same
  shared model used for clipboard Captures.

## Remaining integration boundaries

- Real OpenAI enrichment, embeddings, semantic retrieval, and unpacked-Chrome
  selected-text/no-selection Captures have been verified end to end against the
  macOS client. Keep the credential and machine-specific extension origin only
  in the untracked root `.env`.
- Clipboard, screenshot, and Accessibility source-application detection is best
  effort. Selection capture reads only after its explicit shortcut; it does not
  read active window titles, URLs, surrounding text, or every selection change.
  Applications that do not expose `AXSelectedText` remain compatible through the
  separate clipboard action.
- Global shortcuts work only while Recall is running. Launch at login is a
  separate future opt-in. Stable Screen Recording authorization now survives a
  rebuild. Real-device acceptance also passes: with Recall's main window closed
  and another app focused, the physical screenshot shortcut completed a
  non-empty region, and the clipboard shortcut opened Capture after copying
  text.
- Persistence belongs to the backend SQLite database. The app has no offline
  write queue.
- An abrupt backend exit can interrupt in-process enrichment. On the next
  backend startup, the card becomes a visible retryable error while its source
  and note remain intact.
- App sandboxing, notarization, and bundling the Python service are outside the
  current P0 Build Week scope.

The original D-034 command-line suite executed 108/108 tests. With the D-035
clipboard transaction and D-036 explicit Clipboard Capture intake, the current
suite reached 176/176 tests. The integrated D-037 image-note work now executes
184/184
Accessibility, pasteboard, contract, networking, production Vision,
global-shortcut, lifecycle, validation, image-upload/display/delete, retry,
polling, store, window-placement, and signing-identity tests.

## Manual test matrix

Run the integrated backend and a Debug build against `127.0.0.1:8765`. These
rows describe expected behavior; check them off in the shared checklist only
after rerunning them on the current integrated tree.

| Area | Action | Expected result |
| --- | --- | --- |
| Healthy launch | Start the backend, then launch Recall. | Connection shows **Connected** and live records load. `AI not configured` is acceptable without a key. |
| Offline recovery | Stop the backend, launch Recall, restart the backend, then choose **Try Again** or **Refresh**. | Recall shows an offline state, reconnects, and reloads the library without losing persisted records. |
| Clipboard capture | Copy non-empty text in TextEdit, open **Capture Clipboard**, add a note, and save. | The exact text and note are saved separately; the record appears immediately and progresses to a safe terminal state. |
| Rich clipboard line breaks | Copy a known multiline model response containing headings and a literal delimiter such as `$e$`, then open **Capture Clipboard**. | Clipboard Capture retains line breaks already present in plain text and may restore safe boundaries from equivalent HTML/RTF; a mismatched rich representation never removes `$e$`. |
| Shortcut settings | Confirm the defaults, change screenshot capture to `Option+Shift+Command+5`, relaunch Recall, then choose **Restore Defaults**. Also try one modifier and a duplicate combination. | The valid change persists across restart and defaults restore correctly. Invalid or duplicate combinations are rejected without replacing the active shortcuts. |
| Registration failure | Choose a combination already owned by macOS or another app and apply it. | Recall restores the preceding active shortcuts and exposes the failure in Settings, the menu, and the menu-bar status icon. |
| Global clipboard | Close the main window without quitting Recall, focus another app with 32 known clipboard characters, and press `Option+Shift+Command+C` twice. | Quick Capture opens with the exact 32 characters. The second trigger preserves the existing draft and shows an explanatory notice. |
| Accessibility permission | With Recall absent or disabled in **Privacy & Security > Accessibility**, select text in another app and press `Option+Shift+Command+S`; then grant access and retry. | The first attempt reads and saves nothing, explains the permission, and offers System Settings/current-clipboard recovery. After authorization, Settings reports access enabled and a new explicit attempt can read the selection. |
| Global selection | Close the main window without quitting Recall, select known Chinese/emoji/multiline text in TextEdit, and press `Option+Shift+Command+S`. Repeat near each screen edge and with no selection. | Quick Capture shows the exact text and Unicode count, opens near the selection while staying inside the visible screen, focuses the optional note, and saves only after review. No-selection stays unsaved with an actionable fallback. |
| Accessibility compatibility | Repeat selection capture in Safari/Chrome, selectable PDF text in Preview, and an Electron or custom-drawn control with Clipboard Compatibility Mode off. Try a password field and a selection longer than 12,000 characters. | Supported apps produce exact text and best-effort positioning. Unsupported controls fail clearly without touching the clipboard. Secure, unknown-safety, and oversized text never becomes a draft or request. |
| Clipboard compatibility | Put known plain text, rich text, an image, and Finder files on the clipboard in turn. Enable Clipboard Compatibility Mode, select known text in WeChat, and press `Option+Shift+Command+S`. Also try no selection, a password field, rapid repeats, switching controls/apps, and manually changing the clipboard during capture. | Eligible WeChat text opens as a selection draft and discloses two temporary Copies. The prior clipboard is restored with all materialized representations in the normal path. Detected focus/payload/count races create no draft and do not attempt restoration; because macOS has no writer identity or atomic restore, verify the clipboard manually rather than claiming zero race risk. Clipboard-history tools may retain the transient selection. |
| Global screenshot | Close the main window without quitting Recall, focus another app, and press `Option+Shift+Command+4`; cancel once and complete a region once. | The selector starts without blocking Recall. Cancellation leaves no draft or temporary PNG; a completed region opens the existing screenshot draft and disclosure UI. |
| Local image note | Keep the global AI master switch off, complete a screenshot, choose **Image note**, add a note, and save. Repeat with the master switch on but disable indexing for that image. | The per-image control is disabled while the master switch is off. Both originals and notes appear immediately and survive restart; neither image is sent to OpenAI. |
| Visual image note | Enable the global AI master switch, capture a diagram or interface whose important visual relationship is absent from its visible text, and keep per-image indexing on. Search for that relationship after processing. | A new image defaults to indexing on. The original appears before analysis completes; background OCR/visual metadata becomes visible/searchable, and the result can match visual concepts rather than only literal OCR. |
| Image analysis failure/retry | Save an analyzed image with OpenAI unavailable, then configure the provider and choose **Retry AI**. | The first attempt preserves the original and note in a visible error state; retry reaches `ready` without duplicating the image. |
| Image deletion | Delete an image note from detail and confirm. Refresh and inspect the configured attachment directory. | The card, search result, metadata row, and referenced image file are gone; another note is unaffected. |
| GPT screenshot note | Choose **Capture Screenshot Note**, select a text region, keep **GPT · Cloud**, and choose **Extract source text**. | A preview appears before upload, the UI states the cloud boundary, extracted text fills only the source field, your optional personal note stays separate, and only text is saved. |
| Local screenshot note | Repeat with **Apple Vision · On device**, disconnect the network after the backend is already running, and extract. | Text extraction succeeds on the Mac, the UI confirms local processing, and no `/v1/ocr` request is made. Saving still uses the localhost Capture API. |
| Screenshot cancellation/limits | Cancel region selection, close the draft while extraction is running, try a non-text image, and select enough text to exceed 12,000 characters. | Cancellation creates no draft; close clears the image and ignores a late result; no-text and oversized results remain unsaved with actionable errors and no silent truncation. |
| Empty clipboard | Clear the clipboard or copy non-text-only content, then open capture. | Recall warns locally and sends no create request. |
| Capture limits | Try clipboard text at 12,000/12,001 characters and notes at 4,000/4,001. | Values at the caps can be submitted; oversized drafts stay visible and show validation without submission. |
| Idempotent retry | Make one create attempt fail after preparing a draft, restore service, and retry the same draft. | The retry uses the same client ID and cannot create two records for that one draft. |
| Durable reload | Save a unique record, quit Recall, and relaunch against the same backend database. | The same record reloads with unchanged source, note, and lifecycle data. |
| Lifecycle polling | Save or retry a processing record and leave it visible. | Polling stops on `ready` or `error`, does not duplicate records, and visibly stops after its time cap. |
| Keyword fallback | Run without a key and search for indexed source/note text. | Backend FTS results display even when `semantic_score` is `null`. |
| Search limits and failure | Try 512/513-character queries, a control character, a backend error, and a genuine search-route `404`. | Valid input reaches the backend; invalid input is blocked locally; only `404` enables the visible local fallback. |
| API-provided web record | POST `contracts/examples/capture-request.json`, refresh, and open the record. | URL, title, selection, note, and truncation state appear in separate sections. Context starts collapsed with a character count; Show/Hide works and long context clearly limits only its on-screen preview. |
| Real Chrome flow | Load the extension unpacked, configure its exact origin, save a web selection, and refresh Recall. | The Chrome-created card appears without a database edit; repeat once with the backend stopped to verify the popup error. |
| Menu-bar entry | Exercise **Open Recall**, **Capture Selection**, **Capture Clipboard**, **Capture Screenshot Note**, **Search**, **Check Connection**, and **Quit Recall**. | Each item performs its intended action without unexpected duplicate windows. |

For the short walkthrough, use
[`docs/demo-script.md`](../../docs/demo-script.md).
