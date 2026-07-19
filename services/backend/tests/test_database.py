from __future__ import annotations

from pathlib import Path

from app.database import MIGRATIONS_DIRECTORY, apply_migrations, database_connection


def test_migrations_are_idempotent_and_complete(tmp_path: Path) -> None:
    database_path = tmp_path / "recall.db"

    assert apply_migrations(database_path) == 2
    assert apply_migrations(database_path) == 2

    with database_connection(database_path) as connection:
        tables = {
            row["name"]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        columns = {
            row["name"] for row in connection.execute("PRAGMA table_info(captures)")
        }
        fts_columns = [
            row["name"]
            for row in connection.execute("PRAGMA table_info(captures_fts)")
        ]
        applied = connection.execute(
            "SELECT version, name FROM schema_migrations ORDER BY version"
        ).fetchall()
        triggers = {
            row["name"]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'trigger'"
            )
        }

    assert {"captures", "captures_fts", "schema_migrations"}.issubset(tables)
    assert {
        "client_capture_id",
        "context_truncated",
        "caveats_json",
        "embedding_json",
        "enrichment_version",
    }.issubset(columns)
    assert fts_columns == [
        "capture_id",
        "source_title",
        "selected_text",
        "surrounding_context",
        "user_note",
        "ai_title",
        "ai_summary",
        "problem",
        "key_insight",
        "why_saved",
        "tags",
        "entities",
        "search_aliases",
    ]
    assert [(row["version"], row["name"]) for row in applied] == [
        (1, "initial_captures"),
        (2, "fts5_keyword_search"),
    ]
    assert triggers == {
        "captures_fts_after_insert",
        "captures_fts_after_update",
        "captures_fts_after_delete",
    }


def test_fts_migration_backfills_existing_capture(tmp_path: Path) -> None:
    database_path = tmp_path / "legacy.db"
    initial_sql = (
        MIGRATIONS_DIRECTORY / "001_initial_captures.sql"
    ).read_text(encoding="utf-8")
    with database_connection(database_path) as connection:
        connection.executescript(initial_sql)
        connection.execute(
            """
            CREATE TABLE schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            "INSERT INTO schema_migrations VALUES (1, 'initial_captures', 'now')"
        )
        connection.execute(
            """
            INSERT INTO captures (
                id, created_at, updated_at, captured_at, status,
                source_type, selected_text, user_note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "legacy-capture",
                "2026-07-18T19:00:00.000000Z",
                "2026-07-18T19:00:00.000000Z",
                "2026-07-18T12:00:00-07:00",
                "error",
                "clipboard",
                "Legacy raw keyword remains searchable",
                "Migration backfill proof",
            ),
        )
        connection.commit()

    assert apply_migrations(database_path) == 2

    with database_connection(database_path) as connection:
        row = connection.execute(
            """
            SELECT capture_id
            FROM captures_fts
            WHERE captures_fts MATCH '"legacy"'
            """
        ).fetchone()

    assert row is not None
    assert row["capture_id"] == "legacy-capture"
