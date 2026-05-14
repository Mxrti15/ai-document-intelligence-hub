from pydantic import BaseModel


class UsageSummaryResponse(BaseModel):
    documents_uploaded: int
    documents_processed: int
    documents_failed: int
    total_tokens: int
    estimated_cost: float
