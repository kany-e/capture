from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

import app.enrichment as enrichment_module
from app.config import REPOSITORY_ROOT
from app.enrichment import (
    ENRICHMENT_MAX_RETRIES,
    ENRICHMENT_TIMEOUT_SECONDS,
    SYSTEM_INSTRUCTIONS,
    EnrichmentPayload,
    EnrichmentProviderError,
    EnrichmentRefusalError,
    EnrichmentService,
    InvalidEnrichmentOutputError,
    OpenAIEnrichmentProvider,
    build_user_input,
    enrichment_schema,
)
from app.models import EnrichmentUpdate, NewCapture
from app.repository import CaptureRepository


def new_capture(**overrides: object) -> NewCapture:
    values: dict[str, object] = {
        "client_capture_id": "149f51e1-8c18-42d4-9778-3f3b062527a2",
        "captured_at": "2026-07-18T10:20:00-07:00",
        "source_type": "web",
        "source_app": "Google Chrome",
        "source_title": "Nginx serves 502 after moving a FastAPI service",
        "source_url": "https://example.com/questions/fastapi-nginx-502",
        "selected_text": "Set WorkingDirectory=/srv/recall and restart Nginx.",
        "surrounding_context": "The service returned HTTP 502 under systemd.",
        "context_truncated": False,
        "user_note": "This was the only fix that worked on my VPS.",
    }
    values.update(overrides)
    return NewCapture.model_validate(values)


def valid_output() -> dict[str, object]:
    path = REPOSITORY_ROOT / "contracts" / "examples" / "enrichment-output.json"
    return json.loads(path.read_text(encoding="utf-8"))


class FakeResponses:
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
    def __init__(self, responses: FakeResponses):
        self.responses = responses


class StaticProvider:
    def __init__(self, result: EnrichmentPayload):
        self.result = result

    def enrich(self, _capture) -> EnrichmentPayload:
        return self.result


class FailingProvider:
    def __init__(self, error: Exception):
        self.error = error

    def enrich(self, _capture) -> EnrichmentPayload:
        raise self.error


def provider_for_output(
    output: str,
    *,
    response_output: list[object] | None = None,
    response_status: str = "completed",
) -> tuple[OpenAIEnrichmentProvider, FakeResponses]:
    responses = FakeResponses(
        SimpleNamespace(
            status=response_status,
            output_text=output,
            output=response_output or [],
        )
    )
    return (
        OpenAIEnrichmentProvider(
            api_key="test-only",
            model="gpt-5.6",
            client=FakeClient(responses),
        ),
        responses,
    )


def test_enrichment_model_fields_match_checked_in_schema() -> None:
    assert set(EnrichmentPayload.model_fields) == set(enrichment_schema()["properties"])


def test_packaged_schema_matches_canonical_contract() -> None:
    canonical_path = REPOSITORY_ROOT / "contracts" / "enriched_capture.schema.json"
    canonical = json.loads(canonical_path.read_text(encoding="utf-8"))

    assert enrichment_schema() == canonical


def test_provider_bounds_timeout_and_disables_sdk_retries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = SimpleNamespace(responses=FakeResponses())
    configured: dict[str, object] = {}

    def fake_openai(**kwargs: object) -> object:
        configured.update(kwargs)
        return client

    monkeypatch.setattr(enrichment_module, "OpenAI", fake_openai)

    provider = OpenAIEnrichmentProvider(api_key="test-only", model="gpt-5.6")

    assert provider._client is client
    assert configured == {
        "api_key": "test-only",
        "timeout": ENRICHMENT_TIMEOUT_SECONDS,
        "max_retries": ENRICHMENT_MAX_RETRIES,
    }
    assert ENRICHMENT_TIMEOUT_SECONDS < 60
    assert ENRICHMENT_MAX_RETRIES == 0


def test_provider_sends_one_strict_schema_request(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(), status="processing")
    provider, responses = provider_for_output(json.dumps(valid_output()))

    result = provider.enrich(capture)

    assert result.title == valid_output()["title"]
    assert len(responses.calls) == 1
    request = responses.calls[0]
    assert request["model"] == "gpt-5.6"
    assert request["instructions"] == SYSTEM_INSTRUCTIONS
    assert request["text"] == {
        "format": {
            "type": "json_schema",
            "name": "recall_enrichment",
            "strict": True,
            "schema": enrichment_schema(),
        }
    }
    assert "WorkingDirectory=/srv/recall" in str(request["input"])
    assert "only fix that worked" in str(request["input"])


@pytest.mark.parametrize(
    "overrides",
    [
        {"source_title": "General article", "selected_text": "Plastic packaging became normalized after wartime production."},
        {"selected_text": "Run systemctl restart recall.service after editing /etc/systemd/system/recall.service."},
        {"selected_text": "English source", "user_note": "这是我唯一成功的修复方法。"},
        {"selected_text": "Saved without a note", "user_note": None},
        {"surrounding_context": "x" * 20_000},
    ],
)
def test_user_input_contains_representative_fixture_content(
    tmp_path: Path,
    overrides: dict[str, object],
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(**overrides))

    prompt = build_user_input(capture)

    assert "SOURCE TYPE:\n" in prompt
    assert "SELECTED CONTENT:\n" in prompt
    assert "SURROUNDING CONTEXT:\n" in prompt
    assert "USER NOTE:\n" in prompt
    for value in overrides.values():
        if isinstance(value, str):
            assert value in prompt


