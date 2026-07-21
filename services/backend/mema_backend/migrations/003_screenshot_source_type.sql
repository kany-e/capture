DROP TRIGGER captures_fts_after_insert;
DROP TRIGGER captures_fts_after_update;
DROP TRIGGER captures_fts_after_delete;
DROP TABLE captures_fts;

ALTER TABLE captures RENAME TO captures_before_screenshot_source;

CREATE TABLE captures (
    id TEXT PRIMARY KEY,
    client_capture_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    captured_at TEXT,
    status TEXT NOT NULL CHECK (
        status IN ('captured', 'processing', 'ready', 'error')
    ),
    source_type TEXT NOT NULL CHECK (
        source_type IN ('web', 'clipboard', 'screenshot')
    ),
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

INSERT INTO captures (
    id, client_capture_id, created_at, updated_at, captured_at, status,
    source_type, source_app, source_title, source_url, selected_text,
    surrounding_context, context_truncated, user_note, ai_title, ai_summary,
    problem, key_insight, why_saved, caveats_json, tags_json, entities_json,
    search_aliases_json, embedding_json, error_message, enrichment_version
)
SELECT
    id, client_capture_id, created_at, updated_at, captured_at, status,
    source_type, source_app, source_title, source_url, selected_text,
    surrounding_context, context_truncated, user_note, ai_title, ai_summary,
    problem, key_insight, why_saved, caveats_json, tags_json, entities_json,
    search_aliases_json, embedding_json, error_message, enrichment_version
FROM captures_before_screenshot_source;

DROP TABLE captures_before_screenshot_source;
CREATE INDEX captures_created_at_idx ON captures(created_at DESC);

CREATE VIRTUAL TABLE captures_fts USING fts5(
    capture_id UNINDEXED,
    source_title,
    selected_text,
    surrounding_context,
    user_note,
    ai_title,
    ai_summary,
    problem,
    key_insight,
    why_saved,
    tags,
    entities,
    search_aliases
);

CREATE TRIGGER captures_fts_after_insert
AFTER INSERT ON captures
BEGIN
    INSERT INTO captures_fts (
        capture_id, source_title, selected_text, surrounding_context,
        user_note, ai_title, ai_summary, problem, key_insight, why_saved,
        tags, entities, search_aliases
    ) VALUES (
        NEW.id, COALESCE(NEW.source_title, ''), NEW.selected_text,
        COALESCE(NEW.surrounding_context, ''), COALESCE(NEW.user_note, ''),
        COALESCE(NEW.ai_title, ''), COALESCE(NEW.ai_summary, ''),
        COALESCE(NEW.problem, ''), COALESCE(NEW.key_insight, ''),
        COALESCE(NEW.why_saved, ''), NEW.tags_json, NEW.entities_json,
        NEW.search_aliases_json
    );
END;

CREATE TRIGGER captures_fts_after_update
AFTER UPDATE ON captures
BEGIN
    DELETE FROM captures_fts WHERE capture_id = OLD.id;
    INSERT INTO captures_fts (
        capture_id, source_title, selected_text, surrounding_context,
        user_note, ai_title, ai_summary, problem, key_insight, why_saved,
        tags, entities, search_aliases
    ) VALUES (
        NEW.id, COALESCE(NEW.source_title, ''), NEW.selected_text,
        COALESCE(NEW.surrounding_context, ''), COALESCE(NEW.user_note, ''),
        COALESCE(NEW.ai_title, ''), COALESCE(NEW.ai_summary, ''),
        COALESCE(NEW.problem, ''), COALESCE(NEW.key_insight, ''),
        COALESCE(NEW.why_saved, ''), NEW.tags_json, NEW.entities_json,
        NEW.search_aliases_json
    );
END;

CREATE TRIGGER captures_fts_after_delete
AFTER DELETE ON captures
BEGIN
    DELETE FROM captures_fts WHERE capture_id = OLD.id;
END;

INSERT INTO captures_fts (
    capture_id, source_title, selected_text, surrounding_context,
    user_note, ai_title, ai_summary, problem, key_insight, why_saved,
    tags, entities, search_aliases
)
SELECT
    id, COALESCE(source_title, ''), selected_text,
    COALESCE(surrounding_context, ''), COALESCE(user_note, ''),
    COALESCE(ai_title, ''), COALESCE(ai_summary, ''),
    COALESCE(problem, ''), COALESCE(key_insight, ''),
    COALESCE(why_saved, ''), tags_json, entities_json, search_aliases_json
FROM captures;
