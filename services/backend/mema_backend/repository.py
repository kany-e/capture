"""Transactional SQLite repository for Mema Capture records."""

from __future__ import annotations

import json
import sqlite3
from collections.abc import Callable, Iterable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal, get_args
from uuid import uuid4

from mema_backend.database import apply_migrations, database_connection
from mema_backend.models import (
    AttachmentRecord,
    CaptureRecord,
    CaptureStatus,
    CaptureUserUpdate,
    EnrichmentUpdate,
    NewAttachment,
    NewCapture,
)
from mema_backend.search import (
    KeywordSearchMatch,
    build_fts_match_query,
    normalize_keyword_matches,
)


VALID_CAPTURE_STATUSES = frozenset(get_args(CaptureStatus))
CaptureSortOrder = Literal[
    "created_desc",
    "created_asc",
    "edited_desc",
    "edited_asc",
]
CAPTURE_SORT_SQL: dict[CaptureSortOrder, str] = {
    "created_desc": "created_at DESC, id DESC",
    "created_asc": "created_at ASC, id ASC",
    "edited_desc": "COALESCE(user_edited_at, created_at) DESC, created_at DESC, id DESC",
    "edited_asc": "COALESCE(user_edited_at, created_at) ASC, created_at ASC, id ASC",
}
FTS_CANDIDATE_MULTIPLIER = 5
FTS_MAX_CANDIDATES = 500
INTERRUPTED_PROCESSING_ERROR_MESSAGE = (
    "AI processing was interrupted by a backend restart. Retry AI to continue."
)


class CaptureNotFoundError(LookupError):
    """Raised when an update targets a missing Capture."""


class CaptureAlreadyProcessingError(RuntimeError):
    """Raised when an enrichment claim targets an active Capture."""


class CaptureEditConflictError(RuntimeError):
    """Raised when a user edit races with active AI processing."""


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


def _decode_optional_list(value: str | None, column: str) -> list[Any] | None:
    return None if value is None else _decode_list(value, column)


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
        source_app=row["user_source_app"] if row["user_source_app"] is not None else row["source_app"],
        source_title=row["user_source_title"] if row["user_source_title"] is not None else row["source_title"],
        source_url=row["user_source_url"] if row["user_source_url"] is not None else row["source_url"],
        selected_text=row["user_selected_text"] if row["user_selected_text"] is not None else row["selected_text"],
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
        user_edited_at=row["user_edited_at"],
        user_selected_text=row["user_selected_text"],
        user_source_app=row["user_source_app"],
        user_source_title=row["user_source_title"],
        user_source_url=row["user_source_url"],
        user_title=row["user_title"],
        user_problem=row["user_problem"],
        user_key_insight=row["user_key_insight"],
        user_why_saved=row["user_why_saved"],
        user_caveats=_decode_optional_list(
            row["user_caveats_json"], "user_caveats_json"
        ),
        user_tags=_decode_optional_list(row["user_tags_json"], "user_tags_json"),
        ai_interpretation_hidden=bool(row["ai_interpretation_hidden"]),
        ai_content_stale=bool(row["ai_content_stale"]),
    )


