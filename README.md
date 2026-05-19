# FASE1 - MVP local

Objetivo: levantar en local el backend FastAPI dockerizado y el frontend React/Vite para probar el flujo completo de AI Document Intelligence Hub.

En esta fase el proyecto demuestra:

- subida de documentos PDF;
- listado y seleccion de documentos;
- analisis mock de IA;
- resumen, datos estructurados y riesgo;
- metricas de uso;
- demo guiada desde la interfaz.

## Requisitos

- Docker Desktop activo.
- Node.js con Corepack/pnpm.
- PowerShell en Windows.

## 1. Levantar backend

Desde la raiz del proyecto:

```powershell
cd C:\Users\Martiko\Desktop\IA\ai-document-intelligence-hub
docker compose up --build -d
```

Validar que FastAPI responde:

```powershell
Invoke-RestMethod http://localhost:8000/health
Invoke-RestMethod http://localhost:8000/ready
```

URLs utiles:

- API local: `http://localhost:8000`
- Health: `http://localhost:8000/health`
- Ready: `http://localhost:8000/ready`

## 2. Levantar frontend

En otra terminal:

```powershell
cd C:\Users\Martiko\Desktop\IA\ai-document-intelligence-hub\frontend
pnpm dev
```

Abrir:

```text
http://localhost:5173
```

Desde la UI se puede ejecutar la demo completa: generar PDF de prueba, subirlo, analizarlo y ver metricas.

## 3. Validacion tecnica

Backend:

```powershell
cd C:\Users\Martiko\Desktop\IA\ai-document-intelligence-hub
docker compose exec -T backend python -m pytest
docker compose exec -T backend python -m ruff check .
```

Frontend:

```powershell
cd C:\Users\Martiko\Desktop\IA\ai-document-intelligence-hub\frontend
pnpm build
```

## 4. Parar entorno local

```powershell
cd C:\Users\Martiko\Desktop\IA\ai-document-intelligence-hub
docker compose down
```

Nota: en Fase 1 la base de datos SQLite y los documentos son locales. La persistencia cloud queda para fases posteriores.

# FASE2

## Estado

🟡 **En progreso**

La Fase 2 tiene como objetivo desplegar el backend actual en Azure sin cambiar todavía la lógica interna de la aplicación.

El objetivo técnico es demostrar:

```text
Docker local
  ↓
Azure Container Registry
  ↓
Azure Container Apps
  ↓
Endpoint público /health funcionando
```

## Servicios usados en esta fase

### Azure CLI

Herramienta usada para gestionar Azure desde terminal.

Permite crear recursos, subir imágenes, desplegar apps y validar el estado sin depender del portal web.

Ejemplo:

```powershell
az group create --name rg-ai-doc-intel-dev --location swedencentral
```

### Azure Resource Group

Grupo lógico donde se agrupan todos los recursos de la fase.

Nombre usado:

```text
rg-ai-doc-intel-dev
```

Ventaja principal:

```powershell
az group delete --name rg-ai-doc-intel-dev --yes
```

Con este comando se puede borrar toda la fase de golpe y evitar costes innecesarios.

### Azure Container Registry

Registro privado de imágenes Docker.

Uso en el proyecto:

```text
Docker build local
  ↓
Docker push
  ↓
Azure Container Registry
```

Ejemplo de imagen:

```text
acidocintel29788.azurecr.io/ai-doc-intel-backend:phase2
```

ACR permite que Azure Container Apps pueda descargar la imagen del backend y ejecutarla en la nube.

### Azure Container Apps Environment

Entorno gestionado donde viven las Container Apps.

Es una capa gestionada por Azure que evita tener que administrar servidores, máquinas virtuales o Kubernetes directamente.

En esta fase se intentó crear primero en:

```text
westeurope
```

pero Azure devolvió:

```text
AKSCapacityHeavyUsage
```

Esto indica que la región estaba experimentando alta demanda de capacidad. Como solución, se cambió la región a:

```text
swedencentral
```

