from __future__ import annotations

import base64
from types import SimpleNamespace

import pytest

import mema_backend.ocr as ocr_module
from mema_backend.limits import OCR_TEXT_MAX_LENGTH, SCREENSHOT_MAX_BYTES
from mema_backend.ocr import (
    OCR_INSTRUCTIONS,
    OCR_MAX_RETRIES,
    OCR_TIMEOUT_SECONDS,
    InvalidOCROutputError,
    OCRFailure,
    OCRRefusalError,
    OCRTextTooLongError,
    OpenAIOCRProvider,
    decode_screenshot,
)


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
    output_text: object,
    *,
    status: str = "completed",
    output: list[object] | None = None,
) -> tuple[OpenAIOCRProvider, FakeResponses]:
    responses = FakeResponses(
        SimpleNamespace(status=status, output_text=output_text, output=output or [])
    )
    return (
        OpenAIOCRProvider(
            api_key="test-only",
            model="gpt-5.6",
            client=FakeClient(responses),
        ),
        responses,
    )


def test_provider_bounds_timeout_and_disables_sdk_retries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = SimpleNamespace(responses=FakeResponses())
    configured: dict[str, object] = {}

    def fake_openai(**kwargs: object) -> object:
        configured.update(kwargs)
        return client

    monkeypatch.setattr(ocr_module, "OpenAI", fake_openai)
    provider = OpenAIOCRProvider(api_key="test-only", model="gpt-5.6")

    assert provider._client is client
    assert configured == {
        "api_key": "test-only",
        "timeout": OCR_TIMEOUT_SECONDS,
        "max_retries": OCR_MAX_RETRIES,
    }


def test_provider_sends_one_high_detail_image_request_and_returns_exact_text() -> None:
    provider, responses = provider_for("  First line\r\nSecond line  ")
    image = b"\x89PNG\r\n\x1a\nprivate bytes"

    result = provider.extract_text(image, "image/png")

    assert result.text == "First line\nSecond line"
    assert result.processing_location == "cloud"
    assert result.model == "gpt-5.6"
    assert len(responses.calls) == 1
    request = responses.calls[0]
    assert request["model"] == "gpt-5.6"
    assert request["store"] is False
    content = request["input"][0]["content"]  # type: ignore[index]
    assert content[0] == {"type": "input_text", "text": OCR_INSTRUCTIONS}
    assert content[1]["type"] == "input_image"
    assert content[1]["detail"] == "high"
    assert content[1]["image_url"] == (
        "data:image/png;base64," + base64.b64encode(image).decode("ascii")
    )


def test_provider_detects_refusal_before_empty_output() -> None:
    refusal = SimpleNamespace(type="refusal", refusal="Cannot inspect")
    message = SimpleNamespace(type="message", content=[refusal])
    provider, _ = provider_for("", output=[message])

    with pytest.raises(OCRRefusalError):
        provider.extract_text(b"image", "image/png")


@pytest.mark.parametrize("output", [None, "", " \n ", 42])
def test_provider_rejects_empty_or_invalid_output(output: object) -> None:
    provider, _ = provider_for(output)

    with pytest.raises(InvalidOCROutputError):
        provider.extract_text(b"image", "image/png")


def test_provider_rejects_oversized_text_without_truncating() -> None:
    assert OCR_TEXT_MAX_LENGTH == 12_000
    provider, _ = provider_for("x" * (OCR_TEXT_MAX_LENGTH + 1))

    with pytest.raises(OCRTextTooLongError):
        provider.extract_text(b"image", "image/png")


def test_provider_accepts_text_at_selected_source_limit() -> None:
    exact = "x" * OCR_TEXT_MAX_LENGTH
    provider, _ = provider_for(exact)

    result = provider.extract_text(b"image", "image/png")

    assert result.text == exact


def test_provider_maps_incomplete_response_and_sdk_details_to_safe_failure() -> None:
    provider, _ = provider_for("text", status="incomplete")
    with pytest.raises(OCRFailure):
        provider.extract_text(b"image", "image/png")

    responses = FakeResponses(error=RuntimeError("secret provider trace"))
    provider = OpenAIOCRProvider(
        api_key="test-only", model="gpt-5.6", client=FakeClient(responses)
    )
    with pytest.raises(OCRFailure) as raised:
        provider.extract_text(b"image", "image/png")
    assert "secret provider trace" not in str(raised.value)


def test_decode_screenshot_validates_base64_size_media_type_and_signature() -> None:
    png = b"\x89PNG\r\n\x1a\nbytes"
    assert decode_screenshot(base64.b64encode(png).decode("ascii"), "image/png") == png

    with pytest.raises(ValueError):
        decode_screenshot("***", "image/png")
    with pytest.raises(ValueError):
        decode_screenshot(base64.b64encode(png).decode("ascii"), "image/jpeg")

    maximum = b"\x89PNG\r\n\x1a\n" + b"x" * (SCREENSHOT_MAX_BYTES - 8)
    assert len(decode_screenshot(base64.b64encode(maximum).decode(), "image/png")) == (
        SCREENSHOT_MAX_BYTES
    )
    oversized = maximum + b"x"
    with pytest.raises(ValueError):
        decode_screenshot(base64.b64encode(oversized).decode(), "image/png")
