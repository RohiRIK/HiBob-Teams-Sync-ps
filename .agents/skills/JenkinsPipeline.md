# JenkinsPipeline

AI agent skill for developing, modifying, and troubleshooting the **HiBob-Teams-Sync-ps** Jenkins pipeline.

## When to Use

Load this skill when the user says any of:

- "modify the pipeline"
- "add a Jenkins stage"
- "update credentials"
- "add a stage"
- "debug the pipeline"
- "add retry logic"
- "add a new parameter"
- "add a new API integration"
- "the pipeline is failing"
- "update the Jenkinsfile"

---

## Project Overview

**HiBob-Teams-Sync-ps** syncs employee profile pictures from HiBob (HRIS) to Microsoft Teams (Entra ID) via a Jenkins pipeline. The data flow is: HiBob API → download avatars → Microsoft Graph API → Teams user profiles.

**Entry point:** `src/powershell/Invoke-Sync.ps1` — thin orchestrator that validates env vars, fetches employees, authenticates Graph, and calls `Invoke-EmployeeSync`.

**Core module:** `src/powershell/HiBobSync.psm1` — all business logic: `Get-HiBobEmployees`, `Get-HiBobAvatar`, `Connect-ToGraph`, `Set-TeamsPhoto`, `Invoke-EmployeeSync`, `Invoke-WithRetry`, `Write-Log`.

**Jenkins pipeline:** `HiBobTeamsSync.groovy` — declarative pipeline that injects 4 secrets from Jenkins vault as env vars, maps pipeline parameters to PowerShell env vars, and handles exit code 2 as a partial-failure (UNSTABLE) signal.

**Tests:** `tests/HiBobSync.Tests.ps1` — Pester 5.x test suite covering all exported functions with `-ModuleName HiBobSync` mocks.

**Architecture reference:** `CLAUDE.md` (65 lines) — concise architecture summary. `AGENTS.md` (264 lines) — full coding guidelines.

---

## Jenkinsfile Conventions

### File Location

The pipeline file is **`HiBobTeamsSync.groovy`** — NOT `Jenkinsfile`. It uses the shared library / multibranch pattern where the filename matches the job name.

### Declarative Syntax Structure

```groovy
pipeline {
    agent any

    parameters { ... }   // Build parameters — user-configurable at run time
    options { ... }      // Pipeline-level guards
    environment { ... }  // Env vars injected for all stages
    stages { ... }       // Ordered execution stages
    post { ... }         // Always-run cleanup/notification
}
```

### `options {}` Block (from `HiBobTeamsSync.groovy` lines 10–14)

```groovy
options {
    timeout(time: 30, unit: 'MINUTES')      // Kill runaway builds
    disableConcurrentBuilds()               // Prevent overlapping syncs
    buildDiscarder(logRotator(numToKeepStr: '30'))  // Keep last 30 builds
}
```

**Rule:** Always include all three. `disableConcurrentBuilds()` is critical — concurrent runs would race on the same user set.

### `parameters {}` Block (from `HiBobTeamsSync.groovy` lines 4–8)

```groovy
parameters {
    string(name: 'TEST_USER_EMAIL', defaultValue: '', description: 'Enter a single email to test the sync safely on one user.')
    booleanParam(name: 'DRY_RUN', defaultValue: true, description: 'If checked, logs all intended changes without writing to Microsoft 365 or syncing avatars.')
    string(name: 'MAX_USERS', defaultValue: '0', description: 'Maximum number of users to process per run. Set to 0 for unlimited (default).')
}
```

**Rule:** `DRY_RUN` defaults to `true` — safe by default. New parameters follow the same `string`/`booleanParam` pattern with descriptive `description` fields.

### `credentials()` Pattern (from `HiBobTeamsSync.groovy` lines 17–20)

```groovy
environment {
    HIBOB_TOKEN           = credentials('hibob-api-token')
    ENTRAID_CLIENT_ID     = credentials('azure-app-client-id')
    ENTRAID_CLIENT_SECRET = credentials('azure-app-client-secret')
    ENTRAID_TENANT_ID     = credentials('azure-tenant-id')
    IS_DRY_RUN            = "${params.DRY_RUN}"
    MAX_USERS             = "${params.MAX_USERS}"
    TEST_USER_EMAIL       = "${params.TEST_USER_EMAIL}"
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
}
```

