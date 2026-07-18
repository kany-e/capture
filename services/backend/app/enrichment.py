"""OpenAI Structured Output provider and Capture enrichment orchestration."""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from importlib.resources import files
from typing import Any, Protocol

from openai import OpenAI
from pydantic import BaseModel, ConfigDict, ValidationError

from app.embeddings import (
    EmbeddingProvider,
    build_embedding_input,
)
from app.models import CaptureRecord, EnrichmentUpdate
from app.repository import CaptureNotFoundError, CaptureRepository


logger = logging.getLogger(__name__)
ENRICHMENT_SCHEMA_RESOURCE = files("app").joinpath(
    "schemas/enriched_capture.schema.json"
)
ENRICHMENT_TIMEOUT_SECONDS = 45.0
ENRICHMENT_MAX_RETRIES = 0
GENERIC_TITLES = frozenset(
    {"interesting note", "linux information", "a useful solution"}
)

SYSTEM_INSTRUCTIONS = """You transform captured source material into a compact personal memory record.

Your output is not a generic article summary. Its purpose is to help the same user remember, months later:

1. what they were doing,
2. what problem or idea they encountered,
3. what the saved content contributed,
4. why they personally saved it,
5. what cautions matter when applying it again.

Strictly distinguish among:
- facts stated by the source,
- context explicitly provided by the user,
- cautious inferences.

Do not invent technical details.
Do not claim the saved method worked unless the user's note says it worked.
Preserve exact error codes, commands, product names, APIs, libraries, and technical entities when present.

Generate:
- a concise, specific title;
- a contextual memory summary;
- the underlying problem or subject;
- the key insight;
- why the user likely saved it, primarily grounded in the user note;
- practical caveats;
- a small set of reusable tags;
- named entities;
- natural-language search aliases, including memorable or emotional descriptions used by the user.

If no user note was supplied, explicitly state in why_saved that no personal reason was provided. Never invent one.
Use the language most appropriate to the user's note and captured content.
"""


class EnrichmentPayload(BaseModel):
    """Validated provider output matching enriched_capture.schema.json."""

    model_config = ConfigDict(extra="forbid")

    title: str
    summary: str
    problem: str
    key_insight: str
    why_saved: str
    caveats: list[str]
    tags: list[str]
    entities: list[str]
    search_aliases: list[str]


class EnrichmentFailure(RuntimeError):
    code = "provider_failure"
    safe_message = "AI enrichment could not be completed. Retry later."


class EnrichmentRefusalError(EnrichmentFailure):
    code = "refusal"
    safe_message = "The AI provider refused this Capture."


class InvalidEnrichmentOutputError(EnrichmentFailure):
    code = "invalid_output"
    safe_message = "AI enrichment returned an invalid result."


class EnrichmentProviderError(EnrichmentFailure):
    code = "provider_unavailable"


class EnrichmentProvider(Protocol):
    def enrich(self, capture: CaptureRecord) -> EnrichmentPayload: ...


@lru_cache(maxsize=1)
def enrichment_schema() -> dict[str, Any]:
    return json.loads(ENRICHMENT_SCHEMA_RESOURCE.read_text(encoding="utf-8"))


def _prompt_value(value: str | None) -> str:
    if value is None:
        return ""
    return value.replace("\r\n", "\n").replace("\r", "\n").strip()


def build_user_input(capture: CaptureRecord) -> str:
    """Build product-plan §11.6 input without changing persisted originals."""

    fields = (
        ("SOURCE TYPE", capture.source_type),
        ("SOURCE APPLICATION", capture.source_app),
        ("SOURCE TITLE", capture.source_title),
        ("SOURCE URL", capture.source_url),
        ("SELECTED CONTENT", capture.selected_text),
        ("SURROUNDING CONTEXT", capture.surrounding_context),
        ("USER NOTE", capture.user_note),
    )
    return "\n\n".join(
        f"{label}:\n{_prompt_value(value)}" for label, value in fields
    )


def _normalized_payload(payload: EnrichmentPayload) -> EnrichmentPayload:
    values = payload.model_dump()
    for field in ("title", "summary", "problem", "key_insight", "why_saved"):
        value = values[field].strip()
        if not value:
            raise InvalidEnrichmentOutputError
        values[field] = value

    if values["title"].casefold() in GENERIC_TITLES:
        raise InvalidEnrichmentOutputError

    for field in ("caveats", "tags", "entities", "search_aliases"):
        normalized = [value.strip() for value in values[field]]
        if any(not value for value in normalized):
            raise InvalidEnrichmentOutputError
        values[field] = normalized

    return EnrichmentPayload.model_validate(values)


