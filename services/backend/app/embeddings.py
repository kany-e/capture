"""Stable embedding projection and provider-neutral vector operations."""

from __future__ import annotations

import math
from typing import Any, Protocol

from openai import OpenAI

from app.models import CaptureRecord


EMBEDDING_TIMEOUT_SECONDS = 20.0
EMBEDDING_MAX_RETRIES = 0


class EmbeddingProviderError(RuntimeError):
    """Raised when an embedding request cannot produce a usable vector."""


class EmbeddingProvider(Protocol):
    def embed(self, text: str) -> list[float]: ...


def _projection_value(value: str | None) -> str:
    if value is None:
        return ""
    return value.replace("\r\n", "\n").replace("\r", "\n").strip()


def build_embedding_input(capture: CaptureRecord) -> str:
    """Build the exact product-plan §12.1 projection with a final newline."""

    fields = (
        ("TITLE", capture.ai_title),
        ("SUMMARY", capture.ai_summary),
        ("USER NOTE", capture.user_note),
        ("SELECTED CONTENT", capture.selected_text),
        ("PROBLEM", capture.problem),
        ("KEY INSIGHT", capture.key_insight),
        ("TAGS", ", ".join(_projection_value(value) for value in capture.tags)),
        (
            "SEARCH ALIASES",
            ", ".join(
                _projection_value(value) for value in capture.search_aliases
            ),
        ),
    )
    return (
        "\n\n".join(
            f"{label}:\n{_projection_value(value)}" for label, value in fields
        )
        + "\n"
    )


def _validated_vector(value: object) -> list[float]:
    if not isinstance(value, (list, tuple)) or not value:
        raise EmbeddingProviderError

    vector: list[float] = []
    for component in value:
        if isinstance(component, bool) or not isinstance(component, (int, float)):
            raise EmbeddingProviderError
        number = float(component)
        if not math.isfinite(number):
            raise EmbeddingProviderError
        vector.append(number)
    return vector


class OpenAIEmbeddingProvider:
    """One-request OpenAI embedding provider using default model dimensions."""

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
            timeout=EMBEDDING_TIMEOUT_SECONDS,
            max_retries=EMBEDDING_MAX_RETRIES,
        )

    def embed(self, text: str) -> list[float]:
        if not text.strip():
            raise EmbeddingProviderError

        try:
            response = self._client.embeddings.create(
                model=self.model,
                input=text,
                encoding_format="float",
            )
            data = getattr(response, "data", None)
            if not isinstance(data, (list, tuple)) or len(data) != 1:
                raise EmbeddingProviderError
            return _validated_vector(getattr(data[0], "embedding", None))
        except EmbeddingProviderError:
            raise
        except Exception as error:
            raise EmbeddingProviderError from error


def normalized_embedding(value: list[float]) -> tuple[float, ...] | None:
    """Return an overflow-safe unit vector or ``None`` for unusable input."""

    if not value:
        return None
    if any(
        isinstance(component, bool)
        or not isinstance(component, (int, float))
        or not math.isfinite(float(component))
        for component in value
    ):
        return None

    components = tuple(float(component) for component in value)
    norm = math.hypot(*components)
    if norm == 0.0 or not math.isfinite(norm):
        return None
    return tuple(component / norm for component in components)


def cosine_similarity(left: list[float], right: list[float]) -> float | None:
    """Return a finite cosine score in ``0...1`` or ``None`` if incompatible."""

    if len(left) != len(right):
        return None
    normalized_left = normalized_embedding(left)
    normalized_right = normalized_embedding(right)
    if normalized_left is None or normalized_right is None:
        return None

    cosine = sum(a * b for a, b in zip(normalized_left, normalized_right))
    return round(min(1.0, max(0.0, cosine)), 6)