**Credential IDs** (Jenkins vault names):
| Env Var | Jenkins Credential ID |
|---|---|
| `HIBOB_TOKEN` | `hibob-api-token` |
| `ENTRAID_CLIENT_ID` | `azure-app-client-id` |
| `ENTRAID_CLIENT_SECRET` | `azure-app-client-secret` |
| `ENTRAID_TENANT_ID` | `azure-tenant-id` |

**Rule:** Credential IDs use descriptive kebab-case. Never hardcode values. `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'` is required for .NET globalization on Linux agents.

### Stage Structure

The pipeline has two stages (from `HiBobTeamsSync.groovy` lines 27–98):

1. **`Validate Environment`** — OS check (Linux only), PowerShell version check, Graph module check (live runs only)
2. **`Execute Sync`** — runs `Invoke-Sync.ps1` via `pwsh -File`, captures exit code with `returnStatus: true`

### `returnStatus: true` — Exit Code Handling (lines 84–93)

```groovy
def exitCode = sh(script: 'pwsh -File src/powershell/Invoke-Sync.ps1', returnStatus: true)
if (exitCode == 2) {
    currentBuild.result = 'UNSTABLE'
    currentBuild.description = "Partial failure — some users failed to sync"
} else if (exitCode != 0) {
    currentBuild.description = "Sync failed (exit code ${exitCode})"
    error("Sync failed with exit code ${exitCode}")
} else {
    currentBuild.description = "Sync completed successfully"
}
```

**Exit code contract:**
- `0` = full success
- `2` = partial failure (some users failed) → build marked UNSTABLE, not FAILED
- Any other non-zero = hard failure → `error()` throws, build FAILED

**Rule:** Always use `returnStatus: true` when calling PowerShell. Never use bare `sh('pwsh ...')` — it would fail the build on exit code 2.

### `post {}` Block (lines 100–104)

```groovy
post {
    always {
        echo "📝 Build completed."
    }
}
```

Extend with `success`, `failure`, `unstable` blocks for notifications (Teams webhook, email).

---

## PowerShell Module Conventions

### File Locations

```
src/powershell/
├── Invoke-Sync.ps1      # Entry point — thin orchestrator only
└── HiBobSync.psm1       # All business logic — functions + exports
```

### Module Import Pattern (from `Invoke-Sync.ps1` lines 11–12)

```powershell
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$ScriptDir/HiBobSync.psm1" -Force
```

**Rule:** Always `-Force` on import. Use `$MyInvocation.MyCommand.Path` (not `$PSScriptRoot`) in `.ps1` entry points; use `$PSScriptRoot` inside `.psm1` modules.

### `$ErrorActionPreference` (from `Invoke-Sync.ps1` line 9)

```powershell
$ErrorActionPreference = "Stop"
```

Set at the top of every `.ps1` script. Ensures unhandled errors terminate the script with a non-zero exit code.

### Verb-Noun Naming (from `HiBobSync.psm1`)

| Function | Purpose |
|---|---|
| `Get-HiBobEmployees` | Fetch active employees via `POST /v1/people/search` |
| `Get-HiBobAvatar` | Fetch avatar URL per employee |
| `Connect-ToGraph` | OAuth2 client credentials auth to Microsoft Graph |
| `Set-TeamsPhoto` | Download avatar + upload via Graph API |
| `Invoke-EmployeeSync` | Main loop — iterates employees, respects limits |
| `Invoke-WithRetry` | Retry helper with exponential backoff |
| `Write-Log` | Structured logging with severity and context tags |

### `Export-ModuleMember` (from `HiBobSync.psm1` line 230)

```powershell
Export-ModuleMember -Function Get-HiBobEmployees, Get-HiBobAvatar, Connect-ToGraph, Set-TeamsPhoto, Write-Log, Invoke-EmployeeSync
```

**Rule:** `Invoke-WithRetry` is intentionally NOT exported — it's a private helper. Only export functions that tests or callers need directly.

### `Write-Log` Structured Logging (from `HiBobSync.psm1` lines 4–18)

