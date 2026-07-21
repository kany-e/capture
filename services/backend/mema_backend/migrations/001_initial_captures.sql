CREATE TABLE captures (
    id TEXT PRIMARY KEY,
    client_capture_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    captured_at TEXT,
    status TEXT NOT NULL CHECK (
        status IN ('captured', 'processing', 'ready', 'error')
    ),
    source_type TEXT NOT NULL CHECK (source_type IN ('web', 'clipboard')),
    source_app TEXT,
    source_title TEXT,
    source_url TEXT,
    selected_text TEXT NOT NULL,
    surrounding_context TEXT,
    context_truncated INTEGER NOT NULL DEFAULT 0 CHECK (
        context_truncated IN (0, 1)
    ),
    user_note TEXT,
    ai_title TEXT,
    ai_summary TEXT,
    problem TEXT,
    key_insight TEXT,
    why_saved TEXT,
    caveats_json TEXT NOT NULL DEFAULT '[]',
    tags_json TEXT NOT NULL DEFAULT '[]',
    entities_json TEXT NOT NULL DEFAULT '[]',
    search_aliases_json TEXT NOT NULL DEFAULT '[]',
    embedding_json TEXT,
    error_message TEXT,
    enrichment_version INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX captures_created_at_idx ON captures(created_at DESC);
