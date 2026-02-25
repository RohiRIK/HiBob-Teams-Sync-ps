# =============================================================================
# Teams.psm1 - Module for sending Microsoft Teams notifications
# =============================================================================
# This module handles sending adaptive card notifications to Teams channels
#
# ENVIRONMENT VARIABLES USED:
#   TEAMS_WEBHOOK_URL - Incoming webhook URL for Teams channel
#
# API ENDPOINT:
#   POST {webhook_url} - Send adaptive card message to channel
#   Format: Adaptive Card JSON payload
# =============================================================================

function Send-TeamsNotification {
    <#
    .SYNOPSIS
        Sends a Teams notification for a new employee.
    
    .PARAMETER Employee
        Employee object with firstName, surname, email, work properties
    
    .PARAMETER WebhookUrl
        Teams incoming webhook URL
    
    .PARAMETER DryRun
        When enabled, logs what would be sent without making API call
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Employee,

        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl,

        [switch]$DryRun
    )

    Write-Host "Sending Teams notification for $($Employee.firstName) $($Employee.surname)..."

    # Build Adaptive Card payload for Teams
    $Card = @{
        type        = "message"
        attachments = @(
            @{
                contentType = "application/vnd.microsoft.card.adaptive"
                contentUrl  = $null
                content     = @{
                    '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
                    type      = "AdaptiveCard"
                    version   = "1.2"
                    body      = @(
                        @{
                            type   = "TextBlock"
                            text   = "🚀 New Team Member!"
                            weight = "Bolder"
                            size   = "Large"
                            color  = "Accent"
                        },
                        @{
                            type = "TextBlock"
                            text = "Please welcome **$($Employee.firstName) $($Employee.surname)** to the team!"
                            wrap = $true
                            size = "Medium"
                        },
                        @{
                            type  = "FactSet"
                            facts = @(
                                @{ title = "Title:"; value = ($Employee.work.title) },
                                @{ title = "Department:"; value = ($Employee.work.department) },
                                @{ title = "Start Date:"; value = ($Employee.work.startDate) },
                                @{ title = "Email:"; value = ($Employee.email) }
                            )
                        }
                    )
                }
            }
        )
    }

    # Dry-run mode: log without sending
    if ($DryRun) {
        Write-Host "[DRY RUN] Would POST to Teams Webhook"
        Write-Host "[DRY RUN] Card content:" -ForegroundColor Cyan
        $Card | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    try {
        # Send to Teams webhook
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json" -Body ($Card | ConvertTo-Json -Depth 10)
        Write-Host "Notification sent successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to send Teams notification: $_"
    }
}

Export-ModuleMember -Function Send-TeamsNotification
