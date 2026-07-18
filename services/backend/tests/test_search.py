from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.database import database_connection
from app.models import EnrichmentUpdate, NewCapture
from app.repository import CaptureRepository
from app.search import (
    HybridSearchService,
    build_fts_match_query,
    is_technical_query,
    metadata_bonus,
)


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


class StaticEmbeddingProvider:
    def __init__(
        self,
        vector: list[float] | None = None,
        error: Exception | None = None,
    ) -> None:
        self.vector = vector or [1.0, 0.0]
        self.error = error
        self.inputs: list[str] = []

    def embed(self, text: str) -> list[float]:
        self.inputs.append(text)
        if self.error is not None:
            raise self.error
        return self.vector


def create_ready_capture(
    repository: CaptureRepository,
    *,
    embedding: list[float] | None,
    **overrides: object,
):
    tags = list(overrides.pop("tags", []))
    search_aliases = list(overrides.pop("search_aliases", []))
    capture = repository.create(new_capture(**overrides), status="processing")
    return repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(
            status="ready",
            ai_title=str(overrides.get("source_title", "Recall memory")),
            ai_summary="Contextual saved-memory summary",
            problem="Remember the relevant source",
            key_insight="Use the saved context",
            tags=tags,
            search_aliases=search_aliases,
            embedding=embedding,
        ),
    )


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


def test_vague_personal_query_retrieves_semantic_only_capture(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    intended = create_ready_capture(
        repository,
        embedding=[1.0, 0.0],
        selected_text="Set the systemd working directory before restart.",
        user_note="This was the only VPS solution that worked.",
    )
    unrelated = create_ready_capture(
        repository,
        embedding=[0.0, 1.0],
        selected_text="Plastic packaging expanded after wartime production.",
        user_note="Background for an essay.",
    )
    provider = StaticEmbeddingProvider([1.0, 0.0])

    matches = HybridSearchService(repository, provider).search(
        query="thing that finally solved my server problem",
        limit=20,
    )

    assert matches[0].capture.id == intended.id
    assert matches[0].semantic_score == 1.0
    assert matches[0].keyword_score == 0.0
    assert matches[0].score == 0.55
    assert {match.capture.id for match in matches} == {intended.id, unrelated.id}
    assert provider.inputs == ["thing that finally solved my server problem"]


def test_technical_identifier_query_favors_exact_keyword_match(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    exact = create_ready_capture(
        repository,
        embedding=[0.6, 0.8],
        selected_text="Fix ERR_MODULE_NOT_FOUND by checking package exports.",
    )
    semantic_only = create_ready_capture(
        repository,
        embedding=[1.0, 0.0],
        selected_text="A different module-loading memory.",
    )

    matches = HybridSearchService(
        repository,
        StaticEmbeddingProvider([1.0, 0.0]),
    ).search(query="ERR_MODULE_NOT_FOUND", limit=20)

    assert [match.capture.id for match in matches[:2]] == [
        exact.id,
        semantic_only.id,
    ]
    assert matches[0].keyword_score == 1.0
    assert matches[0].score > matches[1].score


def test_chinese_semantic_query_retrieves_english_source_with_chinese_note(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    intended = create_ready_capture(
        repository,
        embedding=[0.9, 0.1],
        selected_text="Set WorkingDirectory before restarting the service.",
        user_note="这是我在部署时唯一成功的方法，以后要记住。",
    )
    create_ready_capture(
        repository,
        embedding=[0.0, 1.0],
        selected_text="Historical article about food packaging.",
        user_note="论文背景资料。",
    )

    matches = HybridSearchService(
        repository,
        StaticEmbeddingProvider([1.0, 0.0]),
    ).search(query="服务器上那个反直觉的解决办法", limit=20)

    assert matches[0].capture.id == intended.id
    assert matches[0].semantic_score is not None
    assert matches[0].keyword_score == 0.0


def test_missing_capture_embedding_falls_back_per_result_without_crashing(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    keyword_only = create_ready_capture(
        repository,
        embedding=None,
        selected_text="unique fallback phrase",
    )
    create_ready_capture(
        repository,
        embedding=[1.0, 0.0],
        selected_text="unrelated semantic memory",
    )

    matches = HybridSearchService(
        repository,
        StaticEmbeddingProvider([1.0, 0.0]),
    ).search(query="unique fallback phrase", limit=20)
    fallback = next(
        match for match in matches if match.capture.id == keyword_only.id
    )

    assert fallback.semantic_score is None
    assert fallback.score == fallback.keyword_score == 1.0


def test_query_embedding_failure_preserves_layer5_fts_results(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    exact = create_ready_capture(
        repository,
        embedding=[1.0, 0.0],
        selected_text="fallback-token",
    )
    keyword_matches = repository.search_captures(
        query="fallback-token",
        limit=20,
    )

    matches = HybridSearchService(
        repository,
        StaticEmbeddingProvider(error=TimeoutError("offline")),
    ).search(query="fallback-token", limit=20)

    assert [match.capture.id for match in matches] == [exact.id]
    assert [match.score for match in matches] == [
        match.keyword_score for match in keyword_matches
    ]
    assert all(match.semantic_score is None for match in matches)


def test_hybrid_score_order_is_deterministic_for_fixed_vectors(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    create_ready_capture(
        repository,
        embedding=[0.8, 0.2],
        selected_text="first deterministic memory",
    )
    create_ready_capture(
        repository,
        embedding=[0.4, 0.6],
        selected_text="second deterministic memory",
    )
    service = HybridSearchService(
        repository,
        StaticEmbeddingProvider([1.0, 0.0]),
    )

    first = service.search(query="vague memory request", limit=20)
    second = service.search(query="vague memory request", limit=20)

    assert [
        (match.capture.id, match.score, match.keyword_score, match.semantic_score)
        for match in first
    ] == [
        (match.capture.id, match.score, match.keyword_score, match.semantic_score)
        for match in second
    ]


def test_metadata_bonus_covers_all_four_baseline_signals(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = create_ready_capture(
        repository,
        embedding=[1.0, 0.0],
        source_app="Google Chrome",
        source_url="https://docs.example.com/repair",
        selected_text="The exact failure was ERR_502.",
        tags=["FastAPI"],
    )

    assert metadata_bonus(capture, "docs.example.com") == 0.25
    assert metadata_bonus(capture, "Chrome") == 0.25
    assert metadata_bonus(capture, "FastAPI") == 0.25
    assert metadata_bonus(capture, "ERR_502") == 0.25
    assert (
        metadata_bonus(
            capture,
            "docs.example.com Chrome FastAPI ERR_502",
        )
        == 1.0
    )


@pytest.mark.parametrize(
    "query",
    [
        "HTTP 502",
        "/etc/systemd/system/recall.service",
        "package-name",
        "snake_case",
        "0xFF",
        "https://docs.example.com",
        "mixedCaseIdentifier",
    ],
)
def test_technical_query_detection(query: str) -> None:
    assert is_technical_query(query) is True


def test_plain_language_query_is_not_technical() -> None:
    assert is_technical_query("thing that finally solved my server problem") is False
