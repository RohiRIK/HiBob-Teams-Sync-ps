# AGENTS.md - Agent Coding Guidelines for HiBob Teams Sync

## Project Overview

PowerShell-based sync tool that fetches employee data from HiBob (HRIS) and syncs profile pictures to Microsoft Teams (Entra ID). Runs as a Jenkins pipeline.

## Commands

### Running Tests

```bash
# Run all tests
pwsh -Command "Invoke-Pester ./tests/"

# Run single test file
pwsh -Command "Invoke-Pester ./tests/HiBobSync.Tests.ps1"

# Run single test by name
pwsh -Command "Invoke-Pester ./tests/HiBobSync.Tests.ps1 -FullNameFilter '*retry*'"

# Run with coverage
pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"
```

### Running the Scripts

```bash
# Dry-run mode (safe, no API calls)
IS_DRY_RUN=true pwsh -File ./src/powershell/Invoke-Sync.ps1

# Production run (requires env vars)
HIBOB_TOKEN="Bearer xxx" ENTRAID_CLIENT_ID="..." ENTRAID_CLIENT_SECRET="..." ENTRAID_TENANT_ID="..." IS_DRY_RUN=false pwsh -File ./src/powershell/Invoke-Sync.ps1

# With user limit
MAX_USERS=10 IS_DRY_RUN=true pwsh -File ./src/powershell/Invoke-Sync.ps1
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
| Functions | Verb-Noun (PascalCase) | `Get-HiBobEmployees`, `Invoke-EmployeeSync` |
| Variables | PascalCase or $camelCase | `$HiBobToken`, `$Employees` |
| Modules | Noun.psm1 | `HiBobSync.psm1` |
| Tests | *.Tests.ps1 | `HiBobSync.Tests.ps1` |
| Parameters | PascalCase | `-Token`, `-MaxUsers` |

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
Import-Module -Force "$PSScriptRoot/HiBobSync.psm1"

# Export functions at end of module
Export-ModuleMember -Function Get-HiBobEmployees, Invoke-EmployeeSync
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
- Wrap API calls with `Invoke-WithRetry` (private helper in HiBobSync.psm1) for transient failure resilience

### Testing

Use **Pester 5.x** with the following patterns:

```powershell
BeforeAll {
    $Script:ModulePath = "$PSScriptRoot/../src/powershell/HiBobSync.psm1"
    Import-Module $Script:ModulePath -Force
}

Describe "Module Tests" {
    It "Should call Get-HiBobAvatar exactly N times" {
        Mock Get-HiBobAvatar { return 'https://fake.url/avatar.jpg' } -ModuleName HiBobSync
        Mock Set-TeamsPhoto { } -ModuleName HiBobSync

        $Emps = @(1..5 | ForEach-Object { [PSCustomObject]@{ id="emp-$_"; email="user$_@test.com" } })
        Invoke-EmployeeSync -Employees $Emps -Token 'test' -MaxUsers 0 -DryRun

        Should -Invoke Get-HiBobAvatar -Times 5 -Exactly -ModuleName HiBobSync
    }
}
```

**Key testing rules:**
- Use `-ModuleName HiBobSync` for mocks when testing functions inside the module
- Run function execution INSIDE the `It` block (not `BeforeAll`) so `Should -Invoke` counts work
- Use `Invoke-EmployeeSync` as the testable seam — it's exported and mockable

### Environment Variables

- Required env vars: `HIBOB_TOKEN`, `ENTRAID_CLIENT_ID`, `ENTRAID_CLIENT_SECRET`, `ENTRAID_TENANT_ID`
- Optional env vars: `IS_DRY_RUN` (default: true), `MAX_USERS` (default: 0 = unlimited), `TEST_USER_EMAIL`
- Check with: `if (-not $env:VAR_NAME) { Write-Error "Missing..."; exit 1 }`

### Credential Handling

- Never hardcode credentials - use Jenkins credentials
- Pass credentials via environment variables injected by Jenkins pipeline
- Use `credentials('credential-id')` in Jenkinsfile

## File Structure

```
HiBobTeamsSync/
├── HiBobTeamsSync.groovy        # Jenkins pipeline
├── src/powershell/
│   ├── Invoke-Sync.ps1          # Main entry point (thin orchestrator)
│   └── HiBobSync.psm1           # Sync module with Graph SDK
├── tests/
│   ├── HiBobSync.Tests.ps1      # Active module tests
│   ├── helpers/TestHelpers.psm1
│   ├── mocks/
│   └── fixtures/
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
    [bool]$DryRun = ($env:IS_DRY_RUN -eq 'true')
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
- `TEST_USER_EMAIL` - Single email for targeted testing (leave empty for all users)
- `DRY_RUN` - Log all changes without writing to Microsoft 365 or syncing avatars (default: true)
- `MAX_USERS` - Maximum number of users to process per run. 0 = unlimited (default: 0)

## Jenkins Setup

For a full step-by-step guide on setting up the pipeline in Jenkins (plugins, credentials, GitHub connection, first run, scheduling), see:

👉 **[docs/jenkins-setup.md](./docs/jenkins-setup.md)**

## Troubleshooting

For errors during setup or runtime (Jenkins config, HiBob API, Azure/Graph, PowerShell), see:

👉 **[docs/troubleshooting.md](./docs/troubleshooting.md)**
