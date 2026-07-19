from __future__ import annotations

import json
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.api_models import CaptureCreateRequest, CaptureResponse
from app.config import REPOSITORY_ROOT, get_settings
from app.enrichment import (
    EnrichmentPayload,
    EnrichmentProviderError,
)
from app.main import (
    app,
    get_embedding_provider,
    get_enrichment_provider,
    get_repository,
)
from app.models import NewCapture
from app.repository import CaptureRepository


@pytest.fixture
def api_client(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> Iterator[tuple[TestClient, Path]]:
    database_path = tmp_path / "recall.db"
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("RECALL_DATABASE_PATH", str(database_path))
    get_settings.cache_clear()
    with TestClient(app) as client:
        yield client, database_path
    app.dependency_overrides.pop(get_enrichment_provider, None)
    app.dependency_overrides.pop(get_embedding_provider, None)
    get_settings.cache_clear()


def fixture_request() -> dict[str, object]:
    path = REPOSITORY_ROOT / "contracts" / "examples" / "capture-request.json"
    return json.loads(path.read_text(encoding="utf-8"))


def fixture_enrichment() -> EnrichmentPayload:
    path = REPOSITORY_ROOT / "contracts" / "examples" / "enrichment-output.json"
    return EnrichmentPayload.model_validate_json(path.read_text(encoding="utf-8"))


class SuccessfulProvider:
    def enrich(self, _capture) -> EnrichmentPayload:
        return fixture_enrichment()


class FailedProvider:
    def enrich(self, _capture) -> EnrichmentPayload:
        raise EnrichmentProviderError from RuntimeError("private provider trace")


class SuccessfulEmbeddingProvider:
    def embed(self, _text: str) -> list[float]:
        return [1.0, 0.0]


class FailedEmbeddingProvider:
    def embed(self, _text: str) -> list[float]:
        raise TimeoutError("private embedding trace")


class InvalidOutputProvider:
    def __init__(self, output: object) -> None:
        self.output = output

    def enrich(self, _capture) -> object:
        return self.output


def test_api_models_match_checked_in_contract_fields() -> None:
    request_schema = json.loads(
        (REPOSITORY_ROOT / "contracts" / "capture.schema.json").read_text(
            encoding="utf-8"
        )
    )
    ready_response = json.loads(
        (
            REPOSITORY_ROOT
            / "contracts"
            / "examples"
            / "capture-ready-response.json"
        ).read_text(encoding="utf-8")
    )

    request_fields = CaptureCreateRequest.model_fields
    assert set(request_fields) == set(request_schema["properties"])
    required_fields = {
        name for name, field in request_fields.items() if field.is_required()
    }
    assert required_fields == set(request_schema["required"])
    assert set(CaptureResponse.model_fields) == set(ready_response)


def assert_validation_error(response) -> None:
    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "validation_error"
    assert body["error"]["details"]
    UUID(body["error"]["request_id"])


def test_valid_web_capture_returns_202_and_can_be_read(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    payload = fixture_request()

    created_response = client.post("/v1/captures", json=payload)

    assert created_response.status_code == 202
    created = created_response.json()
    UUID(created["id"])
    assert created["status"] == "processing"
    assert created["selected_text"] == payload["selected_text"]
    assert created["user_note"] == payload["user_note"]
    assert created["captured_at"] == payload["captured_at"]
    assert created["ai_title"] is None
    assert created["tags"] == []
    assert "embedding" not in created
    assert "embedding_json" not in created

    loaded_response = client.get(f"/v1/captures/{created['id']}")

    assert loaded_response.status_code == 200
    loaded = loaded_response.json()
    assert loaded["status"] == "error"
    assert loaded["error_message"] == "AI enrichment is not configured."
    assert loaded["selected_text"] == created["selected_text"]
    assert loaded["user_note"] == created["user_note"]


def test_clipboard_capture_without_url_succeeds(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    payload = {
        "source_type": "clipboard",
        "source_app": "Terminal",
        "selected_text": "命令输出 mixed with English",
        "user_note": "Keep the exact output.",
        "captured_at": "2026-07-18T12:00:00-07:00",
    }

    response = client.post("/v1/captures", json=payload)

    assert response.status_code == 202
    assert response.json()["source_url"] is None
    assert response.json()["source_title"] is None


def test_configured_provider_enriches_capture_after_create(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider

    created_response = client.post("/v1/captures", json=fixture_request())
    created = created_response.json()
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert created_response.status_code == 202
    assert created["status"] == "processing"
    assert loaded["status"] == "ready"
    assert loaded["ai_title"] == fixture_enrichment().title
    assert loaded["tags"] == fixture_enrichment().tags
    assert loaded["selected_text"] == created["selected_text"]
    assert loaded["user_note"] == created["user_note"]


@pytest.mark.parametrize("output", [None, "", {"title": "partial"}])
def test_invalid_model_output_reaches_terminal_error_state(
    api_client: tuple[TestClient, Path],
    output: object,
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = lambda: InvalidOutputProvider(
        output
    )

    created = client.post("/v1/captures", json=fixture_request()).json()
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert loaded["status"] == "error"
    assert loaded["error_message"] == (
        "The configured AI model returned an invalid enrichment result. "
        "Try a compatible model or retry."
    )
    assert loaded["ai_title"] is None


def test_duplicate_client_capture_id_is_idempotent(
    api_client: tuple[TestClient, Path],
) -> None:
    client, database_path = api_client
    payload = fixture_request()

    first = client.post("/v1/captures", json=payload)
    second = client.post("/v1/captures", json=payload)

    assert first.status_code == second.status_code == 202
    assert second.json()["id"] == first.json()["id"]
    assert CaptureRepository(database_path, initialize=False).list_captures(
        limit=10,
        offset=0,
    ) == [CaptureRepository(database_path, initialize=False).get(first.json()["id"])]


def test_missing_key_rejects_manual_enrichment_with_stable_error(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    created = client.post("/v1/captures", json=fixture_request()).json()

    response = client.post(f"/v1/captures/{created['id']}/enrich")

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "openai_not_configured"
    assert "OPENAI_API_KEY" not in response.text


def test_manual_retry_succeeds_without_modifying_source(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    created = client.post("/v1/captures", json=fixture_request()).json()
    before_retry = client.get(f"/v1/captures/{created['id']}").json()
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider

    retry_response = client.post(f"/v1/captures/{created['id']}/enrich")
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert before_retry["status"] == "error"
    assert retry_response.status_code == 202
    assert retry_response.json()["status"] == "processing"
    assert loaded["status"] == "ready"
    assert loaded["selected_text"] == before_retry["selected_text"]
    assert loaded["surrounding_context"] == before_retry["surrounding_context"]
    assert loaded["user_note"] == before_retry["user_note"]


def test_manual_retry_of_ready_capture_returns_clean_processing_state(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider
    created = client.post("/v1/captures", json=fixture_request()).json()
    ready = client.get(f"/v1/captures/{created['id']}").json()

    retry_response = client.post(f"/v1/captures/{created['id']}/enrich")
    processing = retry_response.json()

    assert ready["status"] == "ready"
    assert ready["ai_title"] is not None
    assert retry_response.status_code == 202
    assert processing["status"] == "processing"
    assert processing["ai_title"] is None
    assert processing["ai_summary"] is None
    assert processing["problem"] is None
    assert processing["key_insight"] is None
    assert processing["why_saved"] is None
    assert processing["caveats"] == []
    assert processing["tags"] == []
    assert processing["entities"] == []
    assert processing["search_aliases"] == []
    assert processing["error_message"] is None
    assert processing["selected_text"] == ready["selected_text"]
    assert processing["user_note"] == ready["user_note"]


def test_concurrent_enrichment_is_rejected(
    api_client: tuple[TestClient, Path],
) -> None:
    client, database_path = api_client
    repository = CaptureRepository(database_path, initialize=False)
    capture = repository.create(
        NewCapture(
            captured_at="2026-07-18T19:00:00Z",
            source_type="clipboard",
            selected_text="already processing",
        ),
        status="processing",
    )
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider

    response = client.post(f"/v1/captures/{capture.id}/enrich")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "capture_already_processing"


def test_unknown_capture_enrichment_returns_404(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider

    response = client.post(f"/v1/captures/{uuid4()}/enrich")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "capture_not_found"


def test_provider_failure_is_persisted_without_private_trace(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = FailedProvider

    created = client.post("/v1/captures", json=fixture_request()).json()
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert loaded["status"] == "error"
    assert loaded["error_message"] == (
        "AI enrichment could not be completed. Retry later."
    )
    assert "private provider trace" not in loaded["error_message"]


def test_search_returns_keyword_only_contract_shape(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider
    created = client.post("/v1/captures", json=fixture_request()).json()

    response = client.get("/v1/search", params={"q": "surprising VPS fix"})

    assert response.status_code == 200
    body = response.json()
    assert body["query"] == "surprising VPS fix"
    assert len(body["results"]) == 1
    result = body["results"][0]
    assert result["capture"]["id"] == created["id"]
    assert result["score"] == result["keyword_score"] == 1.0
    assert result["semantic_score"] is None
    assert 0.0 <= result["score"] <= 1.0


def test_search_returns_semantic_result_after_embedding_pipeline(
    api_client: tuple[TestClient, Path],
) -> None:
    client, database_path = api_client
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider
    app.dependency_overrides[get_embedding_provider] = SuccessfulEmbeddingProvider
    created = client.post("/v1/captures", json=fixture_request()).json()

    stored = CaptureRepository(database_path, initialize=False).get(created["id"])
    response = client.get(
        "/v1/search",
        params={"q": "thing that finally solved my server problem"},
    )

    assert stored is not None
    assert stored.embedding == [1.0, 0.0]
    assert response.status_code == 200
    result = response.json()["results"][0]
    assert result["capture"]["id"] == created["id"]
    assert result["keyword_score"] == 1.0
    assert result["semantic_score"] == 1.0
    assert result["score"] == 0.9


def test_search_query_embedding_failure_returns_keyword_fallback(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    app.dependency_overrides[get_enrichment_provider] = SuccessfulProvider
    app.dependency_overrides[get_embedding_provider] = SuccessfulEmbeddingProvider
    created = client.post("/v1/captures", json=fixture_request()).json()
    app.dependency_overrides[get_embedding_provider] = FailedEmbeddingProvider

    response = client.get("/v1/search", params={"q": "surprising VPS fix"})

    assert response.status_code == 200
    result = response.json()["results"][0]
    assert result["capture"]["id"] == created["id"]
    assert result["score"] == result["keyword_score"] == 1.0
    assert result["semantic_score"] is None


def test_search_without_openai_finds_failed_capture_raw_fields(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    created = client.post("/v1/captures", json=fixture_request()).json()

    response = client.get(
        "/v1/search",
        params={"q": "WorkingDirectory"},
    )

    assert response.status_code == 200
    results = response.json()["results"]
    assert [result["capture"]["id"] for result in results] == [created["id"]]
    assert results[0]["capture"]["status"] == "error"
    assert results[0]["semantic_score"] is None


def test_empty_and_missing_search_query_return_recent_captures(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    first = client.post("/v1/captures", json=fixture_request()).json()
    second_payload = fixture_request()
    second_payload["client_capture_id"] = str(uuid4())
    second_payload["selected_text"] = "newer raw capture"
    second = client.post("/v1/captures", json=second_payload).json()

    missing_query = client.get("/v1/search?limit=2")
    whitespace_query = client.get("/v1/search", params={"q": "   ", "limit": 1})

    assert missing_query.status_code == 200
    assert missing_query.json()["query"] == ""
    assert [
        result["capture"]["id"] for result in missing_query.json()["results"]
    ] == [second["id"], first["id"]]
    assert whitespace_query.status_code == 200
    assert whitespace_query.json()["query"] == "   "
    assert whitespace_query.json()["results"][0]["capture"]["id"] == second["id"]
    assert whitespace_query.json()["results"][0]["keyword_score"] == 0.0


def test_search_no_result_and_client_fts_syntax_are_safe(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    client.post("/v1/captures", json=fixture_request())

    missing = client.get("/v1/search", params={"q": "absent-nebula"})
    syntax = client.get("/v1/search", params={"q": '" OR * -'})

    assert missing.status_code == 200
    assert missing.json()["results"] == []
    assert syntax.status_code == 200
    assert syntax.json()["results"] == []


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "limit=word"])
def test_search_limit_is_enforced(
    api_client: tuple[TestClient, Path],
    query: str,
) -> None:
    client, _ = api_client

    assert_validation_error(client.get(f"/v1/search?{query}"))


@pytest.mark.parametrize("user_note", ["", "长备注" * 1_000])
def test_empty_and_bounded_user_notes_round_trip(
    api_client: tuple[TestClient, Path],
    user_note: str,
) -> None:
    client, _ = api_client
    payload = {
        "source_type": "clipboard",
        "selected_text": "source",
        "user_note": user_note,
        "captured_at": "2026-07-18T19:00:00Z",
    }

    created = client.post("/v1/captures", json=payload)
    loaded = client.get(f"/v1/captures/{created.json()['id']}")

    assert created.status_code == 202
    assert loaded.status_code == 200
    assert loaded.json()["user_note"] == user_note


def test_overlong_user_note_is_rejected(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    payload = fixture_request()
    payload["user_note"] = "x" * 4_001

    assert_validation_error(client.post("/v1/captures", json=payload))


@pytest.mark.parametrize(
    "content",
    [
        {"selected_text": "", "source_title": "Page title"},
        {"selected_text": "", "surrounding_context": "Page context"},
    ],
)
def test_empty_selection_succeeds_with_title_or_context(
    api_client: tuple[TestClient, Path],
    content: dict[str, str],
) -> None:
    client, _ = api_client
    payload = {
        "source_type": "web",
        "captured_at": "2026-07-18T19:00:00Z",
        **content,
    }

    response = client.post("/v1/captures", json=payload)

    assert response.status_code == 202
    assert response.json()["selected_text"] == ""


def test_empty_or_whitespace_only_content_fails(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client
    payload = {
        "source_type": "web",
        "selected_text": "  ",
        "source_title": "\t",
        "surrounding_context": None,
        "captured_at": "2026-07-18T19:00:00Z",
    }

    assert_validation_error(client.post("/v1/captures", json=payload))


def test_unknown_request_field_fails(api_client: tuple[TestClient, Path]) -> None:
    client, _ = api_client
    payload = fixture_request()
    payload["invented_field"] = "not allowed"

    assert_validation_error(client.post("/v1/captures", json=payload))


@pytest.mark.parametrize(
    "field,value",
    [
        ("source_app", "x" * 201),
        ("source_title", "x" * 501),
        ("source_url", "https://example.com/" + "x" * 2_029),
        ("selected_text", "x" * 12_001),
        ("surrounding_context", "x" * 20_001),
        ("user_note", "x" * 4_001),
    ],
)
def test_overlong_content_fails_visibly(
    api_client: tuple[TestClient, Path],
    field: str,
    value: str,
) -> None:
    client, _ = api_client
    payload = fixture_request()
    payload[field] = value

    assert_validation_error(client.post("/v1/captures", json=payload))


@pytest.mark.parametrize(
    "field,value",
    [
        ("client_capture_id", "not-a-uuid"),
        ("source_url", "not a uri"),
        ("captured_at", "2026-07-18T19:00:00"),
        ("captured_at", "0"),
    ],
)
def test_invalid_formatted_fields_fail(
    api_client: tuple[TestClient, Path],
    field: str,
    value: str,
) -> None:
    client, _ = api_client
    payload = fixture_request()
    payload[field] = value

    assert_validation_error(client.post("/v1/captures", json=payload))


@pytest.mark.parametrize("value", [1, "false"])
def test_context_truncated_requires_a_json_boolean(
    api_client: tuple[TestClient, Path],
    value: object,
) -> None:
    client, _ = api_client
    payload = fixture_request()
    payload["context_truncated"] = value

    assert_validation_error(client.post("/v1/captures", json=payload))


@pytest.mark.parametrize("query", ["x" * 513, "safe\x00unsafe"])
def test_unsafe_search_query_is_rejected(
    api_client: tuple[TestClient, Path],
    query: str,
) -> None:
    client, _ = api_client

    assert_validation_error(client.get("/v1/search", params={"q": query}))


def test_invalid_utf8_body_uses_validation_envelope(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client

    response = client.post(
        "/v1/captures",
        content=b'{"selected_text":"\xff"}',
        headers={"Content-Type": "application/json"},
    )

    assert_validation_error(response)


def test_list_is_newest_first_and_paginated(
    api_client: tuple[TestClient, Path],
) -> None:
    client, database_path = api_client
    times = iter(
        [
            datetime(2026, 7, 18, 19, 0, tzinfo=timezone.utc),
            datetime(2026, 7, 18, 19, 1, tzinfo=timezone.utc),
            datetime(2026, 7, 18, 19, 2, tzinfo=timezone.utc),
        ]
    )
    repository = CaptureRepository(
        database_path,
        clock=lambda: next(times),
        initialize=False,
    )
    for text in ["oldest", "middle", "newest"]:
        repository.create(
            NewCapture(
                captured_at="2026-07-18T12:00:00-07:00",
                source_type="clipboard",
                selected_text=text,
            ),
            status="processing",
        )

    first_page = client.get("/v1/captures?limit=2&offset=0")
    second_page = client.get("/v1/captures?limit=2&offset=2")

    assert first_page.status_code == 200
    assert [item["selected_text"] for item in first_page.json()["items"]] == [
        "newest",
        "middle",
    ]
    assert first_page.json()["limit"] == 2
    assert first_page.json()["offset"] == 0
    assert [item["selected_text"] for item in second_page.json()["items"]] == [
        "oldest"
    ]


@pytest.mark.parametrize(
    "query",
    ["limit=0", "limit=101", "limit=word", "offset=-1", "offset=word"],
)
def test_pagination_limits_are_enforced(
    api_client: tuple[TestClient, Path],
    query: str,
) -> None:
    client, _ = api_client

    assert_validation_error(client.get(f"/v1/captures?{query}"))


def test_unknown_uuid_returns_documented_404_envelope(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client

    response = client.get(f"/v1/captures/{uuid4()}")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "capture_not_found"
    assert response.json()["error"]["message"] == "Capture was not found."
    assert response.json()["error"]["details"] is None
    UUID(response.json()["error"]["request_id"])


def test_malformed_capture_id_returns_validation_envelope(
    api_client: tuple[TestClient, Path],
) -> None:
    client, _ = api_client

    assert_validation_error(client.get("/v1/captures/not-a-uuid"))


def test_unexpected_api_failure_uses_internal_error_envelope(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setenv("RECALL_DATABASE_PATH", str(tmp_path / "recall.db"))
    get_settings.cache_clear()

    def fail_repository() -> CaptureRepository:
        raise RuntimeError("simulated repository failure")

    app.dependency_overrides[get_repository] = fail_repository
    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.get("/v1/captures")
    finally:
        app.dependency_overrides.clear()
        get_settings.cache_clear()

    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert response.json()["error"]["details"] is None
    UUID(response.json()["error"]["request_id"])
