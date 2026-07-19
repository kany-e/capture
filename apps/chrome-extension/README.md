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

The extension requests only `activeTab`, `scripting`, `storage`, and access to
the fixed localhost backend. It injects extraction code only after the toolbar
action. `storage` retains an optional note draft for the active tab and removes
it after a successful save; selected source content is not cached.

If no text is selected, the popup warns that it will save limited page context.
If Recall is unavailable, the popup displays the required recovery message
instead of failing silently.

## Test

From this directory:

```bash
npm test
```

`pnpm test` or `node --test tests/*.test.mjs` runs the same dependency-free
suite when npm is not installed.
