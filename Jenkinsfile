pipeline {
    agent {
    docker {
        image 'python:3.11'
    }
}

    environment {
        DOCKER_REGISTRY = 'saipolaki'  // Replace with your Docker Hub username
        IMAGE_NAME = 'my-python-text'
        DEV_EC2_HOST = '3.110.218.88'        // Replace with your dev instance IP
        PROD_EC2_HOST = 'your-prod-instance-ip'      // Replace with your prod instance IP
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
                    python3 -m pip install --upgrade pip
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
        
        // stage('🧪 Unit Tests') {
        //     steps {
        //         echo 'Running unit tests...'
        //         sh '''
        //             cd app
        //             coverage run -m pytest tests/ -v
        //             coverage report
        //             coverage xml
        //         '''
        //     }
        // }
        
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
                script {
                    sh '''
                        # Install Trivy if not present
                        if ! command -v trivy &> /dev/null; then
                            echo "Installing Trivy..."
                            wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
                            echo "deb https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee -a /etc/apt/sources.list
                            sudo apt-get update
                            sudo apt-get install -y trivy
                        fi
                        
                        echo "Scanning image: ${FULL_IMAGE_NAME}"
                        trivy image --exit-code 0 --severity LOW,MEDIUM ${FULL_IMAGE_NAME}
                        trivy image --exit-code 1 --severity HIGH,CRITICAL ${FULL_IMAGE_NAME}
                    '''
                }
            }
        }
        
        stage('📤 Push to Registry') {
            steps {
                echo 'Pushing Docker image to registry...'
                script {
                    withCredentials([usernamePassword(credentialsId: 'docker-hub-credentials', 
                                                     usernameVariable: 'DOCKER_USERNAME', 
                                                     passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh '''
                            echo "Logging into Docker Hub..."
                            echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
                            
                            echo "Pushing images..."
                            docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${ENVIRONMENT}-latest
                        '''
                    }
                }
            }
        }
        
        stage('🚀 Deploy to Environment') {
            steps {
                echo "Deploying to ${env.ENVIRONMENT} environment..."
                script {
                    def targetHost = env.ENVIRONMENT == 'prod' ? env.PROD_EC2_HOST : env.DEV_EC2_HOST
                    
                    withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key', 
                                                       keyFileVariable: 'SSH_KEY')]) {
                        sh """
                            echo "Deploying to host: ${targetHost}"
                            
                            # Set correct permissions for SSH key
                            chmod 600 \$SSH_KEY
                            
                            # Copy Docker Compose file to target server
                            scp -i \$SSH_KEY -o StrictHostKeyChecking=no \
                                deploy/${env.ENVIRONMENT}/docker-compose.${env.ENVIRONMENT}.yml \
                                ec2-user@${targetHost}:/home/ec2-user/
                            
                            # Deploy the application
                            ssh -i \$SSH_KEY -o StrictHostKeyChecking=no ec2-user@${targetHost} '
                                export DOCKER_REGISTRY=${DOCKER_REGISTRY}
                                export IMAGE_NAME=${IMAGE_NAME}
                                export BUILD_NUMBER=${BUILD_NUMBER}
                                
                                echo "Stopping existing containers..."
                                docker-compose -f docker-compose.${ENVIRONMENT}.yml down || true
                                
                                echo "Pulling latest images..."
                                docker-compose -f docker-compose.${ENVIRONMENT}.yml pull
                                
                                echo "Starting new containers..."
                                docker-compose -f docker-compose.${ENVIRONMENT}.yml up -d
                                
                                echo "Cleaning up old images..."
                                docker system prune -f
                                
                                echo "Deployment completed!"
                            '
                        """
                    }
                }
            }
        }
        
        stage('🩺 Health Check') {
            steps {
                echo 'Performing health check...'
                script {
                    def targetHost = env.ENVIRONMENT == 'prod' ? env.PROD_EC2_HOST : env.DEV_EC2_HOST
                    def port = env.ENVIRONMENT == 'prod' ? '80' : '8000'
                    
                    sh """
                        echo "Waiting for application to start..."
                        sleep 30
                        
                        echo "Checking application health..."
                        for i in {1..10}; do
                            if curl -f http://${targetHost}:${port}/health; then
                                echo "✅ Application is healthy!"
                                exit 0
                            fi
                            echo "⏳ Attempt \$i failed, retrying in 10 seconds..."
                            sleep 10
                        done
                        
                        echo "❌ Health check failed after 10 attempts"
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
            echo "🌐 Application deployed to ${env.ENVIRONMENT} environment"
            script {
                def targetHost = env.ENVIRONMENT == 'prod' ? env.PROD_EC2_HOST : env.DEV_EC2_HOST
                def port = env.ENVIRONMENT == 'prod' ? '80' : '8000'
                echo "🔗 Access your application at: http://${targetHost}:${port}"
            }
        }
        failure {
            echo "❌ Pipeline failed!"
            echo "Please check the logs above for error details."
        }
    }
}
