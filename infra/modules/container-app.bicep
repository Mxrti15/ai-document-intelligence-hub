param name string
param location string
param environmentId string
param image string
param targetPort int = 8000
param minReplicas int = 0
param maxReplicas int = 1
param acrLoginServer string
param managedIdentityResourceId string
param azureClientId string
param sqlServerFqdn string
param sqlDatabaseName string
param sqlAdminUser string
param storageAccountName string
param storageContainerName string
param openAiEndpoint string
param openAiDeploymentName string
param keyVaultSqlPasswordSecretUri string
@secure()
param appInsightsConnectionString string

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: managedIdentityResourceId
        }
      ]
      secrets: [
        {
          name: 'sql-password'
          keyVaultUrl: keyVaultSqlPasswordSecretUri
          identity: managedIdentityResourceId
        }
        {
          name: 'appinsights-connection-string'
          value: appInsightsConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: image
          env: [
            {
              name: 'APP_NAME'
              value: 'AI Document Intelligence Hub'
            }
            {
              name: 'ENVIRONMENT'
              value: 'azure-dev'
            }
            {
              name: 'DATABASE_URL'
              value: 'sqlite:///./data/app.db'
            }
            {
              name: 'STORAGE_MODE'
              value: 'azure_blob'
            }
            {
              name: 'LOCAL_STORAGE_PATH'
              value: './data/documents'
            }
            {
              name: 'MAX_UPLOAD_SIZE_MB'
              value: '10'
            }
            {
              name: 'ALLOWED_EXTENSIONS'
              value: 'pdf'
            }
            {
              name: 'AZURE_STORAGE_ACCOUNT_NAME'
              value: storageAccountName
            }
            {
              name: 'AZURE_STORAGE_CONTAINER_NAME'
              value: storageContainerName
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: azureClientId
            }
            {
              name: 'DATABASE_MODE'
              value: 'azure_sql'
            }
            {
              name: 'AZURE_SQL_SERVER'
              value: sqlServerFqdn
            }
            {
              name: 'AZURE_SQL_DATABASE'
              value: sqlDatabaseName
            }
            {
              name: 'AZURE_SQL_USERNAME'
              value: sqlAdminUser
            }
            {
              name: 'AZURE_SQL_PASSWORD'
              secretRef: 'sql-password'
            }
            {
              name: 'AI_ANALYSIS_PROVIDER'
              value: 'azure_openai'
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAiEndpoint
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
              value: openAiDeploymentName
            }
            {
              name: 'AZURE_OPENAI_API_VERSION'
              value: '2024-10-21'
            }
            {
              name: 'AZURE_OPENAI_AUTH_MODE'
              value: 'managed_identity'
            }
            {
              name: 'AI_MAX_INPUT_CHARS'
              value: '12000'
            }
            {
              name: 'AI_MAX_OUTPUT_TOKENS'
              value: '800'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
            {
              name: 'ENABLE_APP_INSIGHTS'
              value: 'true'
            }
            {
              name: 'LOG_LEVEL'
              value: 'INFO'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output containerAppName string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output url string = 'https://${app.properties.configuration.ingress.fqdn}'
output principalId string = app.identity.principalId
