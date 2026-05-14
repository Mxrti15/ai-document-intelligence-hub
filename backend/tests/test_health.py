from fastapi.testclient import TestClient

from app.main import app


def test_health_returns_200() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_ready_returns_200() -> None:
    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_upload_non_pdf_fails() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/documents/upload",
            files={"file": ("notes.txt", b"hello", "text/plain")},
        )

    assert response.status_code == 400


def test_list_documents_returns_200() -> None:
    with TestClient(app) as client:
        response = client.get("/documents")

    assert response.status_code == 200
    assert "documents" in response.json()


def test_analytics_usage_returns_200() -> None:
    with TestClient(app) as client:
        response = client.get("/analytics/usage")

    assert response.status_code == 200
    assert "documents_uploaded" in response.json()
