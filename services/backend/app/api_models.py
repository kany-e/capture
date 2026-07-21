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
    StrictBool,
    TypeAdapter,
    field_validator,
    model_validator,
)

from app.limits import (
    OCR_TEXT_MAX_LENGTH,
    SCREENSHOT_BASE64_MAX_LENGTH,
    SELECTED_TEXT_MAX_LENGTH,
    SOURCE_APP_MAX_LENGTH,
    SOURCE_TITLE_MAX_LENGTH,
    SOURCE_URL_MAX_LENGTH,
    USER_NOTE_MAX_LENGTH,
    USER_DETAIL_MAX_LENGTH,
    USER_LIST_ITEM_MAX_LENGTH,
    USER_LIST_MAX_ITEMS,
    USER_TITLE_MAX_LENGTH,
)
from app.ocr import decode_screenshot
from app.models import AttachmentRecord, CaptureRecord, CaptureUserUpdate, NewCapture


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
    source_type: Literal["web", "clipboard", "screenshot"]
    source_app: str | None = Field(default=None, max_length=SOURCE_APP_MAX_LENGTH)
    source_title: str | None = Field(
        default=None,
        max_length=SOURCE_TITLE_MAX_LENGTH,
    )
    source_url: str | None = Field(default=None, max_length=SOURCE_URL_MAX_LENGTH)
    selected_text: str = Field(max_length=SELECTED_TEXT_MAX_LENGTH)
    surrounding_context: str | None = Field(default=None, max_length=20_000)
    context_truncated: StrictBool = False
    user_note: str | None = Field(default=None, max_length=USER_NOTE_MAX_LENGTH)
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


class ImageCaptureCreateMetadata(ApiModel):
    client_capture_id: str
    source_app: str | None = Field(default=None, max_length=SOURCE_APP_MAX_LENGTH)
    user_note: str | None = Field(default=None, max_length=USER_NOTE_MAX_LENGTH)
    captured_at: str
    analyze_image: StrictBool = False

    @field_validator("client_capture_id")
    @classmethod
    def validate_client_capture_id(cls, value: str) -> str:
        UUID(value)
        return value

    @field_validator("captured_at")
    @classmethod
    def validate_captured_at(cls, value: str) -> str:
        return CaptureCreateRequest.validate_captured_at(value)

    def to_storage_model(self) -> NewCapture:
        return NewCapture(
            client_capture_id=self.client_capture_id,
            captured_at=self.captured_at,
            source_type="screenshot",
            source_app=self.source_app,
            selected_text="",
            user_note=self.user_note,
        )


class AttachmentResponse(ApiModel):
    id: str
    kind: Literal["image"]
    media_type: Literal["image/png", "image/jpeg"]
    byte_size: int
    pixel_width: int
    pixel_height: int
    sha256: str
    content_path: str

    @classmethod
    def from_record(cls, record: AttachmentRecord) -> "AttachmentResponse":
        return cls(
            id=record.id,
            kind=record.kind,
            media_type=record.media_type,
            byte_size=record.byte_size,
            pixel_width=record.pixel_width,
            pixel_height=record.pixel_height,
            sha256=record.sha256,
            content_path=f"/v1/attachments/{record.id}/content",
        )


class CaptureResponse(ApiModel):
    id: str
    client_capture_id: str | None
    created_at: str
    updated_at: str
    captured_at: str
    status: Literal["captured", "processing", "ready", "error"]
    source_type: Literal["web", "clipboard", "screenshot"]
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
    user_edited_at: str | None = None
    user_selected_text: str | None = None
    user_source_app: str | None = None
    user_source_title: str | None = None
    user_source_url: str | None = None
    user_title: str | None = None
    user_problem: str | None = None
    user_key_insight: str | None = None
    user_why_saved: str | None = None
    user_caveats: list[str] | None = None
    user_tags: list[str] | None = None
    ai_interpretation_hidden: bool = False
    ai_content_stale: bool = False
    attachments: list[AttachmentResponse] = Field(default_factory=list)

    @classmethod
    def from_record(
        cls,
        record: CaptureRecord,
        attachments: list[AttachmentRecord] | None = None,
    ) -> "CaptureResponse":
        values = record.model_dump(exclude={"embedding"})
        values["attachments"] = [
            AttachmentResponse.from_record(attachment)
            for attachment in (attachments or [])
        ]
        return cls.model_validate(values)


