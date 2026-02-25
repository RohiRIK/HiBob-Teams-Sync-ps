<#
.SYNOPSIS
    Syncs new hires from HiBob to Microsoft Teams.

.DESCRIPTION
    Fetches employees from HiBob who started within the last N days and posts 
    a welcome message to a Teams channel via Webhook.

.PARAMETER DaysLookback
    Number of days to look back for new hires. Default is 7.

.ENVIRONMENT VARIABLES
    The following environment variables must be set (or passed via Jenkins):

    HIBOB_TOKEN       - HiBob API token for authentication
    HIBOB_API_URL     - HiBob API base URL (default: https://api.hibob.com/v1)
    TEAMS_WEBHOOK_URL - Microsoft Teams incoming webhook URL
    DRY_RUN           - Set to 'true' to simulate without sending notifications

.EXAMPLE
    # Run with defaults (7 days lookback)
    ./Sync-HiBobTeams.ps1

.EXAMPLE
    # Run with custom lookback period
    ./Sync-HiBobTeams.ps1 -DaysLookback 30
#>

param(
    [int]$DaysLookback = 7
)

# Import Modules from same directory as this script
Import-Module -Force "$PSScriptRoot/Modules/HiBob.psm1"
Import-Module -Force "$PSScriptRoot/Modules/Teams.psm1"

# =============================================================================
# ENVIRONMENT VARIABLES CONFIGURATION
# =============================================================================

# HiBob Configuration
# ------------------
# HIBOB_TOKEN: Your HiBob API token (required)
#   Get from: HiBob Settings > Integrations > API
#   Format: "Bearer your-token-here"
$HiBobToken = $env:HIBOB_TOKEN

# HIBOB_API_URL: HiBob API endpoint (optional, has sensible default)
#   Default: https://api.hibob.com/v1
#   Only change if using a different HiBob instance (e.g., EU region)
$HiBobApiUrl = if ($env:HIBOB_API_URL) { 
    $env:HIBOB_API_URL 
} else { 
    "https://api.hibob.com/v1" 
}

# Teams Configuration
# -------------------
# TEAMS_WEBHOOK_URL: Incoming webhook URL for your Teams channel (required)
#   Get from: Teams > Channel > Connectors > Incoming Webhook
#   Format: https://outlook.office.com/webhook/...
$TeamsWebhookUrl = $env:TEAMS_WEBHOOK_URL

# Dry Run Mode
# ------------
# DRY_RUN: When 'true', logs what would happen without making actual changes
#   Default: false
#   Set to 'true' for testing without sending real notifications
$IsDryRun = $env:DRY_RUN -eq 'true'

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Check for required environment variables
if (-not $HiBobToken) {
    Write-Error "Missing required environment variable: HIBOB_TOKEN"
    Write-Error "Get token from: HiBob Settings > Integrations > API"
    exit 1
}

if (-not $TeamsWebhookUrl) {
    Write-Error "Missing required environment variable: TEAMS_WEBHOOK_URL"
    Write-Error "Get webhook from: Teams > Channel > Connectors > Incoming Webhook"
    exit 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

Write-Host "=========================================="
Write-Host "HiBob -> Teams New Hire Sync"
Write-Host "=========================================="
Write-Host "Days Lookback: $DaysLookback"
Write-Host "Dry Run Mode:  $IsDryRun"
Write-Host "HiBob API:     $HiBobApiUrl"
Write-Host "=========================================="

if ($IsDryRun) {
    Write-Host "⚠️  DRY RUN MODE - No changes will be made" -ForegroundColor Yellow
}

try {
    # Step 1: Fetch new hires from HiBob
    # -----------------------------------
    Write-Host "`n📥 Fetching new hires from HiBob..."
    $NewHires = Get-HiBobNewHires -Token $HiBobToken -ApiUrl $HiBobApiUrl -Lookback $DaysLookback -DryRun:$IsDryRun
    
    if ($NewHires.Count -eq 0) {
        Write-Host "No new hires found in the last $DaysLookback days."
        exit 0
    }

    Write-Host "Found $($NewHires.Count) new hire(s)"

    # Step 2: Send Teams notifications
    # ---------------------------------
    Write-Host "`n📤 Sending Teams notifications..."
    $successCount = 0
    $failureCount = 0

    foreach ($Hire in $NewHires) {
        try {
            Send-TeamsNotification -Employee $Hire -WebhookUrl $TeamsWebhookUrl -DryRun:$IsDryRun
            $successCount++
        }
        catch {
            Write-Warning "Failed to notify $($Hire.email): $_"
            $failureCount++
        }
    }

    # Step 3: Summary
    # ---------------
    Write-Host "`n=========================================="
    Write-Host "🏁 Sync Complete"
    Write-Host "   Success: $successCount"
    Write-Host "   Failed:  $failureCount"
    Write-Host "=========================================="

    if ($failureCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Error "Critical error in sync process: $_"
    exit 1
}
