"""Validated local image-attachment storage for Mema."""

from __future__ import annotations

import hashlib
import os
import re
from pathlib import Path
from uuid import uuid4

from mema_backend.limits import (
    IMAGE_MAX_HEIGHT,
    IMAGE_MAX_PIXELS,
    IMAGE_MAX_WIDTH,
    SCREENSHOT_MAX_BYTES,
)
from mema_backend.models import NewAttachment


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
JPEG_SIGNATURE = b"\xff\xd8\xff"
JPEG_START_OF_FRAME_MARKERS = frozenset(
    {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }
)
MANAGED_IMAGE_NAME = re.compile(
    r"(?P<id>[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.(?:png|jpg)"
)
MANAGED_TEMP_NAME = re.compile(
    r"\.(?P<id>[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.(?:png|jpg)\.[0-9a-f]{32}\.tmp"
)


class AttachmentValidationError(ValueError):
    """Raised when uploaded bytes are not a safe supported image."""


class AttachmentStorageError(RuntimeError):
    """Raised when a validated attachment cannot be stored or read."""


def _png_dimensions(image: bytes) -> tuple[int, int]:
    if (
        len(image) < 24
        or not image.startswith(PNG_SIGNATURE)
        or image[12:16] != b"IHDR"
    ):
        raise AttachmentValidationError("image bytes are not a valid PNG")
    return (
        int.from_bytes(image[16:20], "big"),
        int.from_bytes(image[20:24], "big"),
    )


def _jpeg_dimensions(image: bytes) -> tuple[int, int]:
    if len(image) < 4 or not image.startswith(JPEG_SIGNATURE):
        raise AttachmentValidationError("image bytes are not a valid JPEG")

    position = 2
    while position < len(image):
        while position < len(image) and image[position] == 0xFF:
            position += 1
        if position >= len(image):
            break

        marker = image[position]
        position += 1
        if marker in {0x01, 0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
            continue
        if position + 2 > len(image):
            break

        segment_length = int.from_bytes(image[position : position + 2], "big")
        if segment_length < 2 or position + segment_length > len(image):
            raise AttachmentValidationError("image bytes are not a valid JPEG")
        if marker in JPEG_START_OF_FRAME_MARKERS:
            if segment_length < 7:
                raise AttachmentValidationError("image bytes are not a valid JPEG")
            height = int.from_bytes(image[position + 3 : position + 5], "big")
            width = int.from_bytes(image[position + 5 : position + 7], "big")
            return width, height
        position += segment_length

    raise AttachmentValidationError("JPEG image dimensions are unavailable")


def validate_image(image: bytes, media_type: str) -> tuple[int, int]:
    if not image:
        raise AttachmentValidationError("image must not be empty")
    if len(image) > SCREENSHOT_MAX_BYTES:
        raise AttachmentValidationError(
            f"image must not exceed {SCREENSHOT_MAX_BYTES} bytes"
        )

    if media_type == "image/png":
        width, height = _png_dimensions(image)
    elif media_type == "image/jpeg":
        width, height = _jpeg_dimensions(image)
    else:
        raise AttachmentValidationError("image must be PNG or JPEG")

    if width <= 0 or height <= 0:
        raise AttachmentValidationError("image dimensions must be positive")
    if width > IMAGE_MAX_WIDTH or height > IMAGE_MAX_HEIGHT:
        raise AttachmentValidationError(
            f"image dimensions must not exceed {IMAGE_MAX_WIDTH} x {IMAGE_MAX_HEIGHT}"
        )
    if width * height > IMAGE_MAX_PIXELS:
        raise AttachmentValidationError(
            f"image must not exceed {IMAGE_MAX_PIXELS} pixels"
        )
    return width, height


class AttachmentStorage:
    """Store immutable images under a configured application-owned directory."""

    def __init__(self, root: Path) -> None:
        self.root = root.expanduser().resolve()

    def ensure_available(self) -> None:
        try:
            self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
            if not self.root.is_dir() or not os.access(self.root, os.R_OK | os.W_OK):
                raise OSError("attachment directory is not readable and writable")
        except OSError as error:
            raise AttachmentStorageError(
                f"Attachment directory is unavailable: {self.root}"
            ) from error

    def store(self, image: bytes, media_type: str) -> NewAttachment:
        width, height = validate_image(image, media_type)
        self.ensure_available()

        attachment_id = str(uuid4())
        suffix = ".png" if media_type == "image/png" else ".jpg"
        relative_path = Path("images") / attachment_id[:2] / f"{attachment_id}{suffix}"
        destination = self.path_for(relative_path.as_posix())
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = destination.with_name(f".{destination.name}.{uuid4().hex}.tmp")

        try:
            with temporary.open("xb") as handle:
                os.chmod(temporary, 0o600)
                handle.write(image)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        except OSError as error:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
            raise AttachmentStorageError("Image attachment could not be stored") from error

        return NewAttachment(
            id=attachment_id,
            media_type=media_type,
            relative_path=relative_path.as_posix(),
            byte_size=len(image),
            pixel_width=width,
            pixel_height=height,
            sha256=hashlib.sha256(image).hexdigest(),
        )

    def path_for(self, relative_path: str) -> Path:
        relative = Path(relative_path)
        if relative.is_absolute() or ".." in relative.parts:
            raise AttachmentStorageError("Attachment path is invalid")
        candidate = (self.root / relative).resolve()
        if not candidate.is_relative_to(self.root):
            raise AttachmentStorageError("Attachment path escapes its storage root")
        return candidate

    def read_path(self, relative_path: str) -> Path:
        path = self.path_for(relative_path)
        if not path.is_file():
            raise AttachmentStorageError("Attachment file is missing")
        return path

    def delete(self, relative_path: str) -> None:
        path = self.path_for(relative_path)
        try:
            path.unlink(missing_ok=True)
            if path.parent != self.root:
                try:
                    path.parent.rmdir()
                except OSError:
                    pass
        except OSError as error:
            raise AttachmentStorageError("Attachment file could not be deleted") from error

    def cleanup_unreferenced(self, referenced_paths: set[str]) -> int:
        """Remove only app-generated orphan images and interrupted temp files."""

        self.ensure_available()
        image_root = self.root / "images"
        if not image_root.is_dir() or image_root.is_symlink():
            return 0

        removed = 0
        normalized_references = {Path(value).as_posix() for value in referenced_paths}
        try:
            for shard in image_root.iterdir():
                if (
                    shard.is_symlink()
                    or not shard.is_dir()
                    or re.fullmatch(r"[0-9a-f]{2}", shard.name) is None
                ):
                    continue
                for candidate in shard.iterdir():
                    final_match = MANAGED_IMAGE_NAME.fullmatch(candidate.name)
                    temp_match = MANAGED_TEMP_NAME.fullmatch(candidate.name)
                    match = final_match or temp_match
                    if match is None or match.group("id")[:2] != shard.name:
                        continue
                    relative_path = candidate.relative_to(self.root).as_posix()
                    if final_match is not None and relative_path in normalized_references:
                        continue
                    if candidate.is_file() or candidate.is_symlink():
                        candidate.unlink()
                        removed += 1
                try:
                    shard.rmdir()
                except OSError:
                    pass
        except OSError as error:
            raise AttachmentStorageError(
                "Unreferenced image attachments could not be reconciled"
            ) from error
        return removed
