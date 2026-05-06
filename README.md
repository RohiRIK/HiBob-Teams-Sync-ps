# HiBob to Teams Profile Sync (PowerShell)

## 🎯 Goal
Automatically synchronize employee profile pictures from **HiBob** (HRIS) to **Microsoft Teams** (Entra ID).

## 🏗️ Architecture
*   **Runtime:** PowerShell Core
*   **Orchestrator:** Jenkins Pipeline
*   **Secrets Management:** Jenkins Credentials

## 🔄 Flow

```
┌─────────────────────┐
│   Jenkins Pipeline │──▶
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│ Validate Env Vars  │  HIBOB_TOKEN, ENTRAID_*, etc.
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│ Fetch Employees    │  POST /v1/people/search
│ from HiBob         │  (cursor-based pagination)
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│ Get Avatar URL     │  GET /v1/avatars/{id}
│ for each employee  │
└─────────────────────┘
          │
          ▼
    ┌─────────────┐
    │ Avatar      │──Yes──▶ ┌─────────────────────┐
    │ Exists?     │         │ Download Avatar     │
    └─────────────┘         │ Image               │
          │                  └─────────────────────┘
          │No                        │
          ▼                         ▼
┌─────────────────────┐    ┌─────────────────────┐
│ Skip (No Avatar)   │    │ Validate Size       │  Reject empty or >4MB
└─────────────────────┘    └─────────────────────┘
                                    │
                              ┌─────┴─────┐
                              │ Valid?    │
                              └─────┬─────┘
                           No ──────┘──────── Yes
                           │                  │
                           ▼                  ▼
                  ┌──────────────┐   ┌─────────────────────┐
                  │ Skip (Size) │   │ Compare with        │  MD5 hash vs
                  └──────────────┘   │ Current Photo       │  current Graph photo
                                     └─────────────────────┘
                                               │
                                     ┌─────────┴──────────┐
                                     │ Changed?           │
                                     └─────────┬──────────┘
                                  No ──────────┘──────────── Yes
                                  │                          │
                                  ▼                          ▼
                         ┌──────────────────┐    ┌─────────────────────┐
                         │ Skip (Unchanged) │    │ Upload to Teams     │  PUT /users/{id}/photo
                         └──────────────────┘    └─────────────────────┘
                                                           │
                                                           ▼
                                                  ┌─────────────────────┐
                                                  │ Summary Report      │
                                                  │ Uploaded/Unchanged/ │
                                                  │ Failed/Skipped      │
                                                  └─────────────────────┘
```

## ✨ Features

*   **Cursor-based pagination** — fetches all employees from large tenants in pages of 100, following `next_cursor` until exhausted.
*   **Smart retry with exponential backoff** — retries transient failures (HTTP 429, 5xx, network errors) up to 3 times; respects `Retry-After` headers on rate-limit responses. Non-retryable errors (4xx) fail immediately.
*   **Image validation** — rejects empty files and avatars exceeding the 4 MB Graph API limit before attempting an upload.
*   **Change detection** — downloads the current Teams photo and compares MD5 hashes; skips the upload if the photo is already up to date.
*   **Summary reporting** — logs a final count of `Uploaded / Unchanged / Failed / NoAvatar / NoEmail` after every run.
*   **Environment validation** — checks all required env vars before starting; Graph credentials are only required for live (non-dry-run) runs.
*   **Partial failure handling** — exits with code `2` when any user fails, signalling Jenkins to mark the build `UNSTABLE` rather than `FAILURE`.

## ⚙️ Technical Flow

### 1. Fetch Employees
```
POST https://api.hibob.com/v1/people/search
Authorization: {HIBOB_TOKEN}
Content-Type: application/json

Body: { "showInactive": false, "pagination": { "limit": 100, "cursor": "<next_cursor>" } }
```
Pages are fetched in a loop until `response_metadata.next_cursor` is absent.

### 2. Get Avatar URL
```
GET https://api.hibob.com/v1/avatars/{employeeId}
```

### 3. Upload to Teams
```
PUT https://graph.microsoft.com/v1.0/users/{email}/photo/$value
```

## 🕹️ Jenkins Parameters

| Parameter | Description |
| :--- | :--- |
| **TEST_USER_EMAIL** | Single email for testing. Leave empty to process all users. |
| **DRY_RUN** | If checked, logs all intended changes without writing to Microsoft 365 or syncing avatars. Default: true. |
| **MAX_USERS** | Maximum number of users to process per run. Set to 0 for unlimited (default). |

## 🔐 Credentials (Jenkins Vault)

| Credential ID | Description |
| :--- | :--- |
| `hibob-api-token` | HiBob API key |
| `azure-app-client-id` | Entra ID Client ID |
| `azure-app-client-secret` | Entra ID Client Secret |
| `azure-tenant-id` | Microsoft 365 Tenant ID |

**Environment Variables (injected by Jenkins):**
- `HIBOB_TOKEN`
- `ENTRAID_CLIENT_ID`
- `ENTRAID_CLIENT_SECRET`
- `ENTRAID_TENANT_ID`

## 📁 File Structure

```
HiBobTeamsSync/
├── HiBobTeamsSync.groovy        # Jenkins pipeline
├── src/
│   └── powershell/
│       ├── Invoke-Sync.ps1      # Main entry point
│       └── HiBobSync.psm1       # Sync module (functions)
├── tests/
│   ├── HiBobSync.Tests.ps1      # Active module tests
│   ├── helpers/
│   │   └── TestHelpers.psm1
│   ├── mocks/
│   │   ├── Mock-HiBobApi.Tests.ps1
│   │   └── Mock-TeamsWebhook.Tests.ps1
│   └── fixtures/
│       ├── 0-newhires.json
│       └── 5-newhires.json
```

## 🚀 Jenkins Setup

For a full step-by-step guide on wiring this pipeline to a GitHub repository (plugins, credentials, job config, first run, scheduling), see:

👉 **[Jenkins Full Setup Guide](./docs/jenkins-setup.md)**

### Quick checklist

1. Install Jenkins plugins: **Pipeline**, **Git**, **Credentials Binding**
2. Install PowerShell Core (`pwsh`) on the Jenkins agent
3. Add 4 credentials to Jenkins vault (`hibob-api-token`, `azure-app-client-id`, `azure-app-client-secret`, `azure-tenant-id`)
4. Create a **Pipeline** job → **Pipeline script from SCM** → point to this repo → **Script Path:** `HiBobTeamsSync.groovy`
5. First run: `TEST_USER_EMAIL=your@email.com`, `DRY_RUN=true`, `MAX_USERS=1`

## 🔧 Troubleshooting

For errors during setup or runtime (Jenkins config, HiBob API, Azure/Graph, PowerShell), see:

👉 **[Troubleshooting Guide](./docs/troubleshooting.md)**
