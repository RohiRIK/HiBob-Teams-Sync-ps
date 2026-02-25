# Technical Design: HiBob to Teams Profile Sync

## 1. Overview
This automation ensures that employee profile pictures in Microsoft Teams (Entra ID) match their official photos in HiBob (HRIS). It runs nightly via Jenkins.

## 2. API Strategy

### Source: HiBob
*   **Endpoint:** `GET https://api.hibob.com/v1/avatars/{employeeId}`
*   **Method:** REST API
*   **Authentication:** Custom Token header `Authorization: {BOB_TOKEN}`
*   **Response:** JSON containing the *URL* of the avatar.
    ```json
    { "avatarUrl": "https://..." }
    ```

### Sink: Microsoft Graph (Teams/Exchange)
*   **Endpoint:** `PUT https://graph.microsoft.com/v1.0/users/{userPrincipalName}/photo/$value`
*   **Method:** REST API
*   **Authentication:** OAuth2 Client Credentials (Bearer Token).
*   **Body:** Binary Image Data (Blob/Buffer).
*   **Headers:**
    *   `Authorization: Bearer {GRAPH_TOKEN}`
    *   `Content-Type: image/jpeg`
*   **Limits:** Max 4MB file size.

## 3. Implementation Logic (Bun/TypeScript)

```typescript
// 1. Get Avatar URL from Bob
const bobRes = await fetch(`https://api.hibob.com/v1/avatars/${empId}`, {
  headers: { 'Authorization': process.env.HIBOB_TOKEN }
});
const { avatarUrl } = await bobRes.json();

// 2. Stream Binary to Graph
if (avatarUrl) {
    const imageRes = await fetch(avatarUrl);
    const imageBlob = await imageRes.blob();

    await fetch(`https://graph.microsoft.com/v1.0/users/${upn}/photo/$value`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${GRAPH_TOKEN}`,
        'Content-Type': 'image/jpeg'
      },
      body: imageBlob
    });
}
```

## 4. Operational Flow

### Polyglot Execution
The system is designed to be engine-agnostic. The `Jenkinsfile` routes execution to either the TypeScript or PowerShell entry point based on user input. Both implementations share the same logic patterns for configuration and error handling.

### Targeted Testing (Safe Deployment)
To prevent accidental organization-wide changes, the automation supports a `TEST_USER_EMAIL` parameter.
*   If provided, the script filters the internal user list to match only that specific email.
*   If left empty, a full organization sync is performed.

### Logging & Troubleshooting
Both engines utilize a structured logging utility:
*   **TypeScript:** `logger.ts` outputs ISO-8601 timestamped JSON-ready logs.
*   **PowerShell:** `Write-Log` (internal to `HiBobSync.psm1`) ensures color-coded, timestamped console output.
*   All logs include a **[Context]** tag (e.g., `[GraphService]`) to quickly identify where an error occurred.

## 5. Infrastructure & Constraints
*   **Runtime:** Bun + TypeScript (Native fetch, high performance).
*   **Orchestration:** Jenkins Pipeline (Nightly Schedule).
*   **Secrets:** All tokens (HiBob, Azure App) managed via Jenkins Credentials Binding.
*   **Azure Scope:** `User.ReadWrite.All` or `ProfilePhoto.ReadWrite.All`.

## 5. Security & Sovereignty
By utilizing a direct Bun -> API pipeline on Jenkins, we eliminate the need for third-party sync engines, maintain absolute data sovereignty, and secure all credentials within the Jenkins Vault.
