# HiBobSync.Tests.ps1

BeforeAll {
    $Script:ModulePath = "$PSScriptRoot/../src/powershell/HiBobSync.psm1"
    Import-Module $Script:ModulePath -Force
    Import-Module "$PSScriptRoot/helpers/TestHelpers.psm1" -Force
}

Describe "Get-HiBobEmployees" {
    It "Should call HiBob people search endpoint with correct URL and headers" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ employees = @() }
        } -ModuleName HiBobSync -ParameterFilter { $Uri -match 'hibob.com/v1/people/search' }

        $null = Get-HiBobEmployees -Token "Bearer test-token"

        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName HiBobSync -ParameterFilter {
            $Uri -eq "https://api.hibob.com/v1/people/search" -and
            $Method -eq "Post" -and
            $Headers["Authorization"] -eq "Bearer test-token"
        }
    }

    It "Should return the employees array from response" {
        $MockEmployees = New-MockEmployeeList -Count 3
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ employees = $MockEmployees }
        } -ModuleName HiBobSync

        $Result = Get-HiBobEmployees -Token "Bearer test-token"

        $Result.Count | Should -Be 3
    }

    It "Should throw when API call fails" {
        Mock Invoke-RestMethod {
            throw [System.Net.WebException]::new("HTTP 401: Unauthorized")
        } -ModuleName HiBobSync

        { Get-HiBobEmployees -Token "bad-token" } | Should -Throw
    }

    It "Should handle paginated responses with cursor" {
        $Script:PageCallCount = 0
        Mock Invoke-RestMethod {
            $Script:PageCallCount++
            if ($Script:PageCallCount -eq 1) {
                return [PSCustomObject]@{
                    employees = @([PSCustomObject]@{ id = "emp-1"; email = "u1@test.com" })
                    response_metadata = [PSCustomObject]@{ next_cursor = "cursor-page2" }
                }
            } else {
                return [PSCustomObject]@{
                    employees = @([PSCustomObject]@{ id = "emp-2"; email = "u2@test.com" })
                }
            }
        } -ModuleName HiBobSync

        $Result = Get-HiBobEmployees -Token "Bearer test-token"

        $Result.Count | Should -Be 2
        Should -Invoke Invoke-RestMethod -Times 2 -ModuleName HiBobSync
    }

    It "Should send pagination limit in request body" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ employees = @() }
        } -ModuleName HiBobSync -ParameterFilter {
            $BodyObj = $Body | ConvertFrom-Json
            $BodyObj.pagination.limit -eq 100
        }

        $null = Get-HiBobEmployees -Token "Bearer test-token"

        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName HiBobSync
    }
}

Describe "Get-HiBobAvatar" {
    It "Should call avatar endpoint with employee ID in URL" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ avatarUrl = "https://cdn.hibob.com/avatars/emp-42.jpg" }
        } -ModuleName HiBobSync

        $Result = Get-HiBobAvatar -Token "Bearer test-token" -Id "emp-42"

        Should -Invoke Invoke-RestMethod -Times 1 -ModuleName HiBobSync -ParameterFilter {
            $Uri -match "emp-42"
        }
        $Result | Should -Be "https://cdn.hibob.com/avatars/emp-42.jpg"
    }

    It "Should return null when API call fails (no avatar)" {
        Mock Invoke-RestMethod {
            throw [System.Net.WebException]::new("HTTP 404: Not Found")
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync

        $Result = Get-HiBobAvatar -Token "Bearer test-token" -Id "emp-no-avatar"

        $Result | Should -BeNullOrEmpty
    }
}

