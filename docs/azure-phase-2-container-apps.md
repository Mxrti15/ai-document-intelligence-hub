# Fase 2 - Azure Container Apps

## Objetivo

Desplegar el backend FastAPI Dockerizado en Azure Container Apps usando Azure Container Registry.

## Servicios usados

- Resource Group
- Azure Container Registry Basic
- Azure Container Apps Environment
- Azure Container App

## Que queda fuera

- Blob Storage
- Azure SQL
- Azure OpenAI
- Key Vault
- API Management
- Bicep
- GitHub Actions

## Requisitos locales

- Docker
- Docker Compose
- Azure CLI
- Sesion Azure activa con `az login`

## Comandos

### Validacion local previa

```powershell
docker compose up --build -d
docker compose exec -T backend python -m pytest
docker compose exec -T backend python -m ruff check .
Invoke-RestMethod http://localhost:8000/health
Invoke-RestMethod http://localhost:8000/ready
cd frontend
pnpm build
```

### Deploy

```powershell
.\scripts\azure\phase2-deploy.ps1
```

### Validar Azure

```powershell
.\scripts\azure\phase2-validate.ps1
```

### Limpiar recursos

```powershell
.\scripts\azure\phase2-cleanup.ps1
```

## URLs

El deploy escribe `outputs/azure-phase2-deployment.json` con:

- `appUrl`
- `healthUrl`
- `readyUrl`

Endpoints esperados:

- `/health`
- `/ready`

## Coste

- Azure Container Apps usa `minReplicas = 0` y `maxReplicas = 1`.
- Azure Container Registry usa SKU Basic y tiene coste diario bajo.
- Borra el Resource Group si no se usa.

## Limitacion de esta fase

SQLite y documentos son efimeros en Azure Container Apps. Si el contenedor se reinicia o escala a cero, los datos pueden perderse.

La persistencia real llega en fases posteriores:

- Fase 3: Blob Storage
- Fase 4: Azure SQL
