"""Background OCR plus visual-memory enrichment for persisted image notes."""

from __future__ import annotations

import base64
import json
import logging
from functools import lru_cache
from importlib.resources import files
from typing import Annotated, Any, Protocol

from openai import OpenAI
from pydantic import ConfigDict, StringConstraints, ValidationError

from app.attachments import AttachmentStorage, AttachmentStorageError
from app.embeddings import EmbeddingProvider, build_embedding_input
from app.enrichment import (
    EnrichmentFailure,
    EnrichmentPayload,
    EnrichmentProviderError,
    EnrichmentRefusalError,
    InvalidEnrichmentOutputError,
    _normalized_payload,
)
from app.limits import SELECTED_TEXT_MAX_LENGTH
from app.models import CaptureRecord, EnrichmentUpdate
from app.repository import CaptureNotFoundError, CaptureRepository


logger = logging.getLogger(__name__)
IMAGE_ENRICHMENT_SCHEMA_RESOURCE = files("app").joinpath(
    "schemas/image_enrichment.schema.json"
)
IMAGE_ENRICHMENT_TIMEOUT_SECONDS = 60.0
IMAGE_ENRICHMENT_MAX_RETRIES = 0

IMAGE_SYSTEM_INSTRUCTIONS = """You turn one saved screenshot into a searchable personal memory.

Analyze both visible text and visual meaning. The original image remains authoritative.

For extracted_text:
- transcribe visible text in useful reading order;
- preserve spelling, punctuation, numbers, commands, code, formulas, and line breaks when visible;
- do not add commentary or Markdown fences;
- return an empty string only when no text is readable.

For the memory fields:
- describe what the image actually shows, including diagrams, charts, interfaces, objects, and relationships that OCR alone misses;
- generate a concise specific title, contextual summary, subject/problem, key insight, practical caveats, reusable tags, named entities, and natural search aliases;
- distinguish visible facts, user-provided context, and cautious inference;
- never claim a method worked unless the user's note says it did;
- if no user note was supplied, explicitly say that no personal reason was provided.

Use the language most appropriate to the screenshot and the user's note. The output exists primarily to make the image discoverable later.
"""


ExtractedImageText = Annotated[
    str,
    StringConstraints(max_length=SELECTED_TEXT_MAX_LENGTH),
]


class ImageEnrichmentPayload(EnrichmentPayload):
    model_config = ConfigDict(extra="forbid")

    extracted_text: ExtractedImageText


class ImageEnrichmentProvider(Protocol):
    def analyze(
        self,
        capture: CaptureRecord,
        image: bytes,
        media_type: str,
    ) -> ImageEnrichmentPayload: ...


@lru_cache(maxsize=1)
def image_enrichment_schema() -> dict[str, Any]:
    return json.loads(IMAGE_ENRICHMENT_SCHEMA_RESOURCE.read_text(encoding="utf-8"))


def _image_user_context(capture: CaptureRecord) -> str:
    source_app = (capture.source_app or "").strip()
    user_note = (capture.user_note or "").strip()
    corrected_text = (
        capture.selected_text.strip() if capture.user_selected_text is not None else ""
    )
    return (
        f"SOURCE TYPE:\n{capture.source_type}\n\n"
        f"SOURCE APPLICATION:\n{source_app}\n\n"
        f"USER NOTE:\n{user_note}\n\n"
        f"USER-CORRECTED VISIBLE TEXT:\n{corrected_text}"
    )


def _response_was_refused(response: Any) -> bool:
    for output in getattr(response, "output", ()):
        if getattr(output, "type", None) != "message":
            continue
        for item in getattr(output, "content", ()):
            if getattr(item, "type", None) == "refusal":
                return True
    return False


def _normalized_image_payload(payload: object) -> ImageEnrichmentPayload:
    try:
        validated = ImageEnrichmentPayload.model_validate(payload)
    except ValidationError as error:
        raise InvalidEnrichmentOutputError from error

    extracted_text = (
        validated.extracted_text.replace("\r\n", "\n").replace("\r", "\n").strip()
    )
    enrichment = _normalized_payload(
        validated.model_dump(exclude={"extracted_text"})
    )
    return ImageEnrichmentPayload(
        extracted_text=extracted_text,
        **enrichment.model_dump(),
    )


