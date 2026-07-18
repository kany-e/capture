"""Transactional SQLite repository for Recall Capture records."""

from __future__ import annotations

import json
import sqlite3
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, get_args
from uuid import uuid4

from app.database import apply_migrations, database_connection
from app.models import (
    CaptureRecord,
    CaptureStatus,
    EnrichmentUpdate,
    NewCapture,
)
from app.search import (
    KeywordSearchMatch,
    build_fts_match_query,
    normalize_keyword_matches,
)


VALID_CAPTURE_STATUSES = frozenset(get_args(CaptureStatus))
FTS_CANDIDATE_MULTIPLIER = 5
FTS_MAX_CANDIDATES = 500


class CaptureNotFoundError(LookupError):
    """Raised when an update targets a missing Capture."""


class CaptureAlreadyProcessingError(RuntimeError):
    """Raised when an enrichment claim targets an active Capture."""


class CorruptCaptureError(RuntimeError):
    """Raised when persisted JSON cannot be decoded into the storage contract."""


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _encode_json(value: list[Any] | None) -> str | None:
    if value is None:
        return None
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _decode_list(value: str, column: str) -> list[Any]:
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError as error:
        raise CorruptCaptureError(f"Invalid JSON in {column}") from error
    if not isinstance(decoded, list):
        raise CorruptCaptureError(f"Expected a JSON array in {column}")
    return decoded


