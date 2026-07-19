"""Run the Recall backend with validated local-only settings."""

from __future__ import annotations

import logging

import uvicorn

from app.config import get_settings


def main() -> None:
    settings = get_settings()
    logging.basicConfig(
        level=settings.recall_log_level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    logging.getLogger(__name__).info(
        "Starting Recall backend on %s:%s (database=%s, openai_configured=%s)",
        settings.recall_host,
        settings.recall_port,
        settings.recall_database_path,
        settings.openai_configured,
    )
    uvicorn.run(
        "app.main:app",
        host=settings.recall_host,
        port=settings.recall_port,
        log_level=settings.recall_log_level.lower(),
    )


if __name__ == "__main__":
    main()
