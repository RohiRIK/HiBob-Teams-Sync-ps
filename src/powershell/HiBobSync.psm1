# HiBobSync.psm1
# Module for synchronizing HiBob data to Microsoft Teams using Microsoft.Graph SDK

# --- Logging Helper ---
function Write-Log {
    param (
        [string]$Level,
        [string]$Context,
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $Color = switch ($Level) {
        "INFO"  { "White" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        Default { "White" }
    }
    Write-Host "[$Timestamp] [$Level] [$Context] $Message" -ForegroundColor $Color
}

# --- Retry Helper (private) ---
function Invoke-WithRetry {
    param (
        [scriptblock]$Action,
        [int]$MaxRetries = 3,
        [string]$OperationName = "Operation"
    )
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            return (& $Action)
        } catch {
            if ($i -eq $MaxRetries) { throw }
            Write-Log "WARN" "Retry" "Attempt $i/$MaxRetries for ${OperationName}: $($_.Exception.Message)"
            Start-Sleep -Seconds ([Math]::Pow(2, $i - 1))
        }
    }
}

function Get-HiBobEmployees {
    param ([string]$Token)
    Write-Log "INFO" "HiBobService" "Fetching employees..."
    try {
        $Headers = @{ "Authorization" = $Token }
        $Response = Invoke-WithRetry -OperationName "Get-HiBobEmployees" -Action {
            Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Headers $Headers -Body '{"showInactive":false}' -ContentType "application/json" -ErrorAction Stop
        }
        return $Response.employees
    } catch {
        Write-Log "ERROR" "HiBobService" "Failed to fetch employees: $($_.Exception.Message)"
        throw
    }
}

function Get-HiBobAvatar {
    param ([string]$Token, [string]$Id)
    try {
        $Headers = @{ "Authorization" = $Token }
        $Response = Invoke-WithRetry -OperationName "Get-HiBobAvatar($Id)" -Action {
            Invoke-RestMethod -Uri "https://api.hibob.com/v1/avatars/$Id" -Headers $Headers -ErrorAction Stop
        }
        return $Response.avatarUrl
    } catch {
        return $null
    }
}

function Connect-ToGraph {
    param ([string]$ClientId, [string]$ClientSecret, [string]$TenantId)
    Write-Log "INFO" "GraphService" "Authenticating to Microsoft Graph..."

    $SecureSecret = $ClientSecret | ConvertTo-SecureString -AsPlainText -Force
    try {
        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Secret $SecureSecret -NoWelcome -ErrorAction Stop
        Write-Log "INFO" "GraphService" "✅ Connected successfully."
    } catch {
        Write-Log "ERROR" "GraphService" "❌ Authentication Failed: $($_.Exception.Message)"
        throw
    }
}

function Set-TeamsPhoto {
    param (
        [string]$Email,
        [string]$AvatarUrl,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Log "INFO" "GraphService" "[DRY RUN] Would update photo for $Email"
        return
    }

    $TempFile = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WithRetry -OperationName "Set-TeamsPhoto($Email)" -Action {
            # 1. Download to Temp File
            Invoke-WebRequest -Uri $AvatarUrl -OutFile $TempFile -UseBasicParsing -ErrorAction Stop
            # 2. Upload using Graph SDK
            Set-MgUserPhotoContent -UserId $Email -InFile $TempFile -ErrorAction Stop
        }
        Write-Log "INFO" "GraphService" "✅ Success: Updated photo for $Email"
    } catch {
        Write-Log "ERROR" "GraphService" "❌ Failed to update $Email : $($_.Exception.Message)"
    } finally {
        if (Test-Path $TempFile) { Remove-Item $TempFile -Force }
    }
}

function Invoke-EmployeeSync {
    param (
        [array]$Employees,
        [string]$Token,
        [int]$MaxUsers = 0,
        [switch]$DryRun
    )

    # Apply MAX_USERS limit
    if ($MaxUsers -gt 0 -and $Employees.Count -gt $MaxUsers) {
        Write-Log "WARN" "Sync" "⚠️ Limiting to $MaxUsers users (total: $($Employees.Count))"
        $Employees = $Employees | Select-Object -First $MaxUsers
    }

    # Process each employee
    foreach ($Emp in $Employees) {
        if (-not $Emp.email) {
            Write-Log "WARN" "Sync" "Skipping user $($Emp.id) - No Email"
            continue
        }
        $AvatarUrl = Get-HiBobAvatar -Token $Token -Id $Emp.id
        if ($AvatarUrl) {
            Set-TeamsPhoto -Email $Emp.email -AvatarUrl $AvatarUrl -DryRun:$DryRun
        }
    }

    Write-Log "INFO" "Sync" "✅ Sync complete. Processed: $($Employees.Count) users."
}

Export-ModuleMember -Function Get-HiBobEmployees, Get-HiBobAvatar, Connect-ToGraph, Set-TeamsPhoto, Write-Log, Invoke-EmployeeSync
