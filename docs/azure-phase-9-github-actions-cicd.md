# Fase 9 - GitHub Actions CI/CD

La Fase 9 añade CI/CD con GitHub Actions para validar el proyecto, construir la imagen Docker del backend, subirla a Azure Container Registry y actualizar Azure Container Apps solo con una nueva imagen.

## Alcance

Incluye:

- CI de backend con `pytest` y `ruff`.
- Build del frontend con `pnpm build`.
- Docker build del backend.
- Deploy a Azure Container Apps mediante OIDC.
- Bicep build check.

No incluye API Management, RAG ni Azure AI Search.

## Workflows

```text
.github/workflows/ci.yml
.github/workflows/deploy-containerapp.yml
.github/workflows/bicep-check.yml
```

`deploy-containerapp.yml` no modifica secrets ni variables de entorno de Container Apps. Solo ejecuta:

```text
docker build
docker push
az containerapp update --image
```

No ejecuta análisis documental automático para evitar consumo de Azure OpenAI.

## OIDC

No se usan client secrets, publish profiles ni `AZURE_CREDENTIALS`.

El login usa:

```yaml
permissions:
  id-token: write

azure/login@v2
```

Variables esperadas en GitHub:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

Pueden configurarse como repository variables o environment variables del entorno `dev`. No son passwords.

## Scripts Azure

```powershell
.\scripts\azure\phase9-oidc-setup.ps1 -GitHubOwner <owner> -GitHubRepo <repo>
.\scripts\azure\phase9-oidc-validate.ps1 -GitHubOwner <owner> -GitHubRepo <repo>
```

El setup:

- crea o reutiliza una App Registration;
- crea o reutiliza un Service Principal;
- crea una federated credential para `repo:<owner>/<repo>:ref:refs/heads/main`;
- asigna `AcrPush` sobre ACR;
- asigna `Azure Container Apps Contributor` sobre la Container App;
- no crea client secrets.

## Seguridad

- El pipeline no recibe passwords.
- El pipeline no imprime ni modifica connection strings.
- El pipeline no toca `sql-password`, Key Vault, Azure SQL, Blob Storage ni Azure OpenAI.
- El despliegue se limita a la imagen del backend.
