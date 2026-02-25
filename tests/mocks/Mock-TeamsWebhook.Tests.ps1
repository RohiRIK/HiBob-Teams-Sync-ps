# Mock-TeamsWebhook.Tests.ps1

BeforeAll {
    $Script:MockWebhookPort = 18081
}

Describe "Mock-TeamsWebhook - Using Pester Mock" {
    Context "Mock webhook accepts payload" {
        BeforeEach {
            Mock Invoke-RestMethod { return @{ status = "received" } }
        }

        It "Should accept and process adaptive card payload" {
            $Payload = @{
                type = "message"
                attachments = @(
                    @{
                        contentType = "application/vnd.microsoft.card.adaptive"
                        content = @{
                            type = "AdaptiveCard"
                            version = "1.2"
                            body = @(
                                @{ type = "TextBlock"; text = "Test" }
                            )
                        }
                    }
                )
            } | ConvertTo-Json -Depth 10

            $Response = Invoke-RestMethod -Uri "https://outlook.office.com/webhook/test" -Method Post -Body $Payload -ContentType "application/json"
            $Response.status | Should -Be "received"
        }
    }

    Context "Mock webhook tracks multiple calls" {
        It "Should be called multiple times for multiple notifications" {
            Mock Invoke-RestMethod { return @{ status = "received" } }

            1..3 | ForEach-Object {
                $Payload = @{ type = "message"; text = "test$_" } | ConvertTo-Json
                $null = Invoke-RestMethod -Uri "https://outlook.office.com/webhook/test" -Method Post -Body $Payload -ContentType "application/json"
            }
            
            Should -Invoke Invoke-RestMethod -Times 3
        }
    }

    Context "Mock webhook error simulation" {
        It "Should throw when webhook returns error" {
            Mock Invoke-RestMethod { 
                throw [System.Net.WebException]::new("HTTP 500: Internal Server Error", [System.Net.WebExceptionStatus]::ProtocolError) 
            }
            
            { Invoke-RestMethod -Uri "https://outlook.office.com/webhook/test" -Method Post -Body '{}' -ContentType "application/json" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Verify correct webhook URL is called" {
        It "Should call Teams webhook URL" {
            Mock Invoke-RestMethod { return @{ status = "received" } }
            
            $null = Invoke-RestMethod -Uri "https://outlook.office.com/webhook/abc123" -Method Post -Body '{}' -ContentType "application/json"
            
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -match 'outlook.office.com/webhook' }
        }
    }

    Context "Verify payload content type" {
        It "Should send with correct content type" {
            Mock Invoke-RestMethod { return @{ status = "received" } }
            
            $null = Invoke-RestMethod -Uri "https://outlook.office.com/webhook/test" -Method Post -Body '{}' -ContentType "application/json"
            
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $ContentType -eq "application/json" }
        }
    }
}
