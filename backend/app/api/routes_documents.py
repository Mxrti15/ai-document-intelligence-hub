import time

from fastapi import APIRouter, Depends, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.telemetry import track_event, track_exception
from app.db.database import get_db
from app.db.models import Document
from app.schemas.document import DocumentListResponse, DocumentResponse
from app.services.storage_service import delete_document as delete_stored_document
from app.services.storage_service import save_uploaded_file


router = APIRouter(prefix="/documents", tags=["documents"])


@router.post("/upload", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    file: UploadFile,
    db: Session = Depends(get_db),
) -> Document:
    started_at = time.perf_counter()
    try:
        stored_file = await save_uploaded_file(file)

        document = Document(
            original_filename=str(stored_file["original_filename"]),
            stored_filename=str(stored_file["stored_filename"]),
            storage_path=str(stored_file["storage_path"]),
            content_type=str(stored_file["content_type"]),
            size_bytes=int(stored_file["size_bytes"]),
            status="uploaded",
        )
        db.add(document)
        db.commit()
        db.refresh(document)
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        track_event(
            "document_upload_failed",
            properties={
                "filename": file.filename or "unknown",
                "content_type": file.content_type or "unknown",
                "storage_mode": settings.storage_mode,
            },
            measurements={"latency_ms": latency_ms},
        )
        track_exception(exc, {"operation": "document_upload"})
        raise

    latency_ms = int((time.perf_counter() - started_at) * 1000)
    track_event(
        "document_uploaded",
        properties={
            "document_id": str(document.id),
            "filename": document.original_filename,
            "content_type": document.content_type,
            "storage_mode": settings.storage_mode,
            "status": document.status,
        },
        measurements={
            "size_bytes": document.size_bytes,
            "latency_ms": latency_ms,
        },
    )
    return document


@router.get("", response_model=DocumentListResponse)
def list_documents(db: Session = Depends(get_db)) -> DocumentListResponse:
    documents = (
        db.query(Document)
        .filter(Document.status != "deleted")
        .order_by(Document.created_at.desc())
        .all()
    )
    return DocumentListResponse(documents=documents, total=len(documents))


@router.get("/{document_id}", response_model=DocumentResponse)
def get_document(document_id: int, db: Session = Depends(get_db)) -> Document:
    document = (
        db.query(Document)
        .filter(Document.id == document_id, Document.status != "deleted")
        .first()
    )
    if document is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found.",
        )

    return document


@router.delete("/{document_id}", response_model=DocumentResponse)
def delete_document(document_id: int, db: Session = Depends(get_db)) -> Document:
    document = db.query(Document).filter(Document.id == document_id).first()
    if document is None or document.status == "deleted":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found.",
        )

    delete_stored_document(document.storage_path)
    document.status = "deleted"
    db.commit()
    db.refresh(document)

    return document