```powershell
Write-Log "INFO"  "HiBobService" "Fetching employees..."
Write-Log "WARN"  "Sync"         "⚠️ Limiting to $MaxUsers users"
Write-Log "ERROR" "GraphService" "❌ Failed: $($_.Exception.Message)"
```

Format: `[timestamp] [LEVEL] [Context] Message`

**Rule:** Use `Write-Log` for all output in `src/`. Use `Write-Host` with `-ForegroundColor` only in scripts outside the module. Never log raw exception objects — always use `$_.Exception.Message`.

### Error Handling Pattern (from `HiBobSync.psm1` lines 92–95)

```powershell
try {
    $Response = Invoke-WithRetry -OperationName "Get-HiBobEmployees" -Action {
        Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
    }
} catch {
    Write-Log "ERROR" "HiBobService" "Failed to fetch employees: $($_.Exception.Message)"
    throw  # Re-throw to preserve stack trace
}
```

**Rule:** Always `throw` after logging — never swallow exceptions in the module. The entry point (`Invoke-Sync.ps1`) decides the exit code.

---

## Testing Guide

### Framework: Pester 5.x

Run tests:
```bash
pwsh -Command "Invoke-Pester ./tests/"
pwsh -Command "Invoke-Pester ./tests/HiBobSync.Tests.ps1"
pwsh -Command "Invoke-Pester ./tests/HiBobSync.Tests.ps1 -FullNameFilter '*retry*'"
pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"
```

### `BeforeAll` Module Import (from `HiBobSync.Tests.ps1` lines 3–7)

```powershell
BeforeAll {
    $Script:ModulePath = "$PSScriptRoot/../src/powershell/HiBobSync.psm1"
    Import-Module $Script:ModulePath -Force
    Import-Module "$PSScriptRoot/helpers/TestHelpers.psm1" -Force
}
```

**Rule:** Import in `BeforeAll` at the top of the file. Use `$Script:` scope for variables shared across `Describe` blocks.

### `-ModuleName HiBobSync` on All Mocks

```powershell
Mock Get-HiBobAvatar { return 'https://fake.url/avatar.jpg' } -ModuleName HiBobSync
Mock Set-TeamsPhoto  { return 'dry-run' }                    -ModuleName HiBobSync
Mock Invoke-RestMethod { ... }                               -ModuleName HiBobSync
```

**Rule:** Every `Mock` targeting a function called *inside* `HiBobSync.psm1` MUST include `-ModuleName HiBobSync`. Without it, the mock intercepts the caller's scope, not the module's scope, and the real function runs.

### Run Execution Inside `It` Blocks (from `HiBobSync.Tests.ps1` lines 351–358)

```powershell
It "Should process only MaxUsers employees when limit is set" {
    Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
    Mock Set-TeamsPhoto { return 'dry-run' } -ModuleName HiBobSync

    $Employees = New-MockEmployeeList -Count 10
    $null = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 3 -DryRun

    Should -Invoke Get-HiBobAvatar -Times 3 -Exactly -ModuleName HiBobSync
}
```

**Rule:** Call the function under test INSIDE the `It` block, not in `BeforeAll` or `BeforeEach`. `Should -Invoke` counts reset per `It` block.

### `Invoke-EmployeeSync` as Testable Seam

`Invoke-EmployeeSync` (in `HiBobSync.psm1` lines 189–228) is the primary testable seam. It accepts `$Employees`, `$Token`, `$MaxUsers`, and `[switch]$DryRun` — all mockable. Test it by mocking `Get-HiBobAvatar` and `Set-TeamsPhoto` and asserting on the returned `$Summary` hashtable.

### Test Fixtures

Fixtures live in `tests/fixtures/` (JSON files with 0 and 5 employee datasets). The `TestHelpers.psm1` module provides `New-MockEmployeeList -Count N` for generating in-memory employee objects.

### `Should -Invoke` Assertion Pattern

```powershell
Should -Invoke Get-HiBobAvatar -Times 5 -Exactly -ModuleName HiBobSync
Should -Invoke Set-MgUserPhotoContent -Times 0 -ModuleName HiBobSync
Should -Invoke Invoke-RestMethod -Times 1 -ModuleName HiBobSync -ParameterFilter {
    $Uri -eq "https://api.hibob.com/v1/people/search" -and $Method -eq "Post"
}
```

---

## Credential & Environment Variable Guide

