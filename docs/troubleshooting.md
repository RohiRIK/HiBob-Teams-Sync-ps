# Troubleshooting Guide — HiBob Teams Photo Sync

Use this guide when something goes wrong. Errors are grouped by where they appear so you can jump straight to the right section.

---

## How to Read the Console Output

Every time a Jenkins build runs, it produces a log. That's your first stop.

1. Open Jenkins → click your job → click the build number in **Build History** (e.g. `#5`)
2. Click **Console Output** in the left sidebar
3. Scroll to the bottom — errors almost always appear at the end

The script uses structured log lines that look like this:

```
[2026-03-01T08:00:01.000Z] [INFO]  [HiBobService] Fetching employees...
[2026-03-01T08:00:02.000Z] [ERROR] [GraphService] ❌ Authentication Failed: ...
```

The second bracket is the severity (`INFO`, `WARN`, `ERROR`). The third is the component where the error came from. Search for `[ERROR]` first.

---

## Section 1 — Jenkins Setup Errors

These happen before the PowerShell script even runs — usually a misconfiguration in Jenkins itself.

---

### "Missing required environment variable for live run: ENTRAID_CLIENT_SECRET"

**Full error in console:**
```
[ERROR] [Main] Missing required environment variable for live run: ENTRAID_CLIENT_SECRET
```

**Why:** When `DRY_RUN` is unchecked, the script now validates all three Graph credentials (`ENTRAID_CLIENT_ID`, `ENTRAID_CLIENT_SECRET`, `ENTRAID_TENANT_ID`) before starting — not just when the Graph call is made. This means a missing credential fails fast at startup rather than partway through the sync.

**Fix:**
1. Go to **Manage Jenkins → Credentials → System → Global credentials**
2. Confirm all four credentials exist with the exact IDs listed in the table below
3. If a credential is missing, add it — see the "Missing required environment variable: HIBOB_TOKEN" entry below for the full credential ID table

---

### "Missing required environment variable: HIBOB_TOKEN"

**Full error in console:**
```
Write-Error: Missing required environment variable: HIBOB_TOKEN
```

**Why:** The credential stored in Jenkins has a different ID than what the pipeline expects.

**Fix:**
1. Go to **Manage Jenkins → Credentials → System → Global credentials**
2. Find the credential holding your HiBob token
3. Click the **⚙ (gear)** icon → **Update**
4. Check the **ID** field — it must be exactly: `hibob-api-token`
   - All lowercase, hyphen-separated, no spaces
5. If the ID is wrong, you cannot edit it in place — delete the credential and re-add it with the correct ID (the Secret value stays the same)

The same applies to the other three credentials:

| Expected ID | What it holds |
|-------------|---------------|
| `hibob-api-token` | HiBob API token |
| `azure-app-client-id` | Entra ID client ID |
| `azure-app-client-secret` | Entra ID client secret |
| `azure-tenant-id` | Entra ID tenant ID |

---

### "ERROR: This pipeline requires Linux"

**Full error in console:**
```
ERROR: This pipeline requires Linux. Detected OS: Darwin
```

**Why:** The Validate Environment stage checks `uname -s` and requires the result to be `Linux`. The pipeline will not run on macOS or Windows agents.

**Fix:** Assign the job to a Linux agent. In Jenkins, either:
- Set the agent label in the job configuration to a node that runs Linux
- Or provision a Linux agent and connect it to Jenkins before running the job

---

### "ERROR: PowerShell Core (pwsh) is not installed"

**Full error in console:**
```
ERROR: PowerShell Core (pwsh) is not installed on this agent.
Install: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux
```

**Why:** The `pwsh` binary is not on the PATH of the Jenkins agent.

**Fix — Ubuntu/Debian:**
```bash
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
pwsh --version
```

After installing, restart the Jenkins agent service so it picks up the new PATH:
```bash
sudo systemctl restart jenkins   # Linux with systemd
```

---

### "WARNING: PowerShell X.Y detected. Recommended: 7.4 or later"

**Full warning in console:**
```
WARNING: PowerShell 7.2 detected. Recommended: 7.4 or later.
```

**Why:** The installed version of PowerShell is older than 7.4. This is a warning only — the pipeline will still run. However, older versions may have subtle differences in module compatibility or error handling.

**Fix:** Upgrade PowerShell on the agent to 7.4 or later using the same install steps above. Not required immediately, but recommended before issues arise.

---

