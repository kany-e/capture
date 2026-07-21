# Mema for macOS

This directory contains Mema's SwiftUI/AppKit client. Normal runs connect to the
local backend at `http://127.0.0.1:8765`; the app does not embed a production
database or provider key.

## Requirements

- macOS 14 or later
- Xcode 26.x (verified with Xcode 26.2)
- Python 3.10 or later for the backend
- XcodeGen 2.45 or later only when regenerating the checked-in project
- An Apple Development identity only for stable Screen Recording acceptance

## Run

Start the backend from the repository root and keep it running:

```bash
./scripts/dev.sh
```

Open `apps/macos/Mema.xcodeproj`, select the shared **Mema** scheme and
**My Mac**, then choose **Product > Run**. A green **Connected** state confirms
the loopback service is healthy.

No OpenAI key is required for local storage and keyword retrieval. Put a key
only in the ignored root `.env` to exercise GPT-5.6 enrichment, cloud screenshot
OCR, image understanding, embeddings, and semantic search.

## Capture paths

Mema can create a draft from the app, menu bar, or these default global
shortcuts:

| Action | Default shortcut | Permission |
| --- | --- | --- |
| Capture Selection | `Option+Shift+Command+S` | Accessibility |
| Capture Screenshot | `Option+Shift+Command+4` | Screen Recording |
| Capture Clipboard | `Option+Shift+Command+C` | None |

Shortcuts can be changed, disabled, or restored under **Settings > Global
capture shortcuts**. Closing the main window keeps the normal Dock app and menu
bar extra running.

Screenshot Capture offers two distinct paths:

- **Text note** keeps the screenshot transient, extracts text with
  **GPT · Cloud** or **Apple Vision · On device**, and saves reviewed text plus
  a separate note.
- **Image note** persists one original image plus a note. Background cloud OCR
  and visual understanding require both the global privacy switch and the
  per-Capture opt-in.

Clipboard Compatibility Mode is off by default. It exists for custom-drawn apps
that can copy selected text but do not expose it through Accessibility. It uses
a bounded, best-effort transactional copy/restore path; clipboard history tools
or a concurrent writer can still observe or race the temporary copies.

## Stable local signing

Ordinary builds and deterministic tests can use the portable default signing
configuration. Interactive Screen Recording authorization must use a stable
development identity because macOS associates permission with code identity,
not only the app name.

Create the ignored local override:

```bash
cp -n apps/macos/Config/Signing.local.xcconfig.example \
  apps/macos/Config/Signing.local.xcconfig
```

Replace `YOUR_TEAM_ID` with the actual Team ID for the selected Apple
Development identity. Never commit that file or a personal Team ID.

Build and verify the exact app bundle:

```bash
xcodebuild \
  -project apps/macos/Mema.xcodeproj \
  -scheme Mema \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/mema-signed-derived-data \
  build

./scripts/verify-macos-signing.sh \
  /tmp/mema-signed-derived-data/Build/Products/Debug/Mema.app
```

The verifier requires a valid signature, non-empty Team ID, and signer-based
designated requirement. `CODE_SIGNING_ALLOWED=NO` is useful only for automation;
it cannot prove Screen Recording acceptance.

If an older ad-hoc build left a stale permission row, quit every Mema copy,
verify the exact new bundle, then reset only this app and authorize it once:

```bash
tccutil reset ScreenCapture com.camarow.mema
```

Launch the verified build, perform one screenshot capture, allow it in **System
Settings > Privacy & Security > Screen & System Audio Recording**, and relaunch
the same signed app. This reset removes Mema's existing authorization but does
not affect other apps.

## Tests

From the repository root:

```bash
./scripts/test-macos.sh
```

The runner builds the shared **Mema** scheme in a temporary DerivedData path and
runs the complete host test bundle. Deterministic tests use mocks and disable
signing; real Accessibility, Screen Recording, physical hotkeys, Apple Vision,
and live-provider behavior remain manual gates.

To regenerate the project after changing `project.yml`:

```bash
cd apps/macos
xcodegen generate
```

Commit `project.yml` and the regenerated `Mema.xcodeproj` together. The app ID
is `com.camarow.mema`; the test bundle is `com.camarow.mema.tests`.

## Current distribution boundary

The submission runs from Xcode and is not packaged or notarized. Quit other
copies before debugging so only one process owns the global hotkeys, menu-bar
item, and capture coordinator. A future release needs one canonical installed
bundle and an explicit update/migration path.

For the full manual product path, see
[`../../docs/judge-walkthrough.md`](../../docs/judge-walkthrough.md).
