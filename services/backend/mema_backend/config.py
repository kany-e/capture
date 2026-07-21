"""Environment-backed configuration for the local Mema backend."""

from __future__ import annotations

import re
from functools import lru_cache
from ipaddress import ip_address
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _runtime_root() -> Path:
    """Use the checkout root in source builds and the launch directory when installed."""

    source_candidate = Path(__file__).resolve().parents[3]
    if (source_candidate / "services" / "backend" / "pyproject.toml").is_file():
        return source_candidate
    return Path.cwd().resolve()


REPOSITORY_ROOT = _runtime_root()
CHROME_EXTENSION_ID = re.compile(r"[a-p]{32}")


class Settings(BaseSettings):
    """Validated runtime settings loaded from the environment or root .env."""

    model_config = SettingsConfigDict(
        env_file=REPOSITORY_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    openai_api_key: SecretStr | None = None
    openai_model: str = "gpt-5.6"
    openai_embedding_model: str = "text-embedding-3-small"

    mema_host: str = "127.0.0.1"
    mema_port: int = Field(default=8765, ge=1, le=65535)
    mema_database_path: Path = Path("./data/mema.db")
    mema_attachments_path: Path | None = None
    mema_log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = (
        "INFO"
    )
    mema_cors_origins: str = ""

    @field_validator("mema_host")
    @classmethod
    def require_loopback_host(cls, value: str) -> str:
        host = value.strip()
        if host.lower() == "localhost":
            return host

        try:
            is_loopback = ip_address(host).is_loopback
        except ValueError as error:
            raise ValueError(
                "MEMA_HOST must be localhost or a loopback IP address"
            ) from error

        if not is_loopback:
            raise ValueError(
                "MEMA_HOST must be localhost or a loopback IP address"
            )
        return host

    @field_validator("mema_log_level", mode="before")
    @classmethod
    def normalize_log_level(cls, value: object) -> object:
        return value.upper() if isinstance(value, str) else value

    @field_validator("mema_cors_origins")
    @classmethod
    def require_narrow_cors_origins(cls, value: str) -> str:
        origins = [
            origin.strip() for origin in value.split(",") if origin.strip()
        ]
        validated: list[str] = []
        for origin in origins:
            if origin == "*":
                raise ValueError("MEMA_CORS_ORIGINS must not contain a wildcard")

            parsed = urlsplit(origin)
            try:
                parsed.port
            except ValueError as error:
                raise ValueError(
                    "MEMA_CORS_ORIGINS contains an invalid port"
                ) from error
            if (
                not parsed.scheme
                or not parsed.hostname
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError(
                    "MEMA_CORS_ORIGINS entries must be exact origins"
                )

            if parsed.scheme == "chrome-extension":
                if parsed.port is not None or CHROME_EXTENSION_ID.fullmatch(
                    parsed.hostname
                ) is None:
                    raise ValueError(
                        "Chrome extension origins require a 32-character ID"
                    )
            elif parsed.scheme in {"http", "https"}:
                host = parsed.hostname
                if host != "localhost":
                    try:
                        is_loopback = ip_address(host).is_loopback
                    except ValueError as error:
                        raise ValueError(
                            "Web CORS origins must use localhost or loopback"
                        ) from error
                    if not is_loopback:
                        raise ValueError(
                            "Web CORS origins must use localhost or loopback"
                        )
            else:
                raise ValueError(
                    "CORS origins must use chrome-extension, http, or https"
                )

            if origin not in validated:
                validated.append(origin)
        return ",".join(validated)

    @model_validator(mode="after")
    def resolve_storage_paths(self) -> "Settings":
        path = self.mema_database_path.expanduser()
        if not path.is_absolute():
            path = REPOSITORY_ROOT / path
        path = path.resolve()

        if path.exists() and path.is_dir():
            raise ValueError(
                "MEMA_DATABASE_PATH must name a database file, not a directory"
            )

        self.mema_database_path = path

        attachment_path = self.mema_attachments_path
        if attachment_path is None:
            attachment_path = path.parent / "attachments"
        else:
            attachment_path = attachment_path.expanduser()
            if not attachment_path.is_absolute():
                attachment_path = REPOSITORY_ROOT / attachment_path
            attachment_path = attachment_path.resolve()

        if attachment_path.exists() and not attachment_path.is_dir():
            raise ValueError(
                "MEMA_ATTACHMENTS_PATH must name a directory, not a file"
            )
        if (
            attachment_path == path
            or attachment_path in path.parents
            or path in attachment_path.parents
        ):
            raise ValueError(
                "MEMA_ATTACHMENTS_PATH must not contain the SQLite database file"
            )
        self.mema_attachments_path = attachment_path
        return self

    @property
    def openai_configured(self) -> bool:
        if self.openai_api_key is None:
            return False
        return bool(self.openai_api_key.get_secret_value().strip())

    @property
    def cors_origins(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.mema_cors_origins.split(",")
            if origin.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
