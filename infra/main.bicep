targetScope = 'resourceGroup'

param location string = resourceGroup().location
param environmentName string = 'dev'

param acrName string
param acrLoginServer string
param logAnalyticsName string
param logAnalyticsCustomerId string
param appInsightsWorkspaceResourceId string
param appInsightsName string
param storageAccountName string
param storageContainerName string = 'documents'
param sqlServerName string
param sqlServerFqdn string
param sqlDatabaseName string
param keyVaultName string
param openAiAccountName string
param openAiEndpoint string
param openAiDeploymentName string = 'gpt-4o'
param openAiModelName string = 'gpt-4o'
param openAiModelVersion string = '2024-11-20'
param searchServiceName string
param searchSkuName string = 'free'
param searchIndexName string = 'document-chunks'
param ragEnabled bool = false
param embeddingDeploymentName string = 'text-embedding-3-small'
param embeddingModelName string = 'text-embedding-3-small'
param embeddingModelVersion string = '1'
param embeddingSkuName string = 'GlobalStandard'
param containerAppsEnvironmentName string
param containerAppName string
param containerImage string
param userAssignedIdentityName string
param userAssignedIdentityClientId string

param sqlAdminUser string = 'aidocadmin'
param appPort int = 8000
param minReplicas int = 0
param maxReplicas int = 1

module acr 'modules/acr.bicep' = {
  name: 'acr-${environmentName}'
  params: {
    name: acrName
  }
}

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-${environmentName}'
  params: {
    name: logAnalyticsName
  }
}

module appInsights 'modules/app-insights.bicep' = {
  name: 'appi-${environmentName}'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: appInsightsWorkspaceResourceId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-${environmentName}'
  params: {
    name: storageAccountName
    location: location
    containerName: storageContainerName
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sql-${environmentName}'
  params: {
    serverName: sqlServerName
    databaseName: sqlDatabaseName
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'kv-${environmentName}'
  params: {
    name: keyVaultName
    location: location
  }
}

module openAi 'modules/openai.bicep' = {
  name: 'openai-${environmentName}'
  params: {
    name: openAiAccountName
    location: location
    deploymentName: openAiDeploymentName
    modelName: openAiModelName
    modelVersion: openAiModelVersion
  }
}

module search 'modules/search.bicep' = {
  name: 'search-${environmentName}'
  params: {
    name: searchServiceName
    location: location
    skuName: searchSkuName
  }
}

module embeddings 'modules/openai-deployment.bicep' = {
  name: 'openai-embeddings-${environmentName}'
  params: {
    accountName: openAiAccountName
    deploymentName: embeddingDeploymentName
    modelName: embeddingModelName
    modelVersion: embeddingModelVersion
    skuName: embeddingSkuName
  }
}

module containerAppsEnv 'modules/container-apps-env.bicep' = {
  name: 'cae-${environmentName}'
  params: {
    name: containerAppsEnvironmentName
    location: location
    workspaceCustomerId: logAnalyticsCustomerId
    workspaceSharedKey: logAnalytics.outputs.primarySharedKey
  }
}

resource userIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

module containerApp 'modules/container-app.bicep' = {
  name: 'aca-${environmentName}'
  params: {
    name: containerAppName
    location: location
    environmentId: containerAppsEnv.outputs.environmentId
    image: containerImage
    targetPort: appPort
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    acrLoginServer: acrLoginServer
    managedIdentityResourceId: userIdentity.id
    azureClientId: userAssignedIdentityClientId
    sqlServerFqdn: sqlServerFqdn
    sqlDatabaseName: sqlDatabaseName
    sqlAdminUser: sqlAdminUser
    storageAccountName: storage.outputs.storageAccountName
    storageContainerName: storage.outputs.containerName
    openAiEndpoint: openAiEndpoint
    openAiDeploymentName: openAi.outputs.deploymentName
    keyVaultSqlPasswordSecretUri: '${keyVault.outputs.vaultUri}secrets/sql-password'
    appInsightsConnectionString: appInsights.outputs.connectionString
    ragEnabled: ragEnabled
    searchEndpoint: search.outputs.searchEndpoint
    searchServiceName: search.outputs.searchServiceName
    searchIndexName: searchIndexName
    embeddingDeploymentName: embeddings.outputs.deploymentName
  }
}

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'rbac-${environmentName}'
  params: {
    principalId: userIdentity.properties.principalId
    acrName: acrName
    storageAccountName: storageAccountName
    openAiAccountName: openAiAccountName
    keyVaultName: keyVaultName
    searchServiceName: searchServiceName
  }
}

output containerAppUrl string = containerApp.outputs.url
output storageAccountName string = storage.outputs.storageAccountName
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
output keyVaultName string = keyVault.outputs.keyVaultName
output appInsightsName string = appInsights.outputs.appInsightsName
output openAiEndpoint string = openAi.outputs.openAiEndpoint
output searchEndpoint string = search.outputs.searchEndpoint