class OpenAIImageEnrichmentProvider:
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
            timeout=IMAGE_ENRICHMENT_TIMEOUT_SECONDS,
            max_retries=IMAGE_ENRICHMENT_MAX_RETRIES,
        )

    def analyze(
        self,
        capture: CaptureRecord,
        image: bytes,
        media_type: str,
    ) -> ImageEnrichmentPayload:
        image_url = f"data:{media_type};base64,{base64.b64encode(image).decode('ascii')}"
        try:
            response = self._client.responses.create(
                model=self.model,
                store=False,
                instructions=IMAGE_SYSTEM_INSTRUCTIONS,
                input=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "input_text",
                                "text": _image_user_context(capture),
                            },
                            {
                                "type": "input_image",
                                "image_url": image_url,
                                "detail": "high",
                            },
                        ],
                    }
                ],
                text={
                    "format": {
                        "type": "json_schema",
                        "name": "recall_image_enrichment",
                        "strict": True,
                        "schema": image_enrichment_schema(),
                    }
                },
            )
        except Exception as error:
            raise EnrichmentProviderError from error

        if getattr(response, "status", None) != "completed":
            raise EnrichmentProviderError
        if _response_was_refused(response):
            raise EnrichmentRefusalError

        output_text = getattr(response, "output_text", None)
        if not isinstance(output_text, str) or not output_text.strip():
            raise InvalidEnrichmentOutputError
        try:
            payload = json.loads(output_text)
        except json.JSONDecodeError as error:
            raise InvalidEnrichmentOutputError from error
        return _normalized_image_payload(payload)


class ImageEnrichmentService:
    def __init__(
        self,
        repository: CaptureRepository,
        storage: AttachmentStorage,
        provider: ImageEnrichmentProvider,
        embedding_provider: EmbeddingProvider | None = None,
    ) -> None:
        self.repository = repository
        self.storage = storage
        self.provider = provider
        self.embedding_provider = embedding_provider

    def run(self, capture_id: str, attachment_id: str) -> None:
        capture = self.repository.get(capture_id)
        attachment = self.repository.get_attachment(attachment_id)
        if capture is None or attachment is None or attachment.capture_id != capture_id:
            logger.warning("Image enrichment skipped for missing Capture or attachment %s", capture_id)
            return

        try:
            image = self.storage.read_path(attachment.relative_path).read_bytes()
            result = _normalized_image_payload(
                self.provider.analyze(capture, image, attachment.media_type)
            )
            enrichment = EnrichmentPayload.model_validate(
                result.model_dump(exclude={"extracted_text"})
            )
            update = EnrichmentUpdate(
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
                embedding=self._generate_embedding(
                    capture,
                    result.extracted_text,
                    enrichment,
                ),
                enrichment_version=capture.enrichment_version,
            )
            self.repository.update_image_enrichment(
                capture_id,
                extracted_text=result.extracted_text,
                update=update,
            )
        except (EnrichmentFailure, AttachmentStorageError, OSError) as error:
            logger.warning("Image enrichment failed for Capture %s: %s", capture_id, error)
            self._store_error(capture)
        except Exception:
            logger.exception("Unexpected image enrichment failure for Capture %s", capture_id)
            self._store_error(capture)

    def _generate_embedding(
        self,
        capture: CaptureRecord,
        extracted_text: str,
        enrichment: EnrichmentPayload,
    ) -> list[float] | None:
        if self.embedding_provider is None:
            return None
        enriched_capture = capture.model_copy(
            update={
                "selected_text": (
                    capture.selected_text
                    if capture.user_selected_text is not None
                    else extracted_text
                ),
                "status": "ready",
                "ai_title": enrichment.title,
                "ai_summary": enrichment.summary,
                "problem": enrichment.problem,
                "key_insight": enrichment.key_insight,
                "why_saved": enrichment.why_saved,
                "caveats": enrichment.caveats,
                "tags": enrichment.tags,
                "entities": enrichment.entities,
                "search_aliases": enrichment.search_aliases,
            }
        )
        try:
            return self.embedding_provider.embed(build_embedding_input(enriched_capture))
        except Exception:
            logger.warning("Image embedding failed for Capture %s", capture.id)
            return None

    def _store_error(self, capture: CaptureRecord) -> None:
        try:
            self.repository.update_enrichment(
                capture.id,
                EnrichmentUpdate(
                    status="error",
                    error_message=(
                        "AI image analysis could not be completed. The original image is safe; retry later."
                    ),
                    enrichment_version=capture.enrichment_version,
                ),
            )
        except CaptureNotFoundError:
            logger.warning("Could not store image analysis error for missing Capture %s", capture.id)


def mark_image_analysis_not_configured(
    repository: CaptureRepository,
    capture_id: str,
) -> None:
    capture = repository.get(capture_id)
    if capture is None:
        return
    repository.update_enrichment(
        capture_id,
        EnrichmentUpdate(
            status="error",
            error_message=(
                "AI image analysis is not configured. The original image remains saved."
            ),
            enrichment_version=capture.enrichment_version,
        ),
    )
