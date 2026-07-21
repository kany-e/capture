"""Minimal FastAPI application for the Recall localhost service."""

from __future__ import annotations

import logging
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID

from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    Form,
    Query,
    Request,
    Response,
    UploadFile,
    status,
)
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from pydantic import AfterValidator, BaseModel, ValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api_errors import error_response
from app.api_models import (
    CaptureCreateRequest,
    CaptureListResponse,
    CaptureResponse,
    CaptureUpdateRequest,
    ErrorEnvelope,
    ImageCaptureCreateMetadata,
    ScreenshotOCRRequest,
    ScreenshotOCRResponse,
    SearchResponse,
    SearchResult,
)
from app.attachments import (
    AttachmentStorage,
    AttachmentStorageError,
    AttachmentValidationError,
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
from app.image_enrichment import (
    ImageEnrichmentProvider,
    ImageEnrichmentService,
    OpenAIImageEnrichmentProvider,
    mark_image_analysis_not_configured,
)
from app.limits import (
    IMAGE_CAPTURE_METADATA_MAX_LENGTH,
    SEARCH_QUERY_MAX_LENGTH,
    SCREENSHOT_MAX_BYTES,
)
from app.models import AttachmentRecord, CaptureRecord
from app.ocr import OCRFailure, OCRProvider, OpenAIOCRProvider
from app.repository import (
    CaptureAlreadyProcessingError,
    CaptureEditConflictError,
    CaptureNotFoundError,
    CaptureRepository,
)
from app.search import HybridSearchService


logger = logging.getLogger(__name__)
CHECKLIST_HTML = Path(__file__).resolve().parent / "static" / "checklist.html"


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    database: Literal["ok", "error"]
    attachments: Literal["ok", "error"]
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
                        user_caveats_json IS NOT NULL
                        AND CASE WHEN json_valid(user_caveats_json)
                            THEN json_type(user_caveats_json) != 'array' ELSE 1 END
                    )
                    OR (
                        user_tags_json IS NOT NULL
                        AND CASE WHEN json_valid(user_tags_json)
                            THEN json_type(user_tags_json) != 'array' ELSE 1 END
                    )
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
        if settings.recall_attachments_path is None:  # pragma: no cover - validated.
            raise MigrationError("Attachment storage path was not resolved")
        storage = AttachmentStorage(settings.recall_attachments_path)
        storage.ensure_available()
        repository = CaptureRepository(
            settings.recall_database_path,
            initialize=False,
        )
        removed_orphans = storage.cleanup_unreferenced(repository.attachment_paths())
        if removed_orphans:
            logger.warning("Removed %s unreferenced attachment file(s)", removed_orphans)
        recovered_count = repository.recover_stale_processing()
        if recovered_count:
            logger.warning(
                "Marked %s interrupted processing Capture(s) as retryable errors",
                recovered_count,
            )
    except (MigrationError, AttachmentStorageError):
        logger.exception("Local storage startup failed; health will report degraded")
    yield


app = FastAPI(title="Recall Backend", version="0.9.0", lifespan=lifespan)
app.add_middleware(
    ConfiguredCORSMiddleware,
    allow_origins=[],
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["Content-Type"],
    allow_credentials=False,
)


def get_repository() -> CaptureRepository:
    settings = get_settings()
    return CaptureRepository(settings.recall_database_path, initialize=False)


def get_attachment_storage() -> AttachmentStorage:
    settings = get_settings()
    if settings.recall_attachments_path is None:  # pragma: no cover - validated.
        raise AttachmentStorageError("Attachment storage path is not configured")
    return AttachmentStorage(settings.recall_attachments_path)


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


def get_ocr_provider() -> OCRProvider | None:
    settings = get_settings()
    if not settings.openai_configured or settings.openai_api_key is None:
        return None
    return OpenAIOCRProvider(
        api_key=settings.openai_api_key.get_secret_value(),
        model=settings.openai_model,
    )


def get_image_enrichment_provider() -> ImageEnrichmentProvider | None:
    settings = get_settings()
    if not settings.openai_configured or settings.openai_api_key is None:
        return None
    return OpenAIImageEnrichmentProvider(
        api_key=settings.openai_api_key.get_secret_value(),
        model=settings.openai_model,
    )


