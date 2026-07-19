"""Minimal FastAPI application for the Recall localhost service."""

from __future__ import annotations

import logging
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID

from fastapi import BackgroundTasks, Depends, FastAPI, Query, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import AfterValidator, BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api_errors import error_response
from app.api_models import (
    CaptureCreateRequest,
    CaptureListResponse,
    CaptureResponse,
    ErrorEnvelope,
    SearchResponse,
    SearchResult,
)
from app.checklist import build_checklist_snapshot
from app.config import get_settings
from app.cors import ConfiguredCORSMiddleware
from app.database import (
    MigrationError,
    apply_migrations,
    database_schema_is_current,
)
from app.embeddings import EmbeddingProvider, OpenAIEmbeddingProvider
from app.enrichment import (
    EnrichmentProvider,
    EnrichmentService,
    OpenAIEnrichmentProvider,
    mark_enrichment_not_configured,
)
from app.limits import SEARCH_QUERY_MAX_LENGTH
from app.repository import (
    CaptureAlreadyProcessingError,
    CaptureNotFoundError,
    CaptureRepository,
)
from app.search import HybridSearchService


logger = logging.getLogger(__name__)
CHECKLIST_HTML = Path(__file__).resolve().parent / "static" / "checklist.html"


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    database: Literal["ok", "error"]
    openai_configured: bool


def require_safe_search_query(value: str) -> str:
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError("q must not contain control characters")
    return value


SearchQuery = Annotated[
    str,
    Query(max_length=SEARCH_QUERY_MAX_LENGTH),
    AfterValidator(require_safe_search_query),
]


def check_database(database_path: Path) -> Literal["ok", "error"]:
    """Open the configured SQLite file and execute a connectivity probe."""

    try:
        database_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(database_path, timeout=2) as connection:
            connection.row_factory = sqlite3.Row
            result = connection.execute("SELECT 1").fetchone()
            schema_is_current = database_schema_is_current(connection)
            quick_check = connection.execute("PRAGMA quick_check(1)").fetchone()
            corrupt_json = connection.execute(
                """
                SELECT 1 FROM captures
                WHERE
                    CASE WHEN json_valid(caveats_json)
                        THEN json_type(caveats_json) != 'array' ELSE 1 END
                    OR CASE WHEN json_valid(tags_json)
                        THEN json_type(tags_json) != 'array' ELSE 1 END
                    OR CASE WHEN json_valid(entities_json)
                        THEN json_type(entities_json) != 'array' ELSE 1 END
                    OR CASE WHEN json_valid(search_aliases_json)
                        THEN json_type(search_aliases_json) != 'array' ELSE 1 END
                    OR (
                        embedding_json IS NOT NULL
                        AND CASE WHEN json_valid(embedding_json)
                            THEN json_type(embedding_json) != 'array' ELSE 1 END
                    )
                LIMIT 1
                """
            ).fetchone()
        query_succeeded = result is not None and result[0] == 1
        integrity_ok = quick_check is not None and quick_check[0] == "ok"
        return (
            "ok"
            if query_succeeded
            and schema_is_current
            and integrity_ok
            and corrupt_json is None
            else "error"
        )
    except (OSError, sqlite3.Error):
        logger.exception("SQLite health probe failed for %s", database_path)
        return "error"


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    try:
        apply_migrations(settings.recall_database_path)
    except MigrationError:
        logger.exception("SQLite migration failed; health will report degraded")
    yield


app = FastAPI(title="Recall Backend", version="0.7.0", lifespan=lifespan)
app.add_middleware(
    ConfiguredCORSMiddleware,
    allow_origins=[],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
    allow_credentials=False,
)


def get_repository() -> CaptureRepository:
    settings = get_settings()
    return CaptureRepository(settings.recall_database_path, initialize=False)


def get_enrichment_provider() -> EnrichmentProvider | None:
    settings = get_settings()
    if not settings.openai_configured or settings.openai_api_key is None:
        return None
    return OpenAIEnrichmentProvider(
        api_key=settings.openai_api_key.get_secret_value(),
        model=settings.openai_model,
    )


def get_embedding_provider() -> EmbeddingProvider | None:
    settings = get_settings()
    if not settings.openai_configured or settings.openai_api_key is None:
        return None
    return OpenAIEmbeddingProvider(
        api_key=settings.openai_api_key.get_secret_value(),
        model=settings.openai_embedding_model,
    )


@app.exception_handler(RequestValidationError)
async def request_validation_error(
    _: Request,
    error: RequestValidationError,
) -> JSONResponse:
    details = [
        {
            "field": ".".join(str(part) for part in item["loc"]),
            "message": item["msg"],
            "type": item["type"],
        }
        for item in error.errors()
    ]
    return error_response(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        code="validation_error",
        message="Request does not satisfy the API contract.",
        details=details,
    )


@app.exception_handler(StarletteHTTPException)
async def malformed_http_request(
    _: Request,
    error: StarletteHTTPException,
) -> JSONResponse:
    if error.status_code == status.HTTP_400_BAD_REQUEST:
        return error_response(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="validation_error",
            message="Request does not satisfy the API contract.",
            details=[
                {
                    "field": "body",
                    "message": "Request body is not valid UTF-8 JSON.",
                    "type": "invalid_json",
                }
            ],
        )
    return error_response(
        status_code=error.status_code,
        code="http_error",
        message="The requested backend resource is unavailable.",
    )


