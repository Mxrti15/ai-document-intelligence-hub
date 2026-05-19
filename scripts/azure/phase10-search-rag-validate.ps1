param(
    [string]$OutputFile = "outputs\azure-phase10-search-rag.json"
)

$ErrorActionPreference = "Stop"

$script:Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$script:RESOURCE_GROUP = "rg-ai-doc-intel-dev"
$script:CONTAINER_APP_NAME = "aca-ai-doc-intel-api-dev"
$script:OPENAI_ACCOUNT_NAME = "aidocopenai78973"
$script:IDENTITY_NAME = "id-ai-doc-intel-aca-pull-dev"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
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

function Assert-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$Role,
        [string]$Scope
    )

    $count = Invoke-NativeOutput az role assignment list `
        --assignee-object-id $PrincipalId `
        --scope $Scope `
        --query "[?roleDefinitionName=='$Role'] | length(@)" `
        --output tsv `
        --only-show-errors

    if ([int]$count -lt 1) {
        throw "Missing role assignment '$Role' on $Scope"
    }
    Write-Host "OK: $Role"
}

Set-Location $script:Root

$resolvedOutput = Join-Path $script:Root $OutputFile
if (-not (Test-Path $resolvedOutput)) {
    throw "Output file not found: $resolvedOutput. Run phase10-search-rag-deploy.ps1 first."
}

$phase10 = Get-Content $resolvedOutput | ConvertFrom-Json

Write-Step "Validating Azure AI Search service"
$searchId = Invoke-NativeOutput az search service show `
    --name $phase10.searchServiceName `
    --resource-group $script:RESOURCE_GROUP `
    --query id `
    --output tsv `
    --only-show-errors
Write-Host "OK: $($phase10.searchServiceName)"

Write-Step "Validating Container App RAG env vars"
$envVars = Invoke-NativeOutput az containerapp show `
    --name $script:CONTAINER_APP_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query "properties.template.containers[0].env[?starts_with(name, 'RAG_') || starts_with(name, 'AZURE_SEARCH_') || name=='AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME']" `
    --output json `
    --only-show-errors
$envVars | Write-Host

Write-Step "Validating Managed Identity Search roles"
$identityPrincipalId = Invoke-NativeOutput az identity show `
    --name $script:IDENTITY_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query principalId `
    --output tsv `
    --only-show-errors
Assert-RoleAssignment -PrincipalId $identityPrincipalId -Role "Search Index Data Contributor" -Scope $searchId
Assert-RoleAssignment -PrincipalId $identityPrincipalId -Role "Search Service Contributor" -Scope $searchId

Write-Step "Validating embedding deployment"
Invoke-NativeOutput az cognitiveservices account deployment show `
    --name $script:OPENAI_ACCOUNT_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --deployment-name $phase10.embeddingDeploymentName `
    --query name `
    --output tsv `
    --only-show-errors | Write-Host

Write-Step "Validating public endpoints"
$fqdn = Invoke-NativeOutput az containerapp show `
    --name $script:CONTAINER_APP_NAME `
    --resource-group $script:RESOURCE_GROUP `
    --query properties.configuration.ingress.fqdn `
    --output tsv `
    --only-show-errors
$baseUrl = "https://$fqdn"
Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 30 | ConvertTo-Json -Depth 8
Invoke-RestMethod -Uri "$baseUrl/ready" -TimeoutSec 30 | ConvertTo-Json -Depth 8
Invoke-RestMethod -Uri "$baseUrl/docs" -TimeoutSec 30 | Out-Null
Write-Host "OK: Swagger docs available at $baseUrl/docs"

Write-Host ""
Write-Host "Manual RAG validation steps:"
Write-Host "1. Upload a small PDF."
Write-Host "2. POST /documents/{document_id}/index."
Write-Host "3. POST /documents/{document_id}/ask."
Write-Host "No RAG question was executed automatically."
