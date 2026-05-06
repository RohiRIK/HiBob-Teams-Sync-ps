# Jenkins Setup Guide — HiBob Teams Photo Sync

This guide walks you through setting up the Jenkins pipeline from scratch, starting from a fresh Jenkins instance and ending with your first successful photo sync. Follow every step in order.

---

## What you need before you start

- A running Jenkins instance (any version ≥ 2.387)
- Admin access to that Jenkins instance
- Access to your GitHub repository containing this code
- Admin access to your HiBob account
- Admin access to your Azure / Entra ID tenant

---

## Part 1 — Install the Required Jenkins Plugins

Jenkins plugins add features to the base install. You need four of them.

**How to get there:**
1. Open Jenkins in your browser and log in as an admin
2. Click **Manage Jenkins** in the left sidebar
3. Click **Plugins** (you may see it as "Manage Plugins" on older versions)
4. Click the **Available plugins** tab at the top

**Search for and install each of these:**

| Plugin name to search | What it does |
|-----------------------|--------------|
| `Pipeline` | Lets Jenkins run Groovy pipeline scripts (the `HiBobTeamsSync.groovy` file) |
| `Git` | Lets Jenkins clone your GitHub repository |
| `Credentials Binding` | Lets the pipeline read secrets from the vault as environment variables |
| `GitHub Branch Source` | *(Optional)* Auto-discovers branches and pull requests — useful if you want Jenkins to pick up changes automatically |

**To install each one:**
1. Type the plugin name in the search box
2. Tick the checkbox next to it
3. After ticking all four, click **Install** (bottom of page)
4. Tick **Restart Jenkins when installation is complete and no jobs are running**

Wait for Jenkins to restart before continuing.

---

## Part 2 — Install PowerShell Core on the Jenkins Agent

The pipeline runs PowerShell scripts, so `pwsh` must be available on the machine Jenkins uses to run jobs (called an "agent" or "node"). This is usually the same machine Jenkins itself runs on unless you have a separate build server.

> **The pipeline validates this automatically.** The first stage ("Validate Environment") checks that `pwsh` is installed and will print a clear error with an install link if it's missing — the build will fail immediately rather than producing a confusing error later.

**On Ubuntu / Debian:**
```bash
# Add the Microsoft package repo
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb

# Install
sudo apt-get update
sudo apt-get install -y powershell

# Confirm it works
pwsh --version
# Should print: PowerShell 7.x.x
```

**On macOS (if your Jenkins agent is a Mac):**
```bash
brew install --cask powershell
pwsh --version
```

> **Not sure which machine to run this on?**
> In Jenkins, go to **Manage Jenkins → Nodes**. Your agent is listed there. SSH into that machine and run the commands above.

**Recommended version:** PowerShell 7.4 or later. The pipeline will print a warning if your version is below 7.4, but it will **not** stop the build — it's a heads-up, not a blocker. If you see `WARNING: PowerShell 7.x detected. Recommended: 7.4 or later.` in the console, the sync will still run fine; just consider upgrading when convenient.

### Microsoft.Graph PowerShell Module

For **live runs** (`DRY_RUN=false`), the pipeline also requires the `Microsoft.Graph.Users` PowerShell module to be installed on the agent. The Validate Environment stage checks for this automatically and will fail with a clear error if it's missing.

To install it:
```bash
pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Force"
```

> **Dry runs skip this check.** If `DRY_RUN=true`, the module check is skipped entirely — you don't need the Graph module installed just to test the pipeline.

---

## Part 3 — Gather Your Secrets

You need four secrets before touching Jenkins. Collect them all first.

---

### Secret 1 — HiBob API Token

This token lets the script read employee data from HiBob.

1. Log into HiBob as an admin
2. Go to **Settings** (gear icon, top right)
3. Click **Integrations** in the left menu
4. Click **API**
5. Click **Service Users**
6. Click **+ New service user** (or use an existing one)
7. Give it a name like `Jenkins Sync`
8. Copy the token shown — it looks like `Bearer eyJhbGciOiJSUzI1...`

> ⚠️ **Copy it now.** HiBob only shows the token once. If you miss it, you'll need to regenerate it.

Save this value. You'll paste it into Jenkins in Part 4.

---

### Secret 2, 3, 4 — Azure / Entra ID Values

The script needs permission to update photos in Microsoft Teams. You grant this through an **App Registration** in Azure.

#### Create the App Registration (skip if you already have one)

