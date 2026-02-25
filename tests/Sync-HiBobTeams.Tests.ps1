# Sync-HiBobTeams.Tests.ps1

BeforeAll {
    $Script:FixturesPath = "$PSScriptRoot/fixtures"
    $Script:SyncScript = "$PSScriptRoot/../Sync-HiBobTeams.ps1"
    $Script:ModulesPath = "$PSScriptRoot/../Modules"
}

Describe "Sync-HiBobTeams Integration" {
    Context "Dry-run mode - No network calls" {
        It "Should NOT call HiBob API in dry-run mode" {
            Mock Invoke-RestMethod { } -ParameterFilter { $Uri -match 'hibob' }

            Import-Module "$Script:ModulesPath/HiBob.psm1" -Force
            $Result = Get-HiBobNewHires -Token "Bearer test-token" -ApiUrl "https://api.hibob.com/v1" -Lookback 7 -DryRun

            Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Uri -match 'hibob' }
        }

        It "Should NOT send Teams notifications in dry-run mode" {
            Mock Invoke-RestMethod { } -ParameterFilter { $Uri -match 'outlook' }

            Import-Module "$Script:ModulesPath/Teams.psm1" -Force
            $Employee = [PSCustomObject]@{
                firstName = "Test"
                surname = "User"
                email = "test@company.com"
                work = [PSCustomObject]@{ title = "Tester"; department = "QA"; startDate = "2026-02-20" }
            }

            Send-TeamsNotification -Employee $Employee -WebhookUrl "https://outlook.office.com/webhook/test" -DryRun

            Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Uri -match 'outlook' }
        }

        It "Should return mock employee data in dry-run mode" {
            Import-Module "$Script:ModulesPath/HiBob.psm1" -Force
            $Result = Get-HiBobNewHires -Token "Bearer test-token" -ApiUrl "https://api.hibob.com/v1" -Lookback 7 -DryRun

            $Result.Count | Should -BeGreaterThan 0
            $Result[0].firstName | Should -Be "Dry"
        }
    }

    Context "Module behavior tests" {
        It "Get-HiBobNewHires should accept required parameters" {
            Import-Module "$Script:ModulesPath/HiBob.psm1" -Force
            $Result = Get-HiBobNewHires -Token "test" -ApiUrl "test" -Lookback 7 -DryRun

            $Result | Should -Not -BeNullOrEmpty
        }

        It "Send-TeamsNotification should accept required parameters" {
            Import-Module "$Script:ModulesPath/Teams.psm1" -Force
            $Employee = [PSCustomObject]@{
                firstName = "Test"
                surname = "User"
                email = "test@company.com"
                work = [PSCustomObject]@{ title = "Tester"; department = "QA"; startDate = "2026-02-20" }
            }

            { Send-TeamsNotification -Employee $Employee -WebhookUrl "https://outlook.office.com/webhook/test" -DryRun } | Should -Not -Throw
        }
    }

    Context "Configuration validation" {
        It "Should fail when HIBOB_TOKEN is missing" {
            $Env:HIBOB_TOKEN = $null
            $Env:TEAMS_WEBHOOK_URL = "https://outlook.office.com/webhook/test"

            $ErrorActionPreference = "Continue"
            $Output = & $Script:SyncScript -DaysLookback 7 2>&1 | Out-String
            $ErrorActionPreference = "Stop"

            $Output | Should -Match "HIBOB_TOKEN"
        }

        It "Should fail when TEAMS_WEBHOOK_URL is missing" {
            $Env:HIBOB_TOKEN = "Bearer test-token"
            $Env:TEAMS_WEBHOOK_URL = $null

            $ErrorActionPreference = "Continue"
            $Output = & $Script:SyncScript -DaysLookback 7 2>&1 | Out-String
            $ErrorActionPreference = "Stop"

            $Output | Should -Match "TEAMS_WEBHOOK_URL"
        }

        It "Should succeed when all env vars are set" {
            $Env:HIBOB_TOKEN = "Bearer test-token"
            $Env:TEAMS_WEBHOOK_URL = "https://outlook.office.com/webhook/test"
            $Env:DRY_RUN = "true"

            { & $Script:SyncScript -DaysLookback 7 } | Should -Not -Throw
        }
    }

    Context "Full sync script executes in dry-run" {
        It "Should run complete sync in dry-run mode" {
            $Env:HIBOB_TOKEN = "Bearer test-token"
            $Env:TEAMS_WEBHOOK_URL = "https://outlook.office.com/webhook/test"
            $Env:DRY_RUN = "true"
            $Env:HIBOB_API_URL = "https://api.hibob.com/v1"

            { & $Script:SyncScript -DaysLookback 7 } | Should -Not -Throw
        }
    }
}