def _row_to_record(row: sqlite3.Row) -> CaptureRecord:
    embedding = (
        None
        if row["embedding_json"] is None
        else _decode_list(row["embedding_json"], "embedding_json")
    )
    return CaptureRecord(
        id=row["id"],
        client_capture_id=row["client_capture_id"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        captured_at=row["captured_at"],
        status=row["status"],
        source_type=row["source_type"],
        source_app=row["source_app"],
        source_title=row["source_title"],
        source_url=row["source_url"],
        selected_text=row["selected_text"],
        surrounding_context=row["surrounding_context"],
        context_truncated=bool(row["context_truncated"]),
        user_note=row["user_note"],
        ai_title=row["ai_title"],
        ai_summary=row["ai_summary"],
        problem=row["problem"],
        key_insight=row["key_insight"],
        why_saved=row["why_saved"],
        caveats=_decode_list(row["caveats_json"], "caveats_json"),
        tags=_decode_list(row["tags_json"], "tags_json"),
        entities=_decode_list(row["entities_json"], "entities_json"),
        search_aliases=_decode_list(
            row["search_aliases_json"], "search_aliases_json"
        ),
        embedding=embedding,
        error_message=row["error_message"],
        enrichment_version=row["enrichment_version"],
    )


class CaptureRepository:
    def __init__(
        self,
        database_path: Path,
        *,
        clock: Callable[[], datetime] = _utc_now,
        initialize: bool = True,
    ) -> None:
        self.database_path = database_path
        self._clock = clock
        if initialize:
            apply_migrations(database_path)

    def _timestamp(self) -> str:
        now = self._clock()
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("Repository clock must return a timezone-aware datetime")
        return (
            now.astimezone(timezone.utc)
            .isoformat(timespec="microseconds")
            .replace("+00:00", "Z")
        )

    def create(
        self,
        capture: NewCapture,
        *,
        status: CaptureStatus = "captured",
    ) -> CaptureRecord:
        if status not in VALID_CAPTURE_STATUSES:
            raise ValueError(f"Invalid Capture status: {status}")

        capture_id = str(uuid4())
        now = self._timestamp()
        values = (
            capture_id,
            capture.client_capture_id,
            now,
            now,
            capture.captured_at,
            status,
            capture.source_type,
            capture.source_app,
            capture.source_title,
            capture.source_url,
            capture.selected_text,
            capture.surrounding_context,
            int(capture.context_truncated),
            capture.user_note,
        )

        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                connection.execute(
                    """
                    INSERT INTO captures (
                        id, client_capture_id, created_at, updated_at, captured_at,
                        status, source_type, source_app, source_title, source_url,
                        selected_text, surrounding_context, context_truncated,
                        user_note
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    values,
                )
                row = connection.execute(
                    "SELECT * FROM captures WHERE id = ?", (capture_id,)
                ).fetchone()
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        if row is None:  # pragma: no cover - SQLite returned a successful insert.
            raise RuntimeError("Capture insert completed without a readable row")
        return _row_to_record(row)

    def get(self, capture_id: str) -> CaptureRecord | None:
        with database_connection(self.database_path) as connection:
            row = connection.execute(
                "SELECT * FROM captures WHERE id = ?", (capture_id,)
            ).fetchone()
        return None if row is None else _row_to_record(row)

    def list_captures(self, *, limit: int, offset: int) -> list[CaptureRecord]:
        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                """
                SELECT * FROM captures
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
                """,
                (limit, offset),
            ).fetchall()
        return [_row_to_record(row) for row in rows]

    def search_captures(
        self,
        *,
        query: str,
        limit: int,
    ) -> list[KeywordSearchMatch]:
        normalized_query = query.strip()
        if not normalized_query:
            return [
                KeywordSearchMatch(capture=record, keyword_score=0.0)
                for record in self.list_captures(limit=limit, offset=0)
            ]

        candidate_limit = min(
            max(limit * FTS_CANDIDATE_MULTIPLIER, limit),
            FTS_MAX_CANDIDATES,
        )
        match_query = build_fts_match_query(normalized_query)
        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                """
                SELECT captures.*,
                    bm25(
                        captures_fts,
                        0.0, 6.0, 5.0, 2.0, 4.0, 6.0, 3.0,
                        4.0, 5.0, 3.0, 6.0, 6.0, 5.0
                    ) AS fts_rank
                FROM captures_fts
                JOIN captures ON captures.id = captures_fts.capture_id
                WHERE captures_fts MATCH ?
                ORDER BY fts_rank ASC, captures.created_at DESC
                LIMIT ?
                """,
                (match_query, candidate_limit),
            ).fetchall()

        candidates = [
            (_row_to_record(row), max(0.0, -float(row["fts_rank"])))
            for row in rows
        ]
        return normalize_keyword_matches(
            candidates,
            query=normalized_query,
            limit=limit,
        )

    def claim_enrichment(self, capture_id: str) -> CaptureRecord:
        """Atomically move a non-processing Capture into processing state."""

        updated_at = self._timestamp()
        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                cursor = connection.execute(
                    """
                    UPDATE captures
                    SET status = 'processing', updated_at = ?,
                        ai_title = NULL, ai_summary = NULL, problem = NULL,
                        key_insight = NULL, why_saved = NULL,
                        caveats_json = '[]', tags_json = '[]',
                        entities_json = '[]', search_aliases_json = '[]',
                        embedding_json = NULL, error_message = NULL
                    WHERE id = ? AND status != 'processing'
                    """,
                    (updated_at, capture_id),
                )
                row = connection.execute(
                    "SELECT * FROM captures WHERE id = ?", (capture_id,)
                ).fetchone()
                if row is None:
                    raise CaptureNotFoundError(capture_id)
                if cursor.rowcount != 1:
                    raise CaptureAlreadyProcessingError(capture_id)
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        return _row_to_record(row)

    def update_enrichment(
        self,
        capture_id: str,
        update: EnrichmentUpdate,
    ) -> CaptureRecord:
        updated_at = self._timestamp()
        values = (
            update.status,
            updated_at,
            update.ai_title,
            update.ai_summary,
            update.problem,
            update.key_insight,
            update.why_saved,
            _encode_json(update.caveats),
            _encode_json(update.tags),
            _encode_json(update.entities),
            _encode_json(update.search_aliases),
            _encode_json(update.embedding),
            update.error_message,
            update.enrichment_version,
            capture_id,
        )

        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                cursor = connection.execute(
                    """
                    UPDATE captures SET
                        status = ?, updated_at = ?, ai_title = ?, ai_summary = ?,
                        problem = ?, key_insight = ?, why_saved = ?,
                        caveats_json = ?, tags_json = ?, entities_json = ?,
                        search_aliases_json = ?, embedding_json = ?,
                        error_message = ?, enrichment_version = ?
                    WHERE id = ?
                    """,
                    values,
                )
                if cursor.rowcount != 1:
                    raise CaptureNotFoundError(capture_id)
                row = connection.execute(
                    "SELECT * FROM captures WHERE id = ?", (capture_id,)
                ).fetchone()
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        if row is None:  # pragma: no cover - the guarded update returned one row.
            raise RuntimeError("Capture update completed without a readable row")
        return _row_to_record(row)