1. Go to [portal.azure.com](https://portal.azure.com) and log in
2. Search for **App registrations** in the top search bar and click it
3. Click **+ New registration**
4. Fill in:
   - **Name:** `HiBob Teams Sync` (or any name)
   - **Supported account types:** leave as "Accounts in this organizational directory only"
   - **Redirect URI:** leave blank
5. Click **Register**

#### Get the Client ID and Tenant ID

After registering, you land on the app's **Overview** page. You'll see:

```
Application (client) ID:  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   ← copy this
Directory (tenant) ID:    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   ← copy this
```

Save both values.

#### Create a Client Secret

1. In the left menu of your app, click **Certificates & secrets**
2. Click **+ New client secret**
3. Add a description like `Jenkins` and choose an expiry (12 or 24 months)
4. Click **Add**
5. **Copy the Value column immediately** — it disappears after you leave the page

> ⚠️ Copy the **Value**, not the Secret ID. They look similar. The Value is the long alphanumeric string.

#### Grant the Required API Permission

The app needs permission to update user photos.

1. In the left menu, click **API permissions**
2. Click **+ Add a permission**
3. Click **Microsoft Graph**
4. Click **Application permissions** (not Delegated)
5. Search for `User.ReadWrite.All`
6. Tick it and click **Add permissions**
7. Click **Grant admin consent for [your org]** — the button at the top of the permissions list
8. Confirm when prompted. The status column should turn green showing "Granted"

---

## Part 4 — Store the Secrets in Jenkins

Jenkins has a built-in vault for secrets. The pipeline reads from it automatically — secrets never appear in your code or logs.

**How to get there:**
1. Click **Manage Jenkins** in the left sidebar
2. Click **Credentials**
3. Under "Stores scoped to Jenkins", click **(global)** next to "System"
4. Click **+ Add Credentials** in the left menu

**Add each secret one at a time. For each one:**
- **Kind:** Select `Secret text` from the dropdown
- **Scope:** Leave as `Global`
- **Secret:** Paste the value
- **ID:** Type the ID exactly as shown in the table below ← this must match the code exactly
- **Description:** Optional, but helpful

| ID to enter | What to paste in "Secret" |
|-------------|---------------------------|
| `hibob-api-token` | The full HiBob token including `Bearer ` at the start, e.g. `Bearer eyJhbG...` |
| `azure-app-client-id` | The Application (client) ID GUID from Azure |
| `azure-app-client-secret` | The client secret Value from Azure |
| `azure-tenant-id` | The Directory (tenant) ID GUID from Azure |

Click **Create** after each one. When done, you should see all four listed in the credentials store.

> ⚠️ **The IDs must match exactly** — including hyphens and lowercase. If the ID is wrong, the pipeline will fail with `Missing required environment variable`.

---

## Part 5 — Create the Jenkins Pipeline Job

Now you'll create the job that Jenkins will run.

1. Click the **Jenkins** logo in the top-left to go to the dashboard
2. Click **+ New Item** in the left sidebar
3. In the **Item name** field, type: `HiBob-Teams-Photo-Sync` (or any name you like)
4. Click **Pipeline** in the list of job types below
5. Click **OK**

You'll land on the job configuration page. Stay here for the next step.

---

## Part 6 — Connect the Job to Your Pipeline Script

You have two ways to do this. Pick the one that matches your situation.

---

### Option A — Pull from GitHub (Recommended)

Use this when the Groovy file lives in your GitHub repository. Jenkins clones the repo every time it runs, so you always execute the latest version of the script without touching Jenkins.

Scroll down the job configuration page to the **Pipeline** section (near the bottom).

**Step 1 — Change the Definition:**
- Click the **Definition** dropdown — it currently says `Pipeline script`
- Select `Pipeline script from SCM`

New fields appear below.

**Step 2 — Set the SCM:**
- Click the **SCM** dropdown and select `Git`

**Step 3 — Enter the Repository URL:**
- Paste your full GitHub HTTPS URL, e.g. `https://github.com/your-org/hibob-teams-sync.git`
- If the repo is **public**, skip to Step 4
- If the repo is **private**, you need a GitHub Personal Access Token:

  > 1. Go to GitHub → click your profile photo → **Settings**
  > 2. Scroll to the bottom of the left menu → click **Developer settings**
  > 3. Click **Personal access tokens → Tokens (classic)**
  > 4. Click **Generate new token (classic)**
  > 5. Give it a name like `Jenkins HiBob Sync`, set an expiry (90 days or 1 year)
  > 6. Tick the **repo** scope — read access is all Jenkins needs
  > 7. Click **Generate token** and copy it immediately — GitHub only shows it once
  >
  > Back in Jenkins, click **+ Add → Jenkins** next to the Credentials field:
  > - **Kind:** `Username with password`
  > - **Username:** Your GitHub username
  > - **Password:** Paste the token
  > - **ID:** `github-pat`
  > - Click **Add**, then select it from the **Credentials** dropdown

**Step 4 — Set the Branch:**
- The field defaults to `*/master`
- Change it to `*/main` if your repo's default branch is `main`

**Step 5 — Set the Script Path:**
- The field defaults to `Jenkinsfile`
- Clear it and type: `HiBobTeamsSync.groovy`
- This is the name of the pipeline file at the root of this repo

Click **Save**.

> **Why this option is recommended:** Any update to `HiBobTeamsSync.groovy` in GitHub is automatically picked up next time the job runs. You don't need to touch Jenkins at all.

---

### Option B — Paste the Groovy Directly into Jenkins

Use this when you don't want Jenkins to connect to GitHub at all — for example, if your Jenkins instance has no internet access, or you just want the simplest possible setup.

Scroll down to the **Pipeline** section of the job configuration.

**Leave the Definition as `Pipeline script`** — don't change the dropdown.

You'll see a large text box labelled **Script**.

**Paste the full contents of `HiBobTeamsSync.groovy` into that box.**

To get the file contents:
1. Open the repository on GitHub (or locally)
2. Open `HiBobTeamsSync.groovy`
3. Select all → copy
4. Paste into the Jenkins Script box

Click **Save**.

> ⚠️ **Important:** With this option, Jenkins stores the script inside its own database. If you update `HiBobTeamsSync.groovy` in your repo, **Jenkins will not pick up the change automatically** — you'll need to come back here, open the job config, and paste the new version manually. That's why Option A is preferred if GitHub is reachable.

---

## Part 7 — Your First Safe Run

Before running on real employees, test on yourself with dry-run on.

1. Click **Build with Parameters** in the left sidebar of your job
2. Fill in the parameters:

| Parameter | What to enter |
|-----------|---------------|
| **TEST_USER_EMAIL** | Your own work email address, e.g. `john@yourcompany.com` |
| **DRY_RUN** | Leave this **ticked** ✅ — nothing will actually change |
| **MAX_USERS** | Type `1` |

3. Click **Build**
4. A new entry appears in **Build History** on the left (e.g. `#1`)
5. Click on it, then click **Console Output**

You should see output like:
```
[INFO] [HiBobService] Fetching employees...
[INFO] [HiBobService] Total employees fetched: 1
[INFO] [Sync] Processing 1 users...
[INFO] [GraphService] [DRY RUN] Would update photo for john@yourcompany.com
[INFO] [Sync] Sync complete. Total=1 Uploaded=0 Unchanged=0 Failed=0 NoAvatar=0 NoEmail=0
```

**If you see that — the setup is working.** Nothing was changed in Teams yet because DRY_RUN was on.

The summary line at the end tells you exactly what happened:
- **Total** — how many users were processed
- **Uploaded** — photos successfully updated in Teams
- **Unchanged** — users whose photo was already up to date (skipped)
- **Failed** — users that encountered an error (check the lines above for details)
- **NoAvatar** — users with no photo in HiBob
- **NoEmail** — users with no email address (can't match to a Teams account)

---

## Understanding Build Status

After each run, Jenkins marks the build with a colour-coded status. Here's what each one means:

| Status | Colour | What it means |
|--------|--------|---------------|
| **SUCCESS** | Green | All users were processed without errors |
| **UNSTABLE** | Yellow | The sync ran to completion, but some users failed — check the console output for lines containing `[ERROR]` or `[WARN]` to see which users were affected and why |
| **FAILURE** | Red | The pipeline itself crashed before finishing — check the console output for the error that caused it (e.g. missing credentials, PowerShell not installed, network error) |

> **UNSTABLE is not a disaster.** It means the pipeline did its job but hit a problem with specific users (for example, a user exists in HiBob but not in Entra ID). The rest of the users were still synced. Review the failed users and re-run or investigate individually.

---

## Pipeline Options

The pipeline is configured with the following built-in protections:

| Option | Value | What it means |
|--------|-------|---------------|
| **Timeout** | 30 minutes | If a run takes longer than 30 minutes, Jenkins cancels it automatically — prevents hung builds from blocking the agent indefinitely |
| **Concurrent builds** | Disabled | Only one instance of this job can run at a time — prevents two syncs from racing each other and causing duplicate updates |
| **Log rotation** | Keeps last 30 builds | Jenkins automatically deletes older build logs to save disk space |

These are set in the pipeline itself (`HiBobTeamsSync.groovy`) and apply automatically — you don't need to configure them in the Jenkins UI.

---

## Part 8 — Gradual Rollout

Now that dry-run works, roll out in stages:

**Stage 1 — Live test on yourself:**
- `TEST_USER_EMAIL` = your email
- `DRY_RUN` = **unticked** ← this will actually update your photo
- `MAX_USERS` = `1`

Check Teams — your profile photo should update within a minute or two.

**Stage 2 — Small batch:**
- `TEST_USER_EMAIL` = *(leave blank)*
- `DRY_RUN` = unticked
- `MAX_USERS` = `20`

This runs on the first 20 employees in HiBob. Check a few to confirm.

**Stage 3 — Full run:**
- `TEST_USER_EMAIL` = *(leave blank)*
- `DRY_RUN` = unticked
- `MAX_USERS` = `0` ← 0 means unlimited

---

## Part 9 — Schedule Automatic Runs (Optional)

To run the sync automatically on a schedule:

1. Open the job → click **Configure** in the left sidebar
2. Scroll to the **Build Triggers** section
3. Tick **Build periodically**
4. A text box appears — enter a cron expression:

```
# Every day at 6 AM
0 6 * * *

# Every Monday at 8 AM
0 8 * * 1

# Every weekday at 7 AM
0 7 * * 1-5
```

> The format is: `minute hour day-of-month month day-of-week`
> Jenkins shows a human-readable preview below the box as you type — use that to confirm your schedule is correct.

5. Click **Save**

---


---

## Something went wrong?

👉 **[Troubleshooting Guide](./troubleshooting.md)** — covers every error by category: Jenkins setup, HiBob API, Azure/Graph, and runtime issues.
