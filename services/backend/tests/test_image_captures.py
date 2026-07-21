from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from mema_backend.attachments import AttachmentStorage
from mema_backend.config import get_settings
from mema_backend.image_enrichment import ImageEnrichmentPayload
from mema_backend.main import (
    app,
    get_embedding_provider,
    get_image_enrichment_provider,
)
from mema_backend.models import CaptureRecord


def png_image(width: int = 3, height: int = 2, suffix: bytes = b"") -> bytes:
    return (
        b"\x89PNG\r\n\x1a\n"
        + b"\x00\x00\x00\rIHDR"
        + width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
        + b"\x08\x02\x00\x00\x00"
        + b"\x00\x00\x00\x00"
        + suffix
    )


def image_metadata(*, analyze: bool, client_id: str | None = None) -> str:
    return json.dumps(
        {
            "client_capture_id": client_id or str(uuid4()),
            "source_app": "Screenshot",
            "user_note": "Remember the relationship shown in this diagram.",
            "captured_at": "2026-07-21T10:30:00-07:00",
            "analyze_image": analyze,
        }
    )


def post_image(
    client: TestClient,
    *,
    image: bytes,
    metadata: str,
    media_type: str = "image/png",
):
    return client.post(
        "/v1/image-captures",
        data={"metadata": metadata},
        files={"image": ("capture.png", image, media_type)},
    )


class SuccessfulImageProvider:
    def __init__(self) -> None:
        self.calls: list[tuple[str, bytes, str]] = []
        self.contexts: list[CaptureRecord] = []

    def analyze(
        self,
        capture: CaptureRecord,
        image: bytes,
        media_type: str,
    ) -> ImageEnrichmentPayload:
        self.calls.append((capture.id, image, media_type))
        self.contexts.append(capture)
        return ImageEnrichmentPayload(
            extracted_text="Logistic Growth\nln absolute values",
            title="Logistic growth derivation diagram",
            summary="A screenshot explaining how constants absorb logarithm signs.",
            problem="Understanding a logistic-growth derivation.",
            key_insight="An arbitrary integration constant absorbs the sign.",
            why_saved="The user wants to remember the relationship in the diagram.",
            caveats=["The screenshot remains the authoritative source."],
            tags=["logistic growth", "differential equations"],
            entities=["Logistic Growth"],
            search_aliases=["惊险的绝对值消消乐", "ln sign absorbed by constant"],
        )


class SuccessfulEmbeddingProvider:
    def __init__(self) -> None:
        self.inputs: list[str] = []

    def embed(self, text: str) -> list[float]:
        self.inputs.append(text)
        return [1.0, 0.0]


