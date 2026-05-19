# Fase 6 - Azure Key Vault

## Objetivo

Centralizar el secreto `sql-password` en Azure Key Vault y hacer que Azure Container Apps lo consuma mediante Managed Identity.

## Servicios usados

- Azure Key Vault
- Azure Container Apps
- Managed Identity
- Azure RBAC
- Azure SQL Database

## Que secreto se mueve

- `sql-password`

## Flujo

```text
Container App -> Managed Identity -> Key Vault -> sql-password -> Azure SQL
```

## Seguridad

El valor del secreto no esta en Git ni en outputs.

Container Apps usa una referencia a Key Vault:

```text
sql-password=keyvaultref:<secret-id>,identityref:<managed-identity-resource-id>
```

La variable de entorno de la aplicacion se mantiene como:

```env
AZURE_SQL_PASSWORD=secretref:sql-password
```

## Limitacion

Azure SQL sigue usando SQL authentication. Mas adelante se puede migrar a autenticacion passwordless con Microsoft Entra ID.

## Validacion

- `/health` OK.
- `/ready` OK despues de rotar la password.
- Upload PDF OK.
- Analyze OK.
- Analytics OK.
