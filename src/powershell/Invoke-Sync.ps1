# Invoke-Sync.ps1
# Entry point for Jenkins to run the sync

$ErrorActionPreference = "Stop"

param (
    [switch]$DryRun = ([System.Convert]::ToBoolean($env:IS_DRY_RUN)),
    [string]$TestUser = $env:TEST_USER_EMAIL
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$ScriptDir/HiBobSync.psm1" -Force

$CTX = "Main"

# Validation
if (-not $env:HIBOB_TOKEN -or -not $env:ENTRAID_CLIENT_ID) {
    Write-Log "ERROR" $CTX "Missing required environment variables."
    exit 1
}

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

# 3. Loop
foreach ($Emp in $Employees) {
    if (-not $Emp.email) { 
        Write-Log "WARN" $CTX "Skipping user $($Emp.id) - No Email"
        continue 
    }

    if ($env:DO_SYNC_AVATARS -eq 'true') {
        $AvatarUrl = Get-HiBobAvatar -Token $env:HIBOB_TOKEN -Id $Emp.id
        if ($AvatarUrl) {
            Set-TeamsPhoto -Email $Emp.email -AvatarUrl $AvatarUrl -DryRun:$DryRun
        }
    }
}
