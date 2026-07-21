"""Run the Mema backend with validated local-only settings."""

from __future__ import annotations

import logging

import uvicorn

from mema_backend.config import get_settings


def main() -> None:
    settings = get_settings()
    logging.basicConfig(
        level=settings.mema_log_level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    logging.getLogger(__name__).info(
        "Starting Mema backend on %s:%s (database=%s, openai_configured=%s)",
        settings.mema_host,
        settings.mema_port,
        settings.mema_database_path,
        settings.openai_configured,
    )
    uvicorn.run(
        "mema_backend.main:app",
        host=settings.mema_host,
        port=settings.mema_port,
        log_level=settings.mema_log_level.lower(),
    )


if __name__ == "__main__":
    main()
