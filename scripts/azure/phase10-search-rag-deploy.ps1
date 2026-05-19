param(
    [switch]$AllowPaidSku,
    [string]$SearchSku = "free",
    [string]$SearchServiceName = ""
)

$ErrorActionPreference = "Stop"

$script:Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$script:OutputsDir = Join-Path $script:Root "outputs"
$script:OutputFile = Join-Path $script:OutputsDir "azure-phase10-search-rag.json"

$script:RESOURCE_GROUP = "rg-ai-doc-intel-dev"
$script:LOCATION = "swedencentral"
$script:ACR_NAME = "acidocintel30929"
$script:ACR_LOGIN_SERVER = "acidocintel30929.azurecr.io"
$script:CONTAINER_APP_NAME = "aca-ai-doc-intel-api-dev"
$script:OPENAI_ACCOUNT_NAME = "aidocopenai78973"
$script:IDENTITY_NAME = "id-ai-doc-intel-aca-pull-dev"
$script:IMAGE_NAME = "ai-doc-intel-backend"
$script:IMAGE_TAG = "phase10"
$script:SEARCH_INDEX_NAME = "document-chunks"
$script:EMBEDDING_DEPLOYMENT_NAME = "text-embedding-3-small"
$script:EMBEDDING_MODEL_NAME = "text-embedding-3-small"
$script:EMBEDDING_MODEL_VERSION = "1"
$script:EMBEDDING_SKU_NAME = "GlobalStandard"
$script:EMBEDDING_DIMENSIONS = 1536

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Invoke-NativeOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList
    )

    $output = & $FilePath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')`n$output"
    }
    return ($output | Out-String).Trim()
}

function Ensure-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$Role,
        [string]$Scope
    )

    $existing = Invoke-NativeOutput az role assignment list `
        --assignee-object-id $PrincipalId `
        --scope $Scope `
        --query "[?roleDefinitionName=='$Role'] | length(@)" `
        --output tsv `
        --only-show-errors

    if ([int]$existing -gt 0) {
        Write-Host "$Role already assigned on $Scope"
        return
    }

    Invoke-Native az role assignment create `
        --assignee-object-id $PrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role $Role `
        --scope $Scope `
        --only-show-errors
}

Set-Location $script:Root
New-Item -ItemType Directory -Force -Path $script:OutputsDir | Out-Null

if ($SearchSku -ne "free" -and -not $AllowPaidSku) {
    throw "SearchSku '$SearchSku' may create cost. Re-run with -AllowPaidSku to confirm explicitly."
}

if ([string]::IsNullOrWhiteSpace($SearchServiceName)) {
    $script:SEARCH_SERVICE_NAME = "aidocsearch$(Get-Random -Minimum 10000 -Maximum 99999)"
}
else {
    $script:SEARCH_SERVICE_NAME = $SearchServiceName
}

Write-Step "Registering Microsoft.Search provider"
Invoke-Native az provider register --namespace Microsoft.Search --wait

Write-Step "Creating Azure AI Search service"
$existingSearch = Invoke-NativeOutput az search service list `
    --resource-group $script:RESOURCE_GROUP `
    --query "[?name=='$script:SEARCH_SERVICE_NAME'] | length(@)" `
    --output tsv `
    --only-show-errors

if ([int]$existingSearch -gt 0) {
    Write-Host "Search service already exists: $script:SEARCH_SERVICE_NAME"
}
else {
    try {
        Invoke-Native az search service create `
            --name $script:SEARCH_SERVICE_NAME `
            --resource-group $script:RESOURCE_GROUP `
            --location $script:LOCATION `
            --sku $SearchSku `
            --only-show-errors
    }
    catch {
        if ($SearchSku -eq "free") {
            throw "Azure AI Search SKU free could not be created. No paid SKU was attempted. Details: $_"
        }
        throw
    }
}

$searchId = Invoke-NativeOutput az search service show `
    --name $script:SEARCH_SERVICE_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query id `
    --output tsv `
    --only-show-errors

Write-Step "Creating Azure OpenAI embedding deployment"
$existingEmbeddingDeployment = Invoke-NativeOutput az cognitiveservices account deployment list `
    --name $script:OPENAI_ACCOUNT_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query "[?name=='$script:EMBEDDING_DEPLOYMENT_NAME'] | length(@)" `
    --output tsv `
    --only-show-errors

if ([int]$existingEmbeddingDeployment -gt 0) {
    Write-Host "Embedding deployment already exists: $script:EMBEDDING_DEPLOYMENT_NAME"
}
else {
    try {
        Invoke-Native az cognitiveservices account deployment create `
            --name $script:OPENAI_ACCOUNT_NAME `
            --resource-group $script:RESOURCE_GROUP `
            --deployment-name $script:EMBEDDING_DEPLOYMENT_NAME `
            --model-name $script:EMBEDDING_MODEL_NAME `
            --model-version $script:EMBEDDING_MODEL_VERSION `
            --model-format OpenAI `
            --sku-name $script:EMBEDDING_SKU_NAME `
            --sku-capacity 1 `
            --only-show-errors
    }
    catch {
        throw "Embedding deployment could not be created. Check Azure OpenAI quota/model availability in $script:LOCATION. Details: $_"
    }
}

