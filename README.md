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
│ Fetch Employees    │  POST /v1/people/search
│ from HiBob         │
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
│ Skip User          │    │ Upload to Teams     │  PUT /users/{id}/photo
└─────────────────────┘    └─────────────────────┘
                                    │
                                    ▼
                           ┌─────────────────────┐
                           │       End           │
                           └─────────────────────┘
```

## ⚙️ Technical Flow

### 1. Fetch Employees
```
GET https://api.hibob.com/v1/people/search
Authorization: {HIBOB_TOKEN}
```

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
