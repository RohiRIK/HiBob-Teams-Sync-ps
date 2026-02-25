# AGENTS.md - Agent Coding Guidelines for HiBob Teams Sync

## Project Overview

PowerShell-based sync tool that fetches employee data from HiBob (HRIS) and syncs profile pictures to Microsoft Teams (Entra ID). Runs as a Jenkins pipeline.

## Commands

### Running Tests

```bash
# Run all tests
pwsh -Command "Invoke-Pester ./tests/"

# Run single test file
pwsh -Command "Invoke-Pester ./tests/Sync-HiBobTeams.Tests.ps1"

# Run single test by name
pwsh -Command "Invoke-Pester ./tests/Sync-HiBobTeams.Tests.ps1 -TestName 'Should NOT call HiBob API in dry-run mode'"

# Run with coverage
pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"
```

### Running the Scripts

```bash
# Dry-run mode (safe, no API calls)
pwsh -File ./Sync-HiBobTeams.ps1

# Production run (requires env vars)
HIBOB_TOKEN="Bearer xxx" TEAMS_WEBHOOK_URL="https://..." pwsh -File ./Sync-HiBobTeams.ps1

# Alternative entry point
pwsh -File ./src/powershell/Invoke-Sync.ps1 -DryRun
```

### Linting

This project uses **PSScriptAnalyzer** for linting:

```bash
# Install if needed
pwsh -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser"

# Run analyzer
pwsh -Command "Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error"
```

## Code Style Guidelines

### General Principles

- Use **PowerShell Core** (pwsh 7.x) - not Windows PowerShell 5.1
- Use **strict mode**: `Set-StrictMode -Version Latest`
- Use `-ErrorAction Stop` for critical operations; use `-ErrorAction SilentlyContinue` for optional operations
- Always use `$PSScriptRoot` for relative paths in modules

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Functions | Verb-Noun (PascalCase) | `Get-HiBobNewHires`, `Send-TeamsNotification` |
| Variables | PascalCase or $camelCase | `$HiBobToken`, `$Employees` |
| Modules | Noun.psm1 | `HiBob.psm1`, `Teams.psm1` |
| Tests | *.Tests.ps1 | `Sync-HiBobTeams.Tests.ps1` |
| Parameters | PascalCase | `-Token`, `-ApiUrl` |

### Parameters

```powershell
function Example-Function {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $false)]
        [string]$ApiUrl = "https://api.hibob.com/v1",

        [switch]$DryRun  # Boolean switches use [switch]
    )
}
```

### Imports

```powershell
# Always use -Force when importing modules
Import-Module -Force "$PSScriptRoot/Modules/HiBob.psm1"

# Export functions at end of module
Export-ModuleMember -Function Get-HiBobNewHires, Send-TeamsNotification
```

### Error Handling

```powershell
try {
    $Result = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body -ErrorAction Stop
}
catch {
    Write-Error "Failed to fetch from HiBob: $_"
    throw  # Re-throw to preserve stack trace
}
finally {
    # Cleanup if needed
    if ($TempFile) { Remove-Item $TempFile -Force }
}
```

### Logging

Use `Write-Host` with colors for user-facing output:

```powershell
Write-Host "Processing..." -ForegroundColor Green
Write-Host "Warning message" -ForegroundColor Yellow
Write-Error "Critical error"
```

For structured logging in the src/ module, use the custom `Write-Log` function:

```powershell
Write-Log "INFO" "Context" "Message"
Write-Log "ERROR" "Service" "Failed: $($_.Exception.Message)"
```

### API Calls

- Use `Invoke-RestMethod` for REST APIs returning JSON
- Use `Invoke-WebRequest` for downloading files (avatars)
- Always set `-ContentType "application/json"` for JSON APIs
- Use descriptive variable names: `$Headers`, `$Body`, `$Response`

### Testing

Use **Pester 5.x** with the following patterns:

```powershell
BeforeAll {
    $Script:ModulesPath = "$PSScriptRoot/../Modules"
}

Describe "Module Tests" {
    It "Should accept required parameters" {
        Import-Module "$Script:ModulesPath/HiBob.psm1" -Force
        $Result = Get-HiBobNewHires -Token "test" -ApiUrl "test" -DryRun

        $Result | Should -Not -BeNullOrEmpty
    }

    It "Should NOT call API in dry-run mode" {
        Mock Invoke-RestMethod { } -ParameterFilter { $Uri -match 'hibob' }

        Get-HiBobNewHires -Token "test" -ApiUrl "test" -DryRun

        Should -Invoke Invoke-RestMethod -Times 0
    }
}
```

### Environment Variables

- Required env vars: `HIBOB_TOKEN`, `ENTRAID_CLIENT_ID`, `ENTRAID_CLIENT_SECRET`, `ENTRAID_TENANT_ID`
- Optional env vars: `HIBOB_API_URL`, `DRY_RUN`, `DEBUG_MODE`
- Check with: `if (-not $env:VAR_NAME) { Write-Error "Missing..."; exit 1 }`

### Credential Handling

- Never hardcode credentials - use Jenkins credentials
- Pass credentials via environment variables injected by Jenkins pipeline
- Use `credentials('credential-id')` in Jenkinsfile

## File Structure

```
HiBobTeamsSync/
├── Sync-HiBobTeams.ps1           # Legacy entry point
├── Modules/
│   ├── HiBob.psm1               # HiBob API module
│   └── Teams.psm1               # Teams API module
├── src/powershell/
│   ├── Invoke-Sync.ps1          # Main entry point
│   └── HiBobSync.psm1           # Sync module with Graph SDK
├── tests/
│   ├── Sync-HiBobTeams.Tests.ps1
│   ├── helpers/TestHelpers.psm1
│   ├── mocks/
│   └── fixtures/
└── HiBobTeamsSync.groovy        # Jenkins pipeline
```

## Secrets & Security

- Never commit secrets, tokens, or credentials
- Add `*.env`, `credentials.json`, `*.key`, `*.pfx` to .gitignore
- Use Jenkins credentials for secrets injection
- Never log sensitive data (tokens, passwords)

## Common Patterns

### Module Template

```powershell
function Verb-Noun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredParam,

        [string]$OptionalParam = "default"
    )

    # Validate inputs
    if (-not $RequiredParam) {
        throw "RequiredParam is required"
    }

    # Main logic
    try {
        # API call
    }
    catch {
        Write-Error "Failed: $_"
        throw
    }
}

Export-ModuleMember -Function Verb-Noun
```

### Script with Parameter Validation

```powershell
param(
    [int]$DaysLookback = 7
)

# Env var validation
if (-not $env:HIBOB_TOKEN) {
    Write-Error "Missing required environment variable: HIBOB_TOKEN"
    exit 1
}

# Main logic
# ...
```

## Jenkins Integration

The pipeline accepts these parameters:
- `TEST_USER_EMAIL` - Single email for targeted testing
- `DRY_RUN` - Log changes without writing (default: true)
- `SYNC_AVATARS` - Toggle avatar sync
- `DEBUG_MODE` - Verbose logging
- `MAX_USERS` - Safety limit for processing
