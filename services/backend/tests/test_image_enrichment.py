from __future__ import annotations

import base64
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

import mema_backend.image_enrichment as image_enrichment_module
from mema_backend.enrichment import (
    EnrichmentProviderError,
    EnrichmentRefusalError,
    InvalidEnrichmentOutputError,
)
from mema_backend.image_enrichment import (
    IMAGE_ENRICHMENT_MAX_RETRIES,
    IMAGE_ENRICHMENT_TIMEOUT_SECONDS,
    IMAGE_SYSTEM_INSTRUCTIONS,
    ImageEnrichmentPayload,
    OpenAIImageEnrichmentProvider,
    image_enrichment_schema,
)
from mema_backend.models import NewCapture
from mema_backend.repository import CaptureRepository


def valid_output() -> dict[str, object]:
    return {
        "extracted_text": "Logistic Growth\r\nln absolute values",
        "title": "Logistic growth derivation diagram",
        "summary": "A diagram explaining how an arbitrary constant absorbs signs.",
        "problem": "Understanding a logistic-growth derivation.",
        "key_insight": "The integration constant absorbs the sign.",
        "why_saved": "The user wants to remember the diagram.",
        "caveats": ["The original image remains authoritative."],
        "tags": ["logistic growth", "differential equations"],
        "entities": ["Logistic Growth"],
        "search_aliases": ["ln sign absorbed by constant"],
    }


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


def provider_for(
    output: object,
    *,
    status: str = "completed",
    response_output: list[object] | None = None,
) -> tuple[OpenAIImageEnrichmentProvider, FakeResponses]:
    responses = FakeResponses(
        SimpleNamespace(
            status=status,
            output_text=output,
            output=response_output or [],
        )
    )
    return (
        OpenAIImageEnrichmentProvider(
            api_key="test-only",
            model="gpt-5.6",
            client=FakeClient(responses),
        ),
        responses,
    )


def capture_record(tmp_path: Path):
    return CaptureRepository(tmp_path / "mema.db").create(
        NewCapture(
            captured_at="2026-07-21T10:30:00-07:00",
            source_type="screenshot",
            source_app="Gemini",
            selected_text="",
            user_note="Remember this visual relationship.",
        ),
        status="processing",
    )


def test_image_model_fields_match_packaged_strict_schema() -> None:
    assert set(ImageEnrichmentPayload.model_fields) == set(
        image_enrichment_schema()["properties"]
    )


def test_provider_bounds_timeout_and_disables_sdk_retries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = SimpleNamespace(responses=FakeResponses())
    configured: dict[str, object] = {}

    def fake_openai(**kwargs: object) -> object:
        configured.update(kwargs)
        return client

    monkeypatch.setattr(image_enrichment_module, "OpenAI", fake_openai)
    provider = OpenAIImageEnrichmentProvider(
        api_key="test-only",
        model="gpt-5.6",
    )

    assert provider._client is client
    assert configured == {
        "api_key": "test-only",
        "timeout": IMAGE_ENRICHMENT_TIMEOUT_SECONDS,
        "max_retries": IMAGE_ENRICHMENT_MAX_RETRIES,
    }
    assert IMAGE_ENRICHMENT_TIMEOUT_SECONDS <= 60
    assert IMAGE_ENRICHMENT_MAX_RETRIES == 0


def test_provider_sends_one_strict_high_detail_multimodal_request(
    tmp_path: Path,
) -> None:
    capture = capture_record(tmp_path)
    provider, responses = provider_for(json.dumps(valid_output()))
    image = b"private screenshot bytes"

    result = provider.analyze(capture, image, "image/png")

    assert result.extracted_text == "Logistic Growth\nln absolute values"
    assert len(responses.calls) == 1
    request = responses.calls[0]
    assert request["model"] == "gpt-5.6"
    assert request["store"] is False
    assert request["instructions"] == IMAGE_SYSTEM_INSTRUCTIONS
    assert request["text"] == {
        "format": {
            "type": "json_schema",
            "name": "mema_image_enrichment",
            "strict": True,
            "schema": image_enrichment_schema(),
        }
    }
    content = request["input"][0]["content"]  # type: ignore[index]
    assert "Remember this visual relationship" in content[0]["text"]
    assert content[1] == {
        "type": "input_image",
        "image_url": (
            "data:image/png;base64," + base64.b64encode(image).decode("ascii")
        ),
        "detail": "high",
    }


def test_provider_rejects_refusal_incomplete_invalid_and_remote_failure(
    tmp_path: Path,
) -> None:
    capture = capture_record(tmp_path)
    refusal = SimpleNamespace(type="refusal", refusal="Cannot inspect")
    message = SimpleNamespace(type="message", content=[refusal])
    refused, _ = provider_for("", response_output=[message])
    with pytest.raises(EnrichmentRefusalError):
        refused.analyze(capture, b"image", "image/png")

    incomplete, _ = provider_for(json.dumps(valid_output()), status="incomplete")
    with pytest.raises(EnrichmentProviderError):
        incomplete.analyze(capture, b"image", "image/png")

    invalid, _ = provider_for(json.dumps({"title": "partial"}))
    with pytest.raises(InvalidEnrichmentOutputError):
        invalid.analyze(capture, b"image", "image/png")

    responses = FakeResponses(error=RuntimeError("secret provider trace"))
    failing = OpenAIImageEnrichmentProvider(
        api_key="test-only",
        model="gpt-5.6",
        client=FakeClient(responses),
    )
    with pytest.raises(EnrichmentProviderError) as raised:
        failing.analyze(capture, b"image", "image/png")
    assert "secret provider trace" not in str(raised.value)
