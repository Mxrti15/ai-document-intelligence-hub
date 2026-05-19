param(
    [string]$SubscriptionId = "7d0e447c-06f8-4533-9c87-65540c5c1a0a",
    [string]$ResourceGroupName = "rg-ai-doc-intel-dev",
    [string]$AcrName = "acidocintel30929",
    [string]$ContainerAppName = "aca-ai-doc-intel-api-dev",
    [Parameter(Mandatory = $true)][string]$GitHubOwner,
    [Parameter(Mandatory = $true)][string]$GitHubRepo,
    [string]$Branch = "main",
    [string]$AppDisplayName = "github-ai-doc-intel-cicd"
)

$ErrorActionPreference = "Stop"

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
        -o tsv `
        --only-show-errors

    if ([int]$count -lt 1) {
        throw "Missing role assignment '$Role' on scope '$Scope'."
    }

    Write-Host "OK: $Role on $Scope"
}

Write-Step "Reading Azure context"
az account set --subscription $SubscriptionId --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select subscription $SubscriptionId."
}

$tenantId = Invoke-NativeOutput az account show --query tenantId -o tsv --only-show-errors
$subscriptionId = Invoke-NativeOutput az account show --query id -o tsv --only-show-errors

Write-Step "Validating app registration and service principal"
$appId = Invoke-NativeOutput az ad app list `
    --display-name $AppDisplayName `
    --query "[0].appId" `
    -o tsv `
    --only-show-errors

if ([string]::IsNullOrWhiteSpace($appId)) {
    throw "App registration not found: $AppDisplayName"
}

$objectId = Invoke-NativeOutput az ad app show --id $appId --query id -o tsv --only-show-errors
$servicePrincipalObjectId = Invoke-NativeOutput az ad sp list `
    --filter "appId eq '$appId'" `
    --query "[0].id" `
    -o tsv `
    --only-show-errors

if ([string]::IsNullOrWhiteSpace($servicePrincipalObjectId)) {
    throw "Service principal not found for appId $appId"
}

Write-Step "Validating federated credential"
$subject = "repo:${GitHubOwner}/${GitHubRepo}:ref:refs/heads/${Branch}"
$credentialCount = Invoke-NativeOutput az ad app federated-credential list `
    --id $objectId `
    --query "[?subject=='$subject' && issuer=='https://token.actions.githubusercontent.com'] | length(@)" `
    -o tsv `
    --only-show-errors

if ([int]$credentialCount -lt 1) {
    throw "Federated credential not found for subject '$subject'."
}

Write-Host "OK: federated credential subject $subject"

Write-Step "Validating Azure role assignments"
$acrId = Invoke-NativeOutput az acr show --name $AcrName --resource-group $ResourceGroupName --query id -o tsv --only-show-errors
$containerAppId = Invoke-NativeOutput az containerapp show --name $ContainerAppName --resource-group $ResourceGroupName --query id -o tsv --only-show-errors

Assert-RoleAssignment -PrincipalId $servicePrincipalObjectId -Role "AcrPush" -Scope $acrId
Assert-RoleAssignment -PrincipalId $servicePrincipalObjectId -Role "Azure Container Apps Contributor" -Scope $containerAppId

Write-Host ""
Write-Host "OIDC validation completed."
Write-Host "GitHub variables expected:"
Write-Host "AZURE_CLIENT_ID=$appId"
Write-Host "AZURE_TENANT_ID=$tenantId"
Write-Host "AZURE_SUBSCRIPTION_ID=$subscriptionId"
