param name string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: name
}

output workspaceId string = workspace.id
output customerId string = workspace.properties.customerId
@secure()
output primarySharedKey string = workspace.listKeys().primarySharedKey
