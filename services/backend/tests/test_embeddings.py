from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

import app.embeddings as embeddings_module
from app.config import REPOSITORY_ROOT
from app.embeddings import (
    EMBEDDING_MAX_RETRIES,
    EMBEDDING_TIMEOUT_SECONDS,
    EmbeddingProviderError,
    OpenAIEmbeddingProvider,
    build_embedding_input,
    cosine_similarity,
)
from app.enrichment import (
    EnrichmentPayload,
    EnrichmentProviderError,
    EnrichmentService,
)
from app.models import EnrichmentUpdate, NewCapture
from app.repository import CaptureRepository


class FakeEmbeddings:
    def __init__(self, response: object | None = None, error: Exception | None = None):
        self.response = response
        self.error = error
        self.calls: list[dict[str, object]] = []

    def create(self, **kwargs: object) -> object:
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        assert self.response is not None
        return self.response


class FakeClient:
    def __init__(self, embeddings: FakeEmbeddings):
        self.embeddings = embeddings


class StaticEnrichmentProvider:
    def __init__(self, payload: EnrichmentPayload):
        self.payload = payload

    def enrich(self, _capture) -> EnrichmentPayload:
        return self.payload


class FailedEnrichmentProvider:
    def enrich(self, _capture) -> EnrichmentPayload:
        raise EnrichmentProviderError


class RecordingEmbeddingProvider:
    def __init__(
        self,
        vector: list[float] | None = None,
        error: Exception | None = None,
    ) -> None:
        self.vector = vector or [0.25, 0.5, 0.75]
        self.error = error
        self.inputs: list[str] = []

    def embed(self, text: str) -> list[float]:
        self.inputs.append(text)
        if self.error is not None:
            raise self.error
        return self.vector


def fixture_capture_and_enrichment() -> tuple[NewCapture, EnrichmentPayload]:
    capture_path = REPOSITORY_ROOT / "contracts/examples/capture-request.json"
    enrichment_path = REPOSITORY_ROOT / "contracts/examples/enrichment-output.json"
    return (
        NewCapture.model_validate_json(capture_path.read_text(encoding="utf-8")),
        EnrichmentPayload.model_validate_json(
            enrichment_path.read_text(encoding="utf-8")
        ),
    )


def ready_fixture(repository: CaptureRepository):
    capture_input, enrichment = fixture_capture_and_enrichment()
    capture = repository.create(capture_input, status="processing")
    return repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(
            status="ready",
            ai_title=enrichment.title,
            ai_summary=enrichment.summary,
            problem=enrichment.problem,
            key_insight=enrichment.key_insight,
            why_saved=enrichment.why_saved,
            caveats=enrichment.caveats,
            tags=enrichment.tags,
            entities=enrichment.entities,
            search_aliases=enrichment.search_aliases,
        ),
    )