@pytest.fixture
def image_api_client(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> Iterator[tuple[TestClient, Path]]:
    database_path = tmp_path / "mema.db"
    attachment_path = tmp_path / "attachments"
    monkeypatch.setenv("OPENAI_API_KEY", "")
    monkeypatch.setenv("MEMA_DATABASE_PATH", str(database_path))
    monkeypatch.setenv("MEMA_ATTACHMENTS_PATH", str(attachment_path))
    get_settings.cache_clear()
    with TestClient(app) as client:
        yield client, attachment_path
    app.dependency_overrides.pop(get_image_enrichment_provider, None)
    app.dependency_overrides.pop(get_embedding_provider, None)
    get_settings.cache_clear()


def test_image_note_can_be_saved_without_ai_and_read_back(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, _ = image_api_client
    image = png_image()

    response = post_image(
        client,
        image=image,
        metadata=image_metadata(analyze=False),
    )

    assert response.status_code == 202
    created = response.json()
    assert created["status"] == "ready"
    assert created["source_type"] == "screenshot"
    assert created["selected_text"] == ""
    assert created["user_note"].startswith("Remember")
    assert len(created["attachments"]) == 1
    attachment = created["attachments"][0]
    assert attachment["media_type"] == "image/png"
    assert attachment["pixel_width"] == 3
    assert attachment["pixel_height"] == 2

    content = client.get(attachment["content_path"])
    assert content.status_code == 200
    assert content.headers["content-type"] == "image/png"
    assert content.headers["cache-control"] == "no-store"
    assert content.content == image


def test_omitting_analysis_flag_fails_private_and_does_not_call_provider(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, _ = image_api_client
    provider = SuccessfulImageProvider()
    app.dependency_overrides[get_image_enrichment_provider] = lambda: provider
    metadata = json.loads(image_metadata(analyze=True))
    metadata.pop("analyze_image")

    response = post_image(
        client,
        image=png_image(),
        metadata=json.dumps(metadata),
    )

    assert response.status_code == 202
    assert response.json()["status"] == "ready"
    assert provider.calls == []


def test_image_note_ai_analysis_populates_searchable_ocr_and_visual_fields(
    image_api_client: tuple[TestClient, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _ = image_api_client
    provider = SuccessfulImageProvider()
    app.dependency_overrides[get_image_enrichment_provider] = lambda: provider
    app.dependency_overrides[get_embedding_provider] = SuccessfulEmbeddingProvider

    created = post_image(
        client,
        image=png_image(),
        metadata=image_metadata(analyze=True),
    ).json()
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert created["status"] == "processing"
    assert loaded["status"] == "ready"
    assert loaded["selected_text"] == "Logistic Growth\nln absolute values"
    assert loaded["ai_title"] == "Logistic growth derivation diagram"
    assert loaded["tags"] == ["logistic growth", "differential equations"]
    assert provider.calls == [(created["id"], png_image(), "image/png")]

    def reject_per_capture_attachment_query(
        _repository: object,
        _capture_id: str,
    ) -> list[object]:
        raise AssertionError("collection responses must batch attachment metadata")

    monkeypatch.setattr(
        "mema_backend.repository.CaptureRepository.list_attachments",
        reject_per_capture_attachment_query,
    )
    library = client.get("/v1/captures")
    search = client.get("/v1/search", params={"q": "绝对值消消乐"})

    assert library.status_code == 200
    assert library.json()["items"][0]["attachments"] == created["attachments"]
    assert search.status_code == 200
    assert [item["capture"]["id"] for item in search.json()["results"]] == [
        created["id"]
    ]
    assert search.json()["results"][0]["capture"]["attachments"] == created[
        "attachments"
    ]


def test_reanalyzing_edited_image_uses_corrected_visible_text(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, _ = image_api_client
    provider = SuccessfulImageProvider()
    embedding_provider = SuccessfulEmbeddingProvider()
    app.dependency_overrides[get_image_enrichment_provider] = lambda: provider
    app.dependency_overrides[get_embedding_provider] = lambda: embedding_provider
    created = post_image(
        client,
        image=png_image(),
        metadata=image_metadata(analyze=True),
    ).json()
    corrected_text = "User-corrected formula: ln |K-y|"

    edited = client.patch(
        f"/v1/captures/{created['id']}",
        json={
            "selected_text": corrected_text,
            "user_note": "Use my corrected transcription.",
        },
    )
    refreshed = client.post(f"/v1/captures/{created['id']}/enrich")
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert edited.status_code == 200
    assert refreshed.status_code == 202
    assert len(provider.contexts) == 2
    assert provider.contexts[-1].selected_text == corrected_text
    assert provider.contexts[-1].user_selected_text == corrected_text
    assert corrected_text in embedding_provider.inputs[-1]
    assert loaded["selected_text"] == corrected_text
    assert loaded["user_selected_text"] == corrected_text
    assert loaded["ai_content_stale"] is False


def test_requested_image_analysis_without_provider_keeps_original_and_errors(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, _ = image_api_client

    created = post_image(
        client,
        image=png_image(),
        metadata=image_metadata(analyze=True),
    ).json()
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert created["status"] == "processing"
    assert loaded["status"] == "error"
    assert "original image remains saved" in loaded["error_message"]
    assert client.get(loaded["attachments"][0]["content_path"]).content == png_image()


def test_image_capture_idempotency_does_not_leave_duplicate_files(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, attachment_path = image_api_client
    client_id = str(uuid4())
    metadata = image_metadata(analyze=False, client_id=client_id)
    uppercase_metadata = image_metadata(analyze=False, client_id=client_id.upper())

    first = post_image(client, image=png_image(suffix=b"first"), metadata=metadata)
    second = post_image(
        client,
        image=png_image(suffix=b"second"),
        metadata=uppercase_metadata,
    )

    assert first.status_code == second.status_code == 202
    assert first.json()["id"] == second.json()["id"]
    assert second.json()["attachments"] == first.json()["attachments"]
    files = [path for path in attachment_path.rglob("*") if path.is_file()]
    assert len(files) == 1
    assert files[0].read_bytes() == png_image(suffix=b"first")


def test_attachment_reconciliation_removes_only_generated_orphans(
    tmp_path: Path,
) -> None:
    storage = AttachmentStorage(tmp_path / "attachments")
    referenced = storage.store(png_image(suffix=b"referenced"), "image/png")
    orphan = storage.store(png_image(suffix=b"orphan"), "image/png")
    orphan_path = storage.path_for(orphan.relative_path)
    temporary_path = orphan_path.with_name(
        f".{orphan_path.name}.{uuid4().hex}.tmp"
    )
    temporary_path.write_bytes(b"interrupted")
    unrelated_path = orphan_path.parent / "keep-me.txt"
    unrelated_path.write_text("not managed by Mema", encoding="utf-8")

    removed = storage.cleanup_unreferenced({referenced.relative_path})

    assert removed == 2
    assert storage.path_for(referenced.relative_path).is_file()
    assert not orphan_path.exists()
    assert not temporary_path.exists()
    assert unrelated_path.read_text(encoding="utf-8") == "not managed by Mema"


def test_deleting_image_note_removes_metadata_content_and_file(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, attachment_path = image_api_client
    created = post_image(
        client,
        image=png_image(),
        metadata=image_metadata(analyze=False),
    ).json()
    content_path = created["attachments"][0]["content_path"]

    response = client.delete(f"/v1/captures/{created['id']}")

    assert response.status_code == 204
    assert client.get(f"/v1/captures/{created['id']}").status_code == 404
    assert client.get(content_path).status_code == 404
    assert [path for path in attachment_path.rglob("*") if path.is_file()] == []


@pytest.mark.parametrize(
    ("image", "media_type"),
    [
        (b"not an image", "image/png"),
        (png_image(width=20_001), "image/png"),
        (png_image(), "image/gif"),
    ],
)
def test_image_note_rejects_invalid_or_unsupported_images(
    image_api_client: tuple[TestClient, Path],
    image: bytes,
    media_type: str,
) -> None:
    client, _ = image_api_client

    response = post_image(
        client,
        image=image,
        metadata=image_metadata(analyze=False),
        media_type=media_type,
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_image"


def test_image_analysis_can_be_retried_after_configuration_is_added(
    image_api_client: tuple[TestClient, Path],
) -> None:
    client, _ = image_api_client
    created = post_image(
        client,
        image=png_image(),
        metadata=image_metadata(analyze=True),
    ).json()
    provider = SuccessfulImageProvider()
    app.dependency_overrides[get_image_enrichment_provider] = lambda: provider

    retry = client.post(f"/v1/captures/{created['id']}/enrich")
    loaded = client.get(f"/v1/captures/{created['id']}").json()

    assert retry.status_code == 202
    assert retry.json()["status"] == "processing"
    assert loaded["status"] == "ready"
    assert loaded["selected_text"].startswith("Logistic Growth")
