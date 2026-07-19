from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


@pytest.fixture(autouse=True)
def isolated_settings(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    # Explicitly override a developer's repository-root .env for tests that
    # exercise the provider-off contract.
    monkeypatch.setenv("OPENAI_API_KEY", "")
    monkeypatch.setenv("RECALL_DATABASE_PATH", str(tmp_path / "recall.db"))
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_health_reports_database_and_missing_openai_key() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "database": "ok",
        "openai_configured": False,
    }


def test_health_reports_configured_openai_without_exposing_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "test-only-secret")
    get_settings.cache_clear()

    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["openai_configured"] is True
    assert "test-only-secret" not in response.text


def test_health_returns_503_when_database_cannot_be_opened(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("RECALL_DATABASE_PATH", "/dev/null/recall.db")
    get_settings.cache_clear()

    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 503
    assert response.json() == {
        "status": "degraded",
        "database": "error",
        "openai_configured": False,
    }
