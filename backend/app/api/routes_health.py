from fastapi import APIRouter

from app.core.config import settings
from app.db.database import check_database_ready


router = APIRouter()


@router.get("/health")
def health_check() -> dict[str, str]:
    return {
        "status": "ok",
        "service": settings.app_name,
    }


@router.get("/ready")
def readiness_check() -> dict[str, str]:
    check_database_ready()
    return {"status": "ready"}
