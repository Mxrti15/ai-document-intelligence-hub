from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict


class DocumentAnalysisResponse(BaseModel):
    id: int
    document_id: int
    document_type: str
    language: str
    summary: str
    risk_level: str
    structured_data_json: str
    tags_json: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AnalyzeDocumentResponse(BaseModel):
    document_id: int
    status: str
    analysis: DocumentAnalysisResponse
    usage: dict[str, Any]
