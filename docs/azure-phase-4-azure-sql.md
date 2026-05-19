# Fase 4 - Azure SQL Database

## Objetivo

Sustituir SQLite efimero por Azure SQL Database en Azure cuando `DATABASE_MODE=azure_sql`, manteniendo SQLite local con `DATABASE_MODE=sqlite`.

## Servicios usados

- Azure SQL Server
- Azure SQL Database
- Azure Container Apps secrets
- Azure Container Apps env vars
- Azure Blob Storage de Fase 3

## Flujo

PDF -> Blob Storage

Metadatos, analisis y metricas -> Azure SQL

Backend -> Azure Container Apps

## Autenticacion

Fase 4 usa SQL authentication temporal guardada como secret en Container Apps:

- secret: `sql-password`
- env var: `AZURE_SQL_PASSWORD=secretref:sql-password`

En fases posteriores se mejorara con Key Vault y Managed Identity.

## Coste

Azure SQL puede generar coste aunque no haya trafico. Borra el Resource Group completo si no se usa.

## Validacion

- `/ready` conecta a DB;
- upload PDF crea fila en Azure SQL;
- analyze guarda analisis;
- analytics lee datos desde Azure SQL;
- Blob Storage sigue almacenando PDFs.
