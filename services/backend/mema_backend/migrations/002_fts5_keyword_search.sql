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
