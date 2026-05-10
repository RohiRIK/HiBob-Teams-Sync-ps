# HiBobSync.psm1
# Module for synchronizing HiBob data to Microsoft Teams using Microsoft.Graph SDK

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

            # Extract HTTP status code if available
            $StatusCode = $null
            if ($_.Exception.Response) {
                $StatusCode = [int]$_.Exception.Response.StatusCode
            }

            # Only retry transient failures: 429 (rate limit), 5xx (server), network errors (no status)
            $IsTransient = ($null -eq $StatusCode) -or ($StatusCode -eq 429) -or ($StatusCode -ge 500)
            if (-not $IsTransient) {
                $SafeMessage = $_.Exception.Message -replace '(?i)Bearer\s+\S+', 'Bearer [REDACTED]' -replace '(?i)Basic\s+\S+', 'Basic [REDACTED]'
                Write-Log "ERROR" "Retry" "Non-retryable error for ${OperationName} (HTTP $StatusCode): $SafeMessage"
                throw
            }

            # Respect Retry-After header on 429
            $WaitSeconds = [Math]::Pow(2, $i - 1)
            if ($StatusCode -eq 429 -and $_.Exception.Response.Headers) {
                $RetryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($RetryAfter -and [int]::TryParse($RetryAfter, [ref]$null)) {
                    $WaitSeconds = [Math]::Max($WaitSeconds, [int]$RetryAfter)
                }
            }

            $SafeMessage = $_.Exception.Message -replace '(?i)Bearer\s+\S+', 'Bearer [REDACTED]' -replace '(?i)Basic\s+\S+', 'Basic [REDACTED]'
            Write-Log "WARN" "Retry" "Attempt $i/$MaxRetries for ${OperationName}: $SafeMessage (waiting ${WaitSeconds}s)"
            Start-Sleep -Seconds $WaitSeconds
        }
    }
}

function Get-HiBobEmployees {
    param ([string]$Token)
    Write-Log "INFO" "HiBobService" "Fetching employees..."
    try {
        $Headers = @{ "Authorization" = $Token }
        $AllEmployees = @()
        $Cursor = $null
        $PageSize = 100

        do {
            $BodyObj = @{ showInactive = $false; pagination = @{ limit = $PageSize } }
            if ($Cursor) { $BodyObj.pagination.cursor = $Cursor }
            $JsonBody = $BodyObj | ConvertTo-Json -Depth 3

            $Response = Invoke-WithRetry -OperationName "Get-HiBobEmployees" -Action {
                Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Headers $Headers -Body $JsonBody -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
            }

            $AllEmployees += $Response.employees

            # Cursor pagination — stop if API doesn't return next_cursor
            $Cursor = $null
            if ($Response.PSObject.Properties['response_metadata'] -and $Response.response_metadata.next_cursor) {
                $Cursor = $Response.response_metadata.next_cursor
                Write-Log "INFO" "HiBobService" "Fetched $($AllEmployees.Count) employees so far..."
            }
        } while ($Cursor)

        Write-Log "INFO" "HiBobService" "Total employees fetched: $($AllEmployees.Count)"
        return $AllEmployees
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
            Invoke-RestMethod -Uri "https://api.hibob.com/v1/avatars/$Id" -Headers $Headers -TimeoutSec 30 -ErrorAction Stop
        }
        return $Response.avatarUrl
    } catch {
        return $null
    }
}

