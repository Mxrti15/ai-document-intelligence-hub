param name string

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: name
}

output acrId string = acr.id
output loginServer string = acr.properties.loginServer
