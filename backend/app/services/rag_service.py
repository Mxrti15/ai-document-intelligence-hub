import time
from pathlib import Path
from typing import Any

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.telemetry import track_event, track_exception
from app.db.models import AIUsage, Document
from app.services.chunking_service import chunk_text
from app.services.document_parser import extract_text_from_pdf_bytes
from app.services.search_service import (
    SearchServiceError,
    index_document_chunks,
    search_relevant_chunks,
)
from app.services.storage_service import read_document_bytes


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "rag_answer_prompt.txt"


class RagServiceError(RuntimeError):
    pass


def _require_rag_enabled() -> None:
    if not settings.rag_enabled:
        raise RagServiceError("RAG is disabled. Set RAG_ENABLED=true to use this endpoint.")


def _get_document(db: Session, document_id: int) -> Document:
    document = db.query(Document).filter(Document.id == document_id).first()
    if document is None or document.status == "deleted":
        raise RagServiceError("Document not found.")
    return document


def _build_openai_client() -> AzureOpenAI:
    if not settings.azure_openai_endpoint:
        raise RagServiceError("AZURE_OPENAI_ENDPOINT is required for RAG.")
    if not settings.azure_openai_deployment_name:
        raise RagServiceError("AZURE_OPENAI_DEPLOYMENT_NAME is required for RAG.")
    credential = DefaultAzureCredential(managed_identity_client_id=settings.azure_client_id)
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default",
    )
    return AzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        azure_ad_token_provider=token_provider,
        api_version=settings.azure_openai_api_version,
    )


def _usage_from_response(response: Any, latency_ms: int) -> dict[str, Any]:
    usage = getattr(response, "usage", None)
    return {
        "model": settings.azure_openai_deployment_name or "azure-openai",
        "prompt_tokens": int(getattr(usage, "prompt_tokens", 0) or 0),
        "completion_tokens": int(getattr(usage, "completion_tokens", 0) or 0),
        "total_tokens": int(getattr(usage, "total_tokens", 0) or 0),
        "estimated_cost": 0,
        "latency_ms": latency_ms,
    }


def _save_usage(db: Session, document_id: int | None, usage: dict[str, Any]) -> None:
    if document_id is None:
        return
    db.add(
        AIUsage(
            document_id=document_id,
            operation_type="rag_query",
            model=str(usage["model"]),
            prompt_tokens=int(usage["prompt_tokens"]),
            completion_tokens=int(usage["completion_tokens"]),
            total_tokens=int(usage["total_tokens"]),
            estimated_cost=float(usage["estimated_cost"]),
            latency_ms=int(usage["latency_ms"]),
        )
    )
    db.commit()


def index_document_for_rag(db: Session, document_id: int) -> dict[str, Any]:
    _require_rag_enabled()
    started_at = time.perf_counter()
    document = _get_document(db, document_id)
    try:
        text = extract_text_from_pdf_bytes(read_document_bytes(document.storage_path))
        chunks = chunk_text(
            text,
            settings.rag_chunk_size,
            settings.rag_chunk_overlap,
            settings.rag_max_chunks_per_document,
            document_id=document.id,
        )
        indexed = index_document_chunks(document.id, document.original_filename, chunks)
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        track_event(
            "document_index_failed",
            properties={"document_id": str(document_id), "error_type": exc.__class__.__name__},
            measurements={"index_latency_ms": latency_ms},
        )
        track_exception(exc, {"operation": "rag_index", "document_id": str(document_id)})
        raise

    latency_ms = int((time.perf_counter() - started_at) * 1000)
    return {
        "document_id": document.id,
        "status": "indexed",
        "chunks_indexed": indexed,
        "index_name": settings.azure_search_index_name,
        "latency_ms": latency_ms,
    }


def _build_context(chunks: list[dict[str, Any]]) -> str:
    context_parts: list[str] = []
    total_chars = 0
    for chunk in chunks:
        label = f"[{chunk['chunk_id']}]"
        content = str(chunk["content"])
        part = f"{label}\n{content}"
        if total_chars + len(part) > settings.rag_max_context_chars:
            break
        context_parts.append(part)
        total_chars += len(part)
    return "\n\n".join(context_parts)


