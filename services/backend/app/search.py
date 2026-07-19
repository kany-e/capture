"""Keyword retrieval plus provider-neutral hybrid ranking."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from threading import Lock
from typing import Literal, Protocol
from urllib.parse import urlparse

from app.embeddings import EmbeddingProvider, normalized_embedding
from app.models import CaptureRecord


EXACT_PHRASE_BONUS = 0.20
SEARCHABLE_SCALAR_FIELDS = (
    "source_title",
    "selected_text",
    "surrounding_context",
    "user_note",
    "ai_title",
    "ai_summary",
    "problem",
    "key_insight",
    "why_saved",
)
SEARCHABLE_LIST_FIELDS = ("tags", "entities", "search_aliases")
NORMAL_WEIGHTS = (0.55, 0.35, 0.10)
TECHNICAL_WEIGHTS = (0.45, 0.50, 0.05)
IDENTIFIER_PATTERN = re.compile(r"[A-Za-z0-9]+(?:[._:/=-][A-Za-z0-9]+)*")
MIXED_CASE_PATTERN = re.compile(r"[a-z][A-Z]")
URL_PATTERN = re.compile(r"https?://", re.IGNORECASE)


logger = logging.getLogger(__name__)
_semantic_cache_lock = Lock()
_semantic_cache_key: tuple[str, int, int] | None = None
_semantic_cache: tuple[tuple[CaptureRecord, tuple[float, ...]], ...] = ()


@dataclass(frozen=True, slots=True)
class KeywordSearchMatch:
    capture: CaptureRecord
    keyword_score: float


@dataclass(frozen=True, slots=True)
class HybridSearchMatch:
    capture: CaptureRecord
    score: float
    keyword_score: float
    semantic_score: float | None


class SearchRepository(Protocol):
    def search_captures(
        self,
        *,
        query: str,
        limit: int,
    ) -> list[KeywordSearchMatch]: ...

    def list_ready_captures(self) -> list[CaptureRecord]: ...

    def semantic_revision(self) -> tuple[str, int, int]: ...


def build_fts_match_query(
    query: str,
    operator: Literal["AND", "OR"] = "AND",
) -> str:
    """Treat client query segments as escaped phrases, never FTS syntax."""

    return f" {operator} ".join(
        f'"{segment.replace(chr(34), chr(34) * 2)}"'
        for segment in query.split()
    )


def _contains_exact_phrase(capture: CaptureRecord, query: str) -> bool:
    phrase = " ".join(query.split()).casefold()
    if not phrase:
        return False

    searchable_values = [
        getattr(capture, field) or "" for field in SEARCHABLE_SCALAR_FIELDS
    ]
    searchable_values.extend(
        " ".join(getattr(capture, field)) for field in SEARCHABLE_LIST_FIELDS
    )
    return any(phrase in value.casefold() for value in searchable_values)


def normalize_keyword_matches(
    candidates: list[tuple[CaptureRecord, float]],
    *,
    query: str,
    limit: int,
) -> list[KeywordSearchMatch]:
    """Normalize weighted BM25 relevance and apply a small phrase bonus."""

    if not candidates:
        return []

    maximum_relevance = max(relevance for _, relevance in candidates)
    weighted: list[tuple[CaptureRecord, float]] = []
    for capture, relevance in candidates:
        base_score = (
            relevance / maximum_relevance if maximum_relevance > 0 else 1.0
        )
        exact_bonus = EXACT_PHRASE_BONUS if _contains_exact_phrase(capture, query) else 0
        weighted.append((capture, base_score + exact_bonus))

    maximum_weighted = max(score for _, score in weighted)
    matches = [
        KeywordSearchMatch(
            capture=capture,
            keyword_score=round(
                min(1.0, max(0.0, score / maximum_weighted)),
                6,
            ),
        )
        for capture, score in weighted
    ]
    matches.sort(
        key=lambda match: (
            match.keyword_score,
            match.capture.created_at,
        ),
        reverse=True,
    )
    return matches[:limit]


def is_technical_query(query: str) -> bool:
    """Detect the simple technical patterns required by product-plan §12.3."""

    return (
        any(character.isdigit() for character in query)
        or any(character in query for character in "/-_")
        or "0x" in query.casefold()
        or URL_PATTERN.search(query) is not None
        or MIXED_CASE_PATTERN.search(query) is not None
    )


def _normalized_words(value: str) -> set[str]:
    return {match.casefold() for match in IDENTIFIER_PATTERN.findall(value)}


def _capture_search_text(capture: CaptureRecord) -> str:
    scalars = [
        capture.source_app or "",
        capture.source_url or "",
        *(getattr(capture, field) or "" for field in SEARCHABLE_SCALAR_FIELDS),
    ]
    lists = [
        " ".join(getattr(capture, field)) for field in SEARCHABLE_LIST_FIELDS
    ]
    return "\n".join((*scalars, *lists))


def metadata_bonus(capture: CaptureRecord, query: str) -> float:
    """Score the four metadata signals specified by product-plan §12.3."""

    normalized_query = " ".join(query.casefold().split())
    query_words = _normalized_words(query)

    hostname = urlparse(capture.source_url or "").hostname
    domain_match = bool(
        hostname
        and (
            hostname.casefold() in normalized_query
            or hostname.casefold() in query_words
        )
    )
    app = " ".join((capture.source_app or "").casefold().split())
    app_match = bool(
        app
        and (
            app in normalized_query
            or bool(_normalized_words(app).intersection(query_words))
        )
    )

    normalized_tags = {
        " ".join(tag.casefold().split()) for tag in capture.tags if tag.strip()
    }
    tag_match = normalized_query in normalized_tags or bool(
        normalized_tags.intersection(query_words)
    )

    query_identifiers = {
        value
        for value in query_words
        if any(character.isdigit() for character in value)
    }
    capture_words = _normalized_words(_capture_search_text(capture))
    error_code_match = bool(query_identifiers.intersection(capture_words))

    return round(
        sum((domain_match, app_match, tag_match, error_code_match)) / 4.0,
        6,
    )


def _cached_semantic_candidates(
    repository: SearchRepository,
) -> tuple[tuple[CaptureRecord, tuple[float, ...]], ...]:
    """Decode and normalize the single local database once per write revision."""

    global _semantic_cache_key, _semantic_cache
    revision = repository.semantic_revision()
    if revision == _semantic_cache_key:
        return _semantic_cache

    with _semantic_cache_lock:
        if revision == _semantic_cache_key:
            return _semantic_cache
        candidates = []
        for capture in repository.list_ready_captures():
            if capture.embedding is None:
                continue
            unit_vector = normalized_embedding(capture.embedding)
            if unit_vector is not None:
                candidates.append((capture, unit_vector))
        _semantic_cache = tuple(candidates)
        _semantic_cache_key = revision
        return _semantic_cache


class HybridSearchService:
    """Union FTS and in-memory semantic candidates, with safe FTS fallback."""

    def __init__(
        self,
        repository: SearchRepository,
        embedding_provider: EmbeddingProvider | None,
    ) -> None:
        self.repository = repository
        self.embedding_provider = embedding_provider

    def search(self, *, query: str, limit: int) -> list[HybridSearchMatch]:
        normalized_query = query.strip()
        if not normalized_query:
            return [
                HybridSearchMatch(
                    capture=match.capture,
                    score=match.keyword_score,
                    keyword_score=match.keyword_score,
                    semantic_score=None,
                )
                for match in self.repository.search_captures(
                    query=query,
                    limit=limit,
                )
            ]

        keyword_matches = self.repository.search_captures(
            query=normalized_query,
            limit=limit,
        )
        if self.embedding_provider is None:
            return self._keyword_fallback(keyword_matches, limit)

        try:
            query_embedding = self.embedding_provider.embed(normalized_query)
        except Exception:
            logger.warning("Query embedding failed; returning keyword results")
            return self._keyword_fallback(keyword_matches, limit)

        query_unit_vector = normalized_embedding(query_embedding)
        if query_unit_vector is None:
            logger.warning("Query embedding is unusable; returning keyword results")
            return self._keyword_fallback(keyword_matches, limit)

        candidates = {match.capture.id: match.capture for match in keyword_matches}
        keyword_scores = {
            match.capture.id: match.keyword_score for match in keyword_matches
        }
        semantic_scores: dict[str, float] = {}
        for capture, capture_unit_vector in _cached_semantic_candidates(
            self.repository
        ):
            if len(capture_unit_vector) != len(query_unit_vector):
                continue
            semantic_score = round(
                min(
                    1.0,
                    max(
                        0.0,
                        sum(
                            left * right
                            for left, right in zip(
                                capture_unit_vector,
                                query_unit_vector,
                            )
                        ),
                    ),
                ),
                6,
            )
            candidates[capture.id] = capture
            semantic_scores[capture.id] = semantic_score

        if not semantic_scores:
            return self._keyword_fallback(keyword_matches, limit)

        semantic_weight, keyword_weight, metadata_weight = (
            TECHNICAL_WEIGHTS
            if is_technical_query(normalized_query)
            else NORMAL_WEIGHTS
        )
        matches: list[HybridSearchMatch] = []
        for capture_id, capture in candidates.items():
            keyword_score = keyword_scores.get(capture_id, 0.0)
            semantic_score = semantic_scores.get(capture_id)
            if semantic_score is None:
                final_score = keyword_score
            else:
                final_score = (
                    semantic_weight * semantic_score
                    + keyword_weight * keyword_score
                    + metadata_weight * metadata_bonus(capture, normalized_query)
                )
            matches.append(
                HybridSearchMatch(
                    capture=capture,
                    score=round(min(1.0, max(0.0, final_score)), 6),
                    keyword_score=keyword_score,
                    semantic_score=semantic_score,
                )
            )

        matches.sort(
            key=lambda match: (
                match.score,
                match.keyword_score,
                match.semantic_score if match.semantic_score is not None else -1.0,
                match.capture.created_at,
                match.capture.id,
            ),
            reverse=True,
        )
        return matches[:limit]

    @staticmethod
    def _keyword_fallback(
        matches: list[KeywordSearchMatch],
        limit: int,
    ) -> list[HybridSearchMatch]:
        return [
            HybridSearchMatch(
                capture=match.capture,
                score=match.keyword_score,
                keyword_score=match.keyword_score,
                semantic_score=None,
            )
            for match in matches[:limit]
        ]
