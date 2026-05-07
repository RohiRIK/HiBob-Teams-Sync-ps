# JenkinsScaffold

Skill for AI agents: how to scaffold a NEW Jenkins pipeline project from scratch in the `Automations` workspace.

---

## When to Use

Load this skill when the user says any of:
- "create a new Jenkins pipeline"
- "scaffold a new automation"
- "new Jenkins project"
- "start a new automation"
- "set up a new Jenkins job"

Do NOT use this skill for working with an existing pipeline — see `JenkinsPipeline.md` for that.

---

## Required Reading

Before scaffolding, read:
- **`RULES.md`** (workspace root) — single source of truth for naming, structure, credential handling, testing, and lifecycle rules.
- **`JenkinsPipeline.md`** (this directory) — working with existing pipelines, stage patterns, and troubleshooting.

The gold standard project is `Jenkins/HiBob-Teams-Sync-ps/`. When in doubt, look there first.

---

## Step-by-step Scaffold Process

### 1. Choose a project name (`kebab-case`)

All project directory names MUST be `kebab-case`. See `RULES.md §Project Naming`.

| ✅ Correct | ❌ Incorrect |
|---|---|
| `REPLACE-PROJECT-NAME` | `REPLACEProjectName` |
| `my-sync-tool-ps` | `MySyncTool` |

Append a technology suffix when it disambiguates:
- `-ps` for PowerShell-primary projects
- `-la` for Logic App projects

### 2. Create the project directory and git repo

```bash
cd Jenkins/
mkdir REPLACE-PROJECT-NAME
cd REPLACE-PROJECT-NAME
git init
```

> ⚠️ Do NOT nest this inside another git repo. The workspace root (`Automations/`) has no `.git`. Each project is self-contained. See `RULES.md §Known Patterns & Anti-patterns`.

### 3. Create required files

Every project with a git repo MUST have these files (see `RULES.md §Project Lifecycle`):

```bash
touch README.md
touch AGENTS.md
touch .gitignore
touch .env.schema
touch .pre-commit-config.yaml
```

Choose ONE pipeline file type — never mix:
- `Jenkinsfile` — for standalone declarative pipelines
- `REPLACE-PROJECT-NAME.groovy` — for Jenkins shared library pipelines

### 4. Create the recommended directory structure

```bash
mkdir -p src/powershell
mkdir -p tests/helpers
mkdir -p tests/mocks
mkdir -p tests/fixtures
mkdir -p docs
mkdir -p .agents/skills
```

Full expected layout:
```
REPLACE-PROJECT-NAME/
├── REPLACE-MODULE-NAME.groovy   # OR Jenkinsfile (not both)
├── src/
│   └── powershell/
│       ├── Invoke-REPLACE-VERB.ps1   # Thin orchestrator / entry point
│       └── REPLACE-MODULE-NAME.psm1  # Business logic module
├── tests/
│   ├── REPLACE-MODULE-NAME.Tests.ps1
│   ├── helpers/
│   │   └── TestHelpers.psm1
│   ├── mocks/
│   └── fixtures/
├── docs/
│   ├── jenkins-setup.md
│   └── troubleshooting.md
├── .agents/
│   └── skills/
├── AGENTS.md
├── README.md
├── .gitignore
├── .env.schema
└── .pre-commit-config.yaml
```

### 5. Fill in `.env.schema` and `.pre-commit-config.yaml`

Copy the templates from the sections below and fill in the required keys for your project.

### 6. Initial commit

```bash
git add .
git commit -m "chore: initial scaffold for REPLACE-PROJECT-NAME"
```

---

## Jenkinsfile Template

Use this for **standalone** declarative pipelines. Replace all `REPLACE-*` placeholders.

