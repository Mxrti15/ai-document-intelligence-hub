from pathlib import Path
from uuid import uuid4

from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient, ContentSettings
from fastapi import HTTPException, UploadFile, status

from app.core.config import settings


class StorageError(Exception):
    pass


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


def _blob_service_client() -> BlobServiceClient:
    if not settings.azure_storage_account_name:
        raise StorageError("AZURE_STORAGE_ACCOUNT_NAME is required when STORAGE_MODE=azure_blob.")

    account_url = f"https://{settings.azure_storage_account_name}.blob.core.windows.net"
    credential = (
        ManagedIdentityCredential(client_id=settings.azure_client_id)
        if settings.azure_client_id
        else DefaultAzureCredential()
    )
    return BlobServiceClient(account_url=account_url, credential=credential)


async def save_document(file: UploadFile) -> dict[str, str | int]:
    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file must have a filename.",
        )

    extension = _validate_extension(file.filename)
    content = await file.read()
    size_bytes = len(content)
    _validate_size(size_bytes)

    stored_filename = f"{uuid4()}.{extension}"
    content_type = file.content_type or "application/pdf"

    if settings.storage_mode == "azure_blob":
        return _save_document_to_blob(content, stored_filename, content_type, size_bytes, file.filename)

    return _save_document_to_local(content, stored_filename, content_type, size_bytes, file.filename)


async def save_uploaded_file(file: UploadFile) -> dict[str, str | int]:
    return await save_document(file)


def read_document_bytes(storage_path: str) -> bytes:
    if settings.storage_mode == "azure_blob":
        return _read_blob_bytes(storage_path)

    return Path(storage_path).read_bytes()


def delete_document(storage_path: str) -> None:
    if settings.storage_mode == "azure_blob":
        _delete_blob(storage_path)
        return

    path = Path(storage_path)
    if path.exists():
        path.unlink()


def _save_document_to_local(
    content: bytes,
    stored_filename: str,
    content_type: str,
    size_bytes: int,
    original_filename: str,
) -> dict[str, str | int]:
    storage_dir = Path(settings.local_storage_path)
    storage_dir.mkdir(parents=True, exist_ok=True)

    storage_path = storage_dir / stored_filename
    storage_path.write_bytes(content)

    return {
        "original_filename": original_filename,
        "stored_filename": stored_filename,
        "storage_path": str(storage_path),
        "content_type": content_type,
        "size_bytes": size_bytes,
    }


def _save_document_to_blob(
    content: bytes,
    stored_filename: str,
    content_type: str,
    size_bytes: int,
    original_filename: str,
) -> dict[str, str | int]:
    blob_name = f"documents/{stored_filename}"
    blob_client = _blob_service_client().get_blob_client(
        container=settings.azure_storage_container_name,
        blob=blob_name,
    )
    blob_client.upload_blob(
        content,
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type),
    )

    return {
        "original_filename": original_filename,
        "stored_filename": stored_filename,
        "storage_path": blob_name,
        "content_type": content_type,
        "size_bytes": size_bytes,
    }


def _read_blob_bytes(storage_path: str) -> bytes:
    blob_client = _blob_service_client().get_blob_client(
        container=settings.azure_storage_container_name,
        blob=storage_path,
    )
    return blob_client.download_blob().readall()


def _delete_blob(storage_path: str) -> None:
    blob_client = _blob_service_client().get_blob_client(
        container=settings.azure_storage_container_name,
        blob=storage_path,
    )
    blob_client.delete_blob()
