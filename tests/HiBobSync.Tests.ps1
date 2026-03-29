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

        $Result = Get-HiBobAvatar -Token "Bearer test-token" -Id "emp-no-avatar"

        $Result | Should -BeNullOrEmpty
    }
}

Describe "Set-TeamsPhoto" {
    It "Should NOT call Invoke-WebRequest or Set-MgUserPhotoContent when DryRun is true" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync

        Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg" -DryRun

        Should -Invoke Invoke-WebRequest -Times 0 -ModuleName HiBobSync
        Should -Invoke Set-MgUserPhotoContent -Times 0 -ModuleName HiBobSync
    }

    It "Should call Invoke-WebRequest and Set-MgUserPhotoContent when DryRun is false" {
        Mock Invoke-WebRequest { } -ModuleName HiBobSync
        Mock Set-MgUserPhotoContent { } -ModuleName HiBobSync

        Set-TeamsPhoto -Email "user@company.com" -AvatarUrl "https://cdn.hibob.com/avatar.jpg"

        Should -Invoke Invoke-WebRequest -Times 1 -ModuleName HiBobSync
        Should -Invoke Set-MgUserPhotoContent -Times 1 -ModuleName HiBobSync
    }
}

Describe "Invoke-WithRetry (retry logic)" {
    It "Should succeed on third attempt when first two calls fail - retry" {
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

    It "Should throw after exhausting all retries - retry" {
        Mock Invoke-RestMethod {
            throw [System.Exception]::new("Persistent failure")
        } -ModuleName HiBobSync

        Mock Start-Sleep { } -ModuleName HiBobSync

        { Get-HiBobEmployees -Token "Bearer test-token" } | Should -Throw
    }
}

Describe "Invoke-EmployeeSync - MAX_USERS limit" {
    It "Should process only MaxUsers employees when limit is set" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 10
        Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 3 -DryRun

        Should -Invoke Get-HiBobAvatar -Times 3 -Exactly -ModuleName HiBobSync
    }

    It "Should process all employees when MaxUsers is 0 (unlimited)" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 5
        Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        Should -Invoke Get-HiBobAvatar -Times 5 -Exactly -ModuleName HiBobSync
    }

    It "Should skip employees with no email" {
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { } -ModuleName HiBobSync

        $Employees = @(
            [PSCustomObject]@{ id = "emp-1"; email = "user1@company.com" },
            [PSCustomObject]@{ id = "emp-2"; email = $null },
            [PSCustomObject]@{ id = "emp-3"; email = "user3@company.com" }
        )
        Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        Should -Invoke Get-HiBobAvatar -Times 2 -Exactly -ModuleName HiBobSync
    }

    It "Should NOT call Set-TeamsPhoto when avatar URL is empty" {
        Mock Get-HiBobAvatar { return $null } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { } -ModuleName HiBobSync

        $Employees = New-MockEmployeeList -Count 3
        Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        Should -Invoke Set-TeamsPhoto -Times 0 -ModuleName HiBobSync
    }
}