### Azure Container Apps

Servicio donde se ejecutará el backend FastAPI dockerizado.

Configuración objetivo:

```text
ingress externo
target port 8000
minReplicas = 0
maxReplicas = 1
CPU baja
memoria baja
```

Con esta configuración, la app está preparada para pruebas de bajo coste.

---

## Qué se ha conseguido en Fase 2

Durante el primer intento real de despliegue se validó:

```text
Azure CLI instalado y funcionando
Login Azure correcto
Providers registrados
Resource Group creado
ACR Basic creado
Docker build correcto
Docker push correcto
Imagen subida al ACR
```

La parte que quedó pendiente fue la creación del Container Apps Environment por falta de capacidad en `westeurope`.

Error detectado:

```text
AKSCapacityHeavyUsage
```

Solución aplicada:

```text
Cambiar LOCATION de westeurope a swedencentral
```

---

## Providers registrados

La suscripción necesitaba registrar los siguientes providers:

```text
Microsoft.ContainerRegistry
Microsoft.App
Microsoft.OperationalInsights
```

Comandos utilizados:

```powershell
az provider register --namespace Microsoft.ContainerRegistry --wait
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait
```

Validación:

```powershell
az provider show --namespace Microsoft.ContainerRegistry --query registrationState -o tsv
az provider show --namespace Microsoft.App --query registrationState -o tsv
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
```

Resultado esperado:

```text
Registered
Registered
Registered
```

---

## Scripts creados para Fase 2

```text
scripts/azure/phase2-deploy.ps1
scripts/azure/phase2-validate.ps1
scripts/azure/phase2-cleanup.ps1
```

### `phase2-deploy.ps1`

Automatiza:

- validación de herramientas locales;
- validación de Azure CLI;
- registro de providers;
- creación del Resource Group;
- creación del ACR;
- Docker build;
- Docker push;
- creación del Container Apps Environment;
- creación de la Container App;
- obtención de URL pública;
- validación de `/health` y `/ready`;
- generación de outputs.

### `phase2-validate.ps1`

Valida:

- URL pública;
- `/health`;
- `/ready`;
- estado de Container App;
- revisiones;
- logs básicos.

### `phase2-cleanup.ps1`

Borra el Resource Group completo para evitar costes.

---

## Archivos relevantes de Fase 2

```text
backend/.dockerignore
scripts/azure/phase2-deploy.ps1
scripts/azure/phase2-validate.ps1
scripts/azure/phase2-cleanup.ps1
docs/azure-phase-2-container-apps.md
frontend/.env.example
frontend/.env.azure.example
```

Cuando el despliegue termine correctamente, también debe generarse:

```text
outputs/azure-phase2-deployment.json
```

Este archivo no debe subirse al repositorio.

---

## Configuración de región

La región inicial fue:

```powershell
$LOCATION = "westeurope"
```

Después del error de capacidad se cambió a:

```powershell
$LOCATION = "swedencentral"
```

---

## Comandos útiles de Fase 2

### Comprobar que el Resource Group anterior se ha eliminado

```powershell
az group exists --name rg-ai-doc-intel-dev
```

Resultado bueno:

```text
false
```

Si devuelve `true`, comprobar estado:

```powershell
az group show --name rg-ai-doc-intel-dev --query "{name:name, state:properties.provisioningState, location:location}" --output table
```

Si aparece `Deleting`, Azure todavía está borrando el grupo.

### Comprobar providers

```powershell
az provider show --namespace Microsoft.ContainerRegistry --query registrationState -o tsv
az provider show --namespace Microsoft.App --query registrationState -o tsv
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
```

### Ejecutar deploy

```powershell
.\scripts\azure\phase2-deploy.ps1
```

### Validar deploy

```powershell
.\scripts\azure\phase2-validate.ps1
```

### Limpiar recursos

```powershell
.\scripts\azure\phase2-cleanup.ps1
```

---

## Criterios de finalización de Fase 2

La Fase 2 se considerará completada cuando se cumpla:

