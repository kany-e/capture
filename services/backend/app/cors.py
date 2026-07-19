"""Environment-configured CORS enforcement for local Recall clients."""

from __future__ import annotations

from starlette.middleware.cors import CORSMiddleware

from app.config import get_settings


class ConfiguredCORSMiddleware(CORSMiddleware):
    """Resolve the exact allowlist at request time for safe local overrides."""

    def is_allowed_origin(self, origin: str) -> bool:
        return origin in get_settings().cors_origins
