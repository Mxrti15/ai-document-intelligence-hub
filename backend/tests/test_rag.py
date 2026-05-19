from fastapi.testclient import TestClient

from app.main import app
from app.services.chunking_service import chunk_text


def test_chunk_text_respects_limit_and_overlap() -> None:
    chunks = chunk_text(
        " ".join(["contrato"] * 200),
        chunk_size=120,
        overlap=20,
        max_chunks=3,
        document_id=7,
    )

    assert len(chunks) == 3
    assert chunks[0]["chunk_id"] == "doc-7-chunk-0001"
    assert all(chunk["content"] for chunk in chunks)


def test_rag_endpoint_returns_controlled_error_when_disabled() -> None:
    with TestClient(app) as client:
        response = client.post("/documents/1/ask", json={"question": "Que riesgos hay?"})

    assert response.status_code == 503
    assert "RAG is disabled" in response.json()["detail"]
