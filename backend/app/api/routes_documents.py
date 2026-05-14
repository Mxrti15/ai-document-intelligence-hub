from fastapi import APIRouter, Depends, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import Document
from app.schemas.document import DocumentListResponse, DocumentResponse
from app.services.storage_service import save_uploaded_file


router = APIRouter(prefix="/documents", tags=["documents"])


@router.post("/upload", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    file: UploadFile,
    db: Session = Depends(get_db),
) -> Document:
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

    document.status = "deleted"
    db.commit()
    db.refresh(document)

    return document