def capture_response(
    repository: CaptureRepository,
    record: CaptureRecord,
    *,
    attachments: list[AttachmentRecord] | None = None,
) -> CaptureResponse:
    return CaptureResponse.from_record(
        record,
        repository.list_attachments(record.id)
        if attachments is None
        else attachments,
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
        return capture_response(repository, record)
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
    return capture_response(repository, record)


@app.post(
    "/v1/image-captures",
    response_model=CaptureResponse,
    status_code=status.HTTP_202_ACCEPTED,
    responses={
        status.HTTP_422_UNPROCESSABLE_CONTENT: {"model": ErrorEnvelope},
        status.HTTP_503_SERVICE_UNAVAILABLE: {"model": ErrorEnvelope},
    },
)
async def create_image_capture(
    background_tasks: BackgroundTasks,
    metadata: Annotated[str, Form(max_length=IMAGE_CAPTURE_METADATA_MAX_LENGTH)],
    image: Annotated[UploadFile, File()],
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    storage: Annotated[AttachmentStorage, Depends(get_attachment_storage)],
    provider: Annotated[
        ImageEnrichmentProvider | None,
        Depends(get_image_enrichment_provider),
    ],
    embedding_provider: Annotated[
        EmbeddingProvider | None,
        Depends(get_embedding_provider),
    ],
) -> CaptureResponse | JSONResponse:
    try:
        capture_metadata = ImageCaptureCreateMetadata.model_validate_json(metadata)
    except ValidationError as error:
        return error_response(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="validation_error",
            message="Image metadata does not satisfy the API contract.",
            details=error.errors(include_url=False),
        )

    media_type = image.content_type or ""
    try:
        image_bytes = await image.read(SCREENSHOT_MAX_BYTES + 1)
    finally:
        await image.close()

    try:
        stored_attachment = storage.store(image_bytes, media_type)
    except AttachmentValidationError as error:
        return error_response(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="invalid_image",
            message=str(error),
        )
    except AttachmentStorageError:
        logger.exception("Image attachment storage is unavailable")
        return error_response(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="attachment_storage_unavailable",
            message="The image could not be saved to local attachment storage.",
        )

    try:
        record, created = repository.create_with_attachment(
            capture_metadata.to_storage_model(),
            stored_attachment,
            status="processing" if capture_metadata.analyze_image else "ready",
        )
    except Exception:
        storage.delete(stored_attachment.relative_path)
        raise

    if not created:
        storage.delete(stored_attachment.relative_path)
        return capture_response(repository, record)

    if capture_metadata.analyze_image:
        if provider is None:
            background_tasks.add_task(
                mark_image_analysis_not_configured,
                repository,
                record.id,
            )
        else:
            background_tasks.add_task(
                ImageEnrichmentService(
                    repository,
                    storage,
                    provider,
                    embedding_provider,
                ).run,
                record.id,
                stored_attachment.id,
            )
    return capture_response(repository, record)


@app.post(
    "/v1/ocr",
    response_model=ScreenshotOCRResponse,
    responses={
        status.HTTP_502_BAD_GATEWAY: {"model": ErrorEnvelope},
        status.HTTP_503_SERVICE_UNAVAILABLE: {"model": ErrorEnvelope},
    },
)
def extract_screenshot_text(
    request: ScreenshotOCRRequest,
    provider: Annotated[OCRProvider | None, Depends(get_ocr_provider)],
) -> ScreenshotOCRResponse | JSONResponse:
    if provider is None:
        return error_response(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="openai_not_configured",
            message=(
                "GPT screenshot extraction is not configured. "
                "Use Apple Vision on device or configure OpenAI."
            ),
        )

    try:
        result = provider.extract_text(request.image_bytes(), request.media_type)
    except OCRFailure as error:
        return error_response(
            status_code=status.HTTP_502_BAD_GATEWAY,
            code=error.code,
            message=error.safe_message,
        )
    return ScreenshotOCRResponse(
        text=result.text,
        provider=result.provider,
        processing_location=result.processing_location,
        model=result.model,
    )


@app.get("/v1/captures", response_model=CaptureListResponse)
def list_captures(
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    sort: Literal[
        "created_desc",
        "created_asc",
        "edited_desc",
        "edited_asc",
    ] = "created_desc",
) -> CaptureListResponse:
    records = repository.list_captures(limit=limit, offset=offset, sort=sort)
    attachments_by_capture = repository.list_attachments_for_captures(
        record.id for record in records
    )
    return CaptureListResponse(
        items=[
            capture_response(
                repository,
                record,
                attachments=attachments_by_capture[record.id],
            )
            for record in records
        ],
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
    attachments_by_capture = repository.list_attachments_for_captures(
        match.capture.id for match in matches
    )
    return SearchResponse(
        query=q,
        results=[
            SearchResult(
                capture=capture_response(
                    repository,
                    match.capture,
                    attachments=attachments_by_capture[match.capture.id],
                ),
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
    image_provider: Annotated[
        ImageEnrichmentProvider | None,
        Depends(get_image_enrichment_provider),
    ],
    storage: Annotated[AttachmentStorage, Depends(get_attachment_storage)],
) -> CaptureResponse | JSONResponse:
    attachments = repository.list_attachments(str(capture_id))
    is_image_capture = bool(attachments)
    if (is_image_capture and image_provider is None) or (
        not is_image_capture and provider is None
    ):
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

    if is_image_capture:
        background_tasks.add_task(
            ImageEnrichmentService(
                repository,
                storage,
                image_provider,  # type: ignore[arg-type]
                embedding_provider,
            ).run,
            record.id,
            attachments[0].id,
        )
    else:
        background_tasks.add_task(
            EnrichmentService(
                repository,
                provider,  # type: ignore[arg-type]
                embedding_provider,
            ).run,
            record.id,
        )
    return capture_response(repository, record)


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
    return capture_response(repository, record)


@app.patch(
    "/v1/captures/{capture_id}",
    response_model=CaptureResponse,
    responses={
        status.HTTP_404_NOT_FOUND: {"model": ErrorEnvelope},
        status.HTTP_409_CONFLICT: {"model": ErrorEnvelope},
    },
)
def update_capture(
    capture_id: UUID,
    request: CaptureUpdateRequest,
    repository: Annotated[CaptureRepository, Depends(get_repository)],
) -> CaptureResponse | JSONResponse:
    existing = repository.get(str(capture_id))
    if existing is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="capture_not_found",
            message="Capture was not found.",
        )
    try:
        record = repository.update_user_fields(
            str(capture_id),
            request.to_storage_model(existing),
        )
    except CaptureNotFoundError:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="capture_not_found",
            message="Capture was not found.",
        )
    except CaptureEditConflictError:
        return error_response(
            status_code=status.HTTP_409_CONFLICT,
            code="capture_processing",
            message="Wait for AI processing to finish before editing this memory.",
        )
    return capture_response(repository, record)


@app.get(
    "/v1/attachments/{attachment_id}/content",
    response_model=None,
    responses={status.HTTP_404_NOT_FOUND: {"model": ErrorEnvelope}},
)
def get_attachment_content(
    attachment_id: UUID,
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    storage: Annotated[AttachmentStorage, Depends(get_attachment_storage)],
) -> FileResponse | JSONResponse:
    attachment = repository.get_attachment(str(attachment_id))
    if attachment is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="attachment_not_found",
            message="Image attachment was not found.",
        )
    try:
        path = storage.read_path(attachment.relative_path)
    except AttachmentStorageError:
        logger.error("Attachment metadata points to a missing file: %s", attachment.id)
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="attachment_file_missing",
            message="The saved image file is unavailable.",
        )
    return FileResponse(
        path,
        media_type=attachment.media_type,
        filename=None,
        headers={
            "Cache-Control": "private, max-age=31536000, immutable",
            "X-Content-Type-Options": "nosniff",
            "Content-Disposition": "inline",
        },
    )


