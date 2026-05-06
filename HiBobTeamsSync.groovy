pipeline {
    agent any

    parameters {
        string(name: 'TEST_USER_EMAIL', defaultValue: '', description: 'Enter a single email to test the sync safely on one user.')
        booleanParam(name: 'DRY_RUN', defaultValue: true, description: 'If checked, logs all intended changes without writing to Microsoft 365 or syncing avatars.')
        string(name: 'MAX_USERS', defaultValue: '0', description: 'Maximum number of users to process per run. Set to 0 for unlimited (default).')
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        HIBOB_TOKEN = credentials('hibob-api-token')
        ENTRAID_CLIENT_ID = credentials('azure-app-client-id')
        ENTRAID_CLIENT_SECRET = credentials('azure-app-client-secret')
        ENTRAID_TENANT_ID = credentials('azure-tenant-id')
        IS_DRY_RUN = "${params.DRY_RUN}"
        MAX_USERS = "${params.MAX_USERS}"
        TEST_USER_EMAIL = "${params.TEST_USER_EMAIL}"
        DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
    }

    stages {
        stage('Validate Environment') {
            steps {
                script {
                    dir('HiBobTeamsSync') {
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
                                echo "Install: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
                                exit 1
                            fi

                            PWSH_VERSION=$(pwsh --version)
                            echo "✅ $PWSH_VERSION"

                            # Warn on old versions (portable parsing — no grep -P)
                            VERSION_NUM=$(echo "$PWSH_VERSION" | sed 's/[^0-9.]//g')
                            MAJOR=$(echo "$VERSION_NUM" | cut -d. -f1)
                            MINOR=$(echo "$VERSION_NUM" | cut -d. -f2)
                            if [ "${MAJOR:-0}" -lt 7 ] || { [ "${MAJOR:-0}" -eq 7 ] && [ "${MINOR:-0}" -lt 4 ]; }; then
                                echo "⚠️  WARNING: PowerShell ${MAJOR}.${MINOR} detected. Recommended: 7.4 or later."
                            fi
                        '''

                        // Graph module check — only required for live runs
                        if (!params.DRY_RUN) {
                            sh '''
                                echo "🔍 Checking Microsoft.Graph module..."
                                if ! pwsh -Command "if (-not (Get-Module -ListAvailable Microsoft.Graph.Users)) { exit 1 }" > /dev/null 2>&1; then
                                    echo "ERROR: Microsoft.Graph.Users PowerShell module is not installed on this agent."
                                    echo "Required for live runs (DRY_RUN=false)."
                                    echo "Install: pwsh -Command \\"Install-Module Microsoft.Graph -Scope CurrentUser\\""
                                    exit 1
                                fi
                                echo "✅ Microsoft.Graph module found."
                            '''
                        } else {
                            echo "ℹ️  Dry run — skipping Graph module check."
                        }
                    }
                }
            }
        }

        stage('Execute Sync') {
            steps {
                script {
                    dir('HiBobTeamsSync') {
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
                    }
                }
            }
        }
    }

    post {
        always {
            echo "📝 Build completed."
        }
    }
}
