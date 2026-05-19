import time

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

from app.core.config import settings
from app.core.telemetry import track_event, track_exception


class EmbeddingServiceError(RuntimeError):
    pass


def _require_setting(value: str | None, name: str) -> str:
    if value is None or not value.strip():
        raise EmbeddingServiceError(f"Missing required RAG setting: {name}.")
    return value


def _build_client() -> AzureOpenAI:
    endpoint = _require_setting(settings.azure_openai_endpoint, "AZURE_OPENAI_ENDPOINT")
    _require_setting(
        settings.azure_openai_embedding_deployment_name,
        "AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME",
    )

    if settings.azure_openai_auth_mode != "managed_identity":
        raise EmbeddingServiceError("Unsupported Azure OpenAI auth mode. Use managed_identity.")

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


def create_embeddings(texts: list[str]) -> list[list[float]]:
    deployment = _require_setting(
        settings.azure_openai_embedding_deployment_name,
        "AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME",
    )
    if not texts:
        return []

    client = _build_client()
    started_at = time.perf_counter()
    try:
        response = client.embeddings.create(model=deployment, input=texts)
    except Exception as exc:
        latency_ms = int((time.perf_counter() - started_at) * 1000)
        track_event(
            "embedding_failed",
            properties={"deployment": deployment, "error_type": exc.__class__.__name__},
            measurements={"embedding_latency_ms": latency_ms, "texts": len(texts)},
        )
        track_exception(exc, {"operation": "embedding_create"})
        raise

    latency_ms = int((time.perf_counter() - started_at) * 1000)
    track_event(
        "embedding_created",
        properties={"deployment": deployment},
        measurements={"embedding_latency_ms": latency_ms, "texts": len(texts)},
    )
    return [list(item.embedding) for item in response.data]


def create_embedding(text: str) -> list[float]:
    embeddings = create_embeddings([text])
    if not embeddings:
        raise EmbeddingServiceError("Azure OpenAI returned no embedding.")
    return embeddings[0]
