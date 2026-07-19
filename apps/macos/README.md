# Recall for macOS

This directory contains Developer 1's SwiftUI/AppKit client. It talks directly
to the loopback backend at `http://127.0.0.1:8765`; the app does not use an
in-process database or mock client in normal runs.

## Requirements

- Xcode 26.x. The checked-in project was last built with Xcode 26.2.
- macOS 14.0 or later. The deployment target is macOS 14.0.
- Python backend dependencies installed as described in
  [`services/backend/README.md`](../../services/backend/README.md).
- XcodeGen 2.45 or later only when regenerating the project. The checked-in
  `Recall.xcodeproj` can be opened without XcodeGen.

## Run the app

Start the backend before opening or running Recall. From the repository root,
install it once if needed:

```bash
cd services/backend
# Use any Python 3.10+ interpreter. On the current Apple Silicon host:
/opt/homebrew/bin/python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

Check `python3 --version` first on other machines; Apple's `/usr/bin/python3`
may be older than the backend's declared Python 3.10 minimum.

Then keep the backend running in its own terminal:

```bash
cd services/backend
.venv/bin/python -m app
```

Confirm that the local service is ready:

```bash
curl --fail http://127.0.0.1:8765/health
```

A Layer 3 backend without an OpenAI key returns a healthy response with
`"openai_configured": false`. That is expected and does not prevent capture
storage.

Open `apps/macos/Recall.xcodeproj` in Xcode, select the shared `Recall` scheme
and the **My Mac** destination, then run with **Product > Run** (`Command-R`).
The app should show a green **Connected** indicator once it reaches the local
service.

## Build and test from the command line

Run these commands from the repository root. The explicit Derived Data path
keeps command-line output outside the source tree.

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

The same actions are available in Xcode with `Command-B` and `Command-U`.
The test action uses the `RecallTests` target declared in `project.yml`.

## Regenerate the Xcode project

`project.yml` is the source of truth for targets, build settings, sources, and
the shared scheme. Regeneration overwrites project-file-only edits, so change
the YAML first and commit it together with the generated project.

```bash
cd apps/macos
xcodegen generate
```

After regeneration, inspect both files and run the command-line build and test
commands above:

```bash
git diff -- project.yml Recall.xcodeproj
```

## What the current Layer 3 client can do

- Check backend health and expose connection state in the main and menu-bar UI.
- Load the newest 50 durable Captures, refresh them, and show list and detail
  views from live backend responses.
- Copy text in another macOS app, open **Capture Clipboard**, add an optional
  personal note, and persist both through `POST /v1/captures`.
- Preserve the original selection, source application, and user note as
  separate fields in the detail view.
- Show `processing`, `ready`, and `error` states and poll detail responses for
  changes.
- Display AI fields, tags, context, and a valid web source URL when a future
  backend response contains them.
- Fall back to a case-insensitive, all-terms local substring filter over the
  currently loaded 50 records when the backend search route returns `404`.

## Layer 3 limitations

These are integration boundaries, not features to imply in a demo:

- Layer 3 persists captures but does not run enrichment. New records remain
  `processing`, and AI title, summary, tags, entities, and aliases stay empty
  until Developer 2 connects Layer 4.
- FTS5, query embeddings, semantic ranking, and the production
  `GET /v1/search` implementation are not available yet. The client-side filter
  is only a temporary UI fallback; it is limited to loaded records and does no
  ranking or semantic retrieval.
- The Chrome extension and browser-to-backend capture path are not present.
  Web URL, title, and surrounding context can be rendered when supplied by the
  API, but the macOS clipboard flow does not collect them.
- Clipboard source-application detection is best effort. The current flow does
  not read the active window title or Accessibility selection and has no global
  system-wide shortcut.
- Persistence belongs to the backend SQLite database. Recall must be able to
  reach the backend to create or reload records; it has no offline write queue.

Developer 2's Layer 4, 5, and 6 work will respectively unlock real AI
enrichment, backend keyword search, and Chrome capture. Hybrid semantic search
arrives in the later retrieval layer.

## Manual test matrix

Run the backend and use a Debug build against `127.0.0.1:8765` unless the row
says otherwise.

| Area | Action | Expected result at Layer 3 |
| --- | --- | --- |
| Healthy launch | Start the backend, then launch Recall. | Connection shows **Connected** and the newest backend records load without mock data. `AI not configured` is acceptable. |
| Offline launch and recovery | Stop the backend, launch Recall, then restart the backend and choose **Try Again** or **Refresh**. | Recall shows an offline state and a useful error; after restart it reconnects and loads the library. |
| Clipboard capture | In TextEdit, copy non-empty text. Choose the menu-bar **Capture Clipboard**, add a note, and save. | The form shows the exact clipboard text and a best-effort source app. The saved record appears first with `processing`; its note and selection are separate. |
| Empty or non-text clipboard | Clear the clipboard or copy non-text-only content, then choose **Capture Clipboard**. | Recall opens an unavailable state or warning and does not send a create request. |
| Length guard | Try text at and immediately above 12,000 Unicode scalars. | Text at the contract limit can be submitted. Oversized text stays visible in the draft and Save shows a validation message instead of truncating or submitting it. |
| Durable reload | Save a unique capture, quit Recall, relaunch it while the same backend/database is running. | The capture reloads from SQLite with the same source text and user note. At Layer 3 it can still be `processing`. |
| Detail refresh | Select a record and use Refresh; leave a new `processing` record selected for several polling intervals. | Detail requests do not duplicate or lose the record. Layer 3 continues to show the saved source and note while enrichment fields remain empty. |
| Temporary search fallback | Search for an exact word in a loaded selection or note. | The first missing backend search request may show the fallback notice; matching loaded records remain. No semantic behavior or result ranking is claimed. |
| API-provided web record | From the repository root, POST `contracts/examples/capture-request.json`, refresh Recall, and select the new record. | Web title, URL, selection, context, note, and truncation state decode into their separate sections; **Open Source** appears only for a valid `http` or `https` URL. This is API seeding, not Chrome capture. |
| Menu-bar entry | Exercise **Open Recall**, **Capture Clipboard**, **Search**, **Check Connection**, and **Quit Recall**. | Each item opens or focuses the intended UI, refreshes connection state, or quits without leaving an unexpected main window state. |

For the short live walkthrough, use
[`docs/demo-script.md`](../../docs/demo-script.md).
