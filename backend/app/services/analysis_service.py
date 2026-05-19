from typing import Any

from app.core.config import settings
from app.services.openai_service import analyze_document_with_azure_openai


def analyze_document_with_mock(text: str, filename: str) -> dict[str, Any]:
    normalized_text = text.lower()

    document_type = "unknown"
    if "factura" in normalized_text:
        document_type = "invoice"
    elif "contrato" in normalized_text:
        document_type = "contract"
    elif "curriculum" in normalized_text or "experiencia" in normalized_text:
        document_type = "cv"

    risk_level = "medium" if "riesgo" in normalized_text else "low"

    return {
        "document_type": document_type,
        "language": "es",
        "summary": f"Resumen simulado del documento {filename}.",
        "risk_level": risk_level,
        "structured_data": {},
        "tags": ["documento", "analisis"],
        "usage": {
            "model": "mock-model",
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
            "estimated_cost": 0,
            "latency_ms": 0,
        },
    }


def analyze_document_text(text: str, filename: str) -> dict[str, Any]:
    if settings.ai_analysis_provider == "azure_openai":
        return analyze_document_with_azure_openai(text, filename)

    return analyze_document_with_mock(text, filename)
