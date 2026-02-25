# Mock-HiBobApi.Tests.ps1

BeforeAll {
    $Script:FixturesPath = "$PSScriptRoot/../fixtures"
}

Describe "Mock-HiBobApi - Using Pester Mock" {
    Context "Mock API with fixture file" {
        BeforeAll {
            $Script:MockResponse = Get-Content "$FixturesPath/5-newhires.json" -Raw | ConvertFrom-Json
            Mock Invoke-RestMethod { return $Script:MockResponse }
        }

        It "Should return 5 employees from fixture" {
            $Response = Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Body '{}'
            $Response.employees.Count | Should -Be 5
        }

        It "Should return employee with correct structure" {
            $Response = Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Body '{}'
            $Response.employees[0].id | Should -Not -BeNullOrEmpty
            $Response.employees[0].firstName | Should -Not -BeNullOrEmpty
            $Response.employees[0].email | Should -Match '@'
        }
    }

    Context "Mock API error response" {
        BeforeAll {
            Mock Invoke-RestMethod { 
                $ErrorResponse = @{
                    error = "Unauthorized"
                } | ConvertTo-Json
                throw [System.Net.WebException]::new("HTTP 401: Unauthorized", [System.Net.WebExceptionStatus]::ProtocolError) 
            }
        }

        It "Should throw error for 401" {
            { Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Body '{}' -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Mock API empty response" {
        BeforeAll {
            $Script:EmptyResponse = Get-Content "$FixturesPath/0-newhires.json" -Raw | ConvertFrom-Json
            Mock Invoke-RestMethod { return $Script:EmptyResponse }
        }

        It "Should return empty employee list" {
            $Response = Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Body '{}'
            $Response.employees | Should -BeNullOrEmpty
        }
    }

    Context "Verify correct API endpoint is called" {
        It "Should call HiBob API with correct URL" {
            Mock Invoke-RestMethod { return @{ employees = @() } } -ParameterFilter { $Uri -match 'hibob.com' }
            
            $null = Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Body '{}'
            
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -match 'hibob.com' }
        }
    }

    Context "Verify correct headers are sent" {
        It "Should include Authorization header" {
            Mock Invoke-RestMethod { return @{ employees = @() } }
            
            $Headers = @{
                "Authorization" = "Bearer test-token"
                "Content-Type" = "application/json"
            }
            $null = Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/search" -Method Post -Headers $Headers -Body '{}'
            
            Should -Invoke Invoke-RestMethod -Times 1
        }
    }
}
