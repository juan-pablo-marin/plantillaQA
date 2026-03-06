pipeline {
    agent any

    // --- Parámetros Visuales (Build with Parameters) ---
    parameters {
        booleanParam(name: 'RUN_NEWMAN', defaultValue: true, description: 'Ejecutar pruebas de API con Newman')
        booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Ejecutar análisis estático con SonarQube')
        booleanParam(name: 'RUN_PLAYWRIGHT', defaultValue: true, description: 'Ejecutar pruebas End-to-End con Playwright')
        booleanParam(name: 'RUN_K6', defaultValue: false, description: 'Ejecutar pruebas de estrés/rendimiento con k6')
    }

    // --- Ejecución Automática (Nightly Builds) ---
    triggers {
        // Ejecutar de lunes a viernes a la 1:00 AM
        cron('H 1 * * 1-5')
    }

    environment {
        // Obtenemos variables base
        ENVIRONMENT = 'qa'
        PROJECT_KEY = 'fuc-sena'
        
        // Forzar el nombre del proyecto de Docker Compose para que sea idéntico
        // al que usa la máquina anfitriona al levantar Jenkins (fichacaracterizacionv1)
        // y evitar conflictos de redes/volúmenes "app" vs "fichacaracterizacionv1".
        COMPOSE_PROJECT_NAME = 'fichacaracterizacionv1'

        // Comando base de Docker Compose con el override de Jenkins.
        // El override elimina bind mounts de archivos individuales que fallan
        // bajo Docker-in-Docker (el daemon resuelve rutas relativas desde el host,
        // no desde el contenedor de Jenkins).
        COMPOSE_CMD = 'docker compose --env-file /app/.env.qa -f /app/docker-compose.qa.yml -f /app/docker-compose.jenkins.yml'
        
        // Estas deberian venir de credenciales en Jenkins para seguridad
        // SONAR_TOKEN = credentials('sonar-token')
    }

    stages {
        stage('Preparar Entorno Docker') {
            steps {
                script {
                    echo "=> Limpiando entorno previo de QA..."
                    sh '''
                        ${COMPOSE_CMD} stop || true
                        ${COMPOSE_CMD} rm -f -v || true
                    '''
                }
            }
        }

        stage('Levantar Servicios y Dependencias QA') {
            steps {
                script {
                    echo "=> Levantando perfil de dependencias (SonarQube, Base de Datos)..."
                    // Levantamos SonarQube. El pipeline asume que docker y docker compose estan disponibles.
                    sh '${COMPOSE_CMD} --profile sonar up -d'
                }
            }
        }

        stage('Ejecutar Tests (QA Runner)') {
            steps {
                script {
                    echo "=> Ejecutando el QA Orchestrator (Frontend, Backend y Tests)..."
                    echo "=> Parametros recibidos: NEWMAN=${params.RUN_NEWMAN}, SONAR=${params.RUN_SONAR}, E2E=${params.RUN_PLAYWRIGHT}, K6=${params.RUN_K6}"
                    
                    // Inyectamos las variables locales de Jenkins dentro de la ejecución del compose.
                    // Esto sobrescribe lo que haya en .env.qa solo para esta ejecución del Runner.
                    sh """
                        export RUN_NEWMAN=${params.RUN_NEWMAN}
                        export RUN_SONAR=${params.RUN_SONAR}
                        export RUN_PLAYWRIGHT=${params.RUN_PLAYWRIGHT}
                        export RUN_K6=${params.RUN_K6}
                        
                        ${COMPOSE_CMD} --profile test-e2e up --build --abort-on-container-exit qa-runner
                    """
                }
            }
        }
    }

    post {
        always {
            script {
                echo "=> Recolectando resultados de Postman/Newman..."
                archiveArtifacts artifacts: 'qa/reports/newman/**/*', allowEmptyArchive: true
                
                echo "=> Recolectando reportes de Cobertura Go e Javascript..."
                archiveArtifacts artifacts: 'qa/reports/*.out, qa/reports/*.xml, qa/reports/*.json', allowEmptyArchive: true
                
                echo "=> Recolectando Resultados de Jmeter/K6..."
                archiveArtifacts artifacts: 'qa/reports/k6/**/*', allowEmptyArchive: true

                echo "=> Apagando y limpiando contenedores del Pipeline..."
                sh '''
                    ${COMPOSE_CMD} stop || true
                    ${COMPOSE_CMD} rm -f -v || true
                '''
            }
        }
        success {
            echo '¡El pipeline de QA se ejecuto con exito! Todas las pruebas seleccionadas pasaron.'
        }
        failure {
            echo 'El pipeline de QA fallo. Revisa los logs del contenedor fuc-qa-runner y los reportes generados.'
        }
    }
}