def test_missing_note_instruction_forbids_inventing_a_reason(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(user_note=None))

    assert build_user_input(capture).endswith("USER NOTE:\n")
    assert "no personal reason was provided" in SYSTEM_INSTRUCTIONS


def test_prompt_normalization_does_not_modify_stored_source(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    original = "  first\r\nsecond\r  "
    capture = repository.create(new_capture(selected_text=original))

    prompt = build_user_input(capture)
    loaded = repository.get(capture.id)

    assert "first\nsecond" in prompt
    assert loaded is not None
    assert loaded.selected_text == original


def test_provider_detects_refusal(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture())
    refusal = SimpleNamespace(type="refusal", refusal="Cannot comply")
    message = SimpleNamespace(type="message", content=[refusal])
    provider, _ = provider_for_output("", response_output=[message])

    with pytest.raises(EnrichmentRefusalError):
        provider.enrich(capture)


def test_provider_rejects_incomplete_response_even_with_valid_json(
    tmp_path: Path,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture())
    provider, _ = provider_for_output(
        json.dumps(valid_output()),
        response_status="incomplete",
    )

    with pytest.raises(EnrichmentProviderError):
        provider.enrich(capture)


@pytest.mark.parametrize(
    "output",
    [
        "not JSON",
        json.dumps({"title": "Only one field"}),
        json.dumps({**valid_output(), "title": "Interesting Note"}),
        json.dumps({**valid_output(), "summary": "   "}),
        json.dumps({**valid_output(), "tags": ["FastAPI", "  "]}),
    ],
)
def test_provider_rejects_structurally_or_semantically_invalid_output(
    tmp_path: Path,
    output: str,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture())
    provider, _ = provider_for_output(output)

    with pytest.raises(InvalidEnrichmentOutputError):
        provider.enrich(capture)


@pytest.mark.parametrize(
    "provider_error",
    [
        RuntimeError("unauthorized model: secret trace"),
        TimeoutError("provider timeout: secret trace"),
        ConnectionError("connection failed: secret trace"),
    ],
)
def test_provider_wraps_remote_failures_without_exposing_details(
    tmp_path: Path,
    provider_error: Exception,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture())
    responses = FakeResponses(error=provider_error)
    provider = OpenAIEnrichmentProvider(
        api_key="test-only",
        model="gpt-5.6",
        client=FakeClient(responses),
    )

    with pytest.raises(EnrichmentProviderError) as raised:
        provider.enrich(capture)

    assert "secret trace" not in str(raised.value)


def test_service_stores_valid_result_without_modifying_source(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(), status="processing")
    result = EnrichmentPayload.model_validate(valid_output())

    EnrichmentService(repository, StaticProvider(result)).run(capture.id)
    loaded = repository.get(capture.id)

    assert loaded is not None
    assert loaded.status == "ready"
    assert loaded.selected_text == capture.selected_text
    assert loaded.surrounding_context == capture.surrounding_context
    assert loaded.user_note == capture.user_note
    assert loaded.ai_title == result.title
    assert loaded.tags == result.tags
    assert loaded.error_message is None
    assert loaded.enrichment_version == 1


@pytest.mark.parametrize(
    "error,expected_message",
    [
        (EnrichmentRefusalError(), "The AI provider refused this Capture."),
        (
            InvalidEnrichmentOutputError(),
            "The configured AI model returned an invalid enrichment result. "
            "Try a compatible model or retry.",
        ),
        (EnrichmentProviderError(), "AI enrichment could not be completed. Retry later."),
        (RuntimeError("raw provider trace"), "AI enrichment could not be completed. Retry later."),
    ],
)
def test_service_persists_safe_error_without_source_loss(
    tmp_path: Path,
    error: Exception,
    expected_message: str,
) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(), status="processing")

    EnrichmentService(repository, FailingProvider(error)).run(capture.id)
    loaded = repository.get(capture.id)

    assert loaded is not None
    assert loaded.status == "error"
    assert loaded.error_message == expected_message
    assert "raw provider trace" not in loaded.error_message
    assert loaded.selected_text == capture.selected_text
    assert loaded.user_note == capture.user_note


def test_failed_retry_preserves_existing_enrichment_version(tmp_path: Path) -> None:
    repository = CaptureRepository(tmp_path / "recall.db")
    capture = repository.create(new_capture(), status="processing")
    repository.update_enrichment(
        capture.id,
        EnrichmentUpdate(
            status="processing",
            enrichment_version=3,
        ),
    )

    EnrichmentService(
        repository,
        FailingProvider(EnrichmentProviderError()),
    ).run(capture.id)
    loaded = repository.get(capture.id)

    assert loaded is not None
    assert loaded.status == "error"
    assert loaded.enrichment_version == 3