class CaptureListResponse(ApiModel):
    items: list[CaptureResponse]
    limit: int
    offset: int


class CaptureUpdateRequest(ApiModel):
    selected_text: str | None = Field(default=None, max_length=SELECTED_TEXT_MAX_LENGTH)
    user_note: str | None = Field(default=None, max_length=USER_NOTE_MAX_LENGTH)
    source_app: str | None = Field(default=None, max_length=SOURCE_APP_MAX_LENGTH)
    source_title: str | None = Field(default=None, max_length=SOURCE_TITLE_MAX_LENGTH)
    source_url: str | None = Field(default=None, max_length=SOURCE_URL_MAX_LENGTH)
    user_title: str | None = Field(default=None, max_length=USER_TITLE_MAX_LENGTH)
    user_problem: str | None = Field(default=None, max_length=USER_DETAIL_MAX_LENGTH)
    user_key_insight: str | None = Field(default=None, max_length=USER_DETAIL_MAX_LENGTH)
    user_why_saved: str | None = Field(default=None, max_length=USER_DETAIL_MAX_LENGTH)
    user_caveats: list[str] | None = Field(default=None, max_length=USER_LIST_MAX_ITEMS)
    user_tags: list[str] | None = Field(default=None, max_length=USER_LIST_MAX_ITEMS)
    show_ai_interpretation: StrictBool = True

    @field_validator("source_url")
    @classmethod
    def validate_update_source_url(cls, value: str | None) -> str | None:
        if value:
            URL_ADAPTER.validate_python(value)
        return value

    @field_validator("user_caveats", "user_tags")
    @classmethod
    def validate_user_lists(cls, values: list[str] | None) -> list[str] | None:
        if values is None:
            return None
        for value in values:
            if len(value) > USER_LIST_ITEM_MAX_LENGTH:
                raise ValueError(
                    f"list items can use up to {USER_LIST_ITEM_MAX_LENGTH} characters"
                )
        return values

    def to_storage_model(
        self,
        existing: CaptureRecord | None = None,
    ) -> CaptureUserUpdate:
        values = self.model_dump()
        if existing is not None:
            existing_values: dict[str, object] = {
                "selected_text": existing.user_selected_text,
                "user_note": existing.user_note,
                "source_app": existing.user_source_app,
                "source_title": existing.user_source_title,
                "source_url": existing.user_source_url,
                "user_title": existing.user_title,
                "user_problem": existing.user_problem,
                "user_key_insight": existing.user_key_insight,
                "user_why_saved": existing.user_why_saved,
                "user_caveats": existing.user_caveats,
                "user_tags": existing.user_tags,
                "show_ai_interpretation": not existing.ai_interpretation_hidden,
            }
            for field, value in existing_values.items():
                if field not in self.model_fields_set:
                    values[field] = value
        return CaptureUserUpdate.model_validate(values)


class SearchResult(ApiModel):
    capture: CaptureResponse
    score: float = Field(ge=0.0, le=1.0)
    keyword_score: float = Field(ge=0.0, le=1.0)
    semantic_score: float | None = Field(default=None, ge=0.0, le=1.0)


class SearchResponse(ApiModel):
    query: str
    results: list[SearchResult]


class ScreenshotOCRRequest(ApiModel):
    media_type: Literal["image/png", "image/jpeg"]
    image_base64: str = Field(min_length=1, max_length=SCREENSHOT_BASE64_MAX_LENGTH)

    @model_validator(mode="after")
    def validate_image(self) -> "ScreenshotOCRRequest":
        decode_screenshot(self.image_base64, self.media_type)
        return self

    def image_bytes(self) -> bytes:
        return decode_screenshot(self.image_base64, self.media_type)


class ScreenshotOCRResponse(ApiModel):
    text: str = Field(min_length=1, max_length=OCR_TEXT_MAX_LENGTH)
    provider: Literal["openai"]
    processing_location: Literal["cloud"]
    model: str


class ErrorBody(ApiModel):
    code: str
    message: str
    details: object | None = None
    request_id: str


class ErrorEnvelope(ApiModel):
    error: ErrorBody