```groovy
pipeline {
    agent any

    parameters {
        booleanParam(
            name: 'DRY_RUN',
            defaultValue: true,
            description: 'If checked, logs all intended changes without writing to any external system.'
        )
        string(
            name: 'REPLACE-PARAM-NAME',
            defaultValue: '',
            description: 'REPLACE: describe this parameter.'
        )
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        REPLACE_CREDENTIAL_KEY   = credentials('REPLACE-CREDENTIAL-ID')
        REPLACE_CREDENTIAL_KEY_2 = credentials('REPLACE-CREDENTIAL-ID-2')
        IS_DRY_RUN               = "${params.DRY_RUN}"
    }

    stages {
        stage('Validate Environment') {
            steps {
                script {
                    dir('REPLACE-PROJECT-NAME') {
                        sh '''
                            # --- OS validation ---
                            OS=$(uname -s)
                            if [ "$OS" != "Linux" ]; then
                                echo "ERROR: This pipeline requires Linux. Detected OS: $OS"
                                exit 1
                            fi
                            echo "✅ OS: $OS"

                            # --- PowerShell validation ---
                            if ! command -v pwsh > /dev/null 2>&1; then
                                echo "ERROR: PowerShell Core (pwsh) is not installed on this agent."
                                exit 1
                            fi
                            echo "✅ $(pwsh --version)"
                        '''
                    }
                }
            }
        }

        stage('REPLACE-STAGE-1') {
            steps {
                script {
                    dir('REPLACE-PROJECT-NAME') {
                        def exitCode = sh(
                            script: 'pwsh -File src/powershell/Invoke-REPLACE-VERB.ps1',
                            returnStatus: true
                        )
                        if (exitCode == 2) {
                            currentBuild.result = 'UNSTABLE'
                            currentBuild.description = 'Partial failure — some items failed'
                        } else if (exitCode != 0) {
                            currentBuild.description = "Stage failed (exit code ${exitCode})"
                            error("REPLACE-STAGE-1 failed with exit code ${exitCode}")
                        } else {
                            currentBuild.description = 'REPLACE-STAGE-1 completed successfully'
                        }
                    }
                }
            }
        }

        stage('REPLACE-STAGE-2') {
            when {
                expression { !params.DRY_RUN }
            }
            steps {
                script {
                    dir('REPLACE-PROJECT-NAME') {
                        sh 'pwsh -File src/powershell/Invoke-REPLACE-VERB-2.ps1'
                    }
                }
            }
        }
    }

    post {
        always {
            echo "📝 Build completed."
        }
        success {
            echo "✅ REPLACE-PROJECT-NAME completed successfully."
        }
        failure {
            echo "❌ REPLACE-PROJECT-NAME failed. Check logs for details."
        }
    }
}
```

> **Rules enforced by this template** (from `RULES.md §Pipeline File Conventions`):
> - `options {}` block with `timeout`, `disableConcurrentBuilds`, `buildDiscarder` — mandatory.
> - `DRY_RUN` defaults to `true` — require explicit opt-in for live runs.
> - `Validate Environment` stage runs before any business logic.
> - `returnStatus: true` on `sh()` to handle partial failures (exit code 2).

---

## AGENTS.md Template

Every project MUST have an `AGENTS.md` with these five sections in this order (see `RULES.md §AI Agent Conventions`):

```markdown
# AGENTS.md - Agent Coding Guidelines for REPLACE-PROJECT-NAME

## Project Overview

REPLACE: One paragraph — what it does, what systems it touches, how it runs.

## Commands

### Running Tests

\`\`\`bash
pwsh -Command "Invoke-Pester ./tests/"
pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"
\`\`\`

### Running the Scripts

\`\`\`bash
# Dry-run mode (safe, no external writes)
IS_DRY_RUN=true pwsh -File ./src/powershell/Invoke-REPLACE-VERB.ps1

# Production run (requires env vars)
REPLACE_CREDENTIAL_KEY="..." IS_DRY_RUN=false pwsh -File ./src/powershell/Invoke-REPLACE-VERB.ps1
\`\`\`

### Linting

\`\`\`bash
pwsh -Command "Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error"
\`\`\`

## Code Style

- PowerShell Core 7.x (`pwsh`) only — never Windows PowerShell 5.1
- `Set-StrictMode -Version Latest` + `$ErrorActionPreference = "Stop"` at script level
- Verb-Noun function names (PascalCase); `Noun.psm1` module names
- `try/catch/throw` — always re-throw to preserve stack trace
- See `RULES.md §PowerShell Coding Standards` for full reference

## File Structure

\`\`\`
REPLACE-PROJECT-NAME/
├── REPLACE-MODULE-NAME.groovy   # Jenkins pipeline
├── src/powershell/
│   ├── Invoke-REPLACE-VERB.ps1  # Entry point (thin orchestrator)
│   └── REPLACE-MODULE-NAME.psm1 # Business logic module
├── tests/
│   ├── REPLACE-MODULE-NAME.Tests.ps1
│   ├── helpers/TestHelpers.psm1
│   ├── mocks/
│   └── fixtures/
├── docs/
├── .agents/skills/
├── AGENTS.md
├── README.md
├── .gitignore
├── .env.schema
└── .pre-commit-config.yaml
\`\`\`

## Secrets & Security

- Required env vars: `REPLACE_CREDENTIAL_KEY`, `REPLACE_CREDENTIAL_KEY_2`
- Injected via Jenkins `credentials('REPLACE-CREDENTIAL-ID')` — never hardcoded
- Never commit `.env` files — add `*.env` to `.gitignore`
- See `.env.schema` for required keys
```

---

## PowerShell Module Template

Place in `src/powershell/REPLACE-MODULE-NAME.psm1`.

```powershell
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-REPLACE-VERB {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$REPLACE-REQUIRED-PARAM,

        [Parameter(Mandatory = $false)]
        [string]$REPLACE-OPTIONAL-PARAM = "default",

        [switch]$DryRun
    )

    if (-not $REPLACE-REQUIRED-PARAM) { throw "REPLACE-REQUIRED-PARAM is required" }

    try {
        Write-Log "INFO" "REPLACE-MODULE-NAME" "Starting REPLACE-VERB with DryRun=$DryRun"

        # REPLACE: business logic here

        if ($DryRun) {
            Write-Log "INFO" "REPLACE-MODULE-NAME" "[DRY RUN] Would have written to REPLACE-SYSTEM"
            return
        }

        # REPLACE: live write operations here

        Write-Log "INFO" "REPLACE-MODULE-NAME" "REPLACE-VERB completed successfully"
    }
    catch {
        Write-Error "REPLACE-VERB failed: $_"
        throw  # Re-throw to preserve stack trace
    }
}

Export-ModuleMember -Function Invoke-REPLACE-VERB
```

