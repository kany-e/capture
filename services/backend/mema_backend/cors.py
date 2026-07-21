"""Environment-configured CORS enforcement for local Mema clients."""

from __future__ import annotations

from starlette.middleware.cors import CORSMiddleware
from starlette.responses import PlainTextResponse
from starlette.types import Receive, Scope, Send

from mema_backend.config import get_settings


class ConfiguredCORSMiddleware(CORSMiddleware):
    """Enforce the runtime origin allowlist, including simple requests.

    CORS response headers alone do not stop a browser from sending a request.
    Rejecting disallowed origins before routing prevents cross-site multipart
    requests from mutating the local database or starting provider work.
    """

    def is_allowed_origin(self, origin: str) -> bool:
        return origin in get_settings().cors_origins

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope["type"] == "http":
            origin = next(
                (
                    value.decode("latin-1")
                    for name, value in scope.get("headers", [])
                    if name.lower() == b"origin"
                ),
                None,
            )
            if origin is not None and not self.is_allowed_origin(origin):
                response = PlainTextResponse(
                    "Disallowed request origin",
                    status_code=403,
                )
                await response(scope, receive, send)
                return

        await super().__call__(scope, receive, send)