### "ERROR: Microsoft.Graph.Users PowerShell module is not installed"

**Full error in console:**
```
ERROR: Microsoft.Graph.Users PowerShell module is not installed on this agent.
Required for live runs (DRY_RUN=false).
Install: pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser"
```

**Why:** The Microsoft Graph PowerShell SDK is missing on the Jenkins agent. This check only runs when `DRY_RUN` is unchecked — dry runs skip it entirely.

**Fix — run this once on the Jenkins agent machine as the user Jenkins runs as:**
```bash
sudo -u jenkins pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber"
```

If Jenkins runs as your own user, omit `sudo -u jenkins`. After installing, re-run the pipeline.

---

### "pwsh: command not found" or "Cannot find pwsh"

**Why:** PowerShell Core is not installed on the Jenkins agent (the machine running the job).

**Fix — Ubuntu/Debian:**
```bash
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
pwsh --version
```

After installing, restart the Jenkins agent service so it picks up the new PATH:
```bash
sudo systemctl restart jenkins   # Linux with systemd
```

---

### Pipeline doesn't appear in the job / "No such DSL method"

**Why:** The **Pipeline** plugin is missing.

**Fix:**
1. Go to **Manage Jenkins → Plugins → Available plugins**
2. Search for `Pipeline`
3. Install it and restart Jenkins

---

### "SCM checkout failed" or "Repository not found"

**Why:** Jenkins can't reach or authenticate with your GitHub repo.

**Fix steps:**
1. Confirm the repository URL is correct — go to GitHub, copy the HTTPS clone URL exactly
2. If the repo is private, confirm the credential (GitHub PAT) is attached:
   - In the job config → **Pipeline** section → **Credentials** dropdown should show your GitHub credential, not `- none -`
3. If the PAT is there but still failing, the PAT may have expired — generate a new one on GitHub (Settings → Developer settings → Personal access tokens) and update the Jenkins credential
4. Check the PAT has the `repo` scope ticked

---

## Section 2 — HiBob API Errors

These appear in the console as `[ERROR] [HiBobService]`.

---

### "HTTP 401: Unauthorized" from HiBob

**Full error:**
```
[ERROR] [HiBobService] Failed to fetch employees: HTTP 401: Unauthorized
```

**Why:** The HiBob API token is invalid, expired, or missing the `Bearer ` prefix.

**Fix:**
1. Log into HiBob as admin → **Settings → Integrations → API → Service Users**
2. Find your service user — check it hasn't been deleted or deactivated
3. If you need a new token: click the service user → **Regenerate token**
4. Copy the full token — it must start with `Bearer ` (with a space after it)
5. Update the Jenkins credential:
   - **Manage Jenkins → Credentials** → find `hibob-api-token` → **Update**
   - Replace the Secret value with the new token

---

### "HTTP 403: Forbidden" from HiBob

**Why:** The service user exists but doesn't have permission to read employee data.

**Fix:**
1. In HiBob → **Settings → Integrations → API → Service Users**
2. Click your service user → **Edit permissions**
3. Make sure it has at least **Read** access to **People** data

---

### HiBob returns employees but the list is empty

**Why:** The service user may have a scope filter applied, or all employees are marked inactive.

**Fix:**
1. Test directly — run this from a terminal with your token:
   ```bash
   curl -X POST https://api.hibob.com/v1/people/search \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"showInactive":false}'
   ```
2. If the response has an empty `employees` array, check the HiBob service user's data scope in its permission settings

---

## Section 3 — Azure / Microsoft Graph Errors

These appear as `[ERROR] [GraphService]`.

---

### "Authentication Failed" on the Graph step

**Full error:**
```
[ERROR] [GraphService] ❌ Authentication Failed: AADSTS7000215: Invalid client secret provided.
```

**Why:** The client secret has expired or the wrong value was stored.

