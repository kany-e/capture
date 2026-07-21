from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from mema_backend.config import get_settings
from mema_backend.main import app
from mema_backend.models import NewCapture
from mema_backend.repository import (
    CaptureRepository,
    INTERRUPTED_PROCESSING_ERROR_MESSAGE,
)


@pytest.fixture(autouse=True)
def isolated_settings(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    # Explicitly override a developer's repository-root .env for tests that
    # exercise the provider-off contract.
    monkeypatch.setenv("OPENAI_API_KEY", "")
    monkeypatch.setenv("MEMA_DATABASE_PATH", str(tmp_path / "mema.db"))
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
        "attachments": "ok",
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


def test_startup_recovers_interrupted_processing_capture(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    database_path = tmp_path / "restart.db"
    monkeypatch.setenv("MEMA_DATABASE_PATH", str(database_path))
    get_settings.cache_clear()
    repository = CaptureRepository(database_path)
    stale = repository.create(
        NewCapture(
            captured_at="2026-07-18T12:00:00-07:00",
            source_type="clipboard",
            source_app="TextEdit",
            selected_text="source survives restart",
            user_note="note survives restart",
        ),
        status="processing",
    )

    with TestClient(app) as client:
        response = client.get(f"/v1/captures/{stale.id}")

    assert response.status_code == 200
    recovered = response.json()
    assert recovered["status"] == "error"
    assert recovered["error_message"] == INTERRUPTED_PROCESSING_ERROR_MESSAGE
    assert recovered["selected_text"] == "source survives restart"
    assert recovered["user_note"] == "note survives restart"


def test_health_returns_503_when_database_cannot_be_opened(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("MEMA_DATABASE_PATH", "/dev/null/mema.db")
    get_settings.cache_clear()

    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 503
    assert response.json() == {
        "status": "degraded",
        "database": "error",
        "attachments": "error",
        "openai_configured": False,
    }