Write-Step "Granting Search RBAC to Container App managed identity"
$identityPrincipalId = Invoke-NativeOutput az identity show `
    --name $script:IDENTITY_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query principalId `
    --output tsv `
    --only-show-errors

Ensure-RoleAssignment -PrincipalId $identityPrincipalId -Role "Search Index Data Contributor" -Scope $searchId
Ensure-RoleAssignment -PrincipalId $identityPrincipalId -Role "Search Service Contributor" -Scope $searchId

Write-Step "Building and pushing backend image"
$fullImageName = "{0}/{1}:{2}" -f $script:ACR_LOGIN_SERVER, $script:IMAGE_NAME, $script:IMAGE_TAG
Invoke-Native az acr login --name $script:ACR_NAME
Invoke-Native docker build -t $fullImageName ./backend
Invoke-Native docker push $fullImageName

Write-Step "Updating Container App image"
Invoke-Native az containerapp update `
    --name $script:CONTAINER_APP_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --image $fullImageName `
    --only-show-errors

Write-Step "Configuring RAG environment variables"
Invoke-Native az containerapp update `
    --name $script:CONTAINER_APP_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --set-env-vars `
        RAG_ENABLED=true `
        AZURE_SEARCH_ENDPOINT="https://$script:SEARCH_SERVICE_NAME.search.windows.net" `
        AZURE_SEARCH_SERVICE_NAME=$script:SEARCH_SERVICE_NAME `
        AZURE_SEARCH_INDEX_NAME=$script:SEARCH_INDEX_NAME `
        AZURE_SEARCH_AUTH_MODE=managed_identity `
        AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME=$script:EMBEDDING_DEPLOYMENT_NAME `
        AZURE_OPENAI_EMBEDDING_DIMENSIONS=$script:EMBEDDING_DIMENSIONS `
        RAG_CHUNK_SIZE=1200 `
        RAG_CHUNK_OVERLAP=200 `
        RAG_MAX_CHUNKS_PER_DOCUMENT=80 `
        RAG_TOP_K=5 `
        RAG_MAX_CONTEXT_CHARS=10000 `
        RAG_MAX_OUTPUT_TOKENS=800 `
    --only-show-errors

Write-Step "Validating health endpoints"
$fqdn = Invoke-NativeOutput az containerapp show `
    --name $script:CONTAINER_APP_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query properties.configuration.ingress.fqdn `
    --output tsv `
    --only-show-errors

$baseUrl = "https://$fqdn"
Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 30 | ConvertTo-Json -Depth 8
Invoke-RestMethod -Uri "$baseUrl/ready" -TimeoutSec 30 | ConvertTo-Json -Depth 8

Write-Step "Writing safe deployment output"
$output = [ordered]@{
    resourceGroup = $script:RESOURCE_GROUP
    location = $script:LOCATION
    searchServiceName = $script:SEARCH_SERVICE_NAME
    searchEndpoint = "https://$script:SEARCH_SERVICE_NAME.search.windows.net"
    searchIndexName = $script:SEARCH_INDEX_NAME
    searchSku = $SearchSku
    embeddingDeploymentName = $script:EMBEDDING_DEPLOYMENT_NAME
    image = $fullImageName
    containerAppName = $script:CONTAINER_APP_NAME
    containerAppUrl = $baseUrl
}
$output | ConvertTo-Json -Depth 8 | Set-Content -Path $script:OutputFile -Encoding utf8
Write-Host "Output written to $script:OutputFile"
