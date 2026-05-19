import json
import time
from pathlib import Path
from typing import Any

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

from app.core.config import settings
from app.core.telemetry import track_event, track_exception, track_metric


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "azure_openai_document_analysis.txt"


class AzureOpenAIAnalysisError(RuntimeError):
    pass


def _require_setting(value: str | None, name: str) -> str:
    if value is None or not value.strip():
        raise AzureOpenAIAnalysisError(f"Missing required setting for Azure OpenAI: {name}.")
    return value


def _build_client() -> AzureOpenAI:
    endpoint = _require_setting(settings.azure_openai_endpoint, "AZURE_OPENAI_ENDPOINT")
    _require_setting(settings.azure_openai_deployment_name, "AZURE_OPENAI_DEPLOYMENT_NAME")

    if settings.azure_openai_auth_mode != "managed_identity":
        raise AzureOpenAIAnalysisError("Unsupported Azure OpenAI auth mode. Use managed_identity.")

    credential = DefaultAzureCredential(managed_identity_client_id=settings.azure_client_id)
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default",
    )

    return AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version=settings.azure_openai_api_version,
    )


def _load_system_prompt() -> str:
    return PROMPT_PATH.read_text(encoding="utf-8")


def _parse_json_response(content: str | None) -> dict[str, Any]:
    if content is None or not content.strip():
        raise AzureOpenAIAnalysisError("Azure OpenAI returned an empty response.")

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError as exc:
        raise AzureOpenAIAnalysisError("Azure OpenAI returned invalid JSON.") from exc

    if not isinstance(parsed, dict):
        raise AzureOpenAIAnalysisError("Azure OpenAI JSON response must be an object.")

    return parsed


def _normalize_analysis(parsed: dict[str, Any]) -> dict[str, Any]:
    structured_data = parsed.get("structured_data")
    tags = parsed.get("tags")

    return {
        "document_type": str(parsed.get("document_type") or "unknown"),
        "language": str(parsed.get("language") or "unknown"),
        "summary": str(parsed.get("summary") or "No summary returned."),
        "risk_level": str(parsed.get("risk_level") or "medium"),
        "structured_data": structured_data if isinstance(structured_data, dict) else {},
        "tags": tags if isinstance(tags, list) else [],
        "risks": parsed.get("risks") if isinstance(parsed.get("risks"), list) else [],
        "recommended_actions": (
            parsed.get("recommended_actions")
            if isinstance(parsed.get("recommended_actions"), list)
            else []
        ),
    }


def _read_usage(response: Any, latency_ms: int) -> dict[str, Any]:
    usage = getattr(response, "usage", None)
    return {
        "model": settings.azure_openai_deployment_name or "azure-openai",
        "prompt_tokens": int(getattr(usage, "prompt_tokens", 0) or 0),
        "completion_tokens": int(getattr(usage, "completion_tokens", 0) or 0),
        "total_tokens": int(getattr(usage, "total_tokens", 0) or 0),
        "estimated_cost": 0,
        "latency_ms": latency_ms,
    }


def analyze_document_with_azure_openai(text: str, filename: str) -> dict[str, Any]:
    deployment_name = _require_setting(
        settings.azure_openai_deployment_name,
        "AZURE_OPENAI_DEPLOYMENT_NAME",
    )
    trimmed_text = text[: settings.ai_max_input_chars]
    user_content = (
        f"Archivo: {filename}\n"
        f"Texto extraido, recortado a {settings.ai_max_input_chars} caracteres:\n\n"
        f"{trimmed_text}"
    )

    client = _build_client()
    started_at = time.perf_counter()
    try:
        response = client.chat.completions.create(
            model=deployment_name,
            messages=[
                {"role": "system", "content": _load_system_prompt()},
                {"role": "user", "content": user_content},
            ],
            response_format={"type": "json_object"},
            max_tokens=settings.ai_max_output_tokens,
            temperature=0.1,
        )
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        track_event(
            "azure_openai_call_failed",
            properties={
                "deployment": deployment_name,
                "api_version": settings.azure_openai_api_version,
                "auth_mode": settings.azure_openai_auth_mode,
                "error_type": exc.__class__.__name__,
            },
            measurements={"latency_ms": latency_ms},
        )
        track_exception(exc, {"operation": "azure_openai_call"})
        raise

    latency_ms = int((time.perf_counter() - started_at) * 1000)

    content = response.choices[0].message.content
    analysis = _normalize_analysis(_parse_json_response(content))
    analysis["usage"] = _read_usage(response, latency_ms)
    track_event(
        "azure_openai_call_completed",
        properties={
            "deployment": deployment_name,
            "api_version": settings.azure_openai_api_version,
            "auth_mode": settings.azure_openai_auth_mode,
        },
        measurements={
            "latency_ms": latency_ms,
            "prompt_tokens": analysis["usage"]["prompt_tokens"],
            "completion_tokens": analysis["usage"]["completion_tokens"],
            "total_tokens": analysis["usage"]["total_tokens"],
        },
    )
    track_metric("openai_latency_ms", latency_ms, {"deployment": deployment_name})
    return analysis
