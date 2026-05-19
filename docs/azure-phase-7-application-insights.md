# Fase 7 - Application Insights

## Objetivo

Anadir observabilidad real a la API FastAPI desplegada en Azure Container Apps.

## Servicios usados

- Azure Application Insights
- Azure Monitor
- Azure Container Apps
- OpenTelemetry

## Que se observa

- requests;
- errores;
- latencia;
- upload de documentos;
- analisis de documentos;
- llamadas a Azure OpenAI;
- tokens;
- analytics.

## Seguridad

No se loggea texto completo de documentos, prompts completos, passwords, connection strings ni secretos.

La telemetria permitida incluye:

- `document_id`;
- `filename`;
- `document_type`;
- `risk_level`;
- `status`;
- `latency_ms`;
- `tokens`;
- `model/deployment`;
- `operation_type`;
- `error_type`.

## Validacion

- `/health`;
- `/ready`;
- upload;
- analyze;
- analytics;
- consultas KQL en Application Insights.

## KQL

Requests recientes:

```kusto
requests
| order by timestamp desc
| take 20
```

Errores recientes:

```kusto
exceptions
| order by timestamp desc
| take 20
```

Traces de eventos:

```kusto
traces
| where message contains "document_"
   or message contains "azure_openai_call"
   or message contains "analytics_requested"
| order by timestamp desc
| take 50
```

Tokens:

```kusto
traces
| where message contains "tokens"
| order by timestamp desc
| take 50
```