Describe "Set-TeamsPhoto" {
    It "Should return 'dry-run' and NOT download when DryRun is true" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg" -DryRun

        $Result | Should -Be 'dry-run'
        Should -Invoke Invoke-WebRequest -Times 0 -ModuleName HiBobSync
        Should -Invoke Set-MgUserPhotoContent -Times 0 -ModuleName HiBobSync
    }

    It "Should return 'uploaded' on successful upload" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Get-Item { [PSCustomObject]@{ Length = 1024 } } -ModuleName HiBobSync
        Mock Get-MgUserPhotoContent { throw "No photo" } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync
        Mock Get-FileHash { [PSCustomObject]@{ Hash = "abc123" } } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        $Result | Should -Be 'uploaded'
        Should -Invoke Set-MgUserPhotoContent -Times 1 -ModuleName HiBobSync
    }

    It "Should return 'unchanged' when photo hashes match" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Get-Item { [PSCustomObject]@{ Length = 1024 } } -ModuleName HiBobSync
        Mock Get-MgUserPhotoContent { } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync
        Mock Get-FileHash { [PSCustomObject]@{ Hash = "same-hash-value" } } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        $Result | Should -Be 'unchanged'
        Should -Invoke Set-MgUserPhotoContent -Times 0 -ModuleName HiBobSync
    }

    It "Should return 'failed' when avatar is empty (0 bytes)" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Get-Item { [PSCustomObject]@{ Length = 0 } } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        $Result | Should -Be 'failed'
        Should -Invoke Set-MgUserPhotoContent -Times 0 -ModuleName HiBobSync
    }

    It "Should return 'failed' when avatar exceeds 4MB" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Get-Item { [PSCustomObject]@{ Length = 5 * 1024 * 1024 } } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        $Result | Should -Be 'failed'
        Should -Invoke Set-MgUserPhotoContent -Times 0 -ModuleName HiBobSync
    }

    It "Should handle malformed avatar URL without crashing" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Get-Item { [PSCustomObject]@{ Length = 1024 } } -ModuleName HiBobSync
        Mock Get-MgUserPhotoContent { throw "No photo" } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync
        Mock Get-FileHash { [PSCustomObject]@{ Hash = "abc123" } } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "not-a-url"

        $Result | Should -Be 'uploaded'
    }

    It "Should pass TimeoutSec to Invoke-WebRequest" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync -ParameterFilter { $TimeoutSec -eq 30 }
        Mock Get-Item { [PSCustomObject]@{ Length = 1024 } } -ModuleName HiBobSync
        Mock Get-MgUserPhotoContent { throw "No photo" } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync
        Mock Get-FileHash { [PSCustomObject]@{ Hash = "abc123" } } -ModuleName HiBobSync

        Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        Should -Invoke Invoke-WebRequest -Times 1 -ModuleName HiBobSync -ParameterFilter { $TimeoutSec -eq 30 }
    }
}

