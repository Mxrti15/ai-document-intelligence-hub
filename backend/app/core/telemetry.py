import json
from typing import Any

from fastapi import FastAPI

from app.core.config import settings
from app.core.logging import get_logger


logger = get_logger("app.telemetry")


def _safe_payload(
    properties: dict[str, Any] | None = None,
    measurements: dict[str, Any] | None = None,
) -> str:
    payload = {
        "properties": properties or {},
        "measurements": measurements or {},
    }
    return json.dumps(payload, ensure_ascii=False, default=str)


def configure_telemetry(app: FastAPI) -> None:
    if not settings.enable_app_insights:
        logger.info("app_insights_disabled")
        return

    if not settings.applicationinsights_connection_string:
        logger.warning("app_insights_enabled_without_connection_string")
        return

    try:
        from azure.monitor.opentelemetry import configure_azure_monitor
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        from opentelemetry.instrumentation.requests import RequestsInstrumentor

        configure_azure_monitor(
            connection_string=settings.applicationinsights_connection_string,
            logger_name="app",
        )
        FastAPIInstrumentor.instrument_app(app)
        RequestsInstrumentor().instrument()
        HTTPXClientInstrumentor().instrument()
        logger.info("app_insights_configured")
    except Exception:
        logger.exception("app_insights_configuration_failed")


def track_event(
    name: str,
    properties: dict[str, Any] | None = None,
    measurements: dict[str, Any] | None = None,
) -> None:
    logger.info("event=%s %s", name, _safe_payload(properties, measurements))


def track_metric(
    name: str,
    value: float,
    properties: dict[str, Any] | None = None,
) -> None:
    track_event(
        "metric_recorded",
        properties={"metric_name": name, **(properties or {})},
        measurements={"value": value},
    )


def track_exception(error: Exception, properties: dict[str, Any] | None = None) -> None:
    safe_properties = {
        "error_type": error.__class__.__name__,
        **(properties or {}),
    }
    logger.exception("event=exception %s", _safe_payload(safe_properties))
