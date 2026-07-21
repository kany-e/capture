# Mema

[![CI](https://github.com/CamaroW/Mema/actions/workflows/ci.yml/badge.svg)](https://github.com/CamaroW/Mema/actions/workflows/ci.yml)

Mema is a local-first memory tool for macOS. Save selected text, clipboard
content, screenshots, images, or web pages with the reason they mattered;
Mema preserves the original source and turns it into a searchable memory.

The product has three runnable parts:

| Part | What it does |
| --- | --- |
| macOS app | Global text, clipboard, screenshot, and image capture; library, editing, and search |
| Chrome extension | Toolbar, keyboard, and opt-in inline capture from web pages |
| Local backend | Loopback-only FastAPI API, SQLite/FTS5 storage, attachments, GPT enrichment, and hybrid search |

Original source, personal notes, user edits, and AI interpretation remain
separate. Mema works without an OpenAI key for local storage and keyword
search; cloud enrichment, OCR, image understanding, embeddings, and semantic
search are optional.

## Five-minute judge path

### 1. Requirements

- macOS 14 or later
- Xcode 26.x (verified with Xcode 26.2)
- Python 3.10 or later
- Google Chrome 102 or later for the extension
- Node.js 22 only for extension tests
- An OpenAI API key only for the optional GPT-5.6 path

Clone and enter the repository:

```bash
git clone https://github.com/CamaroW/Mema.git
cd Mema
```

### 2. Start the local backend

The helper creates a virtual environment, installs dependencies, validates the
configuration, starts Mema on `127.0.0.1:8765`, and waits for a healthy SQLite
database:

```bash
./scripts/dev.sh
```

Keep that terminal open. In another terminal, verify the service:

```bash
curl --fail http://127.0.0.1:8765/health
```

The expected provider-off response includes:

```json
{"status":"ok","database":"ok","attachments":"ok","openai_configured":false}
```

To judge GPT-5.6 enrichment, copy the example configuration before starting
the backend and add a key only to the ignored root `.env`:

```bash
cp .env.example .env
```

```text
OPENAI_API_KEY=your_key_here
OPENAI_MODEL=gpt-5.6
```

Never commit `.env` or an API key.

### 3. Run the macOS app

Open [`apps/macos/Mema.xcodeproj`](apps/macos/Mema.xcodeproj) in Xcode, select
the shared **Mema** scheme and **My Mac**, and run it. With the backend running:

1. Use the app's **New Capture** flow to save text and an optional personal
   note.
2. Confirm the original source appears immediately in the library.
3. With a key configured, wait for the GPT-5.6 interpretation; without a key,
   confirm the original remains stored and keyword-searchable.
4. Search for a source phrase or generated tag and open the result.
5. Edit the source or memory fields and confirm the captured source and AI
   layer remain distinguishable.

Global selection capture requires Accessibility permission. Interactive
screenshot capture requires Screen Recording permission and a stable local
Apple Development signature; ordinary library and text-capture judging does
not. The exact signing path is in the
[`macOS setup guide`](apps/macos/README.md).

### 4. Install and test the Chrome extension

This is a build-free Manifest V3 extension:

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Choose **Load unpacked** and select `apps/chrome-extension/`.
4. Copy the generated extension ID.
5. Add its exact origin to the ignored root `.env`:

   ```text
   MEMA_CORS_ORIGINS=chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
   ```

6. Restart `./scripts/dev.sh`.
7. Open an ordinary `http` or `https` page, select text, open Mema from the
   toolbar, add an optional note, and save.
8. Return to the macOS app and confirm the web Capture is present and
   searchable.

For the optional inline path, open the extension's Settings page and enable
**Show Add to Mema when I select text**. Chrome then requests optional site
access. Turning it off removes Mema's injected controls while toolbar capture
continues to work. More acceptance cases are in the
[`judge walkthrough`](docs/judge-walkthrough.md) and
[`extension guide`](apps/chrome-extension/README.md).

## How GPT-5.6 is used

Mema defaults to `gpt-5.6` and uses the OpenAI Responses API in three explicit,
user-visible flows:

- text Captures use strict Structured Outputs to generate a title, contextual
  summary, problem, key insight, why it was saved, caveats, tags, entities, and
  search aliases;
- **GPT · Cloud** extracts text from a screenshot when the user chooses it;
- image notes can opt in to background OCR plus visual interpretation. The
  original image remains authoritative and is saved before analysis begins.

Every Responses API call sets `store: false`. Provider output is validated
again at the service boundary before it can become a ready memory. Embeddings
use `text-embedding-3-small` as a separate retrieval step; keyword search still
works if the provider is absent or unavailable. Screenshot text also has an
on-device Apple Vision path, and cloud image analysis is off by default.

Implementation choices follow the official OpenAI guidance for
[`gpt-5.6`](https://developers.openai.com/api/docs/guides/latest-model),
[`Structured Outputs`](https://developers.openai.com/api/docs/guides/structured-outputs),
and [`API data controls`](https://developers.openai.com/api/docs/guides/your-data#v1responses).

## How Codex was used

Codex was the engineering collaborator across the Build Week project. It was
used to:

- turn the product idea into contracts, architecture boundaries, and a staged
  implementation plan;
- implement and refactor the Swift/AppKit, Python/FastAPI, and Manifest V3
  clients while keeping one shared Capture contract;
- build regression tests for idempotent retries, migrations, CORS, permissions,
  privacy controls, malformed model output, and offline behavior;
- audit the integrated repository, trace cross-client failures, review security
  and privacy boundaries, and prepare the reproducible judge path.

Human review remained part of the loop: permission-sensitive macOS behavior,
real Chrome injection, product wording, privacy defaults, and final submission
scope were verified against the running product rather than accepted from code
generation alone.

## Run the full test suite

Backend and deterministic stress tests (no real provider calls):

```bash
cd services/backend
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pytest
.venv/bin/python tools/stress_backend.py
.venv/bin/python -m pip check
```

Chrome extension tests:

```bash
cd apps/chrome-extension
npm test
```

macOS build and tests, from the repository root:

```bash
./scripts/test-macos.sh
```

CI runs these as independent backend, stress, Chrome, and macOS jobs and then
requires all four to pass. Tests use local provider doubles and do not need an
API key.

## Privacy and security boundaries

- The backend rejects non-loopback bind addresses.
- Chrome origins must be explicitly allowlisted; wildcards and public web
  origins are rejected before a request can mutate local data.
- SQLite files are created with owner-only permissions and attachment bytes are
  served with `Cache-Control: no-store`.
- Browser selection text stays in the tab until **Save**.
- Cloud screenshot/image processing is explicit, with on-device or local-only
  alternatives.
- Source content is committed before asynchronous AI work, so provider failure
  cannot erase the Capture.

This is a local Build Week prototype, not a hardened multi-user or remotely
hosted service. The AI runner is in-process, there is no account sync, and
packaging/notarization is outside the current submission.

## Repository map

```text
apps/macos/                 SwiftUI/AppKit client
apps/chrome-extension/      Build-free Manifest V3 extension
services/backend/           FastAPI service and tests
contracts/                  Shared API and JSON Schema contracts
docs/                       Architecture, decisions, and judge walkthrough
scripts/                    Startup, signing, and test helpers
```

Key references:

- [`Judge walkthrough`](docs/judge-walkthrough.md)
- [`API contract`](contracts/api.md)
- [`Architecture`](docs/architecture.md)
- [`Decisions`](docs/decisions.md)
- [`Backend setup`](services/backend/README.md)
- [`macOS setup`](apps/macos/README.md)
- [`Chrome extension setup`](apps/chrome-extension/README.md)

## License

Mema is available under the [MIT License](LICENSE).
