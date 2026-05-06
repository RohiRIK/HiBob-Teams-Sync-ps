# Technical Design: HiBob to Teams Profile Sync

## 1. Overview

This automation synchronizes employee profile pictures from HiBob (HRIS) to Microsoft Teams (Entra ID). It is implemented in PowerShell Core and runs as a scheduled Jenkins pipeline on Linux agents.

## 2. File Structure

```
HiBobTeamsSync/
├── HiBobTeamsSync.groovy          # Jenkins pipeline definition
├── src/powershell/
│   ├── Invoke-Sync.ps1            # Entry point — orchestrates the sync run
│   └── HiBobSync.psm1             # Module — all service and sync logic
└── tests/
    ├── HiBobSync.Tests.ps1
    └── helpers/TestHelpers.psm1
```

`Invoke-Sync.ps1` is a thin orchestrator: it validates environment variables, authenticates to Graph, and delegates all sync work to `Invoke-EmployeeSync` in `HiBobSync.psm1`.

## 3. API Strategy

### Source: HiBob

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Employee search | `POST` | `https://api.hibob.com/v1/people/search` |
| Avatar metadata | `GET` | `https://api.hibob.com/v1/avatars/{employeeId}` |

- **Authentication:** `Authorization: {HIBOB_TOKEN}` header (custom token format, not Bearer).
- **Pagination:** Cursor-based. Each request sends `pagination.limit = 100`. The response includes `response_metadata.next_cursor` when more pages exist. Fetching continues until `next_cursor` is absent.

### Sink: Microsoft Graph

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Upload photo | `PUT` | `https://graph.microsoft.com/v1.0/users/{email}/photo/$value` |
| Download photo | `GET` | `https://graph.microsoft.com/v1.0/users/{email}/photo/$value` |

- **Authentication:** OAuth2 Client Credentials via the `Microsoft.Graph` PowerShell module. `Connect-MgGraph` is called with `-ClientSecretCredential` (a `PSCredential` object), not the deprecated `-Secret` parameter.
- **File size limit:** 4 MB maximum per upload.

## 4. Module Functions

### `Write-Log`

Structured logger. Outputs `[timestamp] [LEVEL] [Context] Message` to the console with color coding (white/yellow/red).

### `Invoke-WithRetry`

Wraps a scriptblock with retry logic.

- **Transient errors (retried):** HTTP 429, HTTP 5xx, network errors (no status code).
- **Fast failure:** Any other 4xx error is not retried; the exception is re-thrown immediately.
- **Backoff:** Exponential — waits `2^(attempt-1)` seconds between retries.
- **Rate limiting:** On HTTP 429, respects the `Retry-After` response header if present, using whichever wait time is longer.
- **Security:** Bearer and Basic auth tokens are redacted from all retry log messages before output.

### `Get-HiBobEmployees`

Fetches all active employees from HiBob using cursor-based pagination (100 per page). Returns a flat array of employee objects. Each object includes at minimum `id` and `email`.

### `Get-HiBobAvatar`

Fetches the avatar URL for a single employee by ID. Returns `$null` on any error (missing avatar is not a fatal condition).

### `Connect-ToGraph`

Authenticates to Microsoft Graph using client credentials:

```powershell
$SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$ClientCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecureSecret
Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientCredential -NoWelcome -ErrorAction Stop
```

### `Set-TeamsPhoto`

Handles the full photo update lifecycle for a single user. Returns a string result token:

| Return value | Meaning |
|---|---|
| `'uploaded'` | Photo was downloaded, validated, and uploaded to Graph. |
| `'unchanged'` | MD5 hash of new photo matches current Graph photo — upload skipped. |
| `'failed'` | Download failed, file was empty, file exceeded 4 MB, or Graph upload failed. |
| `'dry-run'` | Dry run mode — no action taken. |

Steps performed (live run):

1. Download avatar from HiBob CDN via `Invoke-WebRequest` to a temp file.
2. Validate file size: reject empty files (0 bytes) and files larger than 4 MB.
3. Download current Graph photo to a second temp file via `Get-MgUserPhotoContent`.
4. Compare MD5 hashes of both files. Skip upload if identical.
5. Upload new photo via `Set-MgUserPhotoContent` wrapped in `Invoke-WithRetry`.
6. Clean up both temp files in a `finally` block regardless of outcome.

### `Invoke-EmployeeSync`

Iterates over the employee list and calls `Get-HiBobAvatar` and `Set-TeamsPhoto` for each. Applies `MaxUsers` truncation before the loop if set. Returns a summary hashtable:

