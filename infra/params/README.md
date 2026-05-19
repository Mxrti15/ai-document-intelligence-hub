# Parámetros Bicep

`dev.bicepparam` contiene nombres de recursos y configuración no secreta del entorno de desarrollo.

No añadas passwords, connection strings, claves de API ni valores de secretos a esta carpeta.

El SQL Server existente se referencia sin password para evitar guardar secretos o provocar rotaciones desde IaC.
