# Fase 10 - Azure AI Search + RAG

## Objetivo

Permitir preguntas sobre documentos usando Azure AI Search y Azure OpenAI.

## Servicios Usados

- Azure AI Search.
- Azure OpenAI embeddings.
- Azure OpenAI chat.
- Azure Blob Storage.
- Azure SQL Database.
- Application Insights.
- Managed Identity/RBAC.

## Flujo

```text
PDF -> texto -> chunks -> embeddings -> Azure AI Search -> pregunta -> retrieval -> Azure OpenAI -> respuesta
```

## Endpoints

- `POST /documents/{document_id}/index`
- `POST /documents/{document_id}/ask`
- `POST /chat`

## Seguridad

- No se loguea contenido completo del documento.
- No se loguean prompts completos ni secretos.
- No se guardan keys de Azure AI Search.
- La autenticacion objetivo es Managed Identity/RBAC.

## Coste

- El script intenta Azure AI Search SKU `free`.
- No pasa a SKU de pago sin `-AllowPaidSku`.
- No indexa automaticamente todos los documentos.
- CI/CD no ejecuta RAG ni consume Azure OpenAI.

## Validacion Manual

1. Abrir `/docs`.
2. Subir un PDF pequeno.
3. Ejecutar `POST /documents/{id}/index`.
4. Ejecutar `POST /documents/{id}/ask`.
5. Verificar `chunks_indexed > 0`, respuesta no vacia, citas no vacias y tokens > 0.