@app.delete(
    "/v1/captures/{capture_id}",
    response_model=None,
    status_code=status.HTTP_204_NO_CONTENT,
    responses={status.HTTP_404_NOT_FOUND: {"model": ErrorEnvelope}},
)
def delete_capture(
    capture_id: UUID,
    repository: Annotated[CaptureRepository, Depends(get_repository)],
    storage: Annotated[AttachmentStorage, Depends(get_attachment_storage)],
) -> Response | JSONResponse:
    paths = repository.delete(str(capture_id))
    if paths is None:
        return error_response(
            status_code=status.HTTP_404_NOT_FOUND,
            code="capture_not_found",
            message="Capture was not found.",
        )
    for relative_path in paths:
        try:
            storage.delete(relative_path)
        except AttachmentStorageError:
            logger.exception("Deleted Capture left an orphan attachment file")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/health", response_model=HealthResponse)
def health(response: Response) -> HealthResponse:
    settings = get_settings()
    database = check_database(settings.recall_database_path)
    try:
        get_attachment_storage().ensure_available()
        attachments: Literal["ok", "error"] = "ok"
    except AttachmentStorageError:
        attachments = "error"
    if database == "error" or attachments == "error":
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return HealthResponse(
            status="degraded",
            database=database,
            attachments=attachments,
            openai_configured=settings.openai_configured,
        )

    return HealthResponse(
        status="ok",
        database=database,
        attachments=attachments,
        openai_configured=settings.openai_configured,
    )
