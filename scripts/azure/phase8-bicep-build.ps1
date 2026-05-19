$ErrorActionPreference = "Stop"

$script:Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$script:TemplateFile = Join-Path $script:Root "infra\main.bicep"

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

Write-Step "Checking Azure Bicep CLI"
Invoke-Native az bicep version

Write-Step "Building infra/main.bicep"
Invoke-Native az bicep build --file $script:TemplateFile

Write-Host ""
Write-Host "Bicep build completed."
