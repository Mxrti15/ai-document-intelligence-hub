import time
from datetime import datetime, timezone
from typing import Any

from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)
from azure.search.documents.models import VectorizedQuery

from app.core.config import settings
from app.core.telemetry import track_event, track_exception
from app.services.embedding_service import create_embedding, create_embeddings


class SearchServiceError(RuntimeError):
    pass


def _require_rag_enabled() -> None:
    if not settings.rag_enabled:
        raise SearchServiceError("RAG is disabled. Set RAG_ENABLED=true to use Azure AI Search.")


def _require_setting(value: str | None, name: str) -> str:
    if value is None or not value.strip():
        raise SearchServiceError(f"Missing required RAG setting: {name}.")
    return value


def _credential() -> DefaultAzureCredential | ManagedIdentityCredential | AzureKeyCredential:
    if settings.azure_search_auth_mode != "managed_identity":
        raise SearchServiceError("Unsupported Azure AI Search auth mode. Use managed_identity.")
    if settings.azure_client_id:
        return ManagedIdentityCredential(client_id=settings.azure_client_id)
    return DefaultAzureCredential()


def _endpoint() -> str:
    return _require_setting(settings.azure_search_endpoint, "AZURE_SEARCH_ENDPOINT")


def _index_name() -> str:
    return settings.azure_search_index_name


def _index_client() -> SearchIndexClient:
    return SearchIndexClient(endpoint=_endpoint(), credential=_credential())


def _search_client() -> SearchClient:
    return SearchClient(endpoint=_endpoint(), index_name=_index_name(), credential=_credential())


def ensure_search_index() -> None:
    _require_rag_enabled()
    index_client = _index_client()
    index_name = _index_name()

    try:
        index_client.get_index(index_name)
        return
    except Exception:
        pass

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="hnsw")],
        profiles=[VectorSearchProfile(name="vector-profile", algorithm_configuration_name="hnsw")],
    )
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SimpleField(
            name="document_id",
            type=SearchFieldDataType.Int32,
            filterable=True,
            sortable=True,
        ),
        SimpleField(name="chunk_id", type=SearchFieldDataType.String, filterable=True),
        SimpleField(
            name="chunk_index",
            type=SearchFieldDataType.Int32,
            filterable=True,
            sortable=True,
        ),
        SearchableField(name="filename", type=SearchFieldDataType.String, filterable=True),
        SearchableField(name="content", type=SearchFieldDataType.String),
        SearchField(
            name="content_vector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=settings.azure_openai_embedding_dimensions,
            vector_search_profile_name="vector-profile",
        ),
        SimpleField(
            name="created_at",
            type=SearchFieldDataType.DateTimeOffset,
            filterable=True,
            sortable=True,
        ),
    ]
    index_client.create_index(
        SearchIndex(name=index_name, fields=fields, vector_search=vector_search)
    )


def delete_document_chunks(document_id: int) -> None:
    _require_rag_enabled()
    search_client = _search_client()
    results = search_client.search(
        search_text="*",
        filter=f"document_id eq {document_id}",
        select=["id"],
        top=settings.rag_max_chunks_per_document,
    )
    docs = [{"id": result["id"]} for result in results]
    if docs:
        search_client.delete_documents(documents=docs)


def index_document_chunks(document_id: int, filename: str, chunks: list[dict]) -> int:
    _require_rag_enabled()
    if not chunks:
        return 0

    ensure_search_index()
    delete_document_chunks(document_id)

    started_at = time.perf_counter()
    embeddings = create_embeddings([str(chunk["content"]) for chunk in chunks])
    now = datetime.now(timezone.utc).isoformat()
    documents = []
    for chunk, embedding in zip(chunks, embeddings, strict=True):
        chunk_id = str(chunk["chunk_id"])
        documents.append(
            {
                "id": chunk_id,
                "document_id": document_id,
                "chunk_id": chunk_id,
                "chunk_index": int(chunk["chunk_index"]),
                "filename": filename,
                "content": str(chunk["content"]),
                "content_vector": embedding,
                "created_at": now,
            }
        )

    result = _search_client().upload_documents(documents=documents)
    indexed = sum(1 for item in result if item.succeeded)
    latency_ms = int((time.perf_counter() - started_at) * 1000)
    track_event(
        "document_indexed",
        properties={"document_id": str(document_id), "index_name": _index_name()},
        measurements={"chunks_indexed": indexed, "index_latency_ms": latency_ms},
    )
    return indexed


def search_relevant_chunks(
    question: str,
    document_id: int | None = None,
    top_k: int = 5,
) -> list[dict[str, Any]]:
    _require_rag_enabled()
    ensure_search_index()

    started_at = time.perf_counter()
    try:
        question_embedding = create_embedding(question)
        vector_query = VectorizedQuery(
            vector=question_embedding,
            k_nearest_neighbors=top_k,
            fields="content_vector",
        )
        filter_expression = f"document_id eq {document_id}" if document_id is not None else None
        results = _search_client().search(
            search_text=question,
            vector_queries=[vector_query],
            filter=filter_expression,
            select=["document_id", "chunk_id", "chunk_index", "filename", "content"],
            top=top_k,
        )
        chunks = [
            {
                "document_id": int(result["document_id"]),
                "chunk_id": str(result["chunk_id"]),
                "chunk_index": int(result["chunk_index"]),
                "filename": result.get("filename"),
                "content": str(result["content"]),
                "score": float(result.get("@search.score", 0.0) or 0.0),
            }
            for result in results
        ]
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        track_event(
            "search_query_failed",
            properties={"document_id": str(document_id or ""), "error_type": exc.__class__.__name__},
            measurements={"search_latency_ms": latency_ms, "top_k": top_k},
        )
        track_exception(exc, {"operation": "rag_search"})
        raise

    latency_ms = int((time.perf_counter() - started_at) * 1000)
    track_event(
        "search_query_completed",
        properties={"document_id": str(document_id or ""), "index_name": _index_name()},
        measurements={"search_latency_ms": latency_ms, "top_k": top_k, "results": len(chunks)},
    )
    return chunks