### Required Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `HIBOB_TOKEN` | Jenkins: `hibob-api-token` | HiBob API Bearer token |
| `ENTRAID_CLIENT_ID` | Jenkins: `azure-app-client-id` | Azure app registration client ID |
| `ENTRAID_CLIENT_SECRET` | Jenkins: `azure-app-client-secret` | Azure app registration client secret |
| `ENTRAID_TENANT_ID` | Jenkins: `azure-tenant-id` | Azure/Entra tenant ID |

### Optional Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `IS_DRY_RUN` | `true` | Skip all writes; log only |
| `MAX_USERS` | `0` (unlimited) | Cap users processed per run |
| `TEST_USER_EMAIL` | `""` | Target a single user for testing |

### How Secrets Flow: Jenkins Vault → PowerShell

1. **Jenkins vault** stores secrets as credential objects (type: Secret Text or Username/Password)
2. **`HiBobTeamsSync.groovy` `environment {}` block** maps credential IDs to env var names via `credentials('id')`
3. **Jenkins injects** env vars into the shell environment before running `sh()`
4. **`Invoke-Sync.ps1`** reads them via `$env:HIBOB_TOKEN`, `$env:ENTRAID_CLIENT_ID`, etc.
5. **`HiBobSync.psm1` functions** receive them as parameters (e.g., `-Token $env:HIBOB_TOKEN`)

**Validation pattern** (from `Invoke-Sync.ps1` lines 17–31):
```powershell
# Always required
if (-not $env:HIBOB_TOKEN) {
    Write-Log "ERROR" $CTX "Missing required environment variable: HIBOB_TOKEN"
    exit 1
}

# Graph credentials — required for live runs only
if (-not $DryRun) {
    $GraphVars = @('ENTRAID_CLIENT_ID', 'ENTRAID_CLIENT_SECRET', 'ENTRAID_TENANT_ID')
    foreach ($Var in $GraphVars) {
        if (-not (Get-Item "env:$Var" -ErrorAction SilentlyContinue)) {
            Write-Log "ERROR" $CTX "Missing required environment variable for live run: $Var"
            exit 1
        }
    }
}
```

### Secrets Scanning

`.pre-commit-config.yaml` runs **TruffleHog** on every commit:
```yaml
- id: trufflehog
  entry: trufflehog git file://. --since-commit HEAD --only-verified --fail
  stages: [pre-commit]
```

Never commit tokens, passwords, or credential values. Use placeholder names in code (e.g., `credentials('hibob-api-token')`).

---

## Common Tasks

### 1. Add a New Pipeline Parameter

**Where:** `HiBobTeamsSync.groovy` `parameters {}` block (lines 4–8).

**Steps:**
1. Add the parameter declaration:
   ```groovy
   // String parameter
   string(name: 'MY_PARAM', defaultValue: 'default', description: 'What this does.')
   // Boolean parameter
   booleanParam(name: 'MY_FLAG', defaultValue: false, description: 'Enable feature X.')
   ```
2. Map it to an env var in the `environment {}` block:
   ```groovy
   MY_PARAM = "${params.MY_PARAM}"
   MY_FLAG  = "${params.MY_FLAG}"
   ```
3. Read it in `Invoke-Sync.ps1`:
   ```powershell
   param (
       [string]$MyParam = $env:MY_PARAM
   )
   ```
4. Pass it to the relevant function in `HiBobSync.psm1`.

**Validation:** If the parameter is required, add a check in `Invoke-Sync.ps1` following the existing pattern (lines 17–31).

---

### 2. Add a New API Integration

**Steps:**
1. **Add function to `src/powershell/HiBobSync.psm1`:**
   ```powershell
   function Get-NewServiceData {
       [CmdletBinding()]
       param (
           [Parameter(Mandatory = $true)]
           [string]$Token,
           [string]$ApiUrl = "https://api.newservice.com/v1"
       )
       try {
           $Headers = @{ "Authorization" = "Bearer $Token" }
           $Response = Invoke-WithRetry -OperationName "Get-NewServiceData" -Action {
               Invoke-RestMethod -Uri "$ApiUrl/endpoint" -Headers $Headers -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
           }
           return $Response.data
       } catch {
           Write-Log "ERROR" "NewService" "Failed: $($_.Exception.Message)"
           throw
       }
   }
   ```
