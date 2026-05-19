Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$PHASE2_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase2-deployment.json"
$PHASE3_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase3-storage.json"
$PHASE4_OUTPUT_FILE = Join-Path $PROJECT_ROOT "outputs\azure-phase4-sql.json"

if (-not (Test-Path $PHASE2_OUTPUT_FILE)) {
  throw "Falta outputs/azure-phase2-deployment.json. Ejecuta primero Fase 2."
}
if (-not (Test-Path $PHASE3_OUTPUT_FILE)) {
  throw "Falta outputs/azure-phase3-storage.json. Ejecuta primero Fase 3."
}

$phase2 = Get-Content -Path $PHASE2_OUTPUT_FILE -Raw | ConvertFrom-Json
$phase3 = Get-Content -Path $PHASE3_OUTPUT_FILE -Raw | ConvertFrom-Json
$existingPhase4 = if (Test-Path $PHASE4_OUTPUT_FILE) {
  Get-Content -Path $PHASE4_OUTPUT_FILE -Raw | ConvertFrom-Json
} else {
  $null
}

$RESOURCE_GROUP = $phase2.resourceGroup
$LOCATION = $phase2.location
$ACR_NAME = $phase2.acrName
$ACR_LOGIN_SERVER = $phase2.acrLoginServer
$CONTAINER_APP_NAME = $phase2.containerAppName
$APP_URL = $phase3.appUrl
$STORAGE_ACCOUNT_NAME = $phase3.storageAccountName
$STORAGE_CONTAINER_NAME = $phase3.storageContainerName
$AZURE_CLIENT_ID = $phase3.azureClientId

$SQL_SERVER_NAME = if ($null -ne $existingPhase4 -and $existingPhase4.sqlServerName) {
  $existingPhase4.sqlServerName
} else {
  "aidocsql$((Get-Random -Minimum 10000 -Maximum 99999))"
}
$SQL_DATABASE_NAME = "aidocinteldb"
$SQL_ADMIN_USER = "aidocadmin"
$IMAGE_NAME = "ai-doc-intel-backend"
$IMAGE_TAG = "phase4"
$FULL_IMAGE_NAME = "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"

Add-Type -AssemblyName System.Web
$SQL_ADMIN_PASSWORD = [System.Web.Security.Membership]::GeneratePassword(24, 6) + "aA1!"

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
  )
  Write-Host ""
  Write-Host "==> $Name" -ForegroundColor Cyan
  & $ScriptBlock
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
  }
}

function Invoke-NativeOutput {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')`n$output"
  }
  $cleanOutput = foreach ($item in $output) {
    if ($item -is [System.Management.Automation.ErrorRecord]) {
      $text = $item.ToString()
      if ($text -match "^WARNING:") { continue }
      $text
    } else {
      [string]$item
    }
  }
  return (($cleanOutput | Out-String).Trim())
}

function Test-AzSqlServerExists {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & az sql server show `
      --name $SQL_SERVER_NAME `
      --resource-group $RESOURCE_GROUP `
      --only-show-errors `
      --query name `
      --output tsv 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($exitCode -eq 0 -and (($output | Out-String).Trim())) {
    return $true
  }

  $text = ($output | Out-String)
  if ($text -match "ResourceNotFound" -or $text -match "was not found") {
    return $false
  }

  throw "Could not check SQL Server existence. az exit code: ${exitCode}`n$text"
}

function Invoke-HttpWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Name,
    [int]$Attempts = 18,
    [int]$DelaySeconds = 10
  )
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      Write-Host "Checking $Name ($attempt/$Attempts): $Url"
      return Invoke-RestMethod -Uri $Url -TimeoutSec 30
    } catch {
      if ($attempt -eq $Attempts) {
        throw "$Name validation failed after $Attempts attempts. Last error: $($_.Exception.Message)"
      }
      Start-Sleep -Seconds $DelaySeconds
    }
  }
}

function Assert-ProviderRegistered {
  param([Parameter(Mandatory = $true)][string]$Namespace)
  Invoke-NativeCommand "az" @("provider", "register", "--namespace", $Namespace, "--wait")
  $state = Invoke-NativeOutput "az" @(
    "provider", "show",
    "--namespace", $Namespace,
    "--only-show-errors",
    "--query", "registrationState",
    "--output", "tsv"
  )
  if ($state -ne "Registered") {
    throw "Azure provider '$Namespace' is not Registered. Current state: '$state'."
  }
  Write-Host "$Namespace is Registered" -ForegroundColor Green
}

