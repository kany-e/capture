# Repository integration history

Last updated: 2026-07-19

This file records how Recall's implementation branches were combined. It is a
history and audit aid, not a list of branches required to run the product.

## Canonical branch scope

`main` is again the canonical runnable integration target. Its tree contains:

- the macOS client under `apps/macos/`;
- the Chrome extension under `apps/chrome-extension/`;
- the complete backend under `services/backend/`;
- shared contracts under `contracts/`; and
- current project documentation under `docs/`.

D-019 records the temporary documentation-only `main` arrangement. D-023
supersedes that exception and restores the product-plan rule that the main
branch contain the integrated product.

## Historical implementation checkpoints

| Branch | Tip | Purpose |
| --- | --- | --- |
| `layer/1-backend-foundation` | `fb7be35` | FastAPI configuration and health foundation |
| `layer/2-sqlite-storage` | `0622ad0` | SQLite migrations, repository, and live checklist dashboard |
| `layer/3-capture-api` | `17264fe` | Capture create, list, and detail API |
| `layer/4-ai-enrichment` | `e24fe4d` | OpenAI enrichment boundary |
| `layer/5-keyword-retrieval` | `8754c9d` | FTS5 keyword retrieval |
| `layer/6-chrome-capture` | `d426ca8` | Manifest V3 extension and strict local CORS |
| `layer/7-hybrid-retrieval` | `faa45d7` | Embeddings and hybrid retrieval |
| `integration/layers-6-7` | `3389bae` | Combined Developer B runtime |
| `test/backend-stress` | `0c9a52f` | Reproducible backend stress harness and report |
| `fix/backend-stress-hardening` | `5ea3d2a` | Fixes for all 13 stress-finding groups |
| `codex/macos-client` | `12862d3` | SwiftUI/AppKit macOS client |

Layers 1–5 are stacked in order. The isolated Layer 6 and Layer 7 branches are
siblings based on Layer 5. `integration/layers-6-7` contains their already
resolved combined runtime; `test/backend-stress` and
`fix/backend-stress-hardening` continue from that combined checkpoint.

## Final tree composition

The final integration deliberately combines trees instead of relying on a
plain merge with the former documentation-only `main`:

- `services/` and `apps/chrome-extension/` come from
  `fix/backend-stress-hardening`;
- `apps/macos/` comes from `codex/macos-client`;
- the hardened contracts shared by the backend and current documentation are
  retained; and
- merge commits preserve the main, hardening, and macOS histories.

This explicit composition was necessary because the historical D-019 commit
deleted `apps/` and `services/` from `main`. A normal three-way merge would have
kept some of those deletions for files unchanged on the hardening branch.

## Verification state

The assembled tree passes 186 backend tests, all 44 deterministic stress
scenarios, 13 extension tests, and 27 macOS tests. Provider-off keyword search,
real OpenAI enrichment and embeddings, semantic retrieval, unpacked Chrome
selected-text and no-selection capture, and macOS display all pass against the
integrated tree. Earlier branch-level results remain historical evidence, while
these counts describe the current integration.

The shared live gates B-007, B-008, and B-009 are resolved. Final submission
artifacts and release packaging remain Layer 10 work.

## Retiring old branch names

After integrated `main` is independently smoke-tested, historical remote branch
names may be deleted without removing commits that are ancestors of `main`.
The isolated Layer 6 commit `d426ca8` and Layer 7 commit `faa45d7` are not
ancestors of the combined checkpoint, so create archival tags first if their
exact sibling commit identities must remain permanently addressable.