def _answer_with_context(question: str, chunks: list[dict[str, Any]]) -> tuple[str, dict[str, Any]]:
    client = _build_openai_client()
    deployment = settings.azure_openai_deployment_name or "azure-openai"
    started_at = time.perf_counter()
    response = client.chat.completions.create(
        model=deployment,
        messages=[
            {"role": "system", "content": PROMPT_PATH.read_text(encoding="utf-8")},
            {
                "role": "user",
                "content": f"Pregunta:\n{question}\n\nContexto:\n{_build_context(chunks)}",
            },
        ],
        max_tokens=settings.rag_max_output_tokens,
        temperature=0.1,
    )
    latency_ms = int((time.perf_counter() - started_at) * 1000)
    answer = response.choices[0].message.content or ""
    return answer.strip(), _usage_from_response(response, latency_ms)


def ask_document(db: Session, document_id: int, question: str) -> dict[str, Any]:
    _require_rag_enabled()
    started_at = time.perf_counter()
    document = _get_document(db, document_id)
    try:
        chunks = search_relevant_chunks(question, document_id=document.id, top_k=settings.rag_top_k)
        if not chunks:
            usage = {"model": settings.azure_openai_deployment_name or "azure-openai", "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0, "estimated_cost": 0, "latency_ms": 0}
            answer = "No hay fragmentos indexados suficientes para responder a esta pregunta."
        else:
            answer, usage = _answer_with_context(question, chunks)
            _save_usage(db, document.id, usage)
    except (RagServiceError, SearchServiceError):
        raise
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        track_event(
            "rag_query_failed",
            properties={"document_id": str(document_id), "error_type": exc.__class__.__name__},
            measurements={"rag_latency_ms": latency_ms, "top_k": settings.rag_top_k},
        )
        track_exception(exc, {"operation": "rag_query", "document_id": str(document_id)})
        raise

    latency_ms = int((time.perf_counter() - started_at) * 1000)
    track_event(
        "rag_query_completed",
        properties={"document_id": str(document.id), "rag_scope": "document"},
        measurements={
            "rag_latency_ms": latency_ms,
            "prompt_tokens": usage["prompt_tokens"],
            "completion_tokens": usage["completion_tokens"],
            "total_tokens": usage["total_tokens"],
            "top_k": settings.rag_top_k,
        },
    )
    return _response_payload(document.id, question, answer, chunks, usage, latency_ms)


def ask_all_documents(db: Session, question: str) -> dict[str, Any]:
    _require_rag_enabled()
    started_at = time.perf_counter()
    chunks = search_relevant_chunks(question, top_k=settings.rag_top_k)
    answer, usage = _answer_with_context(question, chunks) if chunks else (
        "No hay fragmentos indexados suficientes para responder a esta pregunta.",
        {"model": settings.azure_openai_deployment_name or "azure-openai", "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0, "estimated_cost": 0, "latency_ms": 0},
    )
    latency_ms = int((time.perf_counter() - started_at) * 1000)
    track_event(
        "rag_query_completed",
        properties={"rag_scope": "global"},
        measurements={"rag_latency_ms": latency_ms, "total_tokens": usage["total_tokens"], "top_k": settings.rag_top_k},
    )
    return _response_payload(None, question, answer, chunks, usage, latency_ms)


def _response_payload(
    document_id: int | None,
    question: str,
    answer: str,
    chunks: list[dict[str, Any]],
    usage: dict[str, Any],
    latency_ms: int,
) -> dict[str, Any]:
    return {
        "document_id": document_id,
        "question": question,
        "answer": answer,
        "citations": [
            {
                "document_id": int(chunk["document_id"]),
                "chunk_id": str(chunk["chunk_id"]),
                "filename": chunk.get("filename"),
                "content_preview": str(chunk["content"])[:240],
                "score": chunk.get("score"),
            }
            for chunk in chunks
        ],
        "usage": usage,
        "latency_ms": latency_ms,
    }
