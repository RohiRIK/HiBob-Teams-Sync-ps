# Sync-HiBobToTeams.ps1
# Synchronizes HiBob Profile Pictures to Microsoft Teams (Exchange/Entra)

param (
    [switch]$DryRun = ([System.Convert]::ToBoolean($env:IS_DRY_RUN))
)

# --- Configuration ---
$BobToken = $env:HIBOB_TOKEN
$ClientId = $env:ENTRAID_CLIENT_ID
$ClientSecret = $env:ENTRAID_CLIENT_SECRET
$TenantId = $env:ENTRAID_TENANT_ID

if (-not $BobToken -or -not $ClientId) {
    Write-Error "Missing environment variables."
    exit 1
}

# --- Helpers ---
function Get-GraphToken {
    $Body = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    $Uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $Response = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body
    return $Response.access_token
}

# --- Main Logic ---
if ($DryRun) { Write-Host "⚠️ MODE: DRY RUN" -ForegroundColor Yellow }

try {
    # 1. Get Employees
    $BobHeaders = @{ "Authorization" = $BobToken }
    Write-Host "📥 Fetching employees from HiBob..."
    $Employees = (Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Headers $BobHeaders -Body '{"showInactive":false}' -ContentType "application/json").employees

    # 2. Get Graph Token
    $GraphToken = Get-GraphToken
    $GraphHeaders = @{
        "Authorization" = "Bearer $GraphToken"
        "Content-Type"  = "image/jpeg"
    }

    foreach ($Emp in $Employees) {
        $Email = $Emp.email
        if (-not $Email) { continue }

        try {
            # A. Get Avatar
            $AvatarMeta = Invoke-RestMethod -Uri "https://api.hibob.com/v1/avatars/$($Emp.id)" -Headers $BobHeaders
            $AvatarUrl = $AvatarMeta.avatarUrl

            if (-not $AvatarUrl) {
                Write-Host "⚠️ No avatar for $Email" -ForegroundColor Gray
                continue
            }

            # B. Sync
            if ($DryRun) {
                Write-Host "[DRY RUN] Would update photo for $Email" -ForegroundColor Cyan
            } else {
                Write-Host "🔄 Updating photo for $Email..." -NoNewline
                
                # Download Image
                $ImageBytes = Invoke-WebRequest -Uri $AvatarUrl -UseBasicParsing
                
                # Upload to Graph
                try {
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$Email/photo/`$value" `
                        -Method Put `
                        -Headers $GraphHeaders `
                        -Body $ImageBytes.Content
                    
                    Write-Host " [OK]" -ForegroundColor Green
                } catch {
                    Write-Host " [FAILED] $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } catch {
            Write-Error "Error processing $Email : $_"
        }
    }

} catch {
    Write-Error "Critical Failure: $_"
    exit 1
}
