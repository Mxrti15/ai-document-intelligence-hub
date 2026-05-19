# Infraestructura Azure con Bicep

Esta carpeta modela la infraestructura actual del proyecto AI Document Intelligence Hub como IaC con Bicep.

La Fase 8 no despliega cambios automáticamente. Los scripts separan build, validación, what-if y deploy para revisar el impacto antes de tocar Azure.

## Componentes modelados

- Azure Container Registry Basic.
- Log Analytics Workspace.
- Application Insights.
- Storage Account y contenedor `documents`.
- Azure SQL Server y Azure SQL Database.
- Azure Key Vault con RBAC.
- Azure OpenAI y deployment `gpt-4o`.
- Azure Container Apps Environment.
- Azure Container App con Managed Identity, Blob Storage, Azure SQL, Azure OpenAI y Application Insights.
- Role assignments mínimos para la User Assigned Managed Identity.

## Parámetros

Los parámetros de desarrollo están en `infra/params/dev.bicepparam`.

No se guardan passwords ni connection strings en el repositorio. El SQL Server y la base de datos existentes se modelan como `existing` para evitar rotaciones accidentales de password desde Bicep.

## Scripts

```powershell
.\scripts\azure\phase8-bicep-build.ps1
.\scripts\azure\phase8-bicep-validate.ps1
.\scripts\azure\phase8-bicep-whatif.ps1
.\scripts\azure\phase8-bicep-deploy.ps1
```

El deploy pide escribir `DEPLOY` antes de ejecutar `az deployment group create`.
