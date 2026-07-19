# Recall Layer 3 demo script

This is a truthful 90–120 second walkthrough of the currently implemented
vertical slice: real clipboard capture, durable backend storage, and macOS
display. It deliberately does not present AI enrichment, backend retrieval, or
Chrome capture as complete.

## Preflight (not part of the timed demo)

1. Start `services/backend` and confirm
   `curl --fail http://127.0.0.1:8765/health` succeeds.
2. Build Recall once, run it from Xcode, and confirm the main window says
   **Connected**.
3. Open TextEdit with this sample passage ready to select:

   > Set WorkingDirectory to the project directory before restarting the
   > service; otherwise Nginx can return 502 even when the app runs manually.

4. Have this note ready to type or paste:

   > This was the only VPS fix that worked; check the deployment path next time.

5. Keep Xcode ready to stop and rerun the already-built app. Do not seed mock
   data or open an AI-completed preview record for this Layer 3 demo.

## Timed walkthrough (about 118 seconds)

| Time | On screen | Suggested narration |
| --- | --- | --- |
| 0–8 s | Show Recall's main window and green **Connected** indicator. | “Recall turns something useful I see on my Mac into a durable contextual memory. This is today's real Layer 3 slice, connected to the local backend.” |
| 8–20 s | Switch to TextEdit, select the prepared passage, and copy it. | “I found a deployment fix that only makes sense with the reason I care about it.” |
| 20–35 s | Use the Recall menu-bar item and choose **Capture Clipboard**. Pause on the quick-capture form. | “Recall preserves the exact source text and best-effort source application, then asks only for the context that belongs to me.” |
| 35–50 s | Enter the prepared VPS note and press **Save**. | “The note stays separate from the source. Saving writes the original capture to SQLite before any future AI work.” |
| 50–72 s | Select the new first row. Point to `Processing`, **Your note**, **Original selection**, and **Source**. | “This response is live, not mock data. Layer 3 intentionally remains processing: the source and my note are already safe, while AI fields are still empty.” |
| 72–92 s | Quit Recall from its menu-bar menu, then rerun the prebuilt app from Xcode. Select the newest item after it reloads. | “The app has no hidden local copy. After a full relaunch it reads the same record back from the backend database.” |
| 92–108 s | Search for `VPS WorkingDirectory` and show the same item remains. If the fallback notice appears, leave it visible briefly. | “The current client can locally filter its loaded library when the search endpoint is absent. This is an explicit fallback, not the planned FTS or semantic search.” |
| 108–118 s | Clear the search and return to the detail. | “Developer 2's next integrations unlock structured AI enrichment, backend retrieval, and Chrome capture. The durable source-first foundation shown here is already working.” |

## Failure downgrade plan

Use the first applicable recovery. Keep the boundary statement in the
narration; do not replace a failed live capability with an unlabelled mock.

| Failure | Recovery during the demo | What to say |
| --- | --- | --- |
| Recall starts offline | Check the health URL, start or restart `services/backend`, then choose **Try Again** or **Refresh**. If it cannot recover within 15 seconds, switch to the backup recording. | “The macOS client depends on the loopback persistence service; it does not pretend an offline save succeeded.” |
| Clipboard form says nothing is available | Return to TextEdit, select the prepared plain text, press `Command-C`, and immediately choose **Capture Clipboard** again. | “The current stable path is explicit clipboard text.” |
| Source application says `Clipboard` instead of `TextEdit` | Continue; the captured text is authoritative. Mention that application detection is best effort. | “Source-app attribution is best effort in this layer; Accessibility and window-title capture are not connected yet.” |
| Save fails or spins | Leave the draft open, verify backend health, restart the service if needed, and press **Save** once more. Never say the record is durable until it appears in the list. | “Recall keeps the draft visible on transport failure and only confirms after backend persistence succeeds.” |
| Relaunch takes too long | Skip the relaunch. Refresh the app, then show `curl 'http://127.0.0.1:8765/v1/captures?limit=1&offset=0'` in the prepared terminal as persistence evidence. | “This newest record is being read from SQLite through the live list API.” |
| Search shows an availability notice or unexpected local results | Search one exact distinctive term such as `WorkingDirectory`, or omit the search segment and spend the time on source/note separation. | “Search here is only the client fallback over the newest 50 loaded records; backend ranking is not part of Layer 3.” |
| New capture never leaves `Processing` | Continue with the raw capture detail; this is the expected Layer 3 state. Do not press **Retry AI**. | “AI enrichment has not been connected yet, but failure or delay cannot erase the original capture.” |
| Asked to show AI, semantic search, or Chrome | Point to the populated source-first detail and state the ownership boundary. If available, reference the Developer 2 checklist rather than simulating the feature. | “Those capabilities unlock after Developer 2 connects Layers 4–7; this demo does not claim they are live today.” |

## After Developer 2 integration

Replace—not silently append—the fallback moments only after their exit gates
pass:

- Layer 4: wait for the same card to become `ready`, then show the generated
  title, contextual summary, memory details, and tags.
- Layer 5: replace the local-filter disclaimer with a real backend keyword
  search demonstration.
- Layer 6: begin from a Chrome selection that supplies URL, title, selection,
  and surrounding context.
- Layer 7: use a natural-language paraphrase only after hybrid retrieval is
  verified; until then, use exact terms and call the behavior keyword search.
