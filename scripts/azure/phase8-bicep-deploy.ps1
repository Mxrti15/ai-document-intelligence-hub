param(
    [string]$ResourceGroupName = "rg-ai-doc-intel-dev"
)

$ErrorActionPreference = "Stop"

$script:Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$script:TemplateFile = Join-Path $script:Root "infra\main.bicep"
$script:ParametersFile = Join-Path $script:Root "infra\params\dev.bicepparam"

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

Set-Location $script:Root

Write-Step "Protected deployment confirmation"
Write-Host "This will run az deployment group create against resource group '$ResourceGroupName'."
Write-Host "Review phase8-bicep-whatif.ps1 before deploying."
$confirmation = Read-Host "Type DEPLOY to continue"

if ($confirmation -ne "DEPLOY") {
    Write-Host "Deployment cancelled."
    exit 0
}

Write-Step "Deploying Bicep infrastructure"
Invoke-Native az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $script:TemplateFile `
    --parameters $script:ParametersFile `
    --only-show-errors

Write-Host ""
Write-Host "Bicep deployment completed."
