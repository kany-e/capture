from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.database import database_connection
from app.models import EnrichmentUpdate, NewCapture
from app.repository import CaptureRepository
from app.search import build_fts_match_query


def new_capture(**overrides: object) -> NewCapture:
    values: dict[str, object] = {
        "captured_at": "2026-07-18T12:00:00-07:00",
        "source_type": "web",
        "source_app": "Google Chrome",
        "source_title": "Reference page",
        "source_url": "https://example.com/reference",
        "selected_text": "Saved source text",
        "surrounding_context": "Nearby context",
        "context_truncated": False,
        "user_note": "Personal note",
    }
    values.update(overrides)
    return NewCapture.model_validate(values)


def test_keyword_search_finds_title_selection_and_user_note(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(
        new_capture(
            source_title="Rare Quasar Deployment Guide",
            selected_text="Set WorkingDirectory=/srv/recall before restart.",
            user_note="This was the only fix that worked on my VPS.",
        ),
        status="error",
    )

    for query in ("Quasar", "WorkingDirectory=/srv/recall", "only fix"):
        matches = repository.search_captures(query=query, limit=20)
        assert [match.capture.id for match in matches] == [capture.id]
        assert matches[0].keyword_score == 1.0


@pytest.mark.parametrize("query", ["FastAPI", "systemd", "unexpected VPS fix"])
def test_keyword_search_finds_ai_tag_entity_and_alias(
    tmp_path: Path,
    query: str,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(), status="processing")
    repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(
            status="ready",
            ai_title="VPS service repair",
            tags=["FastAPI"],
            entities=["systemd"],
            search_aliases=["unexpected VPS fix"],
        ),
    )

    matches = repository.search_captures(query=query, limit=20)

    assert [match.capture.id for match in matches] == [capture.id]


@pytest.mark.parametrize(
    "query",
    [
        "HTTP 502",
        "ERR_MODULE_NOT_FOUND",
        "/etc/systemd/system/recall.service",
        "systemctl restart recall.service",
        "v2.4.1",
        "https://docs.example.com/v2.4.1/repair",
    ],
)
def test_technical_identifiers_and_paths_remain_searchable(
    tmp_path: Path,
    query: str,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(
        new_capture(
            selected_text=(
                "HTTP 502 ERR_MODULE_NOT_FOUND in "
                "/etc/systemd/system/recall.service after v2.4.1. Run "
                "systemctl restart recall.service and check "
                "https://docs.example.com/v2.4.1/repair"
            )
        ),
        status="error",
    )

    matches = repository.search_captures(query=query, limit=20)

    assert [match.capture.id for match in matches] == [capture.id]


def test_chinese_query_finds_mixed_language_content(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(
        new_capture(
            selected_text="English FastAPI source",
            user_note="这是我唯一成功的修复方法。Keep it for later.",
        ),
        status="error",
    )

    matches = repository.search_captures(
        query="这是我唯一成功的修复方法",
        limit=20,
    )

    assert [match.capture.id for match in matches] == [capture.id]


def test_empty_query_returns_recent_captures_and_no_result_is_empty(
    tmp_path: Path,
) -> None:
    times = iter(
        [
            datetime(2026, 7, 18, 19, 0, tzinfo=timezone.utc),
            datetime(2026, 7, 18, 19, 1, tzinfo=timezone.utc),
            datetime(2026, 7, 18, 19, 2, tzinfo=timezone.utc),
        ]
    )
    repository = CaptureRepository(
        tmp_path / "recall.db",
        clock=lambda: next(times),
    )
    for text in ("oldest", "middle", "newest"):
        repository.create(new_capture(selected_text=text), status="error")

    recent = repository.search_captures(query="  ", limit=2)
    missing = repository.search_captures(query="absent-nebula", limit=20)

    assert [match.capture.selected_text for match in recent] == [
        "newest",
        "middle",
    ]
    assert [match.keyword_score for match in recent] == [0.0, 0.0]
    assert missing == []


def test_failed_enrichment_capture_remains_searchable_from_raw_fields(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(
        new_capture(selected_text="Raw fallback keyword aurora-failure"),
        status="processing",
    )
    repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(
            status="error",
            error_message="AI enrichment could not be completed. Retry later.",
        ),
    )

    matches = repository.search_captures(query="aurora-failure", limit=20)

    assert [match.capture.id for match in matches] == [capture.id]
    assert matches[0].capture.status == "error"


def test_retry_synchronizes_generated_fields_and_preserves_raw_search(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(
        new_capture(selected_text="immutable-source-token"),
        status="processing",
    )
    repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(status="ready", search_aliases=["old-ai-alias"]),
    )
    assert repository.search_captures(query="old-ai-alias", limit=20)

    repository.claim_enrichment(capture.id)

    assert repository.search_captures(query="old-ai-alias", limit=20) == []
    assert repository.search_captures(query="immutable-source-token", limit=20)

    repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(status="ready", search_aliases=["new-ai-alias"]),
    )
    assert repository.search_captures(query="new-ai-alias", limit=20)


def test_exact_phrase_bonus_and_keyword_scores_are_normalized(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    exact = repository.create(
        new_capture(selected_text="systemd working directory fix"),
        status="ready",
    )
    separated = repository.create(
        new_capture(
            selected_text=(
                "systemd troubleshooting found a working service; the directory "
                "was corrected with a final fix"
            )
        ),
        status="ready",
    )

    matches = repository.search_captures(
        query="systemd working directory fix",
        limit=20,
    )

    assert matches[0].capture.id == exact.id
    assert {match.capture.id for match in matches} == {exact.id, separated.id}
    assert matches[0].keyword_score == 1.0
    assert all(0.0 <= match.keyword_score <= 1.0 for match in matches)


def test_delete_trigger_removes_fts_row(tmp_path: Path) -> None:
    database_path = tmp_path / "recall.db"
    repository = CaptureRepository(database_path)
    capture = repository.create(new_capture(selected_text="delete-index-token"))

    with database_connection(database_path) as connection:
        connection.execute("DELETE FROM captures WHERE id = ?", (capture.id,))
        connection.commit()
        count = connection.execute(
            "SELECT count(*) FROM captures_fts WHERE capture_id = ?",
            (capture.id,),
        ).fetchone()[0]

    assert count == 0


def test_fts_query_escapes_client_operators_and_quotes() -> None:
    assert build_fts_match_query('hello OR "world" *') == (
        '"hello" AND "OR" AND """world""" AND "*"'
    )
