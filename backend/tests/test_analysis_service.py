from app.services.analysis_service import analyze_document_with_mock
from app.services.openai_service import AzureOpenAIAnalysisError, _parse_json_response


def test_mock_analysis_keeps_expected_shape() -> None:
    result = analyze_document_with_mock("Factura con riesgo operativo", "test.pdf")

    assert result["document_type"] == "invoice"
    assert result["risk_level"] == "medium"
    assert result["usage"]["total_tokens"] == 0
    assert result["summary"].startswith("Resumen simulado")


def test_openai_json_parser_rejects_invalid_json() -> None:
    try:
        _parse_json_response("not-json")
    except AzureOpenAIAnalysisError as exc:
        assert "invalid JSON" in str(exc)
    else:
        raise AssertionError("Expected AzureOpenAIAnalysisError")