def test_embedding_input_matches_exact_checked_in_fixture(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = ready_fixture(repository)
    expected_path = REPOSITORY_ROOT / "contracts/examples/embedding-input.txt"

    projection = build_embedding_input(capture)

    assert projection == expected_path.read_text(encoding="utf-8")
    assert projection.endswith("\n")
    assert "\r" not in projection


def test_embedding_input_normalizes_outer_space_and_line_endings(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(
        NewCapture(
            captured_at="2026-07-18T19:00:00Z",
            source_type="clipboard",
            selected_text="  first\r\n  internal\rline  ",
            user_note="\twhy\r\nnow\t",
        ),
        status="ready",
    )
    capture = capture.model_copy(
        update={
            "tags": [" FastAPI ", " SQLite\r\nsearch "],
            "search_aliases": [" saved fix ", "以后查找"],
        }
    )

    projection = build_embedding_input(capture)

    assert "USER NOTE:\nwhy\nnow" in projection
    assert "SELECTED CONTENT:\nfirst\n  internal\nline" in projection
    assert "TITLE:\n\n\nSUMMARY:" in projection
    assert "TAGS:\nFastAPI, SQLite\nsearch" in projection
    assert "SEARCH ALIASES:\nsaved fix, 以后查找" in projection


def test_provider_uses_one_float_request_and_default_dimensions() -> None:
    embeddings = FakeEmbeddings(
        SimpleNamespace(data=[SimpleNamespace(embedding=[0.1, 0.2, 0.3])])
    )
    provider = OpenAIEmbeddingProvider(
        api_key="test-only",
        model="text-embedding-3-small",
        client=FakeClient(embeddings),
    )

    vector = provider.embed("query text")

    assert vector == [0.1, 0.2, 0.3]
    assert embeddings.calls == [
        {
            "model": "text-embedding-3-small",
            "input": "query text",
            "encoding_format": "float",
        }
    ]
    assert "dimensions" not in embeddings.calls[0]


def test_provider_bounds_timeout_and_disables_sdk_retries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = FakeClient(FakeEmbeddings())
    configured: dict[str, object] = {}

    def fake_openai(**kwargs: object) -> object:
        configured.update(kwargs)
        return client

    monkeypatch.setattr(embeddings_module, "OpenAI", fake_openai)

    provider = OpenAIEmbeddingProvider(
        api_key="test-only",
        model="text-embedding-3-small",
    )

    assert provider._client is client
    assert configured == {
        "api_key": "test-only",
        "timeout": EMBEDDING_TIMEOUT_SECONDS,
        "max_retries": EMBEDDING_MAX_RETRIES,
    }
    assert EMBEDDING_TIMEOUT_SECONDS < 60
    assert EMBEDDING_MAX_RETRIES == 0


@pytest.mark.parametrize(
    "response",
    [
        SimpleNamespace(data=[]),
        SimpleNamespace(data=[SimpleNamespace(embedding=[])]),
        SimpleNamespace(data=[SimpleNamespace(embedding=[True, 0.2])]),
        SimpleNamespace(data=[SimpleNamespace(embedding=[float("nan")])]),
        SimpleNamespace(
            data=[
                SimpleNamespace(embedding=[0.1]),
                SimpleNamespace(embedding=[0.2]),
            ]
        ),
    ],
)
def test_provider_rejects_invalid_vectors(response: object) -> None:
    provider = OpenAIEmbeddingProvider(
        api_key="test-only",
        model="text-embedding-3-small",
        client=FakeClient(FakeEmbeddings(response)),
    )

    with pytest.raises(EmbeddingProviderError):
        provider.embed("query")


def test_provider_wraps_remote_failure_without_private_details() -> None:
    provider = OpenAIEmbeddingProvider(
        api_key="test-only",
        model="text-embedding-3-small",
        client=FakeClient(
            FakeEmbeddings(error=RuntimeError("private provider trace"))
        ),
    )

    with pytest.raises(EmbeddingProviderError) as raised:
        provider.embed("query")

    assert "private provider trace" not in str(raised.value)


@pytest.mark.parametrize(
    "left,right,expected",
    [
        ([1.0, 0.0], [1.0, 0.0], 1.0),
        ([1.0, 0.0], [0.0, 1.0], 0.0),
        ([1.0, 0.0], [-1.0, 0.0], 0.0),
        ([1.0], [1.0, 0.0], None),
        ([0.0, 0.0], [1.0, 0.0], None),
        ([float("inf")], [1.0], None),
    ],
)
def test_cosine_similarity_is_bounded_and_safe(
    left: list[float],
    right: list[float],
    expected: float | None,
) -> None:
    assert cosine_similarity(left, right) == expected


def test_service_embeds_only_valid_enrichment_and_persists_vector(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture_input, enrichment = fixture_capture_and_enrichment()
    capture = repository.create(capture_input, status="processing")
    embedding_provider = RecordingEmbeddingProvider([0.1, 0.2, 0.3])

    EnrichmentService(
        repository,
        StaticEnrichmentProvider(enrichment),
        embedding_provider,
    ).run(capture.id)
    loaded = repository.get(capture.id)

    assert loaded is not None
    assert loaded.status == "ready"
    assert loaded.embedding == [0.1, 0.2, 0.3]
    assert embedding_provider.inputs == [build_embedding_input(loaded)]


def test_embedding_failure_keeps_ready_capture_with_null_vector(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture_input, enrichment = fixture_capture_and_enrichment()
    capture = repository.create(capture_input, status="processing")
    embedding_provider = RecordingEmbeddingProvider(
        error=EmbeddingProviderError()
    )

    EnrichmentService(
        repository,
        StaticEnrichmentProvider(enrichment),
        embedding_provider,
    ).run(capture.id)
    loaded = repository.get(capture.id)

    assert loaded is not None
    assert loaded.status == "ready"
    assert loaded.embedding is None
    assert loaded.error_message is None
    assert len(embedding_provider.inputs) == 1


def test_failed_enrichment_never_calls_embedding_provider(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture_input, _ = fixture_capture_and_enrichment()
    capture = repository.create(capture_input, status="processing")
    embedding_provider = RecordingEmbeddingProvider()

    EnrichmentService(
        repository,
        FailedEnrichmentProvider(),
        embedding_provider,
    ).run(capture.id)

    assert embedding_provider.inputs == []


def test_embedding_json_survives_repository_restart(tmp_path: Path) -> None:
    database_path = tmp_path / "recall.db"
    first_repository = CaptureRepository(database_path)
    capture = ready_fixture(first_repository)
    first_repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(status="ready", embedding=[0.125, -0.25, 0.5]),
    )

    loaded = CaptureRepository(database_path).get(capture.id)

    assert loaded is not None
    assert loaded.embedding == [0.125, -0.25, 0.5]