Push-Location $PROJECT_ROOT
try {
  Invoke-Step "Checking tooling and providers" {
    Invoke-NativeCommand "az" @("account", "show", "--output", "table")
    Invoke-NativeCommand "docker" @("--version")
    Assert-ProviderRegistered "Microsoft.Sql"
  }

  Invoke-Step "Creating Azure SQL Server" {
    if (Test-AzSqlServerExists) {
      Write-Host "SQL Server already exists: $SQL_SERVER_NAME" -ForegroundColor Green
    } else {
      Invoke-NativeCommand "az" @(
        "sql", "server", "create",
        "--name", $SQL_SERVER_NAME,
        "--resource-group", $RESOURCE_GROUP,
        "--location", $LOCATION,
        "--admin-user", $SQL_ADMIN_USER,
        "--admin-password", $SQL_ADMIN_PASSWORD,
        "--output", "table"
      )
    }
  }

  Invoke-Step "Creating Azure SQL Database" {
    Invoke-NativeCommand "az" @(
      "sql", "db", "create",
      "--resource-group", $RESOURCE_GROUP,
      "--server", $SQL_SERVER_NAME,
      "--name", $SQL_DATABASE_NAME,
      "--service-objective", "Basic",
      "--output", "table"
    )
  }

  Invoke-Step "Allowing Azure services through SQL firewall" {
    Invoke-NativeCommand "az" @(
      "sql", "server", "firewall-rule", "create",
      "--resource-group", $RESOURCE_GROUP,
      "--server", $SQL_SERVER_NAME,
      "--name", "AllowAzureServices",
      "--start-ip-address", "0.0.0.0",
      "--end-ip-address", "0.0.0.0",
      "--output", "table"
    )
  }

  Invoke-Step "Setting Container App SQL password secret" {
    Invoke-NativeCommand "az" @(
      "containerapp", "secret", "set",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--secrets", "sql-password=$SQL_ADMIN_PASSWORD"
    )
  }

  Invoke-Step "Building and pushing backend image phase4" {
    Invoke-NativeCommand "az" @("acr", "login", "--name", $ACR_NAME)
    Invoke-NativeCommand "docker" @("build", "-t", $FULL_IMAGE_NAME, "./backend")
    Invoke-NativeCommand "docker" @("push", $FULL_IMAGE_NAME)
  }

  Invoke-Step "Updating Container App image and SQL env vars" {
    Invoke-NativeCommand "az" @(
      "containerapp", "update",
      "--name", $CONTAINER_APP_NAME,
      "--resource-group", $RESOURCE_GROUP,
      "--image", $FULL_IMAGE_NAME,
      "--set-env-vars",
        "DATABASE_MODE=azure_sql",
        "AZURE_SQL_SERVER=$SQL_SERVER_NAME.database.windows.net",
        "AZURE_SQL_DATABASE=$SQL_DATABASE_NAME",
        "AZURE_SQL_USERNAME=$SQL_ADMIN_USER",
        "AZURE_SQL_PASSWORD=secretref:sql-password",
        "STORAGE_MODE=azure_blob",
        "AZURE_STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME",
        "AZURE_STORAGE_CONTAINER_NAME=$STORAGE_CONTAINER_NAME",
        "AZURE_CLIENT_ID=$AZURE_CLIENT_ID",
      "--output", "table"
    )
  }

  Invoke-Step "Validating health endpoints" {
    Invoke-HttpWithRetry -Url "$APP_URL/health" -Name "/health" | ConvertTo-Json -Depth 8 | Write-Host
    Invoke-HttpWithRetry -Url "$APP_URL/ready" -Name "/ready" | ConvertTo-Json -Depth 8 | Write-Host
  }

  Invoke-Step "Writing phase4 outputs" {
    [ordered]@{
      resourceGroup = $RESOURCE_GROUP
      location = $LOCATION
      sqlServerName = $SQL_SERVER_NAME
      sqlServerFqdn = "$SQL_SERVER_NAME.database.windows.net"
      sqlDatabaseName = $SQL_DATABASE_NAME
      sqlAdminUser = $SQL_ADMIN_USER
      containerAppName = $CONTAINER_APP_NAME
      image = $FULL_IMAGE_NAME
      appUrl = $APP_URL
      healthUrl = "$APP_URL/health"
      readyUrl = "$APP_URL/ready"
      docsUrl = "$APP_URL/docs"
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $PHASE4_OUTPUT_FILE -Encoding UTF8
    Write-Host "Outputs written to $PHASE4_OUTPUT_FILE" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
