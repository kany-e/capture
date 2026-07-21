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

## Enable inline selection capture

The toolbar and keyboard paths continue to work with narrow `activeTab`
access. Inline selection capture is optional:

1. Open the Recall toolbar popup.
2. Enable **Show Add to REcall when I select text**.
3. Approve optional HTTP and HTTPS website access.
4. Select text on a supported page and choose **Add to REcall**.
5. Add an optional comment, then choose **Save Memory**.

The action does not take focus and disappears after four seconds, a selection
change, scroll, outside click, Escape, or tab blur. The comment field takes
focus only after the action is activated. Press `Command+Enter` or
`Control+Enter` to save.

The selected source and page context stay inside the tab until **Save Memory**
is chosen. Disabling the setting revokes optional website access, unregisters
the content script, and removes inline controls from already-open tabs. The
toolbar and keyboard paths remain available.

Phase 2 supports ordinary top-level HTTP and HTTPS page text. Chrome internal
pages, the built-in PDF viewer, cross-origin frames, canvas-based editors, and
form or editable selections are deliberately excluded.

For the keyboard-first path, press `Command+Shift+Y` on macOS or
`Control+Shift+Y` on other platforms. Chrome may reserve or override suggested
shortcuts; confirm or customize Recall's binding at `chrome://extensions/shortcuts`.
The popup focuses the optional note. Press `Command+Enter` or `Control+Enter` to
save. After a brief **Saved** confirmation, the popup closes automatically.

The extension's required permissions remain `activeTab`, `scripting`,
`storage`, and access to the fixed localhost backend. HTTP and HTTPS website
access is declared as optional and requested only when the inline setting is
enabled. `storage` retains an optional toolbar note draft for the active tab and
removes it after a successful save; selected source content is never cached.

If no text is selected, the popup warns that it will save limited page context.
If Recall is unavailable, the popup displays the required recovery message
instead of failing silently.

The popup validates the shared Capture limits before submission. If a POST has
an ambiguous failure, **Try again** reuses the original request and
`client_capture_id` while that popup remains open; the source and note are locked
so a retry cannot silently change an already-committed Capture. Successful saves
clear the optional note draft as before.

Toolbar, keyboard, and inline saves share one extension service-worker
coordinator. It validates runtime messages, freezes the original source, note,
timestamp, and `client_capture_id`, and maps localhost/API failures to the same
recovery states before using the existing `POST /v1/captures` contract.

## Test

From this directory:

```bash
npm test
```

`pnpm test` or `node --test tests/*.test.mjs` runs the same dependency-free
suite when npm is not installed.
