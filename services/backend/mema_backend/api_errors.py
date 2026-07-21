"""Stable API error envelopes shared by validation and route handlers."""

from __future__ import annotations

from typing import Any
from uuid import uuid4

from fastapi.responses import JSONResponse

from mema_backend.api_models import ErrorBody, ErrorEnvelope


def error_response(
    *,
    status_code: int,
    code: str,
    message: str,
    details: Any = None,
) -> JSONResponse:
    envelope = ErrorEnvelope(
        error=ErrorBody(
            code=code,
            message=message,
            details=details,
            request_id=str(uuid4()),
        )
    )
    return JSONResponse(
        status_code=status_code,
        content=envelope.model_dump(mode="json"),
    )
