# TestHelpers.psm1

function Wait-ForApiReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 10,

        [Parameter(Mandatory = $false)]
        [int]$RetryIntervalMs = 200
    )

    $StartTime = Get-Date
    $EndTime = $StartTime.AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $EndTime) {
        try {
            $Response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 2 -ErrorAction Stop
            if ($Response.StatusCode -eq 200) {
                return $true
            }
        }
        catch {
            Start-Milliseconds -Milliseconds $RetryIntervalMs
        }
    }

    return $false
}

function New-MockEmployee {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id = "mock-001",

        [Parameter(Mandatory = $false)]
        [string]$FirstName = "Test",

        [Parameter(Mandatory = $false)]
        [string]$Surname = "User",

        [Parameter(Mandatory = $false)]
        [string]$Email = "test@company.com",

        [Parameter(Mandatory = $false)]
        [string]$Title = "Software Engineer",

        [Parameter(Mandatory = $false)]
        [string]$Department = "Engineering",

        [Parameter(Mandatory = $false)]
        [string]$StartDate = (Get-Date).ToString("yyyy-MM-dd")
    )

    return [PSCustomObject]@{
        id = $Id
        firstName = $FirstName
        surname = $Surname
        email = $Email
        work = [PSCustomObject]@{
            startDate = $StartDate
            title = $Title
            department = $Department
        }
    }
}

function New-MockEmployeeList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Count = 5
    )

    $Employees = @()
    $Departments = @("Engineering", "Product", "Design", "QA", "DevOps")
    $Titles = @("Software Engineer", "Product Manager", "Designer", "QA Engineer", "DevOps Engineer")

    for ($i = 1; $i -le $Count; $i++) {
        $Employees += New-MockEmployee -Id "emp-$i" -FirstName "User$i" -Surname "Test" -Email "user$i@company.com" -Title $Titles[($i - 1) % $Titles.Count] -Department $Departments[($i - 1) % $Departments.Count]
    }

    return $Employees
}

function Start-TestApiServers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$HiBobPort = 18080,

        [Parameter(Mandatory = $false)]
        [int]$TeamsPort = 18081,

        [Parameter(Mandatory = $false)]
        [string]$ResponseFile
    )

    $ModulePath = Split-Path -Parent $PSScriptRoot

    Import-Module "$ModulePath/mocks/Mock-HiBobApi.psm1" -Force -ErrorAction SilentlyContinue
    if (-not (Get-Command Start-MockHiBobApi -ErrorAction SilentlyContinue)) {
        . "$ModulePath/mocks/Mock-HiBobApi.ps1"
    }

    Import-Module "$ModulePath/mocks/Mock-TeamsWebhook.psm1" -Force -ErrorAction SilentlyContinue
    if (-not (Get-Command Start-MockTeamsWebhook -ErrorAction SilentlyContinue)) {
        . "$ModulePath/mocks/Mock-TeamsWebhook.ps1"
    }

    if ($ResponseFile) {
        Start-MockHiBobApi -Port $HiBobPort -ResponseFile $ResponseFile
    }
    else {
        Start-MockHiBobApi -Port $HiBobPort
    }
    Start-MockTeamsWebhook -Port $TeamsPort

    $HiBobReady = Wait-ForApiReady -Url "http://localhost:$HiBobPort/health" -TimeoutSeconds 5
    $TeamsReady = Wait-ForApiReady -Url "http://localhost:$TeamsPort/health" -TimeoutSeconds 5

    if (-not $HiBobReady -or -not $TeamsReady) {
        throw "Failed to start test API servers"
    }
}

function Stop-TestApiServers {
    [CmdletBinding()]
    param()

    $ModulePath = Split-Path -Parent $PSScriptRoot

    if (Get-Command Stop-MockHiBobApi -ErrorAction SilentlyContinue) {
        Stop-MockHiBobApi
    }
    if (Get-Command Stop-MockTeamsWebhook -ErrorAction SilentlyContinue) {
        Stop-MockTeamsWebhook
    }
}

function Assert-RequestLogContains {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPattern,

        [Parameter(Mandatory = $true)]
        $Logs
    )

    $Found = $Logs | Where-Object { $_ -match $LogPattern }
    if (-not $Found) {
        throw "Expected log containing '$LogPattern' not found. Logs: $($Logs | ConvertTo-Json)"
    }
}

Export-ModuleMember -Function Wait-ForApiReady, New-MockEmployee, New-MockEmployeeList, Start-TestApiServers, Stop-TestApiServers, Assert-RequestLogContains
