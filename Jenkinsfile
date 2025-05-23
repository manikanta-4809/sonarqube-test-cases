pipeline {
    agent {
        docker {
            image 'python:3.11-slim'
            args '-u root' // Run as root to avoid permission issues
        }
    }

    environment {
        DOCKER_REGISTRY = 'saipolaki'
        IMAGE_NAME = 'my-python-text'
        DEV_EC2_HOST = '3.110.218.88'
        PROD_EC2_HOST = 'your-prod-instance-ip'
    }

    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'prod'], description: 'Select deployment environment')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip running tests')
    }

    stages {
        stage('📥 Checkout') {
            steps {
                echo 'Checking out source code...'
                checkout scm
            }
        }

        stage('🔧 Setup Environment') {
            steps {
                echo 'Setting up Python environment...'
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install -r app/requirements.txt
                    pip install pytest coverage pylint flake8
                '''
            }
        }

        stage('📊 Code Quality - Linting') {
            steps {
                echo 'Running code quality checks...'
                sh '''
                    echo "Running Flake8..."
                    flake8 app/ --max-line-length=100 --ignore=E501,W503 || true

                    echo "Running Pylint..."
                    pylint app/ --disable=C0114,C0116,C0115 || true
                '''
            }
        }

        stage('🔍 SonarQube Analysis') {
            steps {
                echo 'Running SonarQube analysis...'
                script {
                    def scannerHome = tool 'SonarScanner'
                    withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                        withSonarQubeEnv('SonarQube') {
                            sh "${scannerHome}/bin/sonar-scanner -Dsonar.login=${SONAR_TOKEN}"
                        }
                    }
                }
            }
        }

        stage('🚪 Quality Gate') {
            steps {
                echo 'Waiting for SonarQube Quality Gate...'
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        withSonarQubeEnv('SonarQube') {
                            waitForQualityGate abortPipeline: true
                        }
                    }
                }
            }
        }

        stage('🐳 Docker Build') {
            steps {
                echo 'Building Docker image...'
                script {
                    def imageTag = "${params.ENVIRONMENT}-${env.BUILD_NUMBER}"
                    def imageName = "${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}"

                    sh """
                        echo "Building image: ${imageName}:${imageTag}"
                        docker build -t ${imageName}:${imageTag} .
                        docker tag ${imageName}:${imageTag} ${imageName}:${params.ENVIRONMENT}-latest
                    """

                    env.IMAGE_TAG = imageTag
                    env.FULL_IMAGE_NAME = "${imageName}:${imageTag}"
                }
            }
        }

        stage('🔒 Container Security Scan') {
            steps {
                echo 'Scanning container for vulnerabilities...'
                sh '''
                    apt-get update && apt-get install -y wget gnupg lsb-release
                    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -
                    echo "deb https://aquasecurity.github.io/trivy-repo/deb generic main" > /etc/apt/sources.list.d/trivy.list
                    apt-get update && apt-get install -y trivy

                    echo "Scanning image..."
                    trivy image --exit-code 0 --severity LOW,MEDIUM ${FULL_IMAGE_NAME}
                    trivy image --exit-code 1 --severity HIGH,CRITICAL ${FULL_IMAGE_NAME}
                '''
            }
        }

        stage('📤 Push to Registry') {
            steps {
                echo 'Pushing Docker image to registry...'
                withCredentials([usernamePassword(credentialsId: 'docker-hub-credentials', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                    sh '''
                        echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
                        docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${ENVIRONMENT}-latest
                    '''
                }
            }
        }

        stage('🚀 Deploy to Environment') {
            steps {
                script {
                    def host = (params.ENVIRONMENT == 'prod') ? PROD_EC2_HOST : DEV_EC2_HOST

                    withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY')]) {
                        sh """
                            chmod 600 $SSH_KEY
                            scp -i $SSH_KEY -o StrictHostKeyChecking=no deploy/${params.ENVIRONMENT}/docker-compose.${params.ENVIRONMENT}.yml ec2-user@${host}:/home/ec2-user/
                            ssh -i $SSH_KEY -o StrictHostKeyChecking=no ec2-user@${host} '
                                export DOCKER_REGISTRY=${DOCKER_REGISTRY}
                                export IMAGE_NAME=${IMAGE_NAME}
                                export BUILD_NUMBER=${BUILD_NUMBER}
                                docker-compose -f docker-compose.${params.ENVIRONMENT}.yml down || true
                                docker-compose -f docker-compose.${params.ENVIRONMENT}.yml pull
                                docker-compose -f docker-compose.${params.ENVIRONMENT}.yml up -d
                                docker system prune -f
                            '
                        """
                    }
                }
            }
        }

        stage('🩺 Health Check') {
            steps {
                script {
                    def host = (params.ENVIRONMENT == 'prod') ? PROD_EC2_HOST : DEV_EC2_HOST
                    def port = (params.ENVIRONMENT == 'prod') ? '80' : '8000'

                    sh """
                        sleep 30
                        for i in {1..10}; do
                            if curl -f http://${host}:${port}/health; then
                                echo "✅ Application is healthy!"
                                exit 0
                            fi
                            echo "⏳ Attempt \$i failed, retrying..."
                            sleep 10
                        done
                        echo "❌ Health check failed"
                        exit 1
                    """
                }
            }
        }
    }

    post {
        always {
            echo 'Cleaning up workspace...'
            cleanWs()
        }
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs above."
        }
    }
}
