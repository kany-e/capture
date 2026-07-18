"""HTTP request and response models derived from the checked-in contracts."""

from __future__ import annotations

import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import (
    AnyUrl,
    BaseModel,
    ConfigDict,
    Field,
    TypeAdapter,
    field_validator,
    model_validator,
)

from app.models import CaptureRecord, NewCapture


URL_ADAPTER = TypeAdapter(AnyUrl)
DATETIME_ADAPTER = TypeAdapter(datetime)
RFC3339_TIMESTAMP = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"
    r"[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?"
    r"(?:Z|[+-][0-9]{2}:[0-9]{2})$"
)


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CaptureCreateRequest(ApiModel):
    client_capture_id: str | None = None
    source_type: Literal["web", "clipboard"]
    source_app: str | None = None
    source_title: str | None = None
    source_url: str | None = None
    selected_text: str = Field(max_length=12_000)
    surrounding_context: str | None = Field(default=None, max_length=20_000)
    context_truncated: bool = False
    user_note: str | None = None
    captured_at: str

    @field_validator("client_capture_id")
    @classmethod
    def validate_client_capture_id(cls, value: str | None) -> str | None:
        if value is not None:
            UUID(value)
        return value

    @field_validator("source_url")
    @classmethod
    def validate_source_url(cls, value: str | None) -> str | None:
        if value is not None:
            URL_ADAPTER.validate_python(value)
        return value

    @field_validator("captured_at")
    @classmethod
    def validate_captured_at(cls, value: str) -> str:
        if RFC3339_TIMESTAMP.fullmatch(value) is None:
            raise ValueError("captured_at must be an RFC 3339 timestamp")
        parsed = DATETIME_ADAPTER.validate_python(value)
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            raise ValueError("captured_at must include an RFC 3339 UTC offset")
        return value

    @model_validator(mode="after")
    def require_source_content(self) -> "CaptureCreateRequest":
        content = (
            self.selected_text,
            self.surrounding_context or "",
            self.source_title or "",
        )
        if not any(value.strip() for value in content):
            raise ValueError(
                "selected_text, surrounding_context, or source_title must contain text"
            )
        return self

    def to_storage_model(self) -> NewCapture:
        return NewCapture.model_validate(self.model_dump())


class CaptureResponse(ApiModel):
    id: str
    client_capture_id: str | None
    created_at: str
    updated_at: str
    captured_at: str
    status: Literal["captured", "processing", "ready", "error"]
    source_type: Literal["web", "clipboard"]
    source_app: str | None
    source_title: str | None
    source_url: str | None
    selected_text: str
    surrounding_context: str | None
    context_truncated: bool
    user_note: str | None
    ai_title: str | None
    ai_summary: str | None
    problem: str | None
    key_insight: str | None
    why_saved: str | None
    caveats: list[str]
    tags: list[str]
    entities: list[str]
    search_aliases: list[str]
    error_message: str | None
    enrichment_version: int

    @classmethod
    def from_record(cls, record: CaptureRecord) -> "CaptureResponse":
        return cls.model_validate(record.model_dump(exclude={"embedding"}))


class CaptureListResponse(ApiModel):
    items: list[CaptureResponse]
    limit: int
    offset: int


class SearchResult(ApiModel):
    capture: CaptureResponse
    score: float = Field(ge=0.0, le=1.0)
    keyword_score: float = Field(ge=0.0, le=1.0)
    semantic_score: float | None = Field(default=None, ge=0.0, le=1.0)


class SearchResponse(ApiModel):
    query: str
    results: list[SearchResult]


class ErrorBody(ApiModel):
    code: str
    message: str
    details: object | None = None
    request_id: str


class ErrorEnvelope(ApiModel):
    error: ErrorBody
