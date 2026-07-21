ALTER TABLE captures ADD COLUMN user_edited_at TEXT;
ALTER TABLE captures ADD COLUMN user_selected_text TEXT;
ALTER TABLE captures ADD COLUMN user_source_app TEXT;
ALTER TABLE captures ADD COLUMN user_source_title TEXT;
ALTER TABLE captures ADD COLUMN user_source_url TEXT;
ALTER TABLE captures ADD COLUMN user_title TEXT;
ALTER TABLE captures ADD COLUMN user_problem TEXT;
ALTER TABLE captures ADD COLUMN user_key_insight TEXT;
ALTER TABLE captures ADD COLUMN user_why_saved TEXT;
ALTER TABLE captures ADD COLUMN user_caveats_json TEXT;
ALTER TABLE captures ADD COLUMN user_tags_json TEXT;
ALTER TABLE captures ADD COLUMN ai_interpretation_hidden INTEGER NOT NULL DEFAULT 0
    CHECK (ai_interpretation_hidden IN (0, 1));
ALTER TABLE captures ADD COLUMN ai_content_stale INTEGER NOT NULL DEFAULT 0
    CHECK (ai_content_stale IN (0, 1));

CREATE INDEX captures_user_edited_at_idx
ON captures(user_edited_at DESC);

DROP TRIGGER captures_fts_after_insert;
DROP TRIGGER captures_fts_after_update;

CREATE TRIGGER captures_fts_after_insert
AFTER INSERT ON captures
BEGIN
    INSERT INTO captures_fts (
        capture_id, source_title, selected_text, surrounding_context,
        user_note, ai_title, ai_summary, problem, key_insight, why_saved,
        tags, entities, search_aliases
    ) VALUES (
        NEW.id, COALESCE(NEW.user_source_title, NEW.source_title, ''),
        COALESCE(NEW.user_selected_text, NEW.selected_text),
        COALESCE(NEW.surrounding_context, ''), COALESCE(NEW.user_note, ''),
        COALESCE(
            NEW.user_title,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.ai_title END,
            ''
        ),
        CASE WHEN NEW.ai_content_stale = 0 THEN COALESCE(NEW.ai_summary, '') ELSE '' END,
        COALESCE(
            NEW.user_problem,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.problem END,
            ''
        ),
        COALESCE(
            NEW.user_key_insight,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.key_insight END,
            ''
        ),
        COALESCE(
            NEW.user_why_saved,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.why_saved END,
            ''
        ),
        COALESCE(
            NEW.user_tags_json,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.tags_json END,
            '[]'
        ),
        CASE WHEN NEW.ai_content_stale = 0 THEN NEW.entities_json ELSE '[]' END,
        CASE WHEN NEW.ai_content_stale = 0 THEN NEW.search_aliases_json ELSE '[]' END
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
        NEW.id, COALESCE(NEW.user_source_title, NEW.source_title, ''),
        COALESCE(NEW.user_selected_text, NEW.selected_text),
        COALESCE(NEW.surrounding_context, ''), COALESCE(NEW.user_note, ''),
        COALESCE(
            NEW.user_title,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.ai_title END,
            ''
        ),
        CASE WHEN NEW.ai_content_stale = 0 THEN COALESCE(NEW.ai_summary, '') ELSE '' END,
        COALESCE(
            NEW.user_problem,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.problem END,
            ''
        ),
        COALESCE(
            NEW.user_key_insight,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.key_insight END,
            ''
        ),
        COALESCE(
            NEW.user_why_saved,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.why_saved END,
            ''
        ),
        COALESCE(
            NEW.user_tags_json,
            CASE WHEN NEW.ai_content_stale = 0 THEN NEW.tags_json END,
            '[]'
        ),
        CASE WHEN NEW.ai_content_stale = 0 THEN NEW.entities_json ELSE '[]' END,
        CASE WHEN NEW.ai_content_stale = 0 THEN NEW.search_aliases_json ELSE '[]' END
    );
END;

DELETE FROM captures_fts;
INSERT INTO captures_fts (
    capture_id, source_title, selected_text, surrounding_context,
    user_note, ai_title, ai_summary, problem, key_insight, why_saved,
    tags, entities, search_aliases
)
SELECT
    id, COALESCE(user_source_title, source_title, ''),
    COALESCE(user_selected_text, selected_text),
    COALESCE(surrounding_context, ''), COALESCE(user_note, ''),
    COALESCE(
        user_title,
        CASE WHEN ai_content_stale = 0 THEN ai_title END,
        ''
    ),
    CASE WHEN ai_content_stale = 0 THEN COALESCE(ai_summary, '') ELSE '' END,
    COALESCE(
        user_problem,
        CASE WHEN ai_content_stale = 0 THEN problem END,
        ''
    ),
    COALESCE(
        user_key_insight,
        CASE WHEN ai_content_stale = 0 THEN key_insight END,
        ''
    ),
    COALESCE(
        user_why_saved,
        CASE WHEN ai_content_stale = 0 THEN why_saved END,
        ''
    ),
    COALESCE(
        user_tags_json,
        CASE WHEN ai_content_stale = 0 THEN tags_json END,
        '[]'
    ),
    CASE WHEN ai_content_stale = 0 THEN entities_json ELSE '[]' END,
    CASE WHEN ai_content_stale = 0 THEN search_aliases_json ELSE '[]' END
FROM captures;
