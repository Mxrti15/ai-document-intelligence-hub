# Fase 3 - Azure Blob Storage

## Objetivo

Sustituir almacenamiento local de PDFs por Azure Blob Storage cuando `STORAGE_MODE=azure_blob`, manteniendo `STORAGE_MODE=local` para desarrollo.

## Servicios usados

- Azure Storage Account
- Blob Container
- Azure Container Apps
- Managed Identity
- Azure RBAC

## Flujo

Usuario sube PDF -> FastAPI -> Blob Storage -> analisis lee bytes desde Blob.

## Autenticacion

La Container App usa Managed Identity y el rol `Storage Blob Data Contributor` sobre la Storage Account.

No se guardan claves, connection strings ni secretos en el repositorio.

## Scripts

Deploy:

```powershell
.\scripts\azure\phase3-storage-deploy.ps1
```

Validacion:

```powershell
.\scripts\azure\phase3-storage-validate.ps1
```

## Validacion funcional

Desde Swagger Azure:

1. `GET /health`
2. `GET /ready`
3. `POST /documents/upload` con PDF pequeno
4. `GET /documents`
5. `POST /documents/{id}/analyze`
6. `GET /documents/{id}/analysis`
7. `GET /analytics/usage`

Despues comprobar que el PDF existe en el container `documents`.

## Limitacion

Blob Storage ya persiste PDFs, pero SQLite sigue siendo efimero dentro de Azure Container Apps hasta Fase 4.
