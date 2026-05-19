import json
import time
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.telemetry import track_event, track_exception, track_metric
from app.db.database import get_db
from app.db.models import AIUsage, Document, DocumentAnalysis
from app.schemas.analysis import AnalyzeDocumentResponse, DocumentAnalysisResponse
from app.services.analysis_service import analyze_document_text
from app.services.document_parser import DocumentParserError, extract_text_from_pdf_bytes
from app.services.storage_service import StorageError, read_document_bytes


router = APIRouter(tags=["analysis"])


def _get_active_document(document_id: int, db: Session) -> Document:
    document = db.query(Document).filter(Document.id == document_id).first()
    if document is None or document.status == "deleted":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found.",
        )
    return document


def _save_analysis_result(
    document: Document,
    analysis_result: dict[str, Any],
    db: Session,
) -> tuple[DocumentAnalysis, dict[str, Any]]:
    usage = analysis_result["usage"]

    analysis = DocumentAnalysis(
        document_id=document.id,
        document_type=analysis_result["document_type"],
        language=analysis_result["language"],
        summary=analysis_result["summary"],
        risk_level=analysis_result["risk_level"],
        structured_data_json=json.dumps(analysis_result["structured_data"]),
        tags_json=json.dumps(analysis_result["tags"]),
    )
    usage_record = AIUsage(
        document_id=document.id,
        operation_type="document_analysis",
        model=usage["model"],
        prompt_tokens=usage["prompt_tokens"],
        completion_tokens=usage["completion_tokens"],
        total_tokens=usage["total_tokens"],
        estimated_cost=usage["estimated_cost"],
        latency_ms=usage["latency_ms"],
    )

    db.add(analysis)
    db.add(usage_record)
    document.status = "processed"
    document.processed_at = datetime.utcnow()
    db.commit()
    db.refresh(analysis)
    db.refresh(document)

    return analysis, usage


def _analyze_document(document: Document, db: Session) -> AnalyzeDocumentResponse:
    started_at = time.perf_counter()
    document.status = "processing"
    db.commit()
    db.refresh(document)

    try:
        file_bytes = read_document_bytes(document.storage_path)
        text = extract_text_from_pdf_bytes(file_bytes)
        analysis_result = analyze_document_text(text, document.original_filename)
        analysis, usage = _save_analysis_result(document, analysis_result, db)
    except (DocumentParserError, StorageError, OSError) as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        document.status = "failed"
        db.commit()
        track_event(
            "document_analysis_failed",
            properties={
                "document_id": str(document.id),
                "status": document.status,
                "error_type": exc.__class__.__name__,
                "ai_provider": settings.ai_analysis_provider,
                "storage_mode": settings.storage_mode,
                "database_mode": settings.database_mode,
            },
            measurements={"latency_ms": latency_ms},
        )
        track_exception(exc, {"operation": "document_analysis", "document_id": str(document.id)})
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        document.status = "failed"
        db.commit()
        track_event(
            "document_analysis_failed",
            properties={
                "document_id": str(document.id),
                "status": document.status,
                "error_type": exc.__class__.__name__,
                "ai_provider": settings.ai_analysis_provider,
                "storage_mode": settings.storage_mode,
                "database_mode": settings.database_mode,
            },
            measurements={"latency_ms": latency_ms},
        )
        track_exception(exc, {"operation": "document_analysis", "document_id": str(document.id)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Document analysis failed.",
        ) from exc

    latency_ms = int((time.perf_counter() - started_at) * 1000)
    measurements = {
        "latency_ms": latency_ms,
        "prompt_tokens": usage["prompt_tokens"],
        "completion_tokens": usage["completion_tokens"],
        "total_tokens": usage["total_tokens"],
        "estimated_cost": usage["estimated_cost"],
    }
    track_event(
        "document_analyzed",
        properties={
            "document_id": str(document.id),
            "document_type": analysis.document_type,
            "risk_level": analysis.risk_level,
            "ai_provider": settings.ai_analysis_provider,
            "storage_mode": settings.storage_mode,
            "database_mode": settings.database_mode,
            "status": document.status,
        },
        measurements=measurements,
    )
    track_metric("analysis_latency_ms", latency_ms, {"document_id": str(document.id)})
    track_metric("tokens_used_total", usage["total_tokens"], {"document_id": str(document.id)})
    return AnalyzeDocumentResponse(
        document_id=document.id,
        status=document.status,
        analysis=analysis,
        usage=usage,
    )


@router.post("/documents/{document_id}/analyze", response_model=AnalyzeDocumentResponse)
def analyze_document(document_id: int, db: Session = Depends(get_db)) -> AnalyzeDocumentResponse:
    document = _get_active_document(document_id, db)
    return _analyze_document(document, db)


@router.get("/documents/{document_id}/analysis", response_model=DocumentAnalysisResponse)
def get_document_analysis(
    document_id: int,
    db: Session = Depends(get_db),
) -> DocumentAnalysis:
    _get_active_document(document_id, db)
    analysis = (
        db.query(DocumentAnalysis)
        .filter(DocumentAnalysis.document_id == document_id)
        .order_by(DocumentAnalysis.created_at.desc())
        .first()
    )
    if analysis is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document analysis not found.",
        )

    return analysis


@router.post("/documents/{document_id}/reprocess", response_model=AnalyzeDocumentResponse)
def reprocess_document(document_id: int, db: Session = Depends(get_db)) -> AnalyzeDocumentResponse:
    document = _get_active_document(document_id, db)

    db.query(DocumentAnalysis).filter(DocumentAnalysis.document_id == document_id).delete()
    db.query(AIUsage).filter(AIUsage.document_id == document_id).delete()
    db.commit()

    return _analyze_document(document, db)
