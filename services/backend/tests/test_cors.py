from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from mema_backend.config import get_settings
from mema_backend.main import app


EXTENSION_ORIGIN = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


@pytest.fixture(autouse=True)
def isolated_settings(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    # Keep CORS tests independent from an optional local provider key.
    monkeypatch.setenv("OPENAI_API_KEY", "")
    monkeypatch.setenv("MEMA_DATABASE_PATH", str(tmp_path / "mema.db"))
    monkeypatch.setenv(
        "MEMA_CORS_ORIGINS",
        f"{EXTENSION_ORIGIN},http://127.0.0.1:3000",
    )
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.mark.parametrize(
    "origin",
    [EXTENSION_ORIGIN, "http://127.0.0.1:3000"],
)
@pytest.mark.parametrize("method", ["POST", "PATCH"])
def test_configured_origin_passes_narrow_preflight(
    origin: str,
    method: str,
) -> None:
    with TestClient(app) as client:
        response = client.options(
            "/v1/captures",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": method,
                "Access-Control-Request-Headers": "content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin
    assert method in response.headers["access-control-allow-methods"]
    assert "content-type" in response.headers["access-control-allow-headers"].lower()
    assert response.headers.get("access-control-allow-credentials") is None


def test_unconfigured_public_origin_is_rejected() -> None:
    with TestClient(app) as client:
        response = client.options(
            "/v1/captures",
            headers={
                "Origin": "https://example.com",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type",
            },
        )

    assert response.status_code == 403
    assert "access-control-allow-origin" not in response.headers


def test_unconfigured_origin_cannot_execute_simple_multipart_write() -> None:
    image = (
        b"\x89PNG\r\n\x1a\n"
        + b"\x00\x00\x00\rIHDR"
        + (1).to_bytes(4, "big")
        + (1).to_bytes(4, "big")
        + b"\x08\x02\x00\x00\x00"
        + b"\x00\x00\x00\x00"
    )
    metadata = json.dumps(
        {
            "client_capture_id": "c4cb52df-d414-49d8-af3f-276c16bf4a2d",
            "source_app": "Untrusted page",
            "user_note": "This must never be saved.",
            "captured_at": "2026-07-21T10:30:00-07:00",
            "analyze_image": False,
        }
    )

    with TestClient(app) as client:
        blocked = client.post(
            "/v1/image-captures",
            headers={"Origin": "https://example.com"},
            data={"metadata": metadata},
            files={"image": ("capture.png", image, "image/png")},
        )
        captures = client.get("/v1/captures")

    assert blocked.status_code == 403
    assert captures.status_code == 200
    assert captures.json()["items"] == []


def test_allowed_simple_request_echoes_only_exact_origin() -> None:
    with TestClient(app) as client:
        allowed = client.get("/health", headers={"Origin": EXTENSION_ORIGIN})
        no_origin = client.get("/health")

    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == EXTENSION_ORIGIN
    assert "access-control-allow-origin" not in no_origin.headers