```text
[ ] Resource Group creado correctamente
[ ] ACR Basic creado correctamente
[ ] Imagen Docker subida al ACR
[ ] Container Apps Environment creado correctamente
[ ] Container App creada correctamente
[ ] Ingress externo activo
[ ] Puerto 8000 configurado
[ ] minReplicas = 0
[ ] maxReplicas = 1
[ ] URL pública generada
[ ] /health público responde OK
[ ] /ready público responde OK
[ ] outputs/azure-phase2-deployment.json generado
[ ] Script de validación funcionando
[ ] Script de limpieza disponible
```

---

## Limitaciones de Fase 2

En esta fase la app desplegada en Azure todavía usa almacenamiento local efímero dentro del contenedor.

Esto significa:

- `/health` y `/ready` sirven para validar el despliegue;
- la API puede ejecutarse;
- pero los documentos y SQLite no son persistentes en producción;
- si el contenedor se reinicia o escala a cero, los datos pueden perderse.

La persistencia real se añadirá en fases posteriores:

```text
Fase 3 -> Azure Blob Storage
Fase 4 -> Azure SQL
```

---

## Explicación técnica de Fase 2

En esta fase se lleva una API FastAPI dockerizada desde local hasta Azure.

Primero se construye una imagen Docker del backend. Esa imagen contiene la aplicación, sus dependencias y el comando de arranque de Uvicorn.

Después, la imagen se sube a Azure Container Registry, que funciona como un almacén privado de imágenes Docker.

Finalmente, Azure Container Apps descarga esa imagen desde ACR y la ejecuta como una aplicación gestionada, exponiendo el puerto interno 8000 mediante una URL pública.

Ejemplo conceptual:

```text
FastAPI
  ↓
Dockerfile
  ↓
docker build
  ↓
docker push a ACR
  ↓
Azure Container Apps
  ↓
https://.../health
```

---

## Frase de entrevista

> En la Fase 2 desplegué el backend FastAPI dockerizado en Azure Container Apps. Primero construí la imagen Docker localmente, la subí a Azure Container Registry y después preparé una Container App con ingress externo, target port 8000 y escalado controlado con minReplicas en 0 y maxReplicas en 1. También preparé scripts de despliegue, validación y limpieza para que el proceso fuera reproducible y controlado en costes. Durante el despliegue gestioné problemas reales de Azure, como el registro de resource providers y una limitación de capacidad en West Europe, que resolví cambiando la región a Sweden Central.
# FASE3 - Azure Blob Storage

## Estado

Amarillo: preparada para desplegar y validar.

La Fase 3 sustituye el almacenamiento local de PDFs por Azure Blob Storage cuando el backend se ejecuta con:

```env
STORAGE_MODE=azure_blob
AZURE_STORAGE_ACCOUNT_NAME=<storage-account-name>
AZURE_STORAGE_CONTAINER_NAME=documents
```

En local sigue funcionando:

```env
STORAGE_MODE=local
LOCAL_STORAGE_PATH=./data/documents
```

## Servicios usados

- Azure Storage Account
- Blob Container `documents`
- Azure Container Apps
- Managed Identity
- Rol `Storage Blob Data Contributor`

## Flujo

```text
Usuario sube PDF
  -> FastAPI en Azure Container Apps
  -> Azure Blob Storage
  -> analisis mock lee bytes desde Blob
```

SQLite sigue siendo efimero dentro del contenedor hasta Fase 4. En esta fase se persisten PDFs, no la base de datos.

## Scripts

```powershell
.\scripts\azure\phase3-storage-deploy.ps1
.\scripts\azure\phase3-storage-validate.ps1
```

## Validacion esperada

- `/health` responde en Azure.
- `/ready` responde en Azure.
- Se puede subir un PDF.
- El PDF aparece en el container `documents`.
- Se puede analizar el documento leyendo bytes desde Blob Storage.
- `pytest`, `ruff` y `pnpm build` siguen pasando.

