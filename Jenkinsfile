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

    environment {
        ENVIRONMENT = 'qa'
        PROJECT_KEY = 'fuc-sena'
        COMPOSE_PROJECT_NAME = 'fichacaracterizacionv1'
        COMPOSE_CMD = 'docker compose --env-file /app/.env.qa -f /app/docker-compose.qa.yml -f /app/docker-compose.jenkins.yml'
        
        // Agregar credencial si existe, de momento la dejamos como variable de entorno o vacía
        // DISCORD_WEBHOOK = credentials('discord-webhook-qa') // Para el futuro
        DISCORD_WEBHOOK = "${env.DISCORD_WEBHOOK_URL ?: ''}"
    }

    stages {
        stage('Preparar Entorno y Dependencias Docker') {
            steps {
                script {
                    echo "=> Limpiando entorno previo de QA..."
                    sh '''
                        ${COMPOSE_CMD} stop || true
                        ${COMPOSE_CMD} rm -f -v || true
                    '''

                    echo "=> Levantando perfil Base (DB, Backend, Frontend, SonarQube DB/Server)..."
                    // Levantamos todo EXCEPTO los runners interactivos
                    sh '${COMPOSE_CMD} --profile sonar up -d db backend frontend sonar-db sonarqube influxdb grafana'

                    echo "=> Pre-construyendo QA Runner (Evita Race Conditions en stage Parallel)..."
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
                            sh """
                                ${COMPOSE_CMD} run --rm --name qa-runner-newman \\
                                -e RUN_NEWMAN=true \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=false \\
                                qa-runner
                            """
                        }
                    }
                }

                stage('Análisis Estático (SonarQube)') {
                    when { expression { return params.RUN_SONAR } }
                    steps {
                        script {
                            echo "=> Ejecutando Análisis SonarQube..."
                            sh """
                                ${COMPOSE_CMD} run --rm --name qa-runner-sonar \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=true \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=false \\
                                qa-runner
                            """
                        }
                    }
                }

                stage('End-to-End (Playwright)') {
                    when { expression { return params.RUN_PLAYWRIGHT } }
                    steps {
                        script {
                            echo "=> Ejecutando Playwright Tests..."
                            sh """
                                ${COMPOSE_CMD} run --rm --name qa-runner-e2e \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=true \\
                                -e RUN_K6=false \\
                                qa-runner
                            """
                        }
                    }
                }

                stage('Performance (k6)') {
                    when { expression { return params.RUN_K6 } }
                    steps {
                        script {
                            echo "=> Ejecutando k6 Tests..."
                            sh """
                                ${COMPOSE_CMD} run --rm --name qa-runner-k6 \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=true \\
                                qa-runner
                            """
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                // 1. Archivar artefactos en bruto
                archiveArtifacts artifacts: 'qa/reports/newman/**/*', allowEmptyArchive: true
                archiveArtifacts artifacts: 'qa/reports/*.out, qa/reports/*.xml, qa/reports/*.json', allowEmptyArchive: true
                archiveArtifacts artifacts: 'qa/reports/k6/**/*', allowEmptyArchive: true
                archiveArtifacts artifacts: 'qa/reports/playwright-html/**/*', allowEmptyArchive: true

                // 2. Publicar resultados JUnit tradicionales
                junit testResults: 'qa/reports/js-test-report.xml', allowEmptyResults: true

                // 3. Code Coverage API Plugin (Métricas de Cobertura Go)
                publishCoverage adapters: [
                    coberturaAdapter('qa/reports/coverage-backend.xml')
                ], sourceFileResolver: sourceFiles('STORE_LAST_BUILD')
                
                // 4. Performance Plugin (Resultados de k6)
                perfReport filterRegex: '', sourceDataFiles: 'qa/reports/k6/*.xml'

                // 5. Warnings Next Generation Plugin (Análisis Estático)
                recordIssues enabledForFailure: true, tool: goVet(pattern: 'qa/reports/govet.txt')

                // 6. Reportes HTML (Newman, Playwright)
                publishHTML(target: [
                    reportName: 'Newman API Report',
                    reportDir: 'qa/reports/newman',
                    reportFiles: 'index.html',
                    keepAll: true,
                    alwaysLinkToLastBuild: true,
                    allowMissing: true
                ])

                publishHTML(target: [
                    reportName: 'Playwright E2E Report',
                    reportDir: 'qa/reports/playwright-html',
                    reportFiles: 'index.html',
                    keepAll: true,
                    alwaysLinkToLastBuild: true,
                    allowMissing: true
                ])

                // 7. Dashboard Allure
                allure includeProperties: false, jdk: '', results: [[path: 'qa/reports/allure-results']], reportBuildPolicy: 'ALWAYS'

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
