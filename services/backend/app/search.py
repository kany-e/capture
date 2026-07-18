"""Provider-independent keyword query construction and score normalization."""

from __future__ import annotations

from dataclasses import dataclass

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


@dataclass(frozen=True, slots=True)
class KeywordSearchMatch:
    capture: CaptureRecord
    keyword_score: float


def build_fts_match_query(query: str) -> str:
    """Treat client query segments as escaped phrases, never FTS syntax."""

    return " AND ".join(
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