function Connect-ToGraph {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'ClientSecret is a Jenkins env var (plain string) — conversion is required for PSCredential; no alternative at this system boundary'
    )]
    param ([string]$ClientId, [string]$ClientSecret, [string]$TenantId)
    Write-Log "INFO" "GraphService" "Authenticating to Microsoft Graph..."

    $SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    $ClientCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecureSecret
    try {
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientCredential -NoWelcome -ErrorAction Stop
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
        return 'dry-run'
    }

    try { $AvatarHost = ([System.Uri]::new($AvatarUrl)).Host } catch { $AvatarHost = "unknown" }
    Write-Log "INFO" "GraphService" "Downloading avatar from: $AvatarHost for $Email"

    $TempNewFile = [System.IO.Path]::GetTempFileName()
    $TempCurrentFile = [System.IO.Path]::GetTempFileName()
    try {
        # 1. Download new avatar
        Invoke-WithRetry -OperationName "Download-Avatar($Email)" -Action {
            Invoke-WebRequest -Uri $AvatarUrl -OutFile $TempNewFile -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        }

        # 2. Validate image size (Graph API limit: 4MB)
        $FileSize = (Get-Item $TempNewFile).Length
        if ($FileSize -eq 0) {
            Write-Log "WARN" "GraphService" "Empty avatar file for $Email — skipping"
            return 'failed'
        }
        $MaxSizeBytes = 4 * 1024 * 1024
        if ($FileSize -gt $MaxSizeBytes) {
            Write-Log "WARN" "GraphService" "Avatar too large for $Email ($([Math]::Round($FileSize / 1MB, 2))MB > 4MB) — skipping"
            return 'failed'
        }

        # 3. Change detection — compare with current Graph photo
        try {
            Get-MgUserPhotoContent -UserId $Email -OutFile $TempCurrentFile -ErrorAction Stop
            $NewHash = (Get-FileHash $TempNewFile -Algorithm MD5).Hash
            $CurrentHash = (Get-FileHash $TempCurrentFile -Algorithm MD5).Hash
            if ($NewHash -eq $CurrentHash) {
                Write-Log "INFO" "GraphService" "Photo unchanged for $Email — skipping"
                return 'unchanged'
            }
        } catch {
            # No current photo or can't fetch — proceed with upload
        }

        # 4. Upload to Graph
        Invoke-WithRetry -OperationName "Upload-Photo($Email)" -Action {
            Set-MgUserPhotoContent -UserId $Email -InFile $TempNewFile -ErrorAction Stop
        }
        Write-Log "INFO" "GraphService" "✅ Updated photo for $Email"
        return 'uploaded'
    } catch {
        Write-Log "ERROR" "GraphService" "❌ Failed to update $Email : $($_.Exception.Message)"
        return 'failed'
    } finally {
        if (Test-Path $TempNewFile) { Remove-Item $TempNewFile -Force }
        if (Test-Path $TempCurrentFile) { Remove-Item $TempCurrentFile -Force }
    }
}

function Invoke-EmployeeSync {
    param (
        [array]$Employees,
        [string]$Token,
        [int]$MaxUsers = 0,
        [switch]$DryRun
    )

    $Summary = @{ Uploaded = 0; Unchanged = 0; Failed = 0; NoEmail = 0; NoAvatar = 0 }

    if ($MaxUsers -gt 0 -and $Employees.Count -gt $MaxUsers) {
        Write-Log "WARN" "Sync" "⚠️ Limiting to $MaxUsers users (total: $($Employees.Count))"
        $Employees = $Employees | Select-Object -First $MaxUsers
    }

    foreach ($Emp in $Employees) {
        if (-not $Emp.email) {
            Write-Log "WARN" "Sync" "Skipping user $($Emp.id) - No Email"
            $Summary.NoEmail++
            continue
        }

        $AvatarUrl = Get-HiBobAvatar -Token $Token -Id $Emp.id
        if (-not $AvatarUrl) {
            $Summary.NoAvatar++
            continue
        }

        $Result = Set-TeamsPhoto -Email $Emp.email -AvatarUrl $AvatarUrl -DryRun:$DryRun
        switch ($Result) {
            'uploaded'  { $Summary.Uploaded++ }
            'unchanged' { $Summary.Unchanged++ }
            'failed'    { $Summary.Failed++ }
        }
    }

    $Total = $Employees.Count
    Write-Log "INFO" "Sync" "✅ Sync complete. Total=$Total Uploaded=$($Summary.Uploaded) Unchanged=$($Summary.Unchanged) Failed=$($Summary.Failed) NoAvatar=$($Summary.NoAvatar) NoEmail=$($Summary.NoEmail)"
    return $Summary
}

Export-ModuleMember -Function Get-HiBobEmployees, Get-HiBobAvatar, Connect-ToGraph, Set-TeamsPhoto, Write-Log, Invoke-EmployeeSync
