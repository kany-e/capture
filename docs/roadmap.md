# Mema roadmap

Last updated: 2026-07-21

Mema's Build Week submission scope is implemented on `main`. The original
product plan is preserved as historical context in
[`product-plan.md`](product-plan.md); accepted architecture and scope changes
remain in [`decisions.md`](decisions.md).

## Submission baseline

- Local FastAPI service with loopback-only binding, SQLite migrations, FTS5,
  attachments, strict input limits, and source-preserving async enrichment.
- GPT-5.6 Structured Outputs for text memories and opt-in image understanding.
- Separate `text-embedding-3-small` embeddings with keyword-only fallback.
- SwiftUI/AppKit macOS app with in-app, global selection, clipboard, screenshot
  text, screenshot image, editing, library, and hybrid search flows.
- Build-free Manifest V3 Chrome extension with toolbar, keyboard, and opt-in
  inline selected-text capture.
- Layered CI and deterministic backend, stress, extension, and macOS suites.
- Explicit privacy controls, `store: false` provider calls, exact Chrome-origin
  allowlisting, and owner-only local database permissions.

## Submission gates

- [x] Root setup instructions
- [x] GPT-5.6 and Codex usage documented
- [x] Chrome extension installation and judge testing path
- [x] Mema naming across app, extension, backend, contracts, and docs
- [x] Automated tests run without secrets or provider traffic
- [x] Rename the GitHub repository to `CamaroW/Mema` and update the local remote
- [ ] Record or attach final demo media in the Build Week submission form
- [x] Add the MIT License for public reuse

## Known prototype boundaries

- No account system, cloud sync, or team collaboration
- No remote/LAN backend binding
- No durable distributed enrichment queue
- No App Store packaging or notarization
- Chrome captures selected text and page metadata, not full-page DOM context or
  browser screenshots
- Swift screenshot preflight checks the byte limit; the backend remains the
  authority for image dimensions, pixel count, and file validity

## After Build Week

1. Choose the distribution model and release channel.
2. Package and notarize one canonical Applications-directory build.
3. Add a safe upgrade assistant for legacy local database/config names if this
   prototype gains external users.
4. Add full image decoding and request-level multipart limits before accepting
   untrusted or remote clients.
5. Add migration checksums and a locked release dependency set.
6. Consider opt-in sync only after encryption, deletion, and account boundaries
   are designed.

## Documentation authority

- [`README.md`](../README.md): setup and judge entry point
- [`judge-walkthrough.md`](judge-walkthrough.md): manual acceptance path
- [`architecture.md`](architecture.md): current system boundaries
- [`decisions.md`](decisions.md): why important choices were made
- [`product-plan.md`](product-plan.md): historical Build Week baseline
- [`backend-stress-report-2026-07-18.md`](backend-stress-report-2026-07-18.md):
  dated backend hardening snapshot