@app.exception_handler(Exception)
async def internal_server_error(request: Request, error: Exception) -> JSONResponse:
    logger.error(
        "Unhandled request error for %s %s",
        request.method,
        request.url.path,
        exc_info=(type(error), error, error.__traceback__),
    )
    return error_response(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="internal_error",
        message="An unexpected backend error occurred.",
    )


@app.get("/dev/checklist", include_in_schema=False, response_class=HTMLResponse)
def checklist_dashboard() -> HTMLResponse:
    return HTMLResponse(
        CHECKLIST_HTML.read_text(encoding="utf-8"),
        headers={"Cache-Control": "no-store"},
    )


@app.get("/dev/checklist.json", include_in_schema=False)
def checklist_data() -> JSONResponse:
    return JSONResponse(
        build_checklist_snapshot(),
        headers={"Cache-Control": "no-store"},
    )


@app.post(
    "/v1/captures",
    response_model=CaptureResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def create_capture(
    background_tasks: BackgroundTasks,
    request: CaptureCreateRequest,
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    provider: Annotated[
        EnrichmentProvider | None,
        Depends(get_enrichment_provider),
    ],
    embedding_provider: Annotated[
        EmbeddingProvider | None,
        Depends(get_embedding_provider),
    ],
) -> CaptureResponse:
    record, created = repository.create_or_get(
        request.to_storage_model(),
        status="processing",
    )
    if not created:
        return CaptureResponse.from_record(record)
    if provider is None:
        background_tasks.add_task(
            mark_enrichment_not_configured,
            repository,
            record.id,
        )
    else:
        background_tasks.add_task(
            EnrichmentService(repository, provider, embedding_provider).run,
            record.id,
        )
    return CaptureResponse.from_record(record)


@app.get("/v1/captures", response_model=CaptureListResponse)
def list_captures(
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> CaptureListResponse:
    records = repository.list_captures(limit=limit, offset=offset)
    return CaptureListResponse(
        items=[CaptureResponse.from_record(record) for record in records],
        limit=limit,
        offset=offset,
    )


@app.get("/v1/search", response_model=SearchResponse)
def search_captures(
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    embedding_provider: Annotated[
        EmbeddingProvider | None,
        Depends(get_embedding_provider),
    ],
    q: SearchQuery = "",
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> SearchResponse:
    matches = HybridSearchService(repository, embedding_provider).search(
        query=q,
        limit=limit,
    )
    return SearchResponse(
        query=q,
        results=[
            SearchResult(
                capture=CaptureResponse.from_record(match.capture),
                score=match.score,
                keyword_score=match.keyword_score,
                semantic_score=match.semantic_score,
            )
            for match in matches
        ],
    )


@app.post(
    "/v1/captures/{capture_id}/enrich",
    response_model=CaptureResponse,
    status_code=status.HTTP_202_ACCEPTED,
    responses={
        status.HTTP_404_NOT_FOUND: {"model": ErrorEnvelope},
        status.HTTP_409_CONFLICT: {"model": ErrorEnvelope},
        status.HTTP_503_SERVICE_UNAVAILABLE: {"model": ErrorEnvelope},
    },
)
def enrich_capture(
    capture_id: UUID,
    background_tasks: BackgroundTasks,
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    provider: Annotated[
        EnrichmentProvider | None,
        Depends(get_enrichment_provider),
    ],
    embedding_provider: Annotated[
        EmbeddingProvider | None,
        Depends(get_embedding_provider),
    ],
) -> CaptureResponse | JSONResponse:
    if provider is None:
        return error_response(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="openai_not_configured",
            message="OpenAI enrichment is not configured.",
        )

    try:
        record = repository.claim_enrichment(str(capture_id))
    except CaptureNotFoundError:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="capture_not_found",
            message="Capture was not found.",
        )
    except CaptureAlreadyProcessingError:
        return error_response(
            status_code=status.HTTP_409_CONFLICT,
            code="capture_already_processing",
            message="Capture enrichment is already processing.",
        )

    background_tasks.add_task(
        EnrichmentService(repository, provider, embedding_provider).run,
        record.id,
    )
    return CaptureResponse.from_record(record)


@app.get(
    "/v1/captures/{capture_id}",
    response_model=CaptureResponse,
    responses={status.HTTP_404_NOT_FOUND: {"model": ErrorEnvelope}},
)
def get_capture(
    capture_id: UUID,
    repository: Annotated[CaptureRepository, Depends(get_repository)],
) -> CaptureResponse | JSONResponse:
    record = repository.get(str(capture_id))
    if record is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="capture_not_found",
            message="Capture was not found.",
        )
    return CaptureResponse.from_record(record)


@app.get("/health", response_model=HealthResponse)
def health(response: Response) -> HealthResponse:
    settings = get_settings()
    database = check_database(settings.recall_database_path)
    if database == "error":
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return HealthResponse(
            status="degraded",
            database=database,
            openai_configured=settings.openai_configured,
        )

    return HealthResponse(
        status="ok",
        database=database,
        openai_configured=settings.openai_configured,
    )
