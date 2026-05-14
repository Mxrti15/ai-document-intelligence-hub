from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AIUsage, Document
from app.schemas.analytics import UsageSummaryResponse


router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/usage", response_model=UsageSummaryResponse)
def get_usage_summary(db: Session = Depends(get_db)) -> UsageSummaryResponse:
    documents_uploaded = db.query(Document).filter(Document.status != "deleted").count()
    documents_processed = db.query(Document).filter(Document.status == "processed").count()
    documents_failed = db.query(Document).filter(Document.status == "failed").count()

    total_tokens = db.query(func.coalesce(func.sum(AIUsage.total_tokens), 0)).scalar()
    estimated_cost = db.query(func.coalesce(func.sum(AIUsage.estimated_cost), 0.0)).scalar()

    return UsageSummaryResponse(
        documents_uploaded=documents_uploaded,
        documents_processed=documents_processed,
        documents_failed=documents_failed,
        total_tokens=total_tokens,
        estimated_cost=estimated_cost,
    )
