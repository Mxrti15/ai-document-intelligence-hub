# Fase 5 - Azure OpenAI

## Objetivo

Sustituir el analisis mock por analisis real con Azure OpenAI cuando la app se ejecuta con:

```env
AI_ANALYSIS_PROVIDER=azure_openai
```

El modo local sigue funcionando con:

```env
AI_ANALYSIS_PROVIDER=mock
```

## Servicios usados

- Azure OpenAI
- Azure Container Apps
- Managed Identity
- Azure RBAC
- Azure SQL Database
- Azure Blob Storage

## Flujo

```text
PDF -> Blob Storage -> extraccion de texto -> Azure OpenAI -> JSON estructurado -> Azure SQL
```

## Autenticacion

La Container App usa una User Assigned Managed Identity. Esa identidad recibe el rol:

```text
Cognitive Services OpenAI User
```

sobre el recurso Azure OpenAI. No se guardan API keys en el repositorio.

## Coste

Azure OpenAI consume por tokens. La fase limita:

- caracteres de entrada con `AI_MAX_INPUT_CHARS`;
- salida con `AI_MAX_OUTPUT_TOKENS`;
- validacion con un unico PDF pequeno.

Modelo usado por defecto en los scripts:

```text
gpt-4o
```

## Scripts

```powershell
.\scripts\azure\phase5-openai-deploy.ps1
.\scripts\azure\phase5-openai-validate.ps1
```

## Validacion

La validacion comprueba:

- recurso Azure OpenAI creado;
- deployment disponible;
- RBAC sobre la Managed Identity;
- `/health`;
- `/ready`;
- subida de PDF;
- analisis real;
- `usage.total_tokens > 0`;
- analytics con tokens mayores que 0.