def _refusal_from_response(response: Any) -> str | None:
    for output in getattr(response, "output", ()):
        if getattr(output, "type", None) != "message":
            continue
        for item in getattr(output, "content", ()):
            if getattr(item, "type", None) == "refusal":
                return getattr(item, "refusal", None) or "refused"
    return None


class OpenAIEnrichmentProvider:
    """One-request OpenAI provider using the checked-in strict JSON Schema."""

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
            timeout=ENRICHMENT_TIMEOUT_SECONDS,
            max_retries=ENRICHMENT_MAX_RETRIES,
        )

    def enrich(self, capture: CaptureRecord) -> EnrichmentPayload:
        try:
            response = self._client.responses.create(
                model=self.model,
                instructions=SYSTEM_INSTRUCTIONS,
                input=build_user_input(capture),
                text={
                    "format": {
                        "type": "json_schema",
                        "name": "recall_enrichment",
                        "strict": True,
                        "schema": enrichment_schema(),
                    }
                },
            )
        except Exception as error:
            raise EnrichmentProviderError from error

        if getattr(response, "status", None) != "completed":
            raise EnrichmentProviderError

        if _refusal_from_response(response) is not None:
            raise EnrichmentRefusalError

        output_text = getattr(response, "output_text", None)
        if not isinstance(output_text, str) or not output_text.strip():
            raise InvalidEnrichmentOutputError

        try:
            payload = EnrichmentPayload.model_validate(json.loads(output_text))
        except (json.JSONDecodeError, ValidationError) as error:
            raise InvalidEnrichmentOutputError from error
        return _normalized_payload(payload)


class EnrichmentService:
    """Apply one provider result to a Capture without exposing source data."""

    def __init__(
        self,
        repository: CaptureRepository,
        provider: EnrichmentProvider,
        embedding_provider: EmbeddingProvider | None = None,
    ) -> None:
        self.repository = repository
        self.provider = provider
        self.embedding_provider = embedding_provider

    def run(self, capture_id: str) -> None:
        capture = self.repository.get(capture_id)
        if capture is None:
            logger.warning("Enrichment skipped for missing Capture %s", capture_id)
            return

        try:
            result = self.provider.enrich(capture)
        except EnrichmentFailure as error:
            logger.warning(
                "Enrichment failed for Capture %s (%s)",
                capture_id,
                error.code,
            )
            self._store_error(
                capture_id,
                error.safe_message,
                capture.enrichment_version,
            )
            return
        except Exception:
            logger.exception("Unexpected enrichment failure for Capture %s", capture_id)
            self._store_error(
                capture_id,
                EnrichmentFailure.safe_message,
                capture.enrichment_version,
            )
            return

        update = EnrichmentUpdate(
            status="ready",
            ai_title=result.title,
            ai_summary=result.summary,
            problem=result.problem,
            key_insight=result.key_insight,
            why_saved=result.why_saved,
            caveats=result.caveats,
            tags=result.tags,
            entities=result.entities,
            search_aliases=result.search_aliases,
            embedding=self._generate_embedding(capture, result),
            error_message=None,
            enrichment_version=capture.enrichment_version,
        )
        self.repository.update_enrichment(capture_id, update)

    def _generate_embedding(
        self,
        capture: CaptureRecord,
        result: EnrichmentPayload,
    ) -> list[float] | None:
        if self.embedding_provider is None:
            return None

        enriched_capture = capture.model_copy(
            update={
                "status": "ready",
                "ai_title": result.title,
                "ai_summary": result.summary,
                "problem": result.problem,
                "key_insight": result.key_insight,
                "why_saved": result.why_saved,
                "caveats": result.caveats,
                "tags": result.tags,
                "entities": result.entities,
                "search_aliases": result.search_aliases,
            }
        )
        try:
            return self.embedding_provider.embed(
                build_embedding_input(enriched_capture)
            )
        except Exception:
            logger.warning(
                "Embedding failed for Capture %s; keyword fallback remains available",
                capture.id,
            )
            return None

    def _store_error(
        self,
        capture_id: str,
        message: str,
        enrichment_version: int,
    ) -> None:
        try:
            self.repository.update_enrichment(
                capture_id,
                EnrichmentUpdate(
                    status="error",
                    error_message=message,
                    enrichment_version=enrichment_version,
                ),
            )
        except CaptureNotFoundError:
            logger.warning("Could not store enrichment error; Capture %s is missing", capture_id)


def mark_enrichment_not_configured(
    repository: CaptureRepository,
    capture_id: str,
) -> None:
    capture = repository.get(capture_id)
    if capture is None:
        logger.warning(
            "Could not store configuration error; Capture %s is missing",
            capture_id,
        )
        return
    repository.update_enrichment(
        capture_id,
        EnrichmentUpdate(
            status="error",
            error_message="AI enrichment is not configured.",
            enrichment_version=capture.enrichment_version,
        ),
    )
