# Fase 8 - Bicep IaC

La Fase 8 convierte la infraestructura Azure actual del proyecto AI Document Intelligence Hub en código Bicep.

## Alcance

Incluye:

- Azure Container Registry.
- Log Analytics.
- Application Insights.
- Azure Storage + contenedor de documentos.
- Azure SQL Database.
- Azure Key Vault.
- Azure OpenAI.
- Azure Container Apps Environment.
- Azure Container App.
- Role assignments para la User Assigned Managed Identity.

No incluye GitHub Actions, API Management, RAG ni Azure AI Search.

## Seguridad

- No se guardan passwords ni connection strings en el repositorio.
- Azure SQL se referencia como recurso existente para evitar gestionar o rotar passwords desde Bicep.
- La connection string de Application Insights se pasa como secret de Container Apps desde Bicep, pero no se expone como output de `main.bicep`.
- El secreto `sql-password` se referencia desde Key Vault. El valor debe existir en Key Vault antes de que la Container App pueda arrancar correctamente.
- El despliegue real está protegido por confirmación explícita en `phase8-bicep-deploy.ps1`.

## Flujo recomendado

```powershell
.\scripts\azure\phase8-bicep-build.ps1
.\scripts\azure\phase8-bicep-validate.ps1
.\scripts\azure\phase8-bicep-whatif.ps1
```

Solo después de revisar el what-if:

```powershell
.\scripts\azure\phase8-bicep-deploy.ps1
```

El script pedirá escribir `DEPLOY`.

## Notas operativas

Esta Fase modela la plataforma existente. Si los nombres de recursos cambian en Azure, actualiza `infra/params/dev.bicepparam` con valores no secretos.

## Resultado what-if tras ajuste de drift

El what-if queda sin deletes.

Cambios residuales esperados:

- `Microsoft.App/containerApps/aca-ai-doc-intel-api-dev`: Azure muestra ruido en propiedades gestionadas por el servicio (`runningStatus`, `traffic`, `workloadProfileName`, `maxInactiveRevisions`) y un cambio intencionado en `sql-password` para usar una referencia Key Vault versionless: `https://aidockv17882.vault.azure.net/secrets/sql-password`.
- Role assignments aparecen como `Unsupported` porque el `principalId` de la Managed Identity se resuelve en tiempo de despliegue.
- ACR, Managed Identity, Log Analytics y Azure SQL aparecen como `Ignore` porque se modelan como recursos existentes para evitar drift destructivo.

Sin cambios peligrosos:

- No hay deletes.
- Application Insights conserva su workspace gestionado actual.
- Container Apps Environment conserva el Log Analytics Workspace actual.
- Key Vault mantiene `softDeleteRetentionInDays = 90`.
- Container App mantiene `cpu = 0.25` y `memory = 0.5Gi`.
- Azure SQL no gestiona ni rota passwords desde Bicep.

## Fase 10

Se anade el modulo `infra/modules/search.bicep` para Azure AI Search con SKU `free` por defecto y parametros RAG en Container Apps. No se debe desplegar Bicep sin revisar `what-if`.
