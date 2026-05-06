# Jenkins Plugins — HiBob Teams Photo Sync

This guide covers the plugins required by the pipeline and how to install them.

---

## Required Plugins

| Plugin | What it does | Why the pipeline needs it |
|--------|-------------|--------------------------|
| **Pipeline** | Lets Jenkins execute Groovy pipeline scripts | The `HiBobTeamsSync.groovy` file is a declarative pipeline — Jenkins cannot parse it without this plugin |
| **Git** | Lets Jenkins clone repositories from GitHub, GitLab, Bitbucket, etc. | The job pulls the latest code from your repo on every run |
| **Credentials Binding** | Injects secrets stored in the Jenkins vault as environment variables | The pipeline reads `HIBOB_TOKEN`, `ENTRAID_CLIENT_ID`, `ENTRAID_CLIENT_SECRET`, and `ENTRAID_TENANT_ID` this way |

### Optional

| Plugin | What it does | When you need it |
|--------|-------------|-----------------|
| **GitHub Branch Source** | Auto-discovers branches and pull requests from a GitHub repo | Only if you want Jenkins to trigger builds automatically when code is pushed — not required for manual or scheduled runs |
| **Timestamper** | Adds timestamps to every line in the console output | The pipeline already sets `timestamps()` in its options block — this plugin makes it work. Some Jenkins installs include it by default. |

---

## How to Install

### Step 1 — Open the Plugin Manager

1. Log into Jenkins as an admin
2. Click **Manage Jenkins** in the left sidebar
3. Click **Plugins** (labelled "Manage Plugins" on Jenkins versions before 2.400)
4. Click the **Available plugins** tab at the top

### Step 2 — Search and Select

For each plugin in the table above:

1. Type the plugin name in the search box (e.g. `Pipeline`)
2. Tick the checkbox next to it in the results list
3. Repeat for the next plugin — you can tick multiple before installing

### Step 3 — Install and Restart

1. After ticking all required plugins, click **Install** at the bottom of the page
2. On the next screen, tick **Restart Jenkins when installation is complete and no jobs are running**
3. Wait for Jenkins to restart — this usually takes 30 seconds to a minute

### Step 4 — Verify

After Jenkins restarts:

1. Go to **Manage Jenkins → Plugins → Installed plugins**
2. Search for each plugin name and confirm it appears with a green checkmark
3. If any plugin shows as "pending restart", restart Jenkins manually: **Manage Jenkins → Restart Safely**

---

## Troubleshooting

### "No such DSL method 'pipeline'"

The **Pipeline** plugin is missing or failed to install. Go back to Step 1 and reinstall it.

### "SCM checkout failed" even though the repo URL is correct

The **Git** plugin may be missing. Without it, Jenkins cannot clone from Git repositories. Install it and restart.

### Credentials are stored but the pipeline says "Missing required environment variable"

The **Credentials Binding** plugin may be missing. Without it, the `credentials()` function in the Groovy pipeline cannot inject secrets as environment variables. Install it and restart.

### Plugin install hangs or fails

1. Check that your Jenkins instance has internet access — it downloads plugins from `updates.jenkins.io`
2. If behind a corporate proxy, configure the proxy in **Manage Jenkins → Plugins → Advanced settings → HTTP Proxy Configuration**
3. As a last resort, download the `.hpi` file manually from [plugins.jenkins.io](https://plugins.jenkins.io/) and upload it via **Advanced settings → Deploy Plugin**

---

## Related

- [Jenkins Full Setup Guide](./jenkins-setup.md) — end-to-end setup including credentials, job creation, and first run
- [Troubleshooting Guide](./troubleshooting.md) — error-by-error fixes for the pipeline
