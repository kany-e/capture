# Recall demo script

This is a truthful 90–120 second walkthrough of the integrated product plus the
D-027 screenshot-to-note addition. It demonstrates GPT first, then the same
text-extraction step with Apple Vision on device. Screenshot images are never
presented as stored memories: only reviewed text enters Recall.

## Preflight

1. Run `./scripts/dev.sh`, confirm `/health` is healthy, and verify the untracked
   `OPENAI_API_KEY` has model access.
2. Build Recall with the gitignored local Apple Development signing override,
   then run `./scripts/verify-macos-signing.sh` against that exact app bundle.
   Do not use a `CODE_SIGNING_ALLOWED=NO` automation build for this rehearsal.
3. If this Mac still has an older ad-hoc Recall permission row, quit every
   Recall copy, run `tccutil reset ScreenCapture com.recall.macos`, launch the
   verified build, authorize it once, then quit and relaunch it.
4. Launch Recall and confirm **Connected · AI ready**.
5. Put this high-contrast text on screen for the screenshot region:

   > Keep screenshot images transient. Save only reviewed text and personal
   > context into the searchable memory pipeline.

6. Prepare a second region with `Recall Local Vision 2026` for the locality
   comparison.
7. Repeat the physical screenshot shortcut from another app and drag a non-empty
   region as a private pre-demo rehearsal. D-032 verifies that permission
   survives a same-signer rebuild, and B-014 already records a successful
   real-device interaction.

## Timed walkthrough

| Time | On screen | Suggested narration |
| --- | --- | --- |
| 0–10 s | Show the Recall library and **Connected · AI ready**. | “Recall preserves what I found, why it matters to me, and an AI interpretation as separate searchable layers.” |
| 10–24 s | Choose **Capture Screenshot Note** and drag over the prepared sentence. | “For information I cannot select normally, I can capture just one screen region.” |
| 24–38 s | Pause on the preview and **GPT · Cloud** label, then choose **Extract source text**. | “GPT is the default. Recall shows the image and processing boundary before anything is sent, and extraction happens only when I ask.” |
| 38–52 s | Show the exact extracted source, add a separate personal note, then save. | “The image is temporary. Reviewed source text and my own context stay separate in the same local SQLite, enrichment, and retrieval pipeline.” |
| 52–68 s | Open the new card, show **Your note** and **Extracted source text**, then search for a paraphrase once it is ready. | “There is no screenshot database to drift from the rest of the product. The text becomes an ordinary memory with structured understanding and hybrid retrieval.” |
| 68–84 s | Start a second screenshot, select **Apple Vision · On device**, and turn Wi-Fi off before extracting. | “The identical step can also run with Apple Vision. The image stays on this Mac and no OCR request reaches the backend.” |
| 84–100 s | Extract `Recall Local Vision 2026`, show **Processed on this Mac**, then cancel the draft and turn Wi-Fi back on. | “Locality is visible and testable, not a hidden implementation detail. Cancel clears the temporary image and saves nothing.” |
| 100–112 s | Return to the GPT-created memory and its search result. | “GPT remains the primary judged workflow; local intelligence is a privacy-preserving alternative behind the same experience.” |

## Optional D-031 global-capture pickup

The current stable build has closed B-014: with Recall's main window closed and
another app focused, `Option+Shift+Command+4` completed a non-empty screenshot
region, and `Option+Shift+Command+C` opened clipboard Quick Capture after text
was copied. Before recording, repeat both checks as a private rehearsal and
confirm Screen Recording permission remains effective.

With that gate passed, the 10–24 second step may begin with the screenshot
shortcut instead of the menu command. Briefly show **Shortcut Settings…** only
if there is time: the defaults, enable switches, and restore-defaults action are
more useful than describing Carbon. If either physical shortcut or the system
overlay is unreliable, keep the menu-bar path in the main walkthrough and do
not claim the global-key flow was demonstrated.

## Failure downgrade plan

| Failure | Safe recovery | Truthful narration |
| --- | --- | --- |
| macOS reports permission missing and Recall is disabled in System Settings | Open **Privacy & Security > Screen & System Audio Recording**, allow the verified Recall build, relaunch, and use the backup recording if the delay exceeds 15 seconds. | “Interactive screen selection requires normal macOS recording permission.” |
| System Settings shows Recall enabled but capture still reports permission missing | Stop the demo path. Verify the running bundle with `scripts/verify-macos-signing.sh`; if it is temporary/ad-hoc, rebuild with the local Apple Development identity. Quit all Recall copies, reset only `ScreenCapture` for `com.recall.macos`, reauthorize the verified app once, and relaunch. | “This build did not match the older permission identity, so I am using the stable signed build rather than claiming the toggle alone is sufficient.” |
| GPT returns `openai_not_configured` or another stable OCR error | Switch the same draft to **Apple Vision · On device** and extract locally; do not claim GPT succeeded. | “The cloud extractor is unavailable, so Recall keeps the screenshot draft local and offers the on-device path.” |
| No text is found | Select the prepared high-contrast region again. | “Recall does not fabricate a note when an extractor finds no usable text.” |
| Extracted text exceeds the source limit | Capture a smaller region. Never accept a silently truncated result. | “One extracted source is bounded to 12,000 characters so the reviewed text is preserved exactly.” |
| Save or enrichment fails | Keep the draft visible and check backend health. If creation succeeded but enrichment failed, show the source-preserving error and retry later. | “Persistence is local and precedes AI processing; a provider failure cannot delete the source or note.” |
| Apple Vision works but save fails while Wi-Fi is off | Turn Wi-Fi back on and save only after extraction, or cancel the draft. | “Extraction is local; the normal Capture pipeline still uses the loopback backend, and later AI enrichment may use OpenAI.” |

## Claims to avoid

- Do not say Recall stores or retrieves screenshot images; D-027 stores text
  only.
- Do not describe Apple Vision OCR as local AI enrichment or local semantic
  search; those remain separately gated by D-008.
- Do not hide the GPT/cloud label, permission prompt, provider failure, or
  source-preserving error state.
