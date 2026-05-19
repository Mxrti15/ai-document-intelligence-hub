from pydantic import BaseModel, Field


class DocumentAskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=2000)


class RagCitation(BaseModel):
    document_id: int
    chunk_id: str
    filename: str | None = None
    content_preview: str
    score: float | None = None


class RagAnswerResponse(BaseModel):
    document_id: int | None = None
    question: str
    answer: str
    citations: list[RagCitation]
    usage: dict
    latency_ms: int


class DocumentIndexResponse(BaseModel):
    document_id: int
    status: str
    chunks_indexed: int
    index_name: str
    latency_ms: int
