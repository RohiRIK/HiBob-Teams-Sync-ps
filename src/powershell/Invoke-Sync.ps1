# Invoke-Sync.ps1
# Entry point for Jenkins to run the sync

param (
    [bool]$DryRun = ($env:IS_DRY_RUN -eq 'true'),
    [string]$TestUser = $env:TEST_USER_EMAIL
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$ScriptDir/HiBobSync.psm1" -Force

$CTX = "Main"

# Validation — always required
if (-not $env:HIBOB_TOKEN) {
    Write-Log "ERROR" $CTX "Missing required environment variable: HIBOB_TOKEN"
    exit 1
}

# Graph credentials — required for live runs only
if (-not $DryRun) {
    $GraphVars = @('ENTRAID_CLIENT_ID', 'ENTRAID_CLIENT_SECRET', 'ENTRAID_TENANT_ID')
    foreach ($Var in $GraphVars) {
        if (-not (Get-Item "env:$Var" -ErrorAction SilentlyContinue)) {
            Write-Log "ERROR" $CTX "Missing required environment variable for live run: $Var"
            exit 1
        }
    }
}

# Safe MAX_USERS parsing — never crash on bad input
$MaxUsers = 0
if ($env:MAX_USERS) {
    if (-not [int]::TryParse($env:MAX_USERS, [ref]$MaxUsers)) {
        Write-Log "WARN" $CTX "Invalid MAX_USERS value '$($env:MAX_USERS)', defaulting to 0 (unlimited)"
        $MaxUsers = 0
    }
}
if ($MaxUsers -lt 0) { $MaxUsers = 0 }

if ($DryRun) { Write-Log "WARN" $CTX "⚠️ MODE: DRY RUN (Safe Mode)" }
if ($TestUser) { Write-Log "INFO" $CTX "🎯 Targeted Test Mode: $TestUser" }

# 1. Fetch Employees
try {
    $Employees = Get-HiBobEmployees -Token $env:HIBOB_TOKEN
} catch {
    exit 1
}

# Filter if Test User
if ($TestUser) {
    $Employees = $Employees | Where-Object { $_.email -eq $TestUser }
    if (-not $Employees) {
        Write-Log "ERROR" $CTX "Test user not found in HiBob."
        exit 1
    }
}

Write-Log "INFO" $CTX "ℹ️ Processing $($Employees.Count) users..."

# 2. Authenticate Graph (SDK)
if (-not $DryRun) {
    Connect-ToGraph -ClientId $env:ENTRAID_CLIENT_ID -ClientSecret $env:ENTRAID_CLIENT_SECRET -TenantId $env:ENTRAID_TENANT_ID
} else {
    Write-Log "INFO" $CTX "Skipping Graph Auth (Dry Run)"
}

# 3. Sync
$Summary = Invoke-EmployeeSync -Employees $Employees -Token $env:HIBOB_TOKEN -MaxUsers $MaxUsers -DryRun:$DryRun

# Exit code signals build status to Jenkins: 0=success, 2=partial failure
if ($Summary.Failed -gt 0) {
    Write-Log "WARN" $CTX "⚠️ $($Summary.Failed) user(s) failed to sync"
    exit 2
}
