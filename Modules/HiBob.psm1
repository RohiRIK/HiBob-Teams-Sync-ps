# =============================================================================
# HiBob.psm1 - Module for interacting with HiBob HRIS API
# =============================================================================
# This module handles fetching employee data from HiBob
#
# ENVIRONMENT VARIABLES USED:
#   HIBOB_TOKEN   - API authentication token
#   HIBOB_API_URL - Base URL for HiBob API (optional)
#
# API ENDPOINT:
#   POST /people/search - Returns all employees
#   Filter: work.startDate within lookback period
# =============================================================================

function Get-HiBobNewHires {
    <#
    .SYNOPSIS
        Fetches new hires from HiBob who started within the specified days.
    
    .PARAMETER Token
        HiBob API token (from HIBOB_TOKEN env var)
    
    .PARAMETER ApiUrl
        HiBob API base URL (default: https://api.hibob.com/v1)
    
    .PARAMETER Lookback
        Number of days to look back for new hires (default: 7)
    
    .PARAMETER DryRun
        When enabled, returns mock data without calling API
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,
        
        [Parameter(Mandatory = $true)]
        [string]$ApiUrl,

        [int]$Lookback = 7,
        
        [switch]$DryRun
    )
    
    Write-Host "Fetching HiBob new hires from the last $Lookback days..."
    
    # Build API request headers
    $Headers = @{
        "Authorization" = $Token
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }
    
    # Dry-run mode: return mock data without API call
    if ($DryRun) {
        Write-Host "[DRY RUN] Would POST to $ApiUrl/people/search"
        return @(
            [PSCustomObject]@{
                id        = "mock-001"
                firstName = "Dry"
                surname   = "Run"
                email     = "dry.run@company.com"
                work      = [PSCustomObject]@{
                    startDate  = (Get-Date).ToString("yyyy-MM-dd")
                    title      = "Test User"
                    department = "Testing"
                }
            }
        )
    }

    try {
        # Call HiBob People Search API
        $Url = "$ApiUrl/people/search"
        $Body = @{
            showInactive  = $false
            humanReadable = $true
        } | ConvertTo-Json

        $Response = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body
        $Employees = $Response.employees
        
        # Filter by start date (new hires only)
        $CutoffDate = (Get-Date).AddDays(-$Lookback)
        
        $NewHires = $Employees | Where-Object { 
            $_.work.startDate -and ([DateTime]$_.work.startDate -ge $CutoffDate)
        }
        
        Write-Host "Found $($NewHires.Count) new hire(s)."
        return $NewHires

    }
    catch {
        Write-Error "Failed to fetch from HiBob: $_"
        throw
    }
}

Export-ModuleMember -Function Get-HiBobNewHires