**Fix:**
1. Go to [portal.azure.com](https://portal.azure.com) → **App registrations** → your app
2. Click **Certificates & secrets** in the left menu
3. Check the expiry date of your secret — if expired, click **+ New client secret** to create a fresh one
4. Copy the **Value** column (not the Secret ID — they look similar)
5. Update the Jenkins credential: **Manage Jenkins → Credentials** → `azure-app-client-secret` → **Update** → paste the new value

---

### "Insufficient privileges to complete the operation"

**Full error:**
```
[ERROR] [GraphService] ❌ Failed to update user@company.com : Insufficient privileges to complete the operation.
```

**Why:** The Azure App Registration doesn't have the `User.ReadWrite.All` Graph permission, or admin consent hasn't been granted.

**Fix:**
1. Azure Portal → **App registrations** → your app → **API permissions**
2. Check that `User.ReadWrite.All` is listed under Microsoft Graph → Application permissions
3. If it's missing: click **+ Add a permission → Microsoft Graph → Application permissions** → search `User.ReadWrite.All` → tick it → **Add permissions**
4. Click **Grant admin consent for [your org]** at the top of the permissions page
5. The status column must turn green (✅ Granted) — if you don't see the button, you need a Global Admin to do this step

---

### "Resource not found" for a specific user

**Full error:**
```
[ERROR] [GraphService] ❌ Failed to update john@company.com : Resource 'john@company.com' does not exist
```

**Why:** The employee's email in HiBob doesn't match their UPN (login email) in Entra ID. This is common when someone's display email differs from their Microsoft 365 login.

**Fix:**
- Check in Azure Portal → **Users** → search for the person → confirm their **User principal name** matches the email in HiBob
- If they differ, the HiBob email needs to be updated to match the UPN

---

### "Cannot find module Microsoft.Graph" (runtime import error)

**Full error:**
```
Import-Module : The specified module 'Microsoft.Graph' was not found.
```

**Why:** The Microsoft Graph PowerShell SDK isn't installed on the Jenkins agent. The Validate Environment stage now catches this before the sync runs (see "ERROR: Microsoft.Graph.Users PowerShell module is not installed" in Section 1), but if you bypassed that stage or are running the script directly, you may see this error at runtime.

**Fix — run this once on the Jenkins agent machine:**
```bash
pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber"
```

This installs the SDK for the user account that Jenkins runs as. If Jenkins runs as a service account (e.g. `jenkins`), SSH into the machine as that user first:
```bash
sudo -u jenkins pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Force"
```

---

## Section 4 — Runtime / Sync Errors

---

### Pipeline completes but no photos changed in Teams

**Checklist:**
1. Is `DRY_RUN` checked? → Click **Build with Parameters**, confirm **DRY_RUN is unticked**
2. Look in the console for `[DRY RUN]` log lines — if you see them, dry-run is active
3. Is `TEST_USER_EMAIL` set to someone else? → That limits the run to that one person
4. Did any users have avatars? Look for `Get-HiBobAvatar` returning null — employees without a photo in HiBob will be skipped

---

### Only some employees get updated, others are skipped

**Check the console for lines like:**
```
[WARN] [Sync] Skipping user emp-42 - No Email
```

**Why:** Those employees have no email address set in HiBob.

**Fix:** Update the employee record in HiBob to include a work email. The email must match their Microsoft 365 login.

---

### The sync stops after N users even though MAX_USERS is 0

**Why:** `MAX_USERS=0` means unlimited, but something else may be limiting the run — like `TEST_USER_EMAIL` being set, or a previous build's parameter still being cached.

**Fix:**
- Open the job → **Build with Parameters**
- Make sure `TEST_USER_EMAIL` is empty (not just blank-looking — click in the field and delete any value)
- Confirm `MAX_USERS` is `0`

---

### Retry warnings appear but the job still passes

```
[WARN] [Retry] Attempt 1/3 for Get-HiBobEmployees: ...
[WARN] [Retry] Attempt 2/3 for Get-HiBobEmployees: ...
[INFO] [HiBobService] Fetching employees...
```

**This is normal.** The retry logic caught a transient failure and recovered on its own. No action needed. If you see this frequently (every run), it may indicate network instability between Jenkins and the HiBob API.

**What gets retried:** Only transient errors — HTTP 429 (rate limit), HTTP 5xx (server errors), and network-level failures (no HTTP response). The script respects `Retry-After` headers on 429 responses.

**What does NOT get retried:** HTTP 4xx client errors (401 Unauthorized, 403 Forbidden, 404 Not Found). These are permanent errors and the script fails immediately rather than retrying. See "Non-retryable error for OperationName (HTTP 4xx)" below.

**Security note:** Any Bearer tokens that appear in error messages are automatically redacted to `Bearer [REDACTED]` in the retry log lines.

---

### "Build is UNSTABLE (yellow)"

**Why:** One or more users failed to sync, but the pipeline did not crash. The PowerShell script exits with code `2` when any individual user fails, and Jenkins translates that into an UNSTABLE (yellow) build rather than a FAILURE (red) build.

**What to do:**
1. Open the build → **Console Output**
2. Search for `[ERROR]` lines — each failed user will have one
3. The final summary line shows the total count:
   ```
   [INFO] [Sync] Sync complete. Total=50 Uploaded=45 Unchanged=3 Failed=2 NoAvatar=0 NoEmail=0
   ```
4. Fix the underlying cause for each failed user (see the relevant error entry in this guide)

A yellow build means the majority of users synced successfully. It is not a full outage.

---

### "Avatar too large for user@company.com (X.XXMB > 4MB) — skipping"

**Full warning in console:**
```
[WARN] [GraphService] Avatar too large for user@company.com (5.12MB > 4MB) — skipping
```

**Why:** The Microsoft Graph API rejects profile photos larger than 4 MB. The script validates the file size before attempting the upload and skips oversized files rather than failing.

**Fix:** This cannot be resolved from the Jenkins side. The source image in HiBob needs to be replaced with a smaller one. Ask the employee (or an HR admin) to upload a smaller profile photo in HiBob. JPEG files under 1 MB are typical.

---

### "Empty avatar file for user@company.com — skipping"

**Full warning in console:**
```
[WARN] [GraphService] Empty avatar file for user@company.com — skipping
```

**Why:** HiBob returned a zero-byte file when the avatar was downloaded. This is usually a temporary issue on the HiBob side (e.g. a CDN hiccup or a partially uploaded image).

**Fix:** No immediate action needed. The next scheduled run will retry the download. If the warning persists for the same user across multiple runs, check that the employee's profile photo in HiBob is a valid image file.

---

### "Photo unchanged for user@company.com — skipping"

**Full log line in console:**
```
[INFO] [GraphService] Photo unchanged for user@company.com — skipping
```

**This is not an error.** The script downloaded the current Teams photo and compared its MD5 hash against the HiBob avatar. They matched, so the upload was skipped. This is expected behaviour and saves unnecessary API calls. The user's photo is already up to date in Teams.

---

### "Non-retryable error for OperationName (HTTP 4xx)"

**Full error in console:**
```
[ERROR] [Retry] Non-retryable error for Upload-Photo(user@company.com) (HTTP 403): Insufficient privileges...
```

**Why:** A 4xx HTTP error was returned. These are client errors (bad credentials, missing permissions, resource not found) that will not resolve on their own, so the script does not retry them. Only 429 and 5xx errors are retried.

**Fix by status code:**

| Code | Meaning | Fix |
|------|---------|-----|
| 401 | Unauthorized | Client secret expired or wrong — see "Authentication Failed" in Section 3 |
| 403 | Forbidden | Missing Graph permission — see "Insufficient privileges" in Section 3 |
| 404 | Not Found | User's email in HiBob doesn't match their Entra ID UPN — see "Resource not found" in Section 3 |

---

### "Invalid MAX_USERS value 'abc', defaulting to 0 (unlimited)"

**Full warning in console:**
```
[WARN] [Main] Invalid MAX_USERS value 'abc', defaulting to 0 (unlimited)
```

**Why:** The `MAX_USERS` pipeline parameter was set to a non-numeric value. The script could not parse it as an integer and fell back to `0` (unlimited), so all employees were processed.

**Fix:** Open the job → **Build with Parameters** → set `MAX_USERS` to a valid whole number (e.g. `10`) or `0` for unlimited. Do not enter letters or special characters.

---

## Section 5 — General Checks

If you can't find your error above, run through this checklist:

```
[ ] Pipeline agent is running Linux (uname -s returns Linux)
[ ] Console Output shows [ERROR] — what is the exact message?
[ ] All 4 Jenkins credentials exist with the correct IDs
[ ] HiBob service user is active and has People read permissions
[ ] Azure client secret has not expired
[ ] Azure app has User.ReadWrite.All with admin consent granted
[ ] pwsh --version returns 7.x on the Jenkins agent
[ ] Microsoft.Graph module is installed on the agent (required for live runs)
[ ] DRY_RUN is unchecked for live runs
[ ] TEST_USER_EMAIL is empty for full-company runs
[ ] Build status: green = all users synced, yellow = partial failure (check [ERROR] lines), red = pipeline crashed
```

---

## Still stuck?

1. Copy the full Console Output from the failed build
2. Note which **Part** of the [Jenkins Setup Guide](./jenkins-setup.md) you completed up to
3. Share both with whoever is supporting the Jenkins instance
