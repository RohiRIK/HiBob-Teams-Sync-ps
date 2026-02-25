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
| **TEST_USER_EMAIL** | Single email for testing |
| **DRY_RUN** | Logs changes without writing |
| **SYNC_AVATARS** | Toggle avatar sync on/off |
| **DEBUG_MODE** | Verbose logging |

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
├── HiBobTeamsSync.groovy        # Standalone Jenkins pipeline
├── Sync-HiBobTeams.ps1          # Legacy sync script
├── Modules/
│   ├── HiBob.psm1               # HiBob API module
│   └── Teams.psm1               # Teams API module
├── src/
│   ├── Sync-HiBobToTeams.ps1    # Another sync script
│   └── powershell/
│       ├── Invoke-Sync.ps1      # Main entry point
│       └── HiBobSync.psm1       # Sync module (functions)
├── tests/
│   ├── Sync-HiBobTeams.Tests.ps1
│   ├── helpers/
│   │   └── TestHelpers.psm1
│   ├── mocks/
│   │   ├── Mock-HiBobApi.Tests.ps1
│   │   └── Mock-TeamsWebhook.Tests.ps1
│   └── fixtures/
│       ├── 0-newhires.json
│       └── 5-newhires.json
Jenkinsfile                     # Main Jenkins pipeline
```
