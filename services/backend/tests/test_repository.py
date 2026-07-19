from __future__ import annotations

import sqlite3
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.database import database_connection
from app.models import EnrichmentUpdate, NewCapture
from app.repository import (
    CaptureAlreadyProcessingError,
    CaptureNotFoundError,
    CaptureRepository,
)


def new_capture(**overrides: object) -> NewCapture:
    values: dict[str, object] = {
        "client_capture_id": None,
        "captured_at": "2026-07-18T12:00:00-07:00",
        "source_type": "web",
        "source_app": "Google Chrome",
        "source_title": "Reference",
        "source_url": "https://example.com/reference",
        "selected_text": "Saved source text",
        "surrounding_context": "Nearby context",
        "context_truncated": False,
        "user_note": "Personal note",
    }
    values.update(overrides)
    return NewCapture.model_validate(values)


@pytest.mark.parametrize(
    "selected_text,user_note",
    [
        ("English source", "English note"),
        ("中文来源内容", "这是中文备注。"),
        ("Mixed 中文 and English 🚀", "原因 reason：以后再看"),
    ],
)
def test_create_and_read_multilingual_captures(
    tmp_path: Path,
    selected_text: str,
    user_note: str,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    created = repository.create(
        new_capture(selected_text=selected_text, user_note=user_note)
    )

    loaded = repository.get(created.id)

    assert loaded is not None
    assert loaded.selected_text == selected_text
    assert loaded.user_note == user_note


def test_nullable_source_fields_round_trip(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    created = repository.create(
        new_capture(
            source_app=None,
            source_title=None,
            source_url=None,
            surrounding_context=None,
            user_note=None,
        )
    )

    loaded = repository.get(created.id)

    assert loaded is not None
    assert loaded.source_app is None
    assert loaded.source_title is None
    assert loaded.source_url is None
    assert loaded.surrounding_context is None
    assert loaded.user_note is None


def test_arrays_embeddings_and_context_flag_round_trip(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    created = repository.create(new_capture(context_truncated=True))

    updated = repository.update_enrichment(
        created.id,
        EnrichmentUpdate(
            status="ready",
            ai_title="标题 Title",
            caveats=["first", "第二"],
            tags=["FastAPI", "SQLite", "顺序"],
            entities=["Recall", "SQLite"],
            search_aliases=["saved fix", "以后查找"],
            embedding=[0.25, -0.5, 1.0],
        ),
    )

    assert updated.context_truncated is True
    assert updated.caveats == ["first", "第二"]
    assert updated.tags == ["FastAPI", "SQLite", "顺序"]
    assert updated.entities == ["Recall", "SQLite"]
    assert updated.search_aliases == ["saved fix", "以后查找"]
    assert updated.embedding == [0.25, -0.5, 1.0]


def test_source_and_note_survive_repository_restart_byte_for_byte(
    tmp_path: Path,
) -> None:
    database_path = tmp_path / "recall.db"
    source = "  exact source\n第二行\nemoji: 🧠  "
    note = "\twhy I saved it\n不要修改\n"
    first_repository = CaptureRepository(database_path)
    created = first_repository.create(
        new_capture(selected_text=source, user_note=note)
    )

    restarted_repository = CaptureRepository(database_path)
    loaded = restarted_repository.get(created.id)

    assert loaded is not None
    assert loaded.selected_text.encode("utf-8") == source.encode("utf-8")
    assert loaded.user_note is not None
    assert loaded.user_note.encode("utf-8") == note.encode("utf-8")


def test_enrichment_update_cannot_modify_source_or_user_note(tmp_path: Path) -> None:
    times = iter(
        [
            datetime(2026, 7, 18, 19, 0, tzinfo=timezone.utc),
            datetime(2026, 7, 18, 19, 1, tzinfo=timezone.utc),
        ]
    )
    repository = CaptureRepository(tmp_path / "recall.db", clock=lambda: next(times))
    created = repository.create(
        new_capture(
            selected_text="immutable source",
            surrounding_context="immutable context",
            user_note="immutable note",
        )
    )

    updated = repository.update_enrichment(
        created.id,
        EnrichmentUpdate(
            status="ready",
            ai_title="Generated title",
            ai_summary="Generated summary",
            tags=["generated"],
        ),
    )

    assert updated.selected_text == created.selected_text
    assert updated.surrounding_context == created.surrounding_context
    assert updated.user_note == created.user_note
    assert updated.created_at == "2026-07-18T19:00:00.000000Z"
    assert updated.updated_at == "2026-07-18T19:01:00.000000Z"


@pytest.mark.parametrize("status", ["captured", "processing", "ready", "error"])
def test_all_capture_states_can_be_stored(tmp_path: Path, status: str) -> None:
    repository = CaptureRepository(tmp_path / f"{status}.db")

    created = repository.create(new_capture(), status=status)  # type: ignore[arg-type]

    assert created.status == status


def test_database_constraint_rejects_invalid_status(tmp_path: Path) -> None:
    database_path = tmp_path / "recall.db"
    repository = CaptureRepository(database_path)
    created = repository.create(new_capture())

    with database_connection(database_path) as connection:
        with pytest.raises(sqlite3.IntegrityError):
            connection.execute(
                "UPDATE captures SET status = 'deleted' WHERE id = ?",
                (created.id,),
            )


def test_duplicate_client_capture_id_returns_first_capture(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    client_capture_id = "149f51e1-8c18-42d4-9778-3f3b062527a2"

    first, first_created = repository.create_or_get(
        new_capture(client_capture_id=client_capture_id)
    )
    second, second_created = repository.create_or_get(
        new_capture(client_capture_id=client_capture_id)
    )

    assert first_created is True
    assert second_created is False
    assert second.id == first.id


def test_concurrent_duplicate_client_capture_id_creates_one_row(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    client_capture_id = "149f51e1-8c18-42d4-9778-3f3b062527a2"

    def create() -> tuple[str, bool]:
        record, created = repository.create_or_get(
            new_capture(client_capture_id=client_capture_id)
        )
        return record.id, created

    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda _: create(), range(20)))

    assert len({capture_id for capture_id, _ in results}) == 1
    assert sum(created for _, created in results) == 1


def test_missing_capture_update_rolls_back(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")

    with pytest.raises(CaptureNotFoundError):
        repository.update_enrichment(
            "missing",
            EnrichmentUpdate(status="error", error_message="not found"),
        )


def test_claim_enrichment_atomically_moves_error_to_processing(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    created = repository.create(new_capture(), status="error")
    repository.update_enrichment(
        created.id,
        EnrichmentUpdate(status="error", error_message="retry me"),
    )

    claimed = repository.claim_enrichment(created.id)

    assert claimed.status == "processing"
    assert claimed.error_message is None
    assert claimed.selected_text == created.selected_text
    assert claimed.user_note == created.user_note


def test_claim_enrichment_clears_generated_fields_from_ready_capture(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    created = repository.create(new_capture(), status="processing")
    repository.update_enrichment(
        created.id,
        EnrichmentUpdate(
            status="ready",
            ai_title="Old generated title",
            ai_summary="Old generated summary",
            problem="Old problem",
            key_insight="Old insight",
            why_saved="Old reason",
            caveats=["Old caveat"],
            tags=["old-tag"],
            entities=["Old Entity"],
            search_aliases=["old alias"],
            embedding=[0.25, -0.5],
        ),
    )

    claimed = repository.claim_enrichment(created.id)

    assert claimed.status == "processing"
    assert claimed.ai_title is None
    assert claimed.ai_summary is None
    assert claimed.problem is None
    assert claimed.key_insight is None
    assert claimed.why_saved is None
    assert claimed.caveats == []
    assert claimed.tags == []
    assert claimed.entities == []
    assert claimed.search_aliases == []
    assert claimed.embedding is None
    assert claimed.error_message is None
    assert claimed.selected_text == created.selected_text
    assert claimed.user_note == created.user_note


def test_claim_enrichment_rejects_concurrent_processing(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    created = repository.create(new_capture(), status="processing")

    with pytest.raises(CaptureAlreadyProcessingError):
        repository.claim_enrichment(created.id)


def test_claim_enrichment_reports_missing_capture(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")

    with pytest.raises(CaptureNotFoundError):
        repository.claim_enrichment("missing")