# FASE4 - Azure SQL Database

## Estado

Amarillo: preparada para desplegar y validar.

La Fase 4 sustituye SQLite efimero por Azure SQL Database cuando la app corre con:

```env
DATABASE_MODE=azure_sql
AZURE_SQL_SERVER=<server>.database.windows.net
AZURE_SQL_DATABASE=aidocinteldb
AZURE_SQL_USERNAME=aidocadmin
AZURE_SQL_PASSWORD=secretref:sql-password
```

La app en Azure queda con:

```text
PDFs -> Azure Blob Storage
Metadatos, analisis y metricas -> Azure SQL Database
Backend -> Azure Container Apps
```

## Scripts

```powershell
.\scripts\azure\phase4-sql-deploy.ps1
.\scripts\azure\phase4-sql-validate.ps1
```

## Limitacion

Fase 4 usa SQL authentication temporal como paso intermedio. En Fase 6 se movera a Key Vault y Managed Identity.

Azure SQL puede generar coste aunque no haya trafico. Para limpiar todo:

```powershell
.\scripts\azure\phase2-cleanup.ps1
```

# FASE5 - Azure OpenAI

## Estado

Amarillo: preparada para desplegar y validar.

La Fase 5 sustituye el analisis mock por analisis real con Azure OpenAI cuando la app corre con:

```env
AI_ANALYSIS_PROVIDER=azure_openai
AZURE_OPENAI_ENDPOINT=https://<recurso>.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4o
AZURE_OPENAI_AUTH_MODE=managed_identity
```

En local se mantiene:

```env
AI_ANALYSIS_PROVIDER=mock
```

La app en Azure queda con:

```text
PDFs -> Azure Blob Storage
Texto extraido -> Azure OpenAI
Resultado estructurado y tokens -> Azure SQL Database
Backend -> Azure Container Apps
```

## Scripts

```powershell
.\scripts\azure\phase5-openai-deploy.ps1
.\scripts\azure\phase5-openai-validate.ps1
```

## Seguridad

No se usan API keys ni se guardan secretos en el repositorio. La Container App usa Managed Identity con el rol `Cognitive Services OpenAI User` sobre Azure OpenAI.

## Validacion esperada

- `/health` responde en Azure.
- `/ready` responde en Azure.
- Se puede subir un PDF a Blob Storage.
- El analisis ya no devuelve `Resumen simulado...`.
- `usage.total_tokens` es mayor que 0.
- Analytics muestra tokens acumulados.
- Los resultados se guardan en Azure SQL.

# FASE6 - Azure Key Vault

## Estado

Amarillo: preparada para desplegar y validar.

La Fase 6 centraliza el secreto `sql-password` en Azure Key Vault. Azure Container Apps mantiene:

```env
AZURE_SQL_PASSWORD=secretref:sql-password
```

pero el secret `sql-password` ya no almacena directamente el valor en Container Apps, sino una referencia a Key Vault consumida mediante Managed Identity.

## Servicios usados

- Azure Key Vault
- Azure Container Apps
- Managed Identity
- Azure RBAC
- Azure SQL Database

## Flujo

```text
Container App -> Managed Identity -> Key Vault -> sql-password -> Azure SQL
```

## Scripts

```powershell
.\scripts\azure\phase6-keyvault-deploy.ps1
.\scripts\azure\phase6-keyvault-validate.ps1
```

## Seguridad

No se guardan passwords ni connection strings en el repositorio ni en outputs. La password de Azure SQL se rota durante el deploy y se guarda como secret en Key Vault.

## Validacion esperada

- Key Vault con RBAC activo.
- Secret `sql-password` existe en Key Vault.
- Managed Identity de Container Apps tiene `Key Vault Secrets User`.
- `/health` responde en Azure.
- `/ready` responde despues de rotar la password.
- Upload, analyze y analytics siguen funcionando.

# FASE7 - Application Insights

## Estado

Amarillo: preparada para desplegar y validar.

