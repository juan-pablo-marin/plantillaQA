pipeline {
    agent any

    // --- Parámetros Visuales (Build with Parameters) ---
    parameters {
        booleanParam(name: 'RUN_NEWMAN', defaultValue: true, description: 'Ejecutar pruebas de API con Newman')
        booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Ejecutar análisis estático con SonarQube')
        booleanParam(name: 'RUN_PLAYWRIGHT', defaultValue: true, description: 'Ejecutar pruebas End-to-End con Playwright')
        booleanParam(name: 'RUN_K6', defaultValue: false, description: 'Ejecutar pruebas de estrés/rendimiento con k6')
    }

    triggers {
        cron('H 1 * * 1-5')
    }

    options {
        ansiColor('xterm')
    }

    environment {
        ENVIRONMENT = 'qa'
        COMPOSE_PROJECT_NAME = 'fichacaracterizacionv1'
        COMPOSE_CMD = 'docker compose --env-file /app/.env.qa -f /app/docker-compose.qa.yml -f /app/docker-compose.jenkins.yml'
        
        // Agregar credencial si existe, de momento la dejamos como variable de entorno o vacía
        // DISCORD_WEBHOOK = credentials('discord-webhook-qa') // Para el futuro
        DISCORD_WEBHOOK = "${env.DISCORD_WEBHOOK_URL ?: ''}"
        
        // --- SONAR CONFIG ---
        // Se asume que el token viene de la configuración de Jenkins o archivo .env.qa
        // Referenciados directamente como \${env.SONAR_TOKEN} en los comandos sh
    }

    stages {
        stage('Preparar Entorno y Dependencias Docker') {
            steps {
                script {
                    echo "=> Limpiando entorno previo de QA..."
                    sh '''
                        ${COMPOSE_CMD} stop || true
                        ${COMPOSE_CMD} rm -f -v || true
                        # Forzar apagado de contenedores pesados de UI consumiendo recursos del host
                        docker stop fuc-allure fuc-allure-ui fuc-allure-nginx kiwitcmsdock || true
                        mkdir -p /app/qa/reports
                        rm -rf /app/qa/reports/*
                    '''

                    echo "=> Levantando perfil Base..."
                    sh '${COMPOSE_CMD} --profile sonar up -d db backend frontend sonar-db sonarqube influxdb grafana'

                    echo "=> Construyendo QA Runner (Root Context)..."
                    sh '${COMPOSE_CMD} build qa-runner'
                }
            }
        }

        stage('Tests en Paralelo') {
            parallel {
                stage('API (Newman)') {
                    when { expression { return params.RUN_NEWMAN } }
                    steps {
                        script {
                            echo "=> Ejecutando Newman Tests..."
                            // Removemos --rm para poder copiar los artefactos después
                            sh """
                                ${COMPOSE_CMD} run --name qa-runner-newman \\
                                -e RUN_NEWMAN=true \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=false \\
                                qa-runner || true
                            """
                            
                            echo "=> Extrayendo reportes Newman al workspace de Jenkins..."
                            // Usamos rura absoluta /app/qa/reports/ donde esta montado el proyecto
                            sh "mkdir -p /app/qa/reports/"
                            sh "docker cp qa-runner-newman:/qa/reports/newman /app/qa/reports/ || true"
                            
                            // Limpiamos el contenedor
                            sh "docker rm -f qa-runner-newman || true"
                        }
                    }
                }

                stage('Análisis Estático (SonarQube)') {
                    when { expression { return params.RUN_SONAR } }
                    steps {
                        script {
                            echo "=> Ejecutando Análisis SonarQube..."
                            sh """
                                ${COMPOSE_CMD} run --name qa-runner-sonar \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=true \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=false \\
                                ${env.SONAR_TOKEN ? "-e SONAR_TOKEN=${env.SONAR_TOKEN}" : ""} \\
                                -e PROJECT_KEY=${env.PROJECT_KEY ?: 'fuc-sena'} \\
                                qa-runner || true
                            """
                            
                            echo "=> Extrayendo reportes de cobertura al workspace de Jenkins..."
                            sh "mkdir -p /app/qa/reports/"
                            sh "docker cp qa-runner-sonar:/qa/reports/coverage-backend.out /app/qa/reports/ || true"
                            sh "docker cp qa-runner-sonar:/qa/reports/coverage-backend.xml /app/qa/reports/ || true"
                            sh "docker cp qa-runner-sonar:/qa/reports/js-test-report.xml /app/qa/reports/ || true"
                            sh "docker cp qa-runner-sonar:/app/fuc-app-web/coverage/lcov.info /app/qa/reports/coverage-frontend.lcov || true"
                            sh "docker cp qa-runner-sonar:/qa/reports/govet.txt /app/qa/reports/ || true"
                            
                            sh "docker rm -f qa-runner-sonar || true"
                        }
                    }
                }

                stage('End-to-End (Playwright)') {
                    when { expression { return params.RUN_PLAYWRIGHT } }
                    steps {
                        script {
                            echo "=> Ejecutando Playwright Tests..."
                            sh """
                                ${COMPOSE_CMD} run --name qa-runner-e2e \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=true \\
                                -e RUN_K6=false \\
                                qa-runner || true
                            """
                            
                            echo "=> Extrayendo reportes Playwright al workspace de Jenkins..."
                            sh "mkdir -p /app/qa/reports/"
                            sh "docker cp qa-runner-e2e:/qa/reports/playwright /app/qa/reports/ || true"
                            sh "docker cp qa-runner-e2e:/qa/reports/playwright-html /app/qa/reports/ || true"
                            
                            sh "docker rm -f qa-runner-e2e || true"
                        }
                    }
                }

                stage('Performance (k6)') {
                    when { expression { return params.RUN_K6 } }
                    steps {
                        script {
                            echo "=> Ejecutando k6 Tests..."
                            sh """
                                ${COMPOSE_CMD} run --name qa-runner-k6 \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=true \\
                                qa-runner || true
                            """
                            
                            echo "=> Extrayendo reportes k6 al workspace de Jenkins..."
                            sh "mkdir -p /app/qa/reports/"
                            sh "docker cp qa-runner-k6:/qa/reports/k6 /app/qa/reports/ || true"
                            
                            sh "docker rm -f qa-runner-k6 || true"
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                // Diagnóstico de rutas
                sh 'ls -d /app/qa/reports 2>/dev/null && ls /app/qa/reports/newman/ 2>/dev/null || echo "qa/reports no encontrado en /app"'

                dir('/app') {
                    // 1. Newman artifacts
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/newman/index.html')) {
                            archiveArtifacts artifacts: 'qa/reports/newman/**/*', allowEmptyArchive: true
                        }
                    }

                    // 2. Cobertura & reportes unitarios (solo si Sonar corrió)
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/coverage-backend.xml')) {
                            archiveArtifacts artifacts: 'qa/reports/coverage-backend.*', allowEmptyArchive: true
                            publishCoverage adapters: [
                                coberturaReportAdapter(path: 'qa/reports/coverage-backend.xml')
                            ], sourceFileResolver: sourceFiles('STORE_LAST_BUILD')
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/js-test-report.xml')) {
                            archiveArtifacts artifacts: 'qa/reports/js-test-report.xml', allowEmptyArchive: true
                            junit testResults: 'qa/reports/js-test-report.xml', allowEmptyResults: true
                        }
                    }

                    // 3. k6 Performance
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/k6/summary.json')) {
                            archiveArtifacts artifacts: 'qa/reports/k6/**/*', allowEmptyArchive: true
                            perfReport filterRegex: '', sourceDataFiles: 'qa/reports/k6/*.xml'
                        }
                    }

                    // 4. Go Vet (Warnings NG)
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/govet.txt')) {
                            archiveArtifacts artifacts: 'qa/reports/govet.txt', allowEmptyArchive: true
                            recordIssues enabledForFailure: true, tool: goVet(pattern: 'qa/reports/govet.txt')
                        }
                    }

                    // 5. Playwright
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/playwright-html/index.html')) {
                            archiveArtifacts artifacts: 'qa/reports/playwright-html/**/*', allowEmptyArchive: true
                            publishHTML(target: [
                                reportName: 'Playwright E2E Report',
                                reportDir: 'qa/reports/playwright-html',
                                reportFiles: 'index.html',
                                keepAll: true,
                                alwaysLinkToLastBuild: true,
                                allowMissing: true
                            ])
                        }
                    }

                    // 6. Newman HTML Report (auto-contenido, no necesita servidor)
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/newman/index.html')) {
                            publishHTML(target: [
                                reportName: 'Newman API Report',
                                reportDir: 'qa/reports/newman',
                                reportFiles: 'index.html',
                                keepAll: true,
                                alwaysLinkToLastBuild: true,
                                allowMissing: true
                            ])
                        }
                    }

                    // 7. Allure
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists('qa/reports/allure-results')) {
                            allure includeProperties: false, jdk: '', commandline: 'allure', results: [[path: 'qa/reports/allure-results']], reportBuildPolicy: 'ALWAYS'
                        }
                    }
                }

                // 8. Cleanup
                echo "=> Apagando y limpiando contenedores del Pipeline..."
                sh '''
                    ${COMPOSE_CMD} stop || true
                    ${COMPOSE_CMD} rm -f -v || true
                '''
            }
        }
        success {
            echo '¡El pipeline de QA se ejecuto con exito!'
            script {
                if (env.DISCORD_WEBHOOK) {
                    discordSend webhookURL: env.DISCORD_WEBHOOK, title: "✅ Éxito en Pipeline QA - ${env.JOB_NAME} #${env.BUILD_NUMBER}", result: currentBuild.currentResult, link: env.BUILD_URL
                }
            }
        }
        failure {
            echo 'El pipeline de QA fallo. Revisa los logs.'
            script {
                if (env.DISCORD_WEBHOOK) {
                    discordSend webhookURL: env.DISCORD_WEBHOOK, title: "❌ Fallo en Pipeline QA - ${env.JOB_NAME} #${env.BUILD_NUMBER}", result: currentBuild.currentResult, link: env.BUILD_URL
                }
            }
        }
    }
}
