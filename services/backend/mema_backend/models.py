"""Provider-neutral storage models for Mema Captures."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


CaptureStatus = Literal["captured", "processing", "ready", "error"]
SourceType = Literal["web", "clipboard", "screenshot"]
AttachmentKind = Literal["image"]


class StorageModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class NewCapture(StorageModel):
    client_capture_id: str | None = None
    captured_at: str
    source_type: SourceType
    source_app: str | None = None
    source_title: str | None = None
    source_url: str | None = None
    selected_text: str
    surrounding_context: str | None = None
    context_truncated: bool = False
    user_note: str | None = None


class NewAttachment(StorageModel):
    id: str
    kind: AttachmentKind = "image"
    media_type: Literal["image/png", "image/jpeg"]
    relative_path: str
    byte_size: int
    pixel_width: int
    pixel_height: int
    sha256: str
    sort_order: int = 0


class AttachmentRecord(NewAttachment):
    capture_id: str
    created_at: str


class CaptureRecord(NewCapture):
    id: str
    created_at: str
    updated_at: str
    status: CaptureStatus
    ai_title: str | None = None
    ai_summary: str | None = None
    problem: str | None = None
    key_insight: str | None = None
    why_saved: str | None = None
    caveats: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    entities: list[str] = Field(default_factory=list)
    search_aliases: list[str] = Field(default_factory=list)
    embedding: list[float] | None = None
    error_message: str | None = None
    enrichment_version: int = 1
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


class CaptureUserUpdate(StorageModel):
    selected_text: str | None = None
    user_note: str | None = None
    source_app: str | None = None
    source_title: str | None = None
    source_url: str | None = None
    user_title: str | None = None
    user_problem: str | None = None
    user_key_insight: str | None = None
    user_why_saved: str | None = None
    user_caveats: list[str] | None = None
    user_tags: list[str] | None = None
    show_ai_interpretation: bool = True


class EnrichmentUpdate(StorageModel):
    status: CaptureStatus
    ai_title: str | None = None
    ai_summary: str | None = None
    problem: str | None = None
    key_insight: str | None = None
    why_saved: str | None = None
    caveats: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    entities: list[str] = Field(default_factory=list)
    search_aliases: list[str] = Field(default_factory=list)
    embedding: list[float] | None = None
    error_message: str | None = None
    enrichment_version: int = 1
