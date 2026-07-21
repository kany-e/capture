# Recall Chrome extension

This is a build-free Manifest V3 extension. Chrome runs the checked-in ES
modules directly; only Node's built-in test runner is used during development.

## Load unpacked

1. Start the Recall backend at `http://127.0.0.1:8765`.
2. Open `chrome://extensions` in Google Chrome.
3. Enable **Developer mode**.
4. Choose **Load unpacked** and select this `apps/chrome-extension/` directory.
5. Copy the generated extension ID.
6. Add its exact origin to the untracked root `.env`, for example:

   ```text
   RECALL_CORS_ORIGINS=chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
   ```

7. Restart the backend, open an ordinary `http` or `https` page, select text,
   and use the Recall toolbar action.

## Capture paths

Toolbar and keyboard capture remain available with no broad website access. For
the lower-friction inline path, open the popup and enable **Show Add to Recall
when I select text**. Chrome then asks for optional HTTP/HTTPS website access.
Inline capture is off by default. Granting access dynamically injects the inline
behavior into already-open web pages, so a refresh is not required.

After an eligible mouse or keyboard selection, a transient **Add to Recall**
action appears beside the selection without moving page layout or focus. Open it
to review the selection, add an optional note, then choose **Save**. The
Unicode-aware selected-text count is separate from the note's 4,000-character
count, and a long selection preview can be scrolled with a pointer or keyboard.
Selections through the 12,000-character contract limit keep their content after
the established line-ending and outer-whitespace normalization; longer
selections show their full count and clearly state that only the first 12,000
characters will be saved.

Escape or Cancel closes Recall UI; ordinary page keyboard behavior is not
prevented. Inputs, editable regions, Chrome internal pages, the built-in PDF
viewer, and iframe content are not supported by this path.

For the keyboard-first path, press `Command+Shift+Y` on macOS or
`Control+Shift+Y` on other platforms. Chrome may reserve or override suggested
shortcuts; confirm or customize Recall's binding at `chrome://extensions/shortcuts`.
The popup focuses the optional note. Press `Command+Enter` or `Control+Enter` to
save. After a brief **Saved** confirmation, the popup closes automatically.
The action popup uses a compact width and an internal vertical scroller so its
controls remain reachable on shorter displays.

The extension always requests only `activeTab`, `scripting`, `storage`, and
access to the fixed localhost backend. HTTP/HTTPS page access is optional,
explicit, and revocable. Turning inline capture off unregisters future behavior
and removes existing Recall controls from open tabs; toolbar capture continues
to work. A page restored from Chrome's back-forward cache rechecks the current
permission before inline behavior resumes, and the service worker checks it
again before accepting a content-script save.

Inline selection text remains inside the tab until **Save**. It is not written
to extension storage, logged, or sent merely because a selection exists. The
content script sends one frozen attempt to the extension service worker only
after Save; the worker performs the localhost request. `storage` retains only
an optional toolbar-note draft for the active tab and removes it after a
successful save. Toolbar and inline submissions share this same service-worker
validation and delivery path.

Both browser entry points currently set `surrounding_context` to an empty
string and `context_truncated` to `false`. With a selection they save its first
12,000 characters, title, URL, and optional note; selections within that shared
contract limit are not shortened, while longer ones receive the explicit
warning described above. Without a selection the toolbar saves title, URL, and optional
note. This is a deliberate reliability and privacy boundary after broad
`main`/`body` containers on a conversation SPA captured navigation and
unrelated history. The backend's 20,000-character context capability remains
unchanged. A future browser extractor must center on the selected DOM Range and
apply independent character plus line/block limits before this field is
re-enabled.

This selected-text flow saves text and metadata only. It does not capture,
attach, or persist page images; image attachments require a separate storage,
privacy, deletion, and migration design.

If no text is selected, the popup explains that it will save page metadata
without page text. If Recall is unavailable, the popup displays the required
recovery message instead of failing silently.

Both capture paths validate the shared Unicode-aware Capture limits before
submission. If a POST has an ambiguous failure, **Try again** reuses the exact
original source, note, timestamp, and `client_capture_id`; the frozen attempt
prevents a retry from silently changing an already-committed Capture. A local
validation or ordinary 4xx response is shown without offering a useless retry.

The backend persists the original source and note before AI enrichment. A
successful Save therefore remains a successful Capture even when OpenAI is not
configured and that Capture later displays an enrichment `error`; the original
text and note remain stored and retryable.

## Test

From this directory:

```bash
npm test
```

`pnpm test` or `node --test tests/*.test.mjs` runs the same dependency-free
suite when npm is not installed.

For isolated manual layout and scrolling checks, serve this repository over
HTTP and open
`tests/fixtures/inline-capture-standalone-harness.html?standalone=1`. That
fixture deliberately omits the strict CSP so an in-app browser can inspect the
real Shadow DOM controls. Use `inline-capture-harness.html` through the unpacked
extension for CSP and injection acceptance; the standalone fixture is not CSP
evidence.
