pipeline {
    agent any

    parameters {
        string(name: 'TEST_USER_EMAIL', defaultValue: '', description: 'Enter a single email to test the sync safely on one user.')
        booleanParam(name: 'DRY_RUN', defaultValue: true, description: 'If checked, logs all intended changes without writing to Microsoft 365 or syncing avatars.')
        string(name: 'MAX_USERS', defaultValue: '0', description: 'Maximum number of users to process per run. Set to 0 for unlimited (default).')
    }

    environment {
        HIBOB_TOKEN = credentials('hibob-api-token')
        ENTRAID_CLIENT_ID = credentials('azure-app-client-id')
        ENTRAID_CLIENT_SECRET = credentials('azure-app-client-secret')
        ENTRAID_TENANT_ID = credentials('azure-tenant-id')
        IS_DRY_RUN = "${params.DRY_RUN}"
        MAX_USERS = "${params.MAX_USERS}"
        DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
    }

    stages {
        stage('Prepare Runtime') {
            steps {
                script {
                    dir('HiBobTeamsSync') {
                        echo "📦 Checking/Installing PowerShell..."
                        sh '''
                            if ! command -v pwsh &> /dev/null; then
                                # Install PowerShell Core in workspace (not /var/jenkins_home/)
                                curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/powershell-7.4.1-linux-x64.tar.gz -o /tmp/powershell.tar.gz
                                mkdir -p "${WORKSPACE}/HiBobTeamsSync/tools"
                                tar -xvf /tmp/powershell.tar.gz -C "${WORKSPACE}/HiBobTeamsSync/tools"
                                chmod +x "${WORKSPACE}/HiBobTeamsSync/tools/pwsh"
                            fi
                        '''
                    }
                }
            }
        }

        stage('Execute Sync') {
            environment {
                PATH = "${WORKSPACE}/HiBobTeamsSync/tools:${env.PATH}"
            }
            steps {
                script {
                    dir('HiBobTeamsSync') {
                        echo "⚡ Executing PowerShell Logic..."
                        sh '''
                            pwsh -File src/powershell/Invoke-Sync.ps1
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            echo "📝 Archiving execution logs..."
        }
    }
}
