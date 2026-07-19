from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


EXTENSION_ORIGIN = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


@pytest.fixture(autouse=True)
def isolated_settings(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("RECALL_DATABASE_PATH", str(tmp_path / "recall.db"))
    monkeypatch.setenv(
        "RECALL_CORS_ORIGINS",
        f"{EXTENSION_ORIGIN},http://127.0.0.1:3000",
    )
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.mark.parametrize(
    "origin",
    [EXTENSION_ORIGIN, "http://127.0.0.1:3000"],
)
def test_configured_origin_passes_narrow_preflight(origin: str) -> None:
    with TestClient(app) as client:
        response = client.options(
            "/v1/captures",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin
    assert "POST" in response.headers["access-control-allow-methods"]
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

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_allowed_simple_request_echoes_only_exact_origin() -> None:
    with TestClient(app) as client:
        allowed = client.get("/health", headers={"Origin": EXTENSION_ORIGIN})
        no_origin = client.get("/health")

    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == EXTENSION_ORIGIN
    assert "access-control-allow-origin" not in no_origin.headers