> **Rules enforced** (from `RULES.md §PowerShell Coding Standards`):
> - `[CmdletBinding()]` on every function.
> - `try/catch/throw` — re-throw after logging.
> - `Export-ModuleMember` at end of module.
> - `Write-Log` for structured logging inside `src/` modules.

---

## Pester Test Template

Place in `tests/REPLACE-MODULE-NAME.Tests.ps1`.

```powershell
BeforeAll {
    $Script:ModulePath = "$PSScriptRoot/../src/powershell/REPLACE-MODULE-NAME.psm1"
    Import-Module $Script:ModulePath -Force
}

Describe "Invoke-REPLACE-VERB" {
    It "Should call REPLACE-DEPENDENCY exactly N times in normal operation" {
        Mock REPLACE-DEPENDENCY { return "REPLACE-MOCK-RETURN" } -ModuleName REPLACE-MODULE-NAME
        Mock REPLACE-WRITE-FUNCTION { } -ModuleName REPLACE-MODULE-NAME

        $TestData = @(1..3 | ForEach-Object {
            [PSCustomObject]@{ Id = "item-$_"; Name = "Test Item $_" }
        })

        Invoke-REPLACE-VERB -REPLACE-REQUIRED-PARAM "test-value" -DryRun

        Should -Invoke REPLACE-DEPENDENCY -Times 3 -Exactly -ModuleName REPLACE-MODULE-NAME
    }

    It "Should NOT call REPLACE-WRITE-FUNCTION when DryRun is set" {
        Mock REPLACE-DEPENDENCY { return "REPLACE-MOCK-RETURN" } -ModuleName REPLACE-MODULE-NAME
        Mock REPLACE-WRITE-FUNCTION { } -ModuleName REPLACE-MODULE-NAME

        Invoke-REPLACE-VERB -REPLACE-REQUIRED-PARAM "test-value" -DryRun

        Should -Invoke REPLACE-WRITE-FUNCTION -Times 0 -ModuleName REPLACE-MODULE-NAME
    }

    It "Should throw when REPLACE-REQUIRED-PARAM is missing" {
        { Invoke-REPLACE-VERB -REPLACE-REQUIRED-PARAM "" } | Should -Throw
    }
}

Describe "REPLACE-HELPER-FUNCTION" {
    It "Should return expected result for valid input" {
        $Result = REPLACE-HELPER-FUNCTION -Input "REPLACE-TEST-INPUT"
        $Result | Should -Not -BeNullOrEmpty
    }
}
```

> **Rules enforced** (from `RULES.md §Testing Requirements`):
> - `BeforeAll` imports the module — never import inside `It` blocks.
> - `-ModuleName REPLACE-MODULE-NAME` on ALL `Mock` and `Should -Invoke` calls.
> - Function execution runs INSIDE `It` blocks so `Should -Invoke` counts work.
> - Fixtures (JSON data) go in `tests/fixtures/`.

---

## .env.schema Template

Place at project root as `.env.schema`. Keys only — **never** values.

```
# Environment Schema — REPLACE-PROJECT-NAME
# Keys only — never commit values.
# Copy to .env and fill in values locally.

# @sensitive
REPLACE_CREDENTIAL_KEY=

# @sensitive
REPLACE_CREDENTIAL_KEY_2=

REPLACE_OPTIONAL_KEY=
IS_DRY_RUN=true
```

> See `RULES.md §Credential Handling` for the full `.env.schema` pattern and `.gitignore` requirements.

---

## .pre-commit-config.yaml Template

Copy this verbatim — update `rev` to the latest TruffleHog release if needed.

```yaml
repos:
  - repo: https://github.com/trufflesecurity/trufflehog
    rev: v3.82.13
    hooks:
      - id: trufflehog
        name: TruffleHog secret scan
        entry: trufflehog git file://. --since-commit HEAD --only-verified --fail
        language: system
        stages: [pre-commit]
```

---

## .gitignore Template

```
# Secrets
*.env
credentials.json
*.key
*.pfx
*.pem

# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
*.swp
```

---

## Required Reading

| Document | What it covers |
|---|---|
| `RULES.md` (workspace root) | All naming, structure, credential, testing, and lifecycle rules |
| `JenkinsPipeline.md` (this directory) | Working with existing pipelines, stage patterns, troubleshooting |
| `Jenkins/HiBob-Teams-Sync-ps/` | Gold standard project — every rule is grounded here |

> When in doubt, look at `Jenkins/HiBob-Teams-Sync-ps/` first.
