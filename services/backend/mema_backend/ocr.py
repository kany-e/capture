"""Provider-neutral, one-shot screenshot text extraction."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from typing import Any, Literal, Protocol

from openai import OpenAI

from mema_backend.limits import OCR_TEXT_MAX_LENGTH, SCREENSHOT_MAX_BYTES


OCR_TIMEOUT_SECONDS = 45.0
OCR_MAX_RETRIES = 0
OCR_INSTRUCTIONS = """Extract all visible text from this screenshot.

Return only the extracted text, with useful line breaks and reading order.
Preserve spelling, punctuation, numbers, URLs, commands, and code exactly when visible.
Do not summarize, explain, translate, or add Markdown fences.
"""


class ScreenshotValidationError(ValueError):
    pass


class OCRFailure(RuntimeError):
    code = "ocr_provider_unavailable"
    safe_message = (
        "GPT text extraction is temporarily unavailable. "
        "Try again or use Apple Vision on device."
    )


class OCRRefusalError(OCRFailure):
    code = "ocr_refused"
    safe_message = (
        "GPT could not extract text from this screenshot. "
        "Try a smaller region or use Apple Vision on device."
    )


class InvalidOCROutputError(OCRFailure):
    code = "invalid_ocr_output"
    safe_message = (
        "GPT returned no usable screenshot text. "
        "Try a clearer region or use Apple Vision on device."
    )


class OCRTextTooLongError(OCRFailure):
    code = "ocr_text_too_long"
    safe_message = (
        "The screenshot contains too much source text for one Capture. "
        "Capture a smaller region and try again."
    )


@dataclass(frozen=True)
class OCRResult:
    text: str
    provider: Literal["openai"]
    processing_location: Literal["cloud"]
    model: str


class OCRProvider(Protocol):
    def extract_text(self, image: bytes, media_type: str) -> OCRResult: ...


def decode_screenshot(encoded: str, media_type: str) -> bytes:
    try:
        image = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ScreenshotValidationError("image_base64 must be valid base64") from error

    if not image:
        raise ScreenshotValidationError("image_base64 must decode to a non-empty image")
    if len(image) > SCREENSHOT_MAX_BYTES:
        raise ScreenshotValidationError(
            f"screenshot must not exceed {SCREENSHOT_MAX_BYTES} bytes"
        )

    valid_signature = (
        media_type == "image/png" and image.startswith(b"\x89PNG\r\n\x1a\n")
    ) or (media_type == "image/jpeg" and image.startswith(b"\xff\xd8\xff"))
    if not valid_signature:
        raise ScreenshotValidationError("image bytes do not match media_type")
    return image


def _refusal_from_response(response: Any) -> bool:
    for output in getattr(response, "output", ()):
        if getattr(output, "type", None) != "message":
            continue
        for item in getattr(output, "content", ()):
            if getattr(item, "type", None) == "refusal":
                return True
    return False


def normalize_ocr_text(value: object) -> str:
    if not isinstance(value, str):
        raise InvalidOCROutputError
    text = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        raise InvalidOCROutputError
    if len(text) > OCR_TEXT_MAX_LENGTH:
        raise OCRTextTooLongError
    return text


class OpenAIOCRProvider:
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        client: Any | None = None,
    ) -> None:
        self.model = model
        self._client = client or OpenAI(
            api_key=api_key,
            timeout=OCR_TIMEOUT_SECONDS,
            max_retries=OCR_MAX_RETRIES,
        )

    def extract_text(self, image: bytes, media_type: str) -> OCRResult:
        image_url = f"data:{media_type};base64,{base64.b64encode(image).decode('ascii')}"
        try:
            response = self._client.responses.create(
                model=self.model,
                store=False,
                input=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "input_text", "text": OCR_INSTRUCTIONS},
                            {
                                "type": "input_image",
                                "image_url": image_url,
                                "detail": "high",
                            },
                        ],
                    }
                ],
            )
        except Exception as error:
            raise OCRFailure from error

        if getattr(response, "status", None) != "completed":
            raise OCRFailure
        if _refusal_from_response(response):
            raise OCRRefusalError

        return OCRResult(
            text=normalize_ocr_text(getattr(response, "output_text", None)),
            provider="openai",
            processing_location="cloud",
            model=self.model,
        )