def _row_to_attachment(row: sqlite3.Row) -> AttachmentRecord:
    return AttachmentRecord(
        id=row["id"],
        capture_id=row["capture_id"],
        created_at=row["created_at"],
        kind=row["kind"],
        media_type=row["media_type"],
        relative_path=row["relative_path"],
        byte_size=row["byte_size"],
        pixel_width=row["pixel_width"],
        pixel_height=row["pixel_height"],
        sha256=row["sha256"],
        sort_order=row["sort_order"],
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
        record, _ = self.create_or_get(capture, status=status)
        return record

    def create_or_get(
        self,
        capture: NewCapture,
        *,
        status: CaptureStatus = "captured",
    ) -> tuple[CaptureRecord, bool]:
        """Create once per optional client ID, serialized with other writes."""

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
                row = None
                created = True
                if capture.client_capture_id is not None:
                    row = connection.execute(
                        """
                        SELECT * FROM captures
                        WHERE client_capture_id = ?
                        ORDER BY created_at ASC
                        LIMIT 1
                        """,
                        (capture.client_capture_id,),
                    ).fetchone()
                    created = row is None

                if row is None:
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
        return _row_to_record(row), created

    def create_with_attachment(
        self,
        capture: NewCapture,
        attachment: NewAttachment,
        *,
        status: CaptureStatus,
    ) -> tuple[CaptureRecord, bool]:
        """Create an image Capture and its metadata in one SQLite transaction."""

        if status not in VALID_CAPTURE_STATUSES:
            raise ValueError(f"Invalid Capture status: {status}")

        capture_id = str(uuid4())
        now = self._timestamp()
        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                row = None
                created = True
                if capture.client_capture_id is not None:
                    row = connection.execute(
                        """
                        SELECT * FROM captures
                        WHERE client_capture_id = ?
                        ORDER BY created_at ASC
                        LIMIT 1
                        """,
                        (capture.client_capture_id,),
                    ).fetchone()
                    created = row is None

                if row is None:
                    connection.execute(
                        """
                        INSERT INTO captures (
                            id, client_capture_id, created_at, updated_at, captured_at,
                            status, source_type, source_app, source_title, source_url,
                            selected_text, surrounding_context, context_truncated,
                            user_note
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
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
                        ),
                    )
                    connection.execute(
                        """
                        INSERT INTO capture_attachments (
                            id, capture_id, created_at, kind, media_type,
                            relative_path, byte_size, pixel_width, pixel_height,
                            sha256, sort_order
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            attachment.id,
                            capture_id,
                            now,
                            attachment.kind,
                            attachment.media_type,
                            attachment.relative_path,
                            attachment.byte_size,
                            attachment.pixel_width,
                            attachment.pixel_height,
                            attachment.sha256,
                            attachment.sort_order,
                        ),
                    )
                    row = connection.execute(
                        "SELECT * FROM captures WHERE id = ?", (capture_id,)
                    ).fetchone()
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        if row is None:  # pragma: no cover - guarded SQLite insert.
            raise RuntimeError("Image Capture insert completed without a readable row")
        return _row_to_record(row), created

    def get(self, capture_id: str) -> CaptureRecord | None:
        with database_connection(self.database_path) as connection:
            row = connection.execute(
                "SELECT * FROM captures WHERE id = ?", (capture_id,)
            ).fetchone()
        return None if row is None else _row_to_record(row)

    def list_attachments(self, capture_id: str) -> list[AttachmentRecord]:
        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                """
                SELECT * FROM capture_attachments
                WHERE capture_id = ?
                ORDER BY sort_order ASC, created_at ASC
                """,
                (capture_id,),
            ).fetchall()
        return [_row_to_attachment(row) for row in rows]

    def list_attachments_for_captures(
        self,
        capture_ids: Iterable[str],
    ) -> dict[str, list[AttachmentRecord]]:
        """Load attachments for a response page without one query per Capture."""

        unique_ids = list(dict.fromkeys(capture_ids))
        attachments_by_capture = {capture_id: [] for capture_id in unique_ids}
        if not unique_ids:
            return attachments_by_capture

        placeholders = ", ".join("?" for _ in unique_ids)
        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                f"""
                SELECT * FROM capture_attachments
                WHERE capture_id IN ({placeholders})
                ORDER BY capture_id ASC, sort_order ASC, created_at ASC
                """,
                unique_ids,
            ).fetchall()

        for row in rows:
            attachment = _row_to_attachment(row)
            attachments_by_capture[attachment.capture_id].append(attachment)
        return attachments_by_capture

    def get_attachment(self, attachment_id: str) -> AttachmentRecord | None:
        with database_connection(self.database_path) as connection:
            row = connection.execute(
                "SELECT * FROM capture_attachments WHERE id = ?",
                (attachment_id,),
            ).fetchone()
        return None if row is None else _row_to_attachment(row)

    def attachment_paths(self) -> set[str]:
        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                "SELECT relative_path FROM capture_attachments"
            ).fetchall()
        return {str(row["relative_path"]) for row in rows}

    def delete(self, capture_id: str) -> list[str] | None:
        """Delete a Capture transactionally and return files to remove."""

        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                exists = connection.execute(
                    "SELECT 1 FROM captures WHERE id = ?", (capture_id,)
                ).fetchone()
                if exists is None:
                    connection.rollback()
                    return None
                paths = [
                    str(row["relative_path"])
                    for row in connection.execute(
                        """
                        SELECT relative_path FROM capture_attachments
                        WHERE capture_id = ?
                        """,
                        (capture_id,),
                    ).fetchall()
                ]
                connection.execute("DELETE FROM captures WHERE id = ?", (capture_id,))
                connection.commit()
            except Exception:
                connection.rollback()
                raise
        return paths

    def update_user_fields(
        self,
        capture_id: str,
        update: CaptureUserUpdate,
    ) -> CaptureRecord:
        """Apply explicit user overrides without replacing captured or AI data."""

        now = self._timestamp()
        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                existing = connection.execute(
                    "SELECT * FROM captures WHERE id = ?", (capture_id,)
                ).fetchone()
                if existing is None:
                    raise CaptureNotFoundError(capture_id)
                if existing["status"] == "processing":
                    raise CaptureEditConflictError(capture_id)

                effective_selected_text = (
                    existing["user_selected_text"]
                    if existing["user_selected_text"] is not None
                    else existing["selected_text"]
                )
                effective_source_app = (
                    existing["user_source_app"]
                    if existing["user_source_app"] is not None
                    else existing["source_app"]
                )
                effective_source_title = (
                    existing["user_source_title"]
                    if existing["user_source_title"] is not None
                    else existing["source_title"]
                )
                effective_source_url = (
                    existing["user_source_url"]
                    if existing["user_source_url"] is not None
                    else existing["source_url"]
                )
                new_selected_text = (
                    update.selected_text
                    if update.selected_text is not None
                    else existing["selected_text"]
                )
                new_source_app = (
                    update.source_app
                    if update.source_app is not None
                    else existing["source_app"]
                )
                new_source_title = (
                    update.source_title
                    if update.source_title is not None
                    else existing["source_title"]
                )
                new_source_url = (
                    update.source_url
                    if update.source_url is not None
                    else existing["source_url"]
                )
                source_changed = (
                    new_selected_text != effective_selected_text
                    or new_source_app != effective_source_app
                    or new_source_title != effective_source_title
                    or new_source_url != effective_source_url
                    or update.user_note != existing["user_note"]
                )
                ai_content_stale = bool(existing["ai_content_stale"]) or source_changed
                ai_interpretation_hidden = (
                    source_changed or not update.show_ai_interpretation
                )

                connection.execute(
                    """
                    UPDATE captures SET
                        updated_at = ?, user_edited_at = ?,
                        user_selected_text = ?, user_note = ?,
                        user_source_app = ?, user_source_title = ?,
                        user_source_url = ?, user_title = ?,
                        user_problem = ?, user_key_insight = ?,
                        user_why_saved = ?, user_caveats_json = ?,
                        user_tags_json = ?, ai_interpretation_hidden = ?,
                        ai_content_stale = ?, embedding_json = NULL
                    WHERE id = ?
                    """,
                    (
                        now,
                        now,
                        update.selected_text,
                        update.user_note,
                        update.source_app,
                        update.source_title,
                        update.source_url,
                        update.user_title,
                        update.user_problem,
                        update.user_key_insight,
                        update.user_why_saved,
                        _encode_json(update.user_caveats),
                        _encode_json(update.user_tags),
                        int(ai_interpretation_hidden),
                        int(ai_content_stale),
                        capture_id,
                    ),
                )
                row = connection.execute(
                    "SELECT * FROM captures WHERE id = ?", (capture_id,)
                ).fetchone()
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        if row is None:  # pragma: no cover - guarded update returned one row.
            raise RuntimeError("Capture edit completed without a readable row")
        return _row_to_record(row)

    def list_captures(
        self,
        *,
        limit: int,
        offset: int,
        sort: CaptureSortOrder = "created_desc",
    ) -> list[CaptureRecord]:
        order_by = CAPTURE_SORT_SQL[sort]
        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                f"""
                SELECT * FROM captures
                ORDER BY {order_by}
                LIMIT ? OFFSET ?
                """,
                (limit, offset),
            ).fetchall()
        return [_row_to_record(row) for row in rows]

    def list_ready_captures(self) -> list[CaptureRecord]:
        """Return the small MVP semantic candidate set without a vector index."""

        with database_connection(self.database_path) as connection:
            rows = connection.execute(
                """
                SELECT * FROM captures
                WHERE status = 'ready'
                ORDER BY created_at DESC
                """
            ).fetchall()
        return [_row_to_record(row) for row in rows]

    def recover_stale_processing(self) -> int:
        """Atomically make pre-startup processing records visible and retryable."""

        updated_at = self._timestamp()
        with database_connection(self.database_path) as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                cursor = connection.execute(
                    """
                    UPDATE captures
                    SET status = 'error', updated_at = ?, error_message = ?
                    WHERE status = 'processing'
                    """,
                    (updated_at, INTERRUPTED_PROCESSING_ERROR_MESSAGE),
                )
                recovered_count = cursor.rowcount
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        return recovered_count

    def semantic_revision(self) -> tuple[str, int, int]:
        """Return a cheap cache key for the single local SQLite database."""

        stat = self.database_path.stat()
        return (str(self.database_path), stat.st_mtime_ns, stat.st_size)

    def search_captures(
        self,
        *,
        query: str,
        limit: int,
    ) -> list[KeywordSearchMatch]:
        normalized_query = "".join(
            " " if ord(character) < 32 else character for character in query
        ).strip()
        if not normalized_query:
            return [
                KeywordSearchMatch(capture=record, keyword_score=0.0)
                for record in self.list_captures(limit=limit, offset=0)
            ]

        candidate_limit = min(
            max(limit * FTS_CANDIDATE_MULTIPLIER, limit),
            FTS_MAX_CANDIDATES,
        )

        def execute_match(operator: Literal["AND", "OR"]) -> list[sqlite3.Row]:
            match_query = build_fts_match_query(
                normalized_query,
                operator=operator,
            )
            with database_connection(self.database_path) as connection:
                return connection.execute(
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

        def execute_literal_substring() -> list[sqlite3.Row]:
            """Recover partial identifiers and CJK fragments missed by FTS tokenization."""

            literal_query = " ".join(normalized_query.split())
            with database_connection(self.database_path) as connection:
                return connection.execute(
                    """
                    SELECT captures.*, 0.0 AS fts_rank
                    FROM captures_fts
                    JOIN captures ON captures.id = captures_fts.capture_id
                    WHERE instr(
                        lower(
                            COALESCE(captures_fts.source_title, '') || char(10) ||
                            COALESCE(captures_fts.selected_text, '') || char(10) ||
                            COALESCE(captures_fts.surrounding_context, '') || char(10) ||
                            COALESCE(captures_fts.user_note, '') || char(10) ||
                            COALESCE(captures_fts.ai_title, '') || char(10) ||
                            COALESCE(captures_fts.ai_summary, '') || char(10) ||
                            COALESCE(captures_fts.problem, '') || char(10) ||
                            COALESCE(captures_fts.key_insight, '') || char(10) ||
                            COALESCE(captures_fts.why_saved, '') || char(10) ||
                            COALESCE(captures_fts.tags, '') || char(10) ||
                            COALESCE(captures_fts.entities, '') || char(10) ||
                            COALESCE(captures_fts.search_aliases, '')
                        ),
                        lower(?)
                    ) > 0
                    ORDER BY captures.created_at DESC
                    LIMIT ?
                    """,
                    (literal_query, candidate_limit),
                ).fetchall()

        fts_rows = execute_match("AND")
        if not fts_rows and len(normalized_query.split()) > 1:
            fts_rows = execute_match("OR")

        # FTS can find a complete token while still missing a partial identifier
        # or CJK fragment elsewhere in the library.  Merge the bounded literal
        # pass instead of using it only when FTS returns nothing.
        rows: list[sqlite3.Row] = []
        seen_capture_ids: set[str] = set()
        for row in [*fts_rows, *execute_literal_substring()]:
            capture_id = str(row["id"])
            if capture_id in seen_capture_ids:
                continue
            rows.append(row)
            seen_capture_ids.add(capture_id)
            if len(rows) == candidate_limit:
                break

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
                        embedding_json = NULL, error_message = NULL,
                        ai_interpretation_hidden = 0
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
                        error_message = ?, enrichment_version = ?,
                        ai_content_stale = 0,
                        ai_interpretation_hidden = 0
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

    def update_image_enrichment(
        self,
        capture_id: str,
        *,
        extracted_text: str,
        update: EnrichmentUpdate,
    ) -> CaptureRecord:
        """Store OCR text and visual enrichment as one searchable revision."""

        updated_at = self._timestamp()
        values = (
            extracted_text,
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
                        selected_text = ?, status = ?, updated_at = ?,
                        ai_title = ?, ai_summary = ?, problem = ?,
                        key_insight = ?, why_saved = ?, caveats_json = ?,
                        tags_json = ?, entities_json = ?, search_aliases_json = ?,
                        embedding_json = ?, error_message = ?, enrichment_version = ?,
                        ai_content_stale = 0,
                        ai_interpretation_hidden = 0
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

        if row is None:  # pragma: no cover - guarded update.
            raise RuntimeError("Image enrichment completed without a readable row")
        return _row_to_record(row)