La Fase 7 anade observabilidad real al backend FastAPI desplegado en Azure Container Apps mediante Azure Application Insights y Azure Monitor.

## Servicios usados

- Azure Application Insights
- Azure Monitor
- Azure Container Apps
- OpenTelemetry

## Que se observa

- requests y errores;
- latencia;
- eventos de upload;
- eventos de analisis documental;
- llamadas a Azure OpenAI;
- tokens usados;
- analytics.

## Scripts

```powershell
.\scripts\azure\phase7-appinsights-deploy.ps1
.\scripts\azure\phase7-appinsights-validate.ps1
```

## Seguridad

No se loggea texto completo de documentos, prompts completos ni secretos. La connection string de Application Insights se configura como secret de Container Apps y no se guarda en outputs.

## Validacion esperada

- Application Insights creado.
- `ENABLE_APP_INSIGHTS=true` en Azure.
- `/health` responde.
- `/ready` responde.
- Upload, analyze y analytics siguen funcionando.
- Trazas/eventos visibles en Application Insights.

# FASE8 - Bicep IaC

## Estado

Amarillo: infraestructura modelada como codigo, lista para build, validate y what-if antes de cualquier deploy real.

La Fase 8 convierte la infraestructura Azure actual en Bicep para que el entorno sea reproducible y revisable.

## Servicios modelados

- Azure Container Registry.
- Log Analytics.
- Application Insights.
- Azure Storage y Blob Container `documents`.
- Azure SQL Database.
- Azure Key Vault.
- Azure OpenAI.
- Azure Container Apps Environment.
- Azure Container App.
- Role assignments para Managed Identity.

## Archivos principales

```text
infra/main.bicep
infra/modules/
infra/params/dev.bicepparam
docs/azure-phase-8-bicep-iac.md
```

## Scripts

```powershell
.\scripts\azure\phase8-bicep-build.ps1
.\scripts\azure\phase8-bicep-validate.ps1
.\scripts\azure\phase8-bicep-whatif.ps1
.\scripts\azure\phase8-bicep-deploy.ps1
```

## Seguridad

No se guardan passwords, connection strings ni valores de secrets en el repositorio.

Azure SQL se referencia como recurso existente para evitar rotaciones accidentales de password desde Bicep.

El deploy real pide confirmacion explicita escribiendo `DEPLOY`.

## Validacion esperada

- `az bicep build` compila `infra/main.bicep`.
- `az deployment group validate` funciona sin gestionar passwords SQL desde Bicep.
- `az deployment group what-if` permite revisar cambios antes de desplegar.
- `pytest`, `ruff` y `pnpm build` siguen pasando.

# FASE9 - GitHub Actions CI/CD

## Estado

Amarillo: workflows y scripts preparados para CI/CD con OIDC, sin secretos de cliente.

La Fase 9 añade automatizacion para validar el proyecto y desplegar una nueva imagen del backend en Azure Container Apps.

## Workflows

```text
.github/workflows/ci.yml
.github/workflows/deploy-containerapp.yml
.github/workflows/bicep-check.yml
```

## Que valida CI

- Backend: `pytest`.
- Backend: `ruff check`.
- Frontend: `pnpm build`.
- Docker: build de la imagen del backend.
- Bicep: build de `infra/main.bicep`.

## Deploy

El workflow de deploy usa OIDC con `azure/login@v2`.

No usa:

- client secrets;
- publish profiles;
- `AZURE_CREDENTIALS` con password.

El pipeline solo actualiza la imagen:

```text
az containerapp update --image
```

No modifica secrets ni variables de entorno de Container Apps y no ejecuta analisis automatico para evitar consumo de Azure OpenAI.

## Scripts

```powershell
.\scripts\azure\phase9-oidc-setup.ps1 -GitHubOwner <owner> -GitHubRepo <repo>
.\scripts\azure\phase9-oidc-validate.ps1 -GitHubOwner <owner> -GitHubRepo <repo>
```

Variables esperadas en GitHub:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

Son identificadores, no passwords.
