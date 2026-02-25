pipeline {
    agent any

    parameters {
        string(name: 'TEST_USER_EMAIL', defaultValue: '', description: 'Enter a single email to test the sync safely on one user.')
        booleanParam(name: 'DRY_RUN', defaultValue: true, description: 'If checked, logs intended changes but does not write to Microsoft 365.')
        booleanParam(name: 'SYNC_AVATARS', defaultValue: true, description: 'Master toggle for the profile picture sync feature.')
        booleanParam(name: 'DEBUG_MODE', defaultValue: false, description: 'If checked, enables verbose logging for troubleshooting.')
        string(name: 'MAX_USERS', defaultValue: '0', description: 'Safety limit: Maximum number of users to process (0 for unlimited).')
        booleanParam(name: 'BUILD_TEST_ONLY', defaultValue: false, description: 'If checked, runs a mock build test to verify environment without real API calls.')
    }

    environment {
        HIBOB_TOKEN = credentials('hibob-api-token')
        ENTRAID_CLIENT_ID = credentials('azure-app-client-id')
        ENTRAID_CLIENT_SECRET = credentials('azure-app-client-secret')
        ENTRAID_TENANT_ID = credentials('azure-tenant-id')
        IS_DRY_RUN = "${params.DRY_RUN}"
        DO_SYNC_AVATARS = "${params.SYNC_AVATARS}"
        DEBUG_MODE = "${params.DEBUG_MODE}"
        MAX_USERS = "${params.MAX_USERS}"
        BUILD_TEST_ONLY = "${params.BUILD_TEST_ONLY}"
    }

    stages {
        stage('Prepare Runtime') {
            steps {
                script {
                    dir('HiBobTeamsSync') {
                        echo "📦 Checking/Installing PowerShell..."
                        sh '''
                            if ! command -v pwsh &> /dev/null; then
                                # Install PowerShell Core for Linux (Jenkins default)
                                curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/powershell-7.4.1-linux-x64.tar.gz -o /tmp/powershell.tar.gz
                                mkdir -p /var/jenkins_home/powershell
                                tar -xvf /tmp/powershell.tar.gz -C /var/jenkins_home/powershell
                                chmod +x /var/jenkins_home/powershell/pwsh
                            fi
                            export PATH="/var/jenkins_home/powershell:$PATH"
                            export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
                        '''
                    }
                    }
                }
            }
        }

        stage('Execute Sync') {
            steps {
                script {
                    dir('HiBobTeamsSync') {
                        echo "⚡ Executing PowerShell Logic..."
                        sh '''
                            export PATH="/var/jenkins_home/powershell:$PATH"
                            export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
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