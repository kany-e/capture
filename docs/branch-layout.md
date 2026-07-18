# Repository branch layout

Last updated: 2026-07-18

This file defines the user-directed branch separation introduced after Layers
1–7 were developed. It is the central map for locating implementation code.

## Main branch scope

The current `main` tree contains only shared project material:

- root metadata: `.env.example`, `.gitignore`, `Project_Outline (GPT).md`, and
  `README.md`;
- shared request, response, schema, and example files under `contracts/`; and
- product descriptions, architecture, decisions, handoffs, and checklists under
  `docs/`.

`apps/` and `services/` are intentionally absent from the current `main` tree.
Their earlier commits remain in Git history and are retained by the branches
below. No existing commit was rewritten or force-updated.

## Implementation branches

| Branch | Tip | Purpose |
| --- | --- | --- |
| `layer/1-backend-foundation` | `fb7be35` | FastAPI configuration and health foundation |
| `layer/2-sqlite-storage` | `0622ad0` | SQLite migrations, repository, and live checklist dashboard |
| `layer/3-capture-api` | `17264fe` | Capture create, list, and detail API |
| `layer/4-ai-enrichment` | `e24fe4d` | OpenAI enrichment boundary and delivery-status documentation |
| `layer/5-keyword-retrieval` | `8754c9d` | FTS5 keyword retrieval and its delivery-status documentation |
| `layer/6-chrome-capture` | `d426ca8` | Manifest V3 extension and strict local CORS |
| `layer/7-hybrid-retrieval` | `faa45d7` | Embeddings and hybrid retrieval |
| `integration/layers-6-7` | `3389bae` | Validated combined Developer B runtime at backend 0.7.0 |
| `codex/macos-client` | `12862d3` on `origin` | Developer A's macOS client; left untouched |

The branches are dependency checkpoints, not unrelated orphan trees. Layers
1–5 are stacked in order. Layers 6 and 7 are siblings based on Layer 5 so the
Chrome/CORS delta and embeddings/search delta remain independently reviewable.
Consequently, a later branch includes its prerequisite commits in its history.

A merge-tree audit found expected content conflicts when the Layer 6 and Layer
7 siblings are merged directly: both update `services/backend/app/main.py` and
`services/backend/README.md`. `integration/layers-6-7` preserves the exact
already-resolved combined state that passed 165 backend and 13 extension tests.
Use the sibling branches for focused review and the integration branch for the
combined Developer B runtime.

## Integration consequence

The product plan originally required `main` to remain runnable. A documentation-
only `main` cannot satisfy that requirement; D-019 records this explicit
user-directed exception. Before Layer 8 or the final demo can be called
integrated, the team must either restore a runnable `main` or create and agree
on a separate integration branch that combines all required implementation.
The local `integration/layers-6-7` branch combines Developer B's work, but it
does not yet include Developer A's macOS client and has not been pushed or
accepted as the final team integration branch.
