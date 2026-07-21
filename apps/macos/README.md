# Recall for macOS

This directory contains Recall's SwiftUI/AppKit client. It talks to the
loopback backend at `http://127.0.0.1:8765`; normal runs do not use an in-process
database or mock API client.

The macOS client, hardened backend, and Chrome extension now live in the same
integration tree. The current target builds and passes all 64 contract,
networking, Vision, global-shortcut, lifecycle, validation, idempotency, and
store tests.

## Requirements

- Xcode 26.x. The project was previously built with Xcode 26.2.
- macOS 14.0 or later.
- Python 3.10 or later and backend dependencies installed as described in
  [`services/backend/README.md`](../../services/backend/README.md).
- XcodeGen 2.45 or later only when regenerating the project. The checked-in
  `Recall.xcodeproj` opens without XcodeGen.

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
green **Connected** indicator after it reaches a healthy local service.

## Build and test from the command line

Run from the repository root. The explicit Derived Data path keeps generated
output outside the source tree. The repository test command builds the app and
test bundle, then invokes the bundle directly so Xcode 26.6 cannot leave the
host application waiting indefinitely before test completion:

```bash
./scripts/test-macos.sh
```

Use the commands below when testing interactively through Xcode's normal host
runner rather than the deterministic command-line safeguard.

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

The same actions are available in Xcode with `Command-B` and `Command-U`. If
`xcodebuild test` launches Recall but never finishes, stop that run and use
`./scripts/test-macos.sh`; D-026 and E-045 record the verified Xcode 26.6
workaround.

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
- Register native global screenshot and clipboard shortcuts with Carbon
  `RegisterEventHotKey`, without Accessibility or Input Monitoring permission.
  Defaults are `Option+Shift+Command+4` for screenshot capture and
  `Option+Shift+Command+C` for clipboard capture.
- Configure either action in Settings with an A–Z or 0–9 key plus Command,
  Option, Control, and/or Shift; each shortcut requires at least two modifiers,
  and the two actions cannot use the same combination. Either action can be
  disabled, and **Restore Defaults** restores both defaults.
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
- Clipboard and screenshot source-application detection is best effort. The app
  does not read active window titles or Accessibility selections.
- Global shortcuts work only while Recall is running. Launch at login is a
  separate future opt-in. Actual physical hotkey delivery and region selection
  still need final manual acceptance in the normally signed build; the temporary
  unsigned verification build did not receive Screen Recording permission.
- Persistence belongs to the backend SQLite database. The app has no offline
  write queue.
- An abrupt backend exit can interrupt in-process enrichment. On the next
  backend startup, the card becomes a visible retryable error while its source
  and note remain intact.
- App sandboxing, notarization, and bundling the Python service are outside the
  current P0 Build Week scope.

The current command-line suite executes 68 contract, networking, production
Vision, global-shortcut, lifecycle, validation, retry, polling, and store tests.

## Manual test matrix

Run the integrated backend and a Debug build against `127.0.0.1:8765`. These
rows describe expected behavior; check them off in the shared checklist only
after rerunning them on the current integrated tree.

| Area | Action | Expected result |
| --- | --- | --- |
| Healthy launch | Start the backend, then launch Recall. | Connection shows **Connected** and live records load. `AI not configured` is acceptable without a key. |
| Offline recovery | Stop the backend, launch Recall, restart the backend, then choose **Try Again** or **Refresh**. | Recall shows an offline state, reconnects, and reloads the library without losing persisted records. |
| Clipboard capture | Copy non-empty text in TextEdit, open **Capture Clipboard**, add a note, and save. | The exact text and note are saved separately; the record appears immediately and progresses to a safe terminal state. |
| Shortcut settings | Confirm the defaults, change screenshot capture to `Option+Shift+Command+5`, relaunch Recall, then choose **Restore Defaults**. Also try one modifier and a duplicate combination. | The valid change persists across restart and defaults restore correctly. Invalid or duplicate combinations are rejected without replacing the active shortcuts. |
| Registration failure | Choose a combination already owned by macOS or another app and apply it. | Recall restores the preceding active shortcuts and exposes the failure in Settings, the menu, and the menu-bar status icon. |
| Global clipboard | Close the main window without quitting Recall, focus another app with 32 known clipboard characters, and press `Option+Shift+Command+C` twice. | Quick Capture opens with the exact 32 characters. The second trigger preserves the existing draft and shows an explanatory notice. |
| Global screenshot | Close the main window without quitting Recall, focus another app, and press `Option+Shift+Command+4`; cancel once and complete a region once. | The selector starts without blocking Recall. Cancellation leaves no draft or temporary PNG; a completed region opens the existing screenshot draft and disclosure UI. |
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
| Menu-bar entry | Exercise **Open Recall**, **Capture Clipboard**, **Capture Screenshot Note**, **Search**, **Check Connection**, and **Quit Recall**. | Each item performs its intended action without unexpected duplicate windows. |

For the short walkthrough, use
[`docs/demo-script.md`](../../docs/demo-script.md).
