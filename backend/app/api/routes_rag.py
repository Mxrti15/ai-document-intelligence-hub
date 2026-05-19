from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.schemas.rag import DocumentAskRequest, DocumentIndexResponse, RagAnswerResponse
from app.services.rag_service import (
    RagServiceError,
    ask_all_documents,
    ask_document,
    index_document_for_rag,
)
from app.services.search_service import SearchServiceError


router = APIRouter(tags=["rag"])


def _rag_http_error(exc: Exception) -> HTTPException:
    message = str(exc)
    status_code = (
        status.HTTP_503_SERVICE_UNAVAILABLE
        if "disabled" in message.lower() or "missing required" in message.lower()
        else status.HTTP_422_UNPROCESSABLE_ENTITY
    )
    return HTTPException(status_code=status_code, detail=message)


@router.post("/documents/{document_id}/index", response_model=DocumentIndexResponse)
def index_document(document_id: int, db: Session = Depends(get_db)) -> dict:
    try:
        return index_document_for_rag(db, document_id)
    except (RagServiceError, SearchServiceError) as exc:
        raise _rag_http_error(exc) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Document RAG indexing failed.",
        ) from exc


@router.post("/documents/{document_id}/ask", response_model=RagAnswerResponse)
def ask_single_document(
    document_id: int,
    payload: DocumentAskRequest,
    db: Session = Depends(get_db),
) -> dict:
    try:
        return ask_document(db, document_id, payload.question)
    except (RagServiceError, SearchServiceError) as exc:
        raise _rag_http_error(exc) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Document RAG query failed.",
        ) from exc


@router.post("/chat", response_model=RagAnswerResponse)
def chat(payload: DocumentAskRequest, db: Session = Depends(get_db)) -> dict:
    try:
        return ask_all_documents(db, payload.question)
    except (RagServiceError, SearchServiceError) as exc:
        raise _rag_http_error(exc) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="RAG chat query failed.",
        ) from exc