```powershell
@{
    Uploaded  = <int>   # Photos successfully uploaded
    Unchanged = <int>   # Photos skipped (hash match)
    Failed    = <int>   # Errors during download or upload
    NoAvatar  = <int>   # Employees with no avatar URL in HiBob
    NoEmail   = <int>   # Employees with no email address
}
```

## 5. Entry Point: `Invoke-Sync.ps1`

### Environment Validation

Runs at startup before any API calls:

1. `HIBOB_TOKEN` — always required.
2. `ENTRAID_CLIENT_ID`, `ENTRAID_CLIENT_SECRET`, `ENTRAID_TENANT_ID` — required only when `IS_DRY_RUN` is not `true`.
3. `MAX_USERS` — parsed safely with `[int]::TryParse`. Invalid values default to `0` (unlimited) with a warning. Negative values are clamped to `0`.

### Execution Flow

```
Validate env vars
    |
    v
Get-HiBobEmployees (paginated)
    |
    v
[Filter by TEST_USER_EMAIL if set]
    |
    v
Connect-ToGraph (skipped in dry run)
    |
    v
Invoke-EmployeeSync
    |
    v
Exit 0 (success) or Exit 2 (partial failure)
```

### Exit Codes

| Code | Jenkins result | Condition |
|------|---------------|-----------|
| `0` | SUCCESS | All users processed with no failures. |
| `2` | UNSTABLE | One or more users failed (`$Summary.Failed > 0`). |
| `1` | FAILURE | Missing required environment variable or employee fetch error. |
| other | FAILURE | Unhandled exception. |

## 6. Jenkins Pipeline: `HiBobTeamsSync.groovy`

### Pipeline Options

```groovy
options {
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timestamps()
}
```

- **Timeout:** 30 minutes. Prevents hung runs from blocking the agent.
- **Concurrency:** Disabled. Prevents two runs from writing to the same user simultaneously.
- **Log retention:** Last 30 builds kept.
- **Timestamps:** All console output is prefixed with timestamps.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TEST_USER_EMAIL` | string | `''` | Process only this user. Leave empty for all users. |
| `DRY_RUN` | boolean | `true` | Log intended changes without writing to Graph. |
| `MAX_USERS` | string | `'0'` | Cap on users processed. `0` = unlimited. |

### Environment Variables

Injected from Jenkins Credentials Vault:

| Variable | Credential ID | Notes |
|----------|--------------|-------|
| `HIBOB_TOKEN` | `hibob-api-token` | Always injected. |
| `ENTRAID_CLIENT_ID` | `azure-app-client-id` | Always injected; only used in live runs. |
| `ENTRAID_CLIENT_SECRET` | `azure-app-client-secret` | Always injected; only used in live runs. |
| `ENTRAID_TENANT_ID` | `azure-tenant-id` | Always injected; only used in live runs. |
| `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` | — | Set to `1` to avoid .NET globalization issues on minimal Linux agents. |

### Stage: Validate Environment

Runs a shell script before the sync:

1. **OS check:** Fails if `uname -s` is not `Linux`.
2. **PowerShell check:** Fails if `pwsh` is not on `PATH`.
3. **Version check:** Parses the major/minor version from `pwsh --version`. Emits a warning (does not fail) if the version is below 7.4.
4. **Graph module check:** Only for live runs (`DRY_RUN=false`). Fails if `Microsoft.Graph.Users` is not installed. Skipped entirely for dry runs.

### Stage: Execute Sync

Runs `pwsh -File src/powershell/Invoke-Sync.ps1` and captures the exit code:

- Exit `2` → sets `currentBuild.result = 'UNSTABLE'` with a descriptive message.
- Exit non-zero (other) → calls `error()` to mark the build as `FAILURE`.
- Exit `0` → sets description to "Sync completed successfully".

## 7. Configuration Reference

### Required Environment Variables

| Variable | Required when | Description |
|----------|--------------|-------------|
| `HIBOB_TOKEN` | Always | HiBob API token (full value including `Bearer` prefix if applicable). |
| `ENTRAID_CLIENT_ID` | Live runs | Entra ID application client ID. |
| `ENTRAID_CLIENT_SECRET` | Live runs | Entra ID application client secret. |
| `ENTRAID_TENANT_ID` | Live runs | Microsoft 365 tenant ID. |
| `IS_DRY_RUN` | Optional | Set to `true` to skip all writes. Defaults to `true` if unset. |
| `MAX_USERS` | Optional | Integer cap on users processed. `0` or unset = unlimited. |
| `TEST_USER_EMAIL` | Optional | Filter to a single user by email address. |

### Security

- All credentials are stored in the Jenkins Credentials Vault and injected as environment variables at runtime.
- Credentials are never logged. `Invoke-WithRetry` actively redacts Bearer and Basic auth tokens from error messages before writing to the console.
- No credentials are written to disk or committed to source control.
