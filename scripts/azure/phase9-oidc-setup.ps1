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

$script:Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$script:OutputsDir = Join-Path $script:Root "outputs"
$script:OutputFile = Join-Path $script:OutputsDir "github-actions-oidc.json"

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

Write-Step "Reading Azure context"
Invoke-Native az account set --subscription $SubscriptionId
$tenantId = Invoke-NativeOutput az account show --query tenantId --output tsv --only-show-errors
$subscriptionId = Invoke-NativeOutput az account show --query id --output tsv --only-show-errors

Write-Step "Creating or reusing Microsoft Entra application"
$appId = Invoke-NativeOutput az ad app list `
    --display-name $AppDisplayName `
    --query "[0].appId" `
    --output tsv `
    --only-show-errors

if ([string]::IsNullOrWhiteSpace($appId)) {
    $appId = Invoke-NativeOutput az ad app create `
        --display-name $AppDisplayName `
        --query appId `
        --output tsv `
        --only-show-errors
}

$objectId = Invoke-NativeOutput az ad app show --id $appId --query id --output tsv --only-show-errors

Write-Step "Creating or reusing service principal"
$servicePrincipalObjectId = Invoke-NativeOutput az ad sp list `
    --filter "appId eq '$appId'" `
    --query "[0].id" `
    --output tsv `
    --only-show-errors

if ([string]::IsNullOrWhiteSpace($servicePrincipalObjectId)) {
    $servicePrincipalObjectId = Invoke-NativeOutput az ad sp create `
        --id $appId `
        --query id `
        --output tsv `
        --only-show-errors
}

Write-Step "Creating federated credential for GitHub Actions"
$subject = "repo:${GitHubOwner}/${GitHubRepo}:ref:refs/heads/${Branch}"
$credentialName = "github-${GitHubOwner}-${GitHubRepo}-${Branch}".ToLowerInvariant() -replace "[^a-z0-9-]", "-"
$existingCredential = Invoke-NativeOutput az ad app federated-credential list `
    --id $objectId `
    --query "[?name=='$credentialName'] | length(@)" `
    --output tsv `
    --only-show-errors

if ([int]$existingCredential -eq 0) {
    $credentialFile = Join-Path $script:OutputsDir "phase9-federated-credential.json"
    $credential = [ordered]@{
        name = $credentialName
        issuer = "https://token.actions.githubusercontent.com"
        subject = $subject
        description = "GitHub Actions OIDC for ${GitHubOwner}/${GitHubRepo} ${Branch}"
        audiences = @("api://AzureADTokenExchange")
    }
    $credential | ConvertTo-Json -Depth 8 | Set-Content -Path $credentialFile -Encoding utf8
    Invoke-Native az ad app federated-credential create --id $objectId --parameters "@$credentialFile" --only-show-errors
}
else {
    Write-Host "Federated credential already exists: $credentialName"
}

Write-Step "Assigning least-privilege Azure roles"
$acrId = Invoke-NativeOutput az acr show `
    --name $AcrName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv `
    --only-show-errors

$containerAppId = Invoke-NativeOutput az containerapp show `
    --name $ContainerAppName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv `
    --only-show-errors

Ensure-RoleAssignment -PrincipalId $servicePrincipalObjectId -Role "AcrPush" -Scope $acrId
Ensure-RoleAssignment -PrincipalId $servicePrincipalObjectId -Role "Container Apps Contributor" -Scope $containerAppId

Write-Step "Writing non-secret GitHub Actions OIDC output"
$output = [ordered]@{
    githubRepository = "${GitHubOwner}/${GitHubRepo}"
    branch = $Branch
    appDisplayName = $AppDisplayName
    azureClientId = $appId
    azureTenantId = $tenantId
    azureSubscriptionId = $subscriptionId
    federatedCredentialName = $credentialName
    federatedCredentialSubject = $subject
    acrName = $AcrName
    containerAppName = $ContainerAppName
}

$output | ConvertTo-Json -Depth 8 | Set-Content -Path $script:OutputFile -Encoding utf8

Write-Host ""
Write-Host "OIDC setup completed. No client secret was created."
Write-Host "Configure these GitHub repository variables:"
Write-Host "AZURE_CLIENT_ID=$appId"
Write-Host "AZURE_TENANT_ID=$tenantId"
Write-Host "AZURE_SUBSCRIPTION_ID=$subscriptionId"
Write-Host "Output written to $script:OutputFile"