Describe "Invoke-WithRetry (retry logic)" {
    It "Should succeed on third attempt when first two calls fail with transient error" {
        $Script:CallCount = 0
        Mock Invoke-RestMethod {
            $Script:CallCount++
            if ($Script:CallCount -lt 3) {
                throw [System.Exception]::new("Transient error attempt $Script:CallCount")
            }
            return [PSCustomObject]@{ employees = @() }
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync

        $null = Get-HiBobEmployees -Token "Bearer test-token"

        Should -Invoke Invoke-RestMethod -Times 3 -ModuleName HiBobSync
    }

    It "Should throw after exhausting all retries" {
        Mock Invoke-RestMethod {
            throw [System.Exception]::new("Persistent failure")
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync

        { Get-HiBobEmployees -Token "Bearer test-token" } | Should -Throw
    }

    It "Should redact Bearer tokens in retry warning logs" {
        $Script:LogMessages = @()
        Mock Invoke-RestMethod {
            throw [System.Exception]::new("Auth failed with Bearer secret-token-value-123")
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync
        Mock Write-Host { $Script:LogMessages += $Object } -ModuleName HiBobSync

        try { Get-HiBobEmployees -Token "Bearer test-token" } catch { }

        $RetryLogs = $Script:LogMessages | Where-Object { $_ -match 'Retry' }
        $RetryLogs | ForEach-Object {
            $_ | Should -Not -Match 'secret-token-value-123'
            $_ | Should -Match '\[REDACTED\]'
        }
    }

    It "Should throw immediately on non-retryable 4xx error without retrying" {
        $Script:RetryCallCount = 0
        Mock Invoke-RestMethod {
            $Script:RetryCallCount++
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound)
            $Ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("HTTP 404: Not Found", $Response)
            throw $Ex
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        { Get-HiBobEmployees -Token "Bearer test-token" } | Should -Throw

        $Script:RetryCallCount | Should -Be 1
        Should -Invoke Start-Sleep -Times 0 -ModuleName HiBobSync
    }

    It "Should retry on 429 rate limit (unlike other 4xx errors)" {
        $Script:RateLimitCallCount = 0
        Mock Invoke-RestMethod {
            $Script:RateLimitCallCount++
            if ($Script:RateLimitCallCount -lt 3) {
                $Response = [System.Net.Http.HttpResponseMessage]::new(429)
                $Ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("HTTP 429: Too Many Requests", $Response)
                throw $Ex
            }
            return [PSCustomObject]@{ employees = @() }
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        $null = Get-HiBobEmployees -Token "Bearer test-token"

        # 429 is transient — should retry and eventually succeed on attempt 3
        Should -Invoke Invoke-RestMethod -Times 3 -ModuleName HiBobSync
        Should -Invoke Start-Sleep -Times 2 -ModuleName HiBobSync
    }
}

Describe "Connect-ToGraph" {
    It "Should call Connect-MgGraph with ClientSecretCredential" {
        Mock Connect-MgGraph { } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        Connect-ToGraph -ClientId "test-client-id" -ClientSecret "test-secret" -TenantId "test-tenant"

        Should -Invoke Connect-MgGraph -Times 1 -ModuleName HiBobSync -ParameterFilter {
            $TenantId -eq "test-tenant" -and
            $ClientSecretCredential -ne $null -and
            $NoWelcome -eq $true
        }
    }

    It "Should throw when authentication fails" {
        Mock Connect-MgGraph { throw "Authentication failed" } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        { Connect-ToGraph -ClientId "bad" -ClientSecret "bad" -TenantId "bad" } | Should -Throw
    }

    It "Should create PSCredential from ClientId and ClientSecret" {
        $Script:CapturedCredential = $null
        Mock Connect-MgGraph {
            $Script:CapturedCredential = $ClientSecretCredential
        } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        Connect-ToGraph -ClientId "my-client-id" -ClientSecret "my-secret" -TenantId "my-tenant"

        $Script:CapturedCredential | Should -Not -BeNullOrEmpty
        $Script:CapturedCredential.UserName | Should -Be "my-client-id"
    }
}

Describe "Set-TeamsPhoto (upload failure)" {
    It "Should return 'failed' when Graph upload throws exception" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Get-Item { [PSCustomObject]@{ Length = 1024 } } -ModuleName HiBobSync
        Mock Get-MgUserPhotoContent { throw "No photo" } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { throw "Graph API error: insufficient permissions" } -ModuleName HiBobSync
        Mock Get-FileHash { [PSCustomObject]@{ Hash = "abc123" } } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        $Result | Should -Be 'failed'
    }

    It "Should return 'failed' when avatar download throws exception" {
        Mock Invoke-WebRequest { throw "Download failed" } -ModuleName HiBobSync
        Mock Start-Sleep { } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        $Result = Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        $Result | Should -Be 'failed'
    }
}

Describe "Invoke-EmployeeSync" {
    It "Should return summary with correct counts" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'dry-run' } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 5
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        $Summary | Should -Not -BeNullOrEmpty
        $Summary.GetType().Name | Should -Be 'Hashtable'
    }

    It "Should process only MaxUsers employees when limit is set" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'dry-run' } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 10
        $null = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 3 -DryRun

        Should -Invoke Get-HiBobAvatar -Times 3 -Exactly -ModuleName HiBobSync
    }

    It "Should process all employees when MaxUsers is 0 (unlimited)" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'dry-run' } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 5
        $null = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        Should -Invoke Get-HiBobAvatar -Times 5 -Exactly -ModuleName HiBobSync
    }

    It "Should count employees with no email in summary" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'dry-run' } -ModuleName HiBobSync

        $Employees = @(
            [PSCustomObject]@{ id = "emp-1"; email = "user1@company.com" },
            [PSCustomObject]@{ id = "emp-2"; email = $null },
            [PSCustomObject]@{ id = "emp-3"; email = "user3@company.com" }
        )
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        $Summary.NoEmail | Should -Be 1
        Should -Invoke Get-HiBobAvatar -Times 2 -Exactly -ModuleName HiBobSync
    }

    It "Should count employees with no avatar in summary" {
        Mock Get-HiBobAvatar { return $null } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 3
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        $Summary.NoAvatar | Should -Be 3
        Should -Invoke Set-TeamsPhoto -Times 0 -ModuleName HiBobSync
    }

    It "Should track uploaded count from Set-TeamsPhoto results" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'uploaded' } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 3
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0

        $Summary.Uploaded | Should -Be 3
    }

    It "Should track unchanged count from Set-TeamsPhoto results" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'unchanged' } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 4
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0

        $Summary.Unchanged | Should -Be 4
    }

    It "Should track failed count from Set-TeamsPhoto results" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { return 'failed' } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 2
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0

        $Summary.Failed | Should -Be 2
    }

    It "Should track mixed results correctly across employees" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Write-Host { } -ModuleName HiBobSync

        $Script:PhotoCallCount = 0
        Mock Set-TeamsPhoto {
            $Script:PhotoCallCount++
            switch ($Script:PhotoCallCount) {
                1 { return 'uploaded' }
                2 { return 'unchanged' }
                3 { return 'failed' }
                4 { return 'uploaded' }
            }
        } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 4
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0

        $Summary.Uploaded | Should -Be 2
        $Summary.Unchanged | Should -Be 1
        $Summary.Failed | Should -Be 1
    }
}
