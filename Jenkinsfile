pipeline {
    agent any

    parameters {
        booleanParam(name: 'RUN_NEWMAN',     defaultValue: true,  description: 'Ejecutar pruebas de API con Newman')
        booleanParam(name: 'RUN_SONAR',      defaultValue: true,  description: 'Ejecutar análisis estático con SonarQube')
        booleanParam(name: 'RUN_PLAYWRIGHT', defaultValue: true,  description: 'Ejecutar pruebas End-to-End con Playwright')
        booleanParam(name: 'RUN_K6',         defaultValue: false, description: 'Ejecutar pruebas de estrés/rendimiento con k6')
        booleanParam(name: 'RUN_CLAUDE',     defaultValue: false, description: 'Ejecutar análisis inteligente con Claude AI y generar reporte HTML')
    }

    triggers {
        cron('H 1 * * 1-5')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '15'))
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()
        ansiColor('xterm')
    }

    environment {
        ENVIRONMENT          = 'qa'
        COMPOSE_PROJECT_NAME = 'qa-pipeline'
        IS_FUC               = "${env.JOB_NAME?.toUpperCase()?.contains('FUC') ? 'true' : 'false'}"
        ENV_FILE             = "${env.IS_FUC == 'true' ? '/app/.env.qa_fuc' : '/app/.env.qa'}"
        QA_COMPOSE           = "${env.IS_FUC == 'true' ? '/app/docker-compose.qa_fuc.yml' : '/app/docker-compose.qa.yml'}"
        COMPOSE_CMD          = "docker compose --env-file ${env.ENV_FILE} -f ${env.QA_COMPOSE} -f /app/docker-compose.jenkins.yml"
        QA_REPORTS_DIR       = "${env.IS_FUC == 'true' ? '/qa/reports/fuc' : '/qa/reports/rav'}"
        JENKINS_REPORTS_DIR  = "${env.IS_FUC == 'true' ? '/app/qa/reports/fuc' : '/app/qa/reports/rav'}"
        RELATIVE_REPORTS_DIR = "${env.IS_FUC == 'true' ? 'qa/reports/fuc' : 'qa/reports/rav'}"
        BUILD_TIMESTAMP      = sh(script: 'date +%Y%m%d_%H%M%S', returnStdout: true).trim()
    }

    stages {

        stage('Preparar Entorno y Dependencias Docker') {
            steps {
                script {
                    echo "════════════════════════════════════════"
                    echo "PREPARANDO ENTORNO Y DEPENDENCIAS"
                    echo "════════════════════════════════════════"
                    sh '''
                        # Leer PROJECT_NAME del config actual (fuente unica de verdad)
                        PROJECT_NAME=$(grep '^PROJECT_NAME=' ${ENV_FILE} | cut -d'=' -f2 | tr -d '\r')
                        echo "=> PROJECT_NAME: $PROJECT_NAME"

                        echo "=> Limpiando contenedores transientes del build anterior..."
                        ${COMPOSE_CMD} stop db backend frontend || true
                        ${COMPOSE_CMD} rm -f db backend frontend || true
                        docker rm -f ${PROJECT_NAME}-mongodb-qa ${PROJECT_NAME}-postgres-qa ${PROJECT_NAME}-api-qa ${PROJECT_NAME}-frontend-qa 2>/dev/null || true
                        docker rm -f qa-runner-newman qa-runner-sonar qa-runner-e2e qa-runner-k6 ${PROJECT_NAME}-allure ${PROJECT_NAME}-allure-ui ${PROJECT_NAME}-allure-nginx 2>/dev/null || true
                        mkdir -p ${JENKINS_REPORTS_DIR}
                        mkdir -p ${JENKINS_REPORTS_DIR}/newman/anterior
                        rm -rf ${JENKINS_REPORTS_DIR}/coverage-backend.out ${JENKINS_REPORTS_DIR}/coverage-backend.xml ${JENKINS_REPORTS_DIR}/govet.txt ${JENKINS_REPORTS_DIR}/k6 ${JENKINS_REPORTS_DIR}/js-test-report.xml ${JENKINS_REPORTS_DIR}/go-test-report.json

                        echo "=> Levantando servicios persistentes (sin recrear si ya existen)..."
                        ${COMPOSE_CMD} --profile sonar up -d --no-recreate \
                            sonar-db sonarqube influxdb \
                        || {
                            echo "  WARN: Conflicto de contenedores (probable cambio de proyecto compose)."
                            echo "  Removiendo contenedores huerfanos y reintentando..."
                            docker rm -f ${PROJECT_NAME}-influxdb \
                                ${PROJECT_NAME}-sonar-db ${PROJECT_NAME}-sonarqube 2>/dev/null || true
                            ${COMPOSE_CMD} --profile sonar up -d \
                                sonar-db sonarqube influxdb
                        }


                        echo "=> Levantando Newman Report Viewer (http://localhost:8181)..."
                        docker rm -f ${PROJECT_NAME}-newman-viewer 2>/dev/null || true
                        ${COMPOSE_CMD} up -d --force-recreate newman-viewer || echo "  WARN: Newman viewer falló (no detiene pruebas)"

                        echo "=> Levantando Playwright Report Viewer (http://localhost:8182)..."
                        docker rm -f ${PROJECT_NAME}-playwright-viewer 2>/dev/null || true
                        ${COMPOSE_CMD} up -d --force-recreate playwright-viewer || echo "  WARN: Playwright viewer falló (no detiene pruebas)"

                        echo "=> Levantando Grafana (provisioning + dashboards montados desde el repo)..."
                        docker rm -f ${PROJECT_NAME}-grafana 2>/dev/null || true
                        ${COMPOSE_CMD} up -d --force-recreate grafana || echo "  WARN: Grafana falló al iniciar (no detiene pruebas)"
                        sleep 5

                        echo "=> Levantando servicios transientes de la aplicación..."
                        ${COMPOSE_CMD} --profile sonar up -d \
                            db backend frontend

                        echo "=> Configurando Grafana home dashboard..."
                        for i in $(seq 1 20); do
                            if docker exec ${PROJECT_NAME}-influxdb curl -sf http://grafana:3000/api/health 2>/dev/null | grep -q 'database.*ok'; then
                                docker exec ${PROJECT_NAME}-influxdb curl -sf -X PUT \
                                    -u admin:admin \
                                    -H 'Content-Type: application/json' \
                                    -d '{"homeDashboardUID":"k6-perf"}' \
                                    http://grafana:3000/api/org/preferences > /dev/null 2>&1 && \
                                    echo "  Home dashboard configurado: k6-perf" || \
                                    echo "  WARN: No se pudo configurar el home dashboard"
                                break
                            fi
                            echo "  Grafana no lista aun (intento $i/20)..."
                            sleep 3
                        done

                        echo "=> Construyendo QA Runner (Root Context)..."
                        ${COMPOSE_CMD} build qa-runner

                        echo "Entorno listo"
                    '''
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
                                ${COMPOSE_CMD} run --name qa-runner-newman \\
                                -e REPORTS_DIR=${QA_REPORTS_DIR} \\
                                -e RUN_NEWMAN=true \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=false \\
                                qa-runner || true
                            """
                            sh "mkdir -p ${JENKINS_REPORTS_DIR}/newman/anterior"
                            echo 'Newman: sin docker cp (bind mount ./qa/reports); se conserva el historial en qa/reports/newman/anteriores/'
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
                                -e REPORTS_DIR=${QA_REPORTS_DIR} \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=true \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=false \\
                                qa-runner || true
                            """
                            sh "mkdir -p ${JENKINS_REPORTS_DIR}/"
                            sh "docker cp qa-runner-sonar:${QA_REPORTS_DIR}/coverage-backend.out   ${JENKINS_REPORTS_DIR}/ || true"
                            sh "docker cp qa-runner-sonar:${QA_REPORTS_DIR}/coverage-backend.xml   ${JENKINS_REPORTS_DIR}/ || true"
                            sh "docker cp qa-runner-sonar:${QA_REPORTS_DIR}/js-test-report.xml     ${JENKINS_REPORTS_DIR}/ || true"
                            sh "docker cp qa-runner-sonar:/src/frontend/coverage/lcov.info          ${JENKINS_REPORTS_DIR}/coverage-frontend.lcov || true"
                            sh "docker cp qa-runner-sonar:${QA_REPORTS_DIR}/govet.txt              ${JENKINS_REPORTS_DIR}/ || true"
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
                                -e REPORTS_DIR=${QA_REPORTS_DIR} \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=true \\
                                -e RUN_K6=false \\
                                qa-runner || true
                            """
                            sh "mkdir -p ${JENKINS_REPORTS_DIR}/"
                            sh "docker cp qa-runner-e2e:${QA_REPORTS_DIR}/playwright-html ${JENKINS_REPORTS_DIR}/ || true"
                            sh "docker cp qa-runner-e2e:${QA_REPORTS_DIR}/playwright-results ${JENKINS_REPORTS_DIR}/ || true"
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
                                -e REPORTS_DIR=${QA_REPORTS_DIR} \\
                                -e RUN_NEWMAN=false \\
                                -e RUN_SONAR=false \\
                                -e RUN_PLAYWRIGHT=false \\
                                -e RUN_K6=true \\
                                -e K6_INFLUXDB_PUSH_INTERVAL=5s \\
                                -e K6_INFLUXDB_CONCURRENT_WRITES=4 \\
                                -e BUILD_NUMBER=${env.BUILD_NUMBER} \\
                                qa-runner || true
                            """
                            sh "mkdir -p ${JENKINS_REPORTS_DIR}/"
                            sh "docker cp qa-runner-k6:${QA_REPORTS_DIR}/k6 ${JENKINS_REPORTS_DIR}/ || true"
                            sh "docker rm -f qa-runner-k6 || true"
                        }
                    }
                }
            }
        }

        stage('Análisis Inteligente con Claude API') {
            when { expression { return params.RUN_CLAUDE } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    script {
                        echo "════════════════════════════════════════"
                        echo "ANALIZANDO RESULTADOS CON CLAUDE API"
                        echo "════════════════════════════════════════"
                        withCredentials([string(credentialsId: 'CLAUDE_API_KEY', variable: 'CLAUDE_API_KEY')]) {
                        sh '''
                            mkdir -p ${JENKINS_REPORTS_DIR}/claude-analysis

                            NEWMAN_DATA="{}"
                            [ -f "${JENKINS_REPORTS_DIR}/newman/summary.json" ] && \
                                NEWMAN_DATA=$(cat "${JENKINS_REPORTS_DIR}/newman/summary.json")

                            PLAYWRIGHT_DATA="{}"
                            [ -f "${JENKINS_REPORTS_DIR}/playwright/test-results.json" ] && \
                                PLAYWRIGHT_DATA=$(cat "${JENKINS_REPORTS_DIR}/playwright/test-results.json")

                            K6_DATA="{}"
                            [ -f "${JENKINS_REPORTS_DIR}/k6/summary.json" ] && \
                                K6_DATA=$(cat "${JENKINS_REPORTS_DIR}/k6/summary.json")

                            COVERAGE_DATA="{}"
                            [ -f "${JENKINS_REPORTS_DIR}/coverage-backend.xml" ] && \
                                COVERAGE_DATA='{"coverage":"present"}'

                            PROMPT_TEXT=$(printf '%s\n%s\n%s\n%s\n%s' \
                                "Eres un QA profesional senior. Analiza estos resultados y responde SOLO con JSON valido con estos campos: resumen_ejecutivo (string), metricas_clave (objeto con newman_tests, playwright_tests, k6_requests, coverage), riesgos_detectados (array), recomendaciones_prioritarias (array de 3), proximos_pasos (array de 2). SIN texto adicional, SOLO JSON." \
                                "Newman: $NEWMAN_DATA" \
                                "Playwright: $PLAYWRIGHT_DATA" \
                                "K6: $K6_DATA" \
                                "Coverage: $COVERAGE_DATA")

                            jq -n \
                                --arg model "claude-3-5-sonnet-20241022" \
                                --arg content "$PROMPT_TEXT" \
                                '{"model": $model, "max_tokens": 1024, "messages": [{"role": "user", "content": $content}]}' \
                                > /tmp/claude-payload.json

                            echo "Enviando análisis a Claude API..."

                            RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
                                -H "x-api-key: ${CLAUDE_API_KEY}" \
                                -H "anthropic-version: 2023-06-01" \
                                -H "content-type: application/json" \
                                -d @/tmp/claude-payload.json)

                            ANALYSIS=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')

                            if [ -z "$ANALYSIS" ]; then
                                echo "Claude API no devolvió análisis. Respuesta:"
                                echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
                                exit 1
                            fi

                            jq -n \
                                --arg ts "$(date -Iseconds)" \
                                --argjson bn "${BUILD_NUMBER}" \
                                --arg bu "${BUILD_URL}" \
                                --arg an "$ANALYSIS" \
                                '{"timestamp": $ts, "build_number": $bn, "build_url": $bu, "analysis": $an}' \
                                > ${JENKINS_REPORTS_DIR}/claude-analysis/analysis-report.json

                            echo "Análisis guardado"
                            echo "$ANALYSIS"
                        '''
                        }
                    }
                }
            }
        }

        stage('Generar Reporte HTML Visual') {
            when {
                allOf {
                    expression { return params.RUN_CLAUDE }
                    expression { return fileExists("${JENKINS_REPORTS_DIR}/claude-analysis/analysis-report.json") }
                }
            }
            steps {
                script {
                    echo "════════════════════════════════════════"
                    echo "GENERANDO HTML VISUAL"
                    echo "════════════════════════════════════════"
                    sh '''
                        REPORT_DIR="${JENKINS_REPORTS_DIR}"
                        ANALYSIS_FILE="${REPORT_DIR}/claude-analysis/analysis-report.json"

                        if [ ! -f "$ANALYSIS_FILE" ]; then
                            echo "Archivo de análisis no encontrado: $ANALYSIS_FILE"
                            exit 1
                        fi

                        BUILD_NUM=$(jq -r '.build_number' "$ANALYSIS_FILE")
                        TIMESTAMP=$(jq -r '.timestamp'    "$ANALYSIS_FILE")
                        ANALYSIS=$(jq  -r '.analysis'     "$ANALYSIS_FILE")

                        if echo "$ANALYSIS" | grep -Eqi "PASS|ÉXITO|SUCCESS|exitoso"; then
                            STATUS="EXITOSO"
                            COLOR="28a745"
                            BG="#d4edda"
                            BORDER="#c3e6cb"
                        elif echo "$ANALYSIS" | grep -Eqi "WARN|ATENCIÓN|WARNING"; then
                            STATUS="ATENCIÓN"
                            COLOR="ffc107"
                            BG="#fff3cd"
                            BORDER="#ffeeba"
                        else
                            STATUS="FALLÓ"
                            COLOR="dc3545"
                            BG="#f8d7da"
                            BORDER="#f5c6cb"
                        fi

                        ANALYSIS_HTML=$(printf '%s' "$ANALYSIS" | jq -sRr @html)

                        cat > ${REPORT_DIR}/claude-analysis/index.html <<HTML_EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>QA Analysis Report — Claude AI</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 30px;
            text-align: center;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .subtitle { font-size: 1.1em; opacity: 0.9; margin-bottom: 20px; }
        .build-info {
            display: flex;
            justify-content: center;
            gap: 30px;
            margin-top: 20px;
            padding-top: 20px;
            border-top: 1px solid rgba(255,255,255,0.3);
            font-size: 0.95em;
        }
        .content { padding: 40px 30px; }
        .status-section {
            border-radius: 8px;
            padding: 30px;
            margin-bottom: 40px;
            text-align: center;
        }
        .status-badge { font-size: 2em; font-weight: bold; margin-bottom: 15px; }
        .section { margin-bottom: 40px; }
        .section h2 {
            color: #667eea;
            font-size: 1.8em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #667eea;
        }
        .analysis-box {
            background: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 20px;
            border-radius: 4px;
            white-space: pre-wrap;
            word-break: break-word;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            max-height: 600px;
            overflow-y: auto;
        }
        .footer {
            background: #f8f9fa;
            border-top: 1px solid #dee2e6;
            padding: 20px 30px;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }
        @media (max-width: 768px) {
            .header { padding: 30px 20px; }
            .header h1 { font-size: 1.8em; }
            .content { padding: 20px 15px; }
            .build-info { flex-direction: column; gap: 15px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>QA Analysis Report</h1>
            <p class="subtitle">Análisis Inteligente con Claude AI</p>
            <div class="build-info">
                <span>Build #${BUILD_NUM}</span>
                <span>${TIMESTAMP}</span>
            </div>
        </div>
        <div class="content">
            <div class="status-section" style="background: ${BG}; border: 2px solid ${BORDER};">
                <div class="status-badge" style="color: #${COLOR};">${STATUS}</div>
                <div>Análisis completado con Claude AI</div>
            </div>
            <div class="section">
                <h2>Análisis Completo</h2>
                <div class="analysis-box">${ANALYSIS_HTML}</div>
            </div>
        </div>
        <div class="footer">
            <p>Claude AI QA Pipeline - Análisis Automatizado</p>
            <p>Generado: ${TIMESTAMP}</p>
        </div>
    </div>
</body>
</html>
HTML_EOF

                        echo "HTML generado en ${REPORT_DIR}/claude-analysis/index.html"
                    '''
                }
            }
        }

    }

    post {
        always {
            script {
                try {
                    sh 'ls -d ${JENKINS_REPORTS_DIR} 2>/dev/null && ls ${JENKINS_REPORTS_DIR}/ 2>/dev/null || echo "qa/reports no encontrado"'
                } catch (e) {
                    echo "No se pudo verificar reportes: ${e.message}"
                }

                dir('/app') {
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/newman/index.html")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/newman/**/*", allowEmptyArchive: true
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/coverage-backend.xml")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/coverage-backend.*", allowEmptyArchive: true
                            publishCoverage adapters: [
                                coberturaReportAdapter(path: "${env.RELATIVE_REPORTS_DIR}/coverage-backend.xml")
                            ], sourceFileResolver: sourceFiles('STORE_LAST_BUILD')
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/js-test-report.xml")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/js-test-report.xml", allowEmptyArchive: true
                            junit testResults: "${env.RELATIVE_REPORTS_DIR}/js-test-report.xml", allowEmptyResults: true
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/k6/summary.json")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/k6/**/*", allowEmptyArchive: true
                            perfReport filterRegex: '', sourceDataFiles: "${env.RELATIVE_REPORTS_DIR}/k6/*.xml"
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/govet.txt")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/govet.txt", allowEmptyArchive: true
                            recordIssues enabledForFailure: true, tool: goVet(pattern: "${env.RELATIVE_REPORTS_DIR}/govet.txt")
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/playwright-html/index.html")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/playwright-html/**/*", allowEmptyArchive: true
                            publishHTML(target: [
                                reportName         : 'Playwright E2E Report',
                                reportDir          : "${env.RELATIVE_REPORTS_DIR}/playwright-html",
                                reportFiles        : 'index.html',
                                keepAll            : true,
                                alwaysLinkToLastBuild: true,
                                allowMissing       : true
                            ])
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/newman/index.html")) {
                            publishHTML(target: [
                                reportName         : 'Newman API Report',
                                reportDir          : "${env.RELATIVE_REPORTS_DIR}/newman",
                                reportFiles        : 'index.html',
                                keepAll            : true,
                                alwaysLinkToLastBuild: true,
                                allowMissing       : true
                            ])
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/allure-results")) {
                            allure includeProperties: false, jdk: '', commandline: 'allure',
                                   results: [[path: "${env.RELATIVE_REPORTS_DIR}/allure-results"]],
                                   reportBuildPolicy: 'ALWAYS'
                        }
                    }

                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        if (fileExists("${env.RELATIVE_REPORTS_DIR}/claude-analysis/index.html")) {
                            archiveArtifacts artifacts: "${env.RELATIVE_REPORTS_DIR}/claude-analysis/**", allowEmptyArchive: true
                            publishHTML(target: [
                                reportName         : 'Claude AI Analysis Report',
                                reportDir          : "${env.RELATIVE_REPORTS_DIR}/claude-analysis",
                                reportFiles        : 'index.html',
                                keepAll            : true,
                                alwaysLinkToLastBuild: true,
                                allowMissing       : true
                            ])
                        }
                    }
                }

                try {
                    sh '''
                        PROJECT_NAME=$(grep '^PROJECT_NAME=' ${ENV_FILE} | cut -d'=' -f2 | tr -d '\r')
                        echo "=> Aguardando procesamiento CE task de SonarQube..."
                        sleep 30
                        echo "=> Apagando solo contenedores transientes de la aplicación..."
                        echo "   Servicios persistentes (activos para revisión post-ejecución):"
                        echo "     - SonarQube    → http://localhost:9000"
                        echo "     - Grafana      → http://localhost:3001"
                        echo "     - InfluxDB     → http://localhost:8086"
                        echo "     - Newman HTML  → http://localhost:8181  (historial: ${JENKINS_REPORTS_DIR}/newman/anteriores/ + reports-data.js)"
                        echo "     - Playwright   → http://localhost:8182"
                        echo "   Reportes HTML disponibles en Jenkins → Sidebar del build"
                        ${COMPOSE_CMD} stop db backend frontend || true
                        ${COMPOSE_CMD} rm -f db backend frontend || true
                        docker rm -f qa-runner-newman qa-runner-sonar qa-runner-e2e qa-runner-k6 2>/dev/null || true
                    '''
                } catch (e) {
                    echo "Limpieza post-pipeline omitida: ${e.message}"
                }
            }
        }

        success {
            echo 'El pipeline de QA se ejecutó con éxito!'
            script {
                if (env.DISCORD_WEBHOOK_URL) {
                    discordSend webhookURL: env.DISCORD_WEBHOOK_URL,
                        title      : "Éxito — ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        description: "Pipeline QA completado exitosamente",
                        result     : currentBuild.currentResult,
                        link       : env.BUILD_URL
                } else {
                    echo "Notificación Discord omitida (DISCORD_WEBHOOK_URL no definida)"
                }
            }
        }

        failure {
            echo 'El pipeline de QA falló. Revisa los logs.'
            script {
                if (env.DISCORD_WEBHOOK_URL) {
                    discordSend webhookURL: env.DISCORD_WEBHOOK_URL,
                        title      : "Fallo — ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        description: "Pipeline QA falló - Revisar logs inmediatamente",
                        result     : currentBuild.currentResult,
                        link       : env.BUILD_URL
                } else {
                    echo "Notificación Discord omitida (DISCORD_WEBHOOK_URL no definida)"
                }
            }
        }
    }
}
