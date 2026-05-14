from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile, status

from app.core.config import settings


def _get_allowed_extensions() -> set[str]:
    return {
        extension.strip().lower().lstrip(".")
        for extension in settings.allowed_extensions.split(",")
        if extension.strip()
    }


def _validate_extension(filename: str) -> str:
    extension = Path(filename).suffix.lower().lstrip(".")
    if extension not in _get_allowed_extensions():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only PDF files are allowed.",
        )
    return extension


def _validate_size(size_bytes: int) -> None:
    max_size_bytes = settings.max_upload_size_mb * 1024 * 1024
    if size_bytes > max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File size exceeds the {settings.max_upload_size_mb} MB limit.",
        )


async def save_uploaded_file(file: UploadFile) -> dict[str, str | int]:
    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file must have a filename.",
        )

    extension = _validate_extension(file.filename)
    content = await file.read()
    size_bytes = len(content)
    _validate_size(size_bytes)

    storage_dir = Path(settings.local_storage_path)
    storage_dir.mkdir(parents=True, exist_ok=True)

    stored_filename = f"{uuid4()}.{extension}"
    storage_path = storage_dir / stored_filename
    storage_path.write_bytes(content)

    return {
        "original_filename": file.filename,
        "stored_filename": stored_filename,
        "storage_path": str(storage_path),
        "content_type": file.content_type or "application/pdf",
        "size_bytes": size_bytes,
    }