2. **Export it** — add to `Export-ModuleMember` at the bottom of `HiBobSync.psm1` (line 230).
3. **Add credential** to Jenkins vault and map it in `HiBobTeamsSync.groovy` `environment {}` block.
4. **Add mock in `tests/HiBobSync.Tests.ps1`:**
   ```powershell
   Mock Get-NewServiceData { return @([PSCustomObject]@{ id = "item-1" }) } -ModuleName HiBobSync
   ```
5. **Call from `Invoke-Sync.ps1`** after the existing fetch steps.

---

### 3. Add Retry Logic

Use `Invoke-WithRetry` from `HiBobSync.psm1` (lines 20–60). It handles:
- Exponential backoff: `2^(attempt-1)` seconds
- Retries on: network errors (no status), HTTP 429 (rate limit), HTTP 5xx (server errors)
- Immediate throw on: HTTP 4xx (except 429) — non-retryable
- Token redaction in log messages

**Pattern:**
```powershell
$Result = Invoke-WithRetry -OperationName "Describe-What-You-Are-Doing" -Action {
    Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body -ErrorAction Stop
}
```

**Parameters:**
- `-Action [scriptblock]` — the operation to retry (required)
- `-MaxRetries [int]` — default 3
- `-OperationName [string]` — used in log messages (required for clarity)

**Do NOT** wrap `Invoke-WithRetry` calls in another `try/catch` unless you need to handle the final failure differently. Let it throw — the caller (`Invoke-Sync.ps1`) handles exit codes.

---

### 4. Add a Test Case

**Template** (Pester 5.x with `-ModuleName HiBobSync`):

```powershell
Describe "FunctionName" {
    It "Should <describe expected behavior>" {
        # 1. Arrange — set up mocks
        Mock Get-HiBobAvatar { return "https://cdn.hibob.com/avatar.jpg" } -ModuleName HiBobSync
        Mock Set-TeamsPhoto  { return 'uploaded' }                         -ModuleName HiBobSync

        # 2. Act — call the function under test
        $Employees = @(
            [PSCustomObject]@{ id = "emp-1"; email = "user1@company.com" }
        )
        $Summary = Invoke-EmployeeSync -Employees $Employees -Token "test-token" -MaxUsers 0 -DryRun

        # 3. Assert — verify behavior
        $Summary.Uploaded | Should -Be 1
        Should -Invoke Get-HiBobAvatar -Times 1 -Exactly -ModuleName HiBobSync
    }
}
```

**Checklist for every new test:**
- [ ] `Mock` uses `-ModuleName HiBobSync` for all internal function mocks
- [ ] Function call is inside the `It` block (not `BeforeAll`)
- [ ] `Should -Invoke` uses `-ModuleName HiBobSync`
- [ ] Use `New-MockEmployeeList -Count N` (from `TestHelpers.psm1`) for employee fixtures
- [ ] Mock `Start-Sleep` when testing retry logic to avoid slow tests
- [ ] Mock `Write-Host` when testing log output assertions

---

## Troubleshooting Reference

| Symptom | Likely Cause | Fix |
|---|---|---|
| Build FAILED on exit code 2 | Missing `returnStatus: true` in `sh()` call | Use `def exitCode = sh(script: '...', returnStatus: true)` |
| Mock not intercepting calls | Missing `-ModuleName HiBobSync` on `Mock` | Add `-ModuleName HiBobSync` to every `Mock` |
| `Should -Invoke` count is 0 | Function called in `BeforeAll` not `It` | Move function call inside the `It` block |
| Graph module not found | `Microsoft.Graph.Users` not installed on agent | Install: `pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser"` |
| `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` error | Missing env var on Linux agent | Already set in `HiBobTeamsSync.groovy` line 24 — verify it's present |
| Partial failures not UNSTABLE | Exit code 2 not handled | Check `Invoke-Sync.ps1` line 75–77 and `HiBobTeamsSync.groovy` lines 85–87 |
| Credentials not injected | Wrong credential ID in `credentials()` | Verify ID matches Jenkins vault entry exactly (kebab-case) |

**Full troubleshooting guide:** `docs/troubleshooting.md`
**Jenkins setup guide:** `docs/jenkins-setup.md`
