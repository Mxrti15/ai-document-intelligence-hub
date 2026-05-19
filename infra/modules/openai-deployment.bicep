param accountName string
param deploymentName string
param modelName string
param modelVersion string
param skuName string = 'GlobalStandard'

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: deploymentName
  parent: account
  sku: {
    name: skuName
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.DefaultV2'
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

output deploymentName string = deployment.name
