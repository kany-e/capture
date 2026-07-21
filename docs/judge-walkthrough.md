# Mema judge walkthrough

This path exercises every submitted component without relying on hidden state.
Allow about five minutes for the core flow and another five for optional
screenshot/image analysis.

## Preflight

1. Start the backend from the repository root with `./scripts/dev.sh`.
2. Confirm `http://127.0.0.1:8765/health` reports `status: ok`.
3. Run Mema from `apps/macos/Mema.xcodeproj` with the **Mema** scheme.
4. If judging GPT-5.6, put `OPENAI_API_KEY` in the ignored root `.env` before
   starting the backend and confirm health reports `openai_configured: true`.
5. Load `apps/chrome-extension/` as an unpacked extension and allowlist its
   exact `chrome-extension://…` origin as described in the root README.

## Core walkthrough

### 1. Local-first Capture

Create a text Capture in the macOS app with a distinctive phrase and a short
personal note.

Expected:

- the source and note appear immediately;
- they remain separate in the detail view;
- without an API key, the original is still stored and keyword-searchable;
- with a key, enrichment transitions from processing to ready without changing
  the source.

### 2. GPT-5.6 memory structure

With a key configured, open the ready Capture.

Expected:

- a specific generated title and contextual summary;
- separate problem, key insight, why-saved, caveat, tag, entity, and search
  alias fields;
- search by a paraphrase or generated tag returns the Capture;
- a source edit hides the now-stale AI interpretation until **Retry AI** is
  explicitly selected.

### 3. Chrome extension installation path

On an ordinary web page, select a sentence, open the Mema toolbar action, add
an optional note, and save. Return to the native app.

Expected:

- the exact selected text, page title, URL, and note are present;
- the save succeeds through the local service-worker delivery path;
- a repeated ambiguous retry reuses the same client ID instead of creating a
  duplicate;
- if the backend is stopped, the extension shows a recoverable error rather
  than silently discarding the draft.

Optionally enable **Show Add to Mema when I select text** in extension Settings.
Select text again and save from the inline composer. Disable the option and
confirm page controls disappear while toolbar capture still works.

### 4. Screenshot text extraction

Choose **Capture Screenshot Note**, select a small high-contrast text region,
and keep **Text note** selected.

- **GPT · Cloud** sends the reviewed region only after **Extract source text**
  is chosen.
- **Apple Vision · On device** performs the same extraction locally.
- Cancel clears the temporary image and creates no Capture.
- Save stores reviewed text plus the separate personal note, not the temporary
  screenshot.

Interactive screen selection requires macOS Screen Recording permission. Use a
stably signed local build; see `apps/macos/README.md`.

### 5. Persistent image note

Capture a screenshot again, choose **Image note**, add a note, and leave cloud
analysis off.

Expected:

- the original image and note are stored locally;
- the image is visible in the detail view;
- no image analysis call occurs.

If desired, enable the global image-analysis privacy setting and opt in for one
new image. GPT-5.6 adds OCR and visual indexing in the background. Delete the
Capture and confirm the card and attachment disappear together.

## Automated verification

Run from the paths shown:

```bash
cd services/backend
.venv/bin/python -m pytest
.venv/bin/python tools/stress_backend.py

cd ../../apps/chrome-extension
npm test

cd ../..
./scripts/test-macos.sh
```

The automated suites use provider doubles and require no API key. Real provider
behavior, Chrome injection, Accessibility, and Screen Recording remain manual
acceptance checks because CI cannot grant those user permissions.

## Safe fallback notes

| Problem | Recovery |
| --- | --- |
| Backend unavailable | Restart `./scripts/dev.sh`; the client keeps unsaved input visible. |
| OpenAI unavailable | Continue with local storage/keyword search, or use Apple Vision for screenshot text. |
| Screen Recording denied | Use ordinary text/clipboard Capture, or authorize the exact signed Mema build and relaunch. |
| Accessibility denied | Use clipboard, screenshot, in-app, or Chrome capture; global selection capture is the only affected path. |
| Enrichment fails after save | Show the preserved source and retry explicitly; do not recreate the Capture. |

## Claims and boundaries

- Mema is a local Build Week prototype, not a hosted multi-user service.
- Screenshot **Text note** images are transient; **Image note** images are
  intentionally persisted.
- Apple Vision is local OCR, not local semantic enrichment.
- Packaging, notarization, sync, accounts, and a durable background queue are
  outside this submission.
