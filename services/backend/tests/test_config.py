from __future__ import annotations

from pathlib import Path

import pytest
from pydantic import ValidationError

from app.config import Settings


def test_missing_env_file_uses_safe_defaults(tmp_path: Path) -> None:
    settings = Settings(_env_file=tmp_path / "missing.env")

    assert settings.recall_host == "127.0.0.1"
    assert settings.recall_port == 8765
    assert settings.openai_configured is False


@pytest.mark.parametrize("host", ["0.0.0.0", "192.168.1.5", "example.com"])
def test_non_loopback_host_is_rejected(host: str) -> None:
    with pytest.raises(ValidationError, match="loopback"):
        Settings(_env_file=None, recall_host=host)


@pytest.mark.parametrize("port", [0, 65536])
def test_invalid_port_is_rejected(port: int) -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, recall_port=port)


def test_directory_is_rejected_as_database_path(tmp_path: Path) -> None:
    with pytest.raises(ValidationError, match="database file"):
        Settings(_env_file=None, recall_database_path=tmp_path)


def test_cors_origins_are_parsed_from_comma_separated_setting() -> None:
    settings = Settings(
        _env_file=None,
        recall_cors_origins=(
            "http://127.0.0.1:3000, "
            "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ),
    )

    assert settings.cors_origins == [
        "http://127.0.0.1:3000",
        "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ]


@pytest.mark.parametrize(
    "origins",
    [
        "*",
        "https://example.com",
        "chrome-extension://example",
        "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/path",
        "http://127.0.0.1:3000/path",
    ],
)
def test_broad_or_malformed_cors_origin_is_rejected(origins: str) -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, recall_cors_origins=origins)
