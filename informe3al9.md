Started by user unknown or anonymous
[Pipeline] Start of Pipeline
[Pipeline] node
Running on Jenkins in /var/jenkins_home/workspace/fuc-sena
[Pipeline] {
[Pipeline] sh
+ date +%Y%m%d_%H%M%S
[Pipeline] withEnv
[Pipeline] {
[Pipeline] timeout
Timeout set to expire in 1 hr 0 min
[Pipeline] {
[Pipeline] ansiColor
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Preparar Entorno y Dependencias Docker)
[Pipeline] script
[Pipeline] {
[Pipeline] echo
════════════════════════════════════════
[Pipeline] echo
PREPARANDO ENTORNO Y DEPENDENCIAS
[Pipeline] echo
════════════════════════════════════════
[Pipeline] sh
+ export DOCKER_BUILDKIT=1
+ export COMPOSE_DOCKER_CLI_BUILD=1
+ export COMPOSE_PROJECT_NAME=qa-pipeline
+ export COMPOSE_PROFILES=test-e2e,sonar
+ grep ^PROJECT_NAME= /app/.env.qa_fuc
+ cut -d= -f2
+ tr -d 
+ PROJECT_NAME=fuc-qa-stack
+ echo => PROJECT_NAME: fuc-qa-stack
=> PROJECT_NAME: fuc-qa-stack
+ echo => Compose project: qa-pipeline (mismo que RAV; no usar nombre de carpeta del repo)
=> Compose project: qa-pipeline (mismo que RAV; no usar nombre de carpeta del repo)
+ echo => Limpiando contenedores transientes del build anterior...
=> Limpiando contenedores transientes del build anterior...
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml stop db backend frontend
 Container fuc-qa-stack-frontend-qa Stopping 
 Container fuc-qa-stack-frontend-qa Stopped 
 Container fuc-qa-stack-api-qa Stopping 
 Container fuc-qa-stack-api-qa Stopped 
 Container fuc-qa-stack-postgres-qa Stopping 
 Container fuc-qa-stack-postgres-qa Stopped 
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml rm -f db backend frontend
Going to remove fuc-qa-stack-frontend-qa, fuc-qa-stack-api-qa, fuc-qa-stack-postgres-qa
 Container fuc-qa-stack-frontend-qa Removing 
 Container fuc-qa-stack-api-qa Removing 
 Container fuc-qa-stack-postgres-qa Removing 
 Container fuc-qa-stack-frontend-qa Removed 
 Container fuc-qa-stack-postgres-qa Removed 
 Container fuc-qa-stack-api-qa Removed 
+ docker rm -f fuc-qa-stack-postgres-qa fuc-qa-stack-api-qa fuc-qa-stack-frontend-qa
+ docker rm -f qa-runner-newman qa-runner-sonar qa-runner-e2e qa-runner-k6
+ mkdir -p qa_reports_ws
+ mkdir -p qa_reports_ws/newman/anterior
+ rm -rf qa_reports_ws/coverage-backend.out qa_reports_ws/coverage-backend.xml qa_reports_ws/govet.txt qa_reports_ws/k6 qa_reports_ws/js-test-report.xml qa_reports_ws/go-test-report.json
+ echo => Levantando servicios persistentes (sin recrear si ya existen)...
=> Levantando servicios persistentes (sin recrear si ya existen)...
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d --no-recreate sonar-db sonarqube influxdb
 Container fuc-qa-stack-influxdb Running 
 Container fuc-qa-stack-sonar-db Running 
 Container fuc-qa-stack-sonarqube Running 
 Container fuc-qa-stack-sonar-db Waiting 
 Container fuc-qa-stack-sonar-db Healthy 
+ echo => Levantando cadvisor -> prometheus (orden explicito; evita estado Created sin start)...
=> Levantando cadvisor -> prometheus (orden explicito; evita estado Created sin start)...
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d cadvisor
 Container fuc-qa-stack-cadvisor Running 
+ sleep 3
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d --build prometheus
 Image qa-pipeline-prometheus Building 
#1 [internal] load local bake definitions
#1 reading from stdin 498B done
#1 DONE 0.0s

#2 [internal] load build definition from Dockerfile.prometheus
#2 transferring dockerfile: 237B done
#2 DONE 0.0s

#3 [internal] load metadata for docker.io/prom/prometheus:v2.54.1
#3 DONE 0.2s

#4 [internal] load .dockerignore
#4 transferring context: 2.33kB done
#4 DONE 0.0s

#5 [1/2] FROM docker.io/prom/prometheus:v2.54.1@sha256:f6639335d34a77d9d9db382b92eeb7fc00934be8eae81dbc03b31cfe90411a94
#5 DONE 0.0s

#6 [internal] load build context
#6 transferring context: 105B 0.0s done
#6 DONE 0.0s

#7 [2/2] COPY qa/prometheus/prometheus.yml /etc/prometheus/prometheus.yml
#7 CACHED

#8 exporting to image
#8 exporting layers done
#8 writing image sha256:62351638b73510fa351164855f75c4ad05ab19de496707592ce88708b7518ddb done
#8 naming to docker.io/library/qa-pipeline-prometheus done
#8 DONE 0.0s

#9 resolving provenance for metadata file
#9 DONE 0.0s
 Image qa-pipeline-prometheus Built 
 Container fuc-qa-stack-cadvisor Running 
 Container fuc-qa-stack-prometheus Running 
+ sleep 2
+ C=fuc-qa-stack-cadvisor
+ docker inspect --format={{.State.Status}} fuc-qa-stack-cadvisor
+ ST=running
+ [ running = created ]
+ C=fuc-qa-stack-prometheus
+ docker inspect --format={{.State.Status}} fuc-qa-stack-prometheus
+ ST=running
+ [ running = created ]
+ echo => Levantando Report Viewers (preserva reportes entre builds)...
=> Levantando Report Viewers (preserva reportes entre builds)...
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d newman-viewer
 Container fuc-qa-stack-newman-viewer Running 
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d playwright-viewer
 Container fuc-qa-stack-playwright-viewer Running 
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d security-viewer
 Container fuc-qa-stack-security-viewer Running 
+ echo => Levantando Grafana (provisioning embebido en imagen)...
=> Levantando Grafana (provisioning embebido en imagen)...
+ docker rm -f fuc-qa-stack-grafana
fuc-qa-stack-grafana
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile test-e2e --profile sonar up -d --build grafana
 Image qa-pipeline-grafana Building 
 Image qa-pipeline-prometheus Building 
#1 [internal] load local bake definitions
#1 reading from stdin 894B done
#1 DONE 0.0s

#2 [prometheus internal] load build definition from Dockerfile.prometheus
#2 transferring dockerfile: 237B done
#2 DONE 0.0s

#3 [grafana internal] load build definition from Dockerfile.grafana
#3 transferring dockerfile: 1.19kB done
#3 DONE 0.0s

#4 [prometheus internal] load metadata for docker.io/prom/prometheus:v2.54.1
#4 DONE 0.1s

#5 [grafana internal] load metadata for docker.io/grafana/grafana:latest
#5 DONE 0.3s

#6 [prometheus internal] load .dockerignore
#6 transferring context: 2.33kB done
#6 DONE 0.0s

#7 [prometheus 1/2] FROM docker.io/prom/prometheus:v2.54.1@sha256:f6639335d34a77d9d9db382b92eeb7fc00934be8eae81dbc03b31cfe90411a94
#7 DONE 0.0s

#8 [prometheus internal] load build context
#8 transferring context: 105B done
#8 DONE 0.0s

#9 [prometheus 2/2] COPY qa/prometheus/prometheus.yml /etc/prometheus/prometheus.yml
#9 CACHED

#10 [prometheus] exporting to image
#10 exporting layers done
#10 writing image sha256:62351638b73510fa351164855f75c4ad05ab19de496707592ce88708b7518ddb done
#10 naming to docker.io/library/qa-pipeline-prometheus done
#10 DONE 0.0s

#6 [grafana internal] load .dockerignore
#6 transferring context: 2.33kB done
#6 DONE 0.0s

#11 [grafana 1/4] FROM docker.io/grafana/grafana:latest@sha256:0f86bada30d65ef9d0183b90c1e2682ac92d53d95da8bed322b984ea78a4a73a
#11 DONE 0.0s

#12 [grafana internal] load build context
#12 transferring context: 556B done
#12 DONE 0.0s

#13 [grafana 2/4] COPY ./qa/grafana/provisioning/datasources/ /etc/grafana/provisioning/datasources/
#13 CACHED

#14 [grafana 3/4] COPY ./qa/grafana/provisioning/dashboards/ /etc/grafana/provisioning/dashboards/
#14 CACHED

#15 [prometheus] resolving provenance for metadata file
#15 DONE 0.0s

#16 [grafana 4/4] COPY ./qa/grafana/dashboards/ /etc/grafana/dashboards/
#16 CACHED

#17 [grafana] exporting to image
#17 exporting layers done
#17 writing image sha256:27da4ec79b040a640b37d2d5dda5730a4c97f0a4991f3c024d36785ab2443dac done
#17 naming to docker.io/library/qa-pipeline-grafana done
#17 DONE 0.0s

#18 [grafana] resolving provenance for metadata file
#18 DONE 0.0s
 Image qa-pipeline-prometheus Built 
 Image qa-pipeline-grafana Built 
 Container fuc-qa-stack-cadvisor Running 
 Container fuc-qa-stack-influxdb Running 
 Container fuc-qa-stack-prometheus Running 
 Container fuc-qa-stack-grafana Creating 
 Container fuc-qa-stack-grafana Created 
 Container fuc-qa-stack-influxdb Waiting 
 Container fuc-qa-stack-influxdb Healthy 
 Container fuc-qa-stack-grafana Starting 
 Container fuc-qa-stack-grafana Started 
+ docker inspect --format={{.State.Status}} fuc-qa-stack-grafana
+ G_ST=running
+ [ running = created ]
+ sleep 5
+ echo => Levantando servicios transientes de la aplicación...
=> Levantando servicios transientes de la aplicación...
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml --profile sonar up -d db backend frontend
 Container fuc-qa-stack-postgres-qa Creating 
 Container fuc-qa-stack-postgres-qa Created 
 Container fuc-qa-stack-api-qa Creating 
 Container fuc-qa-stack-api-qa Created 
 Container fuc-qa-stack-frontend-qa Creating 
 Container fuc-qa-stack-frontend-qa Created 
 Container fuc-qa-stack-postgres-qa Starting 
 Container fuc-qa-stack-postgres-qa Started 
 Container fuc-qa-stack-postgres-qa Waiting 
 Container fuc-qa-stack-postgres-qa Healthy 
 Container fuc-qa-stack-api-qa Starting 
 Container fuc-qa-stack-api-qa Started 
 Container fuc-qa-stack-frontend-qa Starting 
 Container fuc-qa-stack-frontend-qa Started 
+ echo => Esperando healthchecks (db + backend + influx; hasta ~9 min por migraciones / arranque)...
=> Esperando healthchecks (db + backend + influx; hasta ~9 min por migraciones / arranque)...
+ DB_CTN=fuc-qa-stack-postgres-qa
+ seq 1 180
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-postgres-qa
+ DB_ST=healthy
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-api-qa
+ BE_ST=starting
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-influxdb
+ IN_ST=healthy
+ IN_PING=bad
+ docker exec fuc-qa-stack-influxdb sh -c wget -q -O- http://127.0.0.1:8086/ping >/dev/null 2>&1 || curl -sf http://127.0.0.1:8086/ping >/dev/null
+ IN_PING=ok
+ IN_OK=0
+ [ healthy = healthy ]
+ IN_OK=1
+ [ healthy = healthy ]
+ [ starting = healthy ]
+ echo   ... espera 1/180: db=healthy backend=starting influxdb=healthy ping=ok
  ... espera 1/180: db=healthy backend=starting influxdb=healthy ping=ok
+ sleep 3
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-postgres-qa
+ DB_ST=healthy
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-api-qa
+ BE_ST=starting
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-influxdb
+ IN_ST=healthy
+ IN_PING=bad
+ docker exec fuc-qa-stack-influxdb sh -c wget -q -O- http://127.0.0.1:8086/ping >/dev/null 2>&1 || curl -sf http://127.0.0.1:8086/ping >/dev/null
+ IN_PING=ok
+ IN_OK=0
+ [ healthy = healthy ]
+ IN_OK=1
+ [ healthy = healthy ]
+ [ starting = healthy ]
+ echo   ... espera 2/180: db=healthy backend=starting influxdb=healthy ping=ok
  ... espera 2/180: db=healthy backend=starting influxdb=healthy ping=ok
+ sleep 3
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-postgres-qa
+ DB_ST=healthy
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-api-qa
+ BE_ST=healthy
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-influxdb
+ IN_ST=healthy
+ IN_PING=bad
+ docker exec fuc-qa-stack-influxdb sh -c wget -q -O- http://127.0.0.1:8086/ping >/dev/null 2>&1 || curl -sf http://127.0.0.1:8086/ping >/dev/null
+ IN_PING=ok
+ IN_OK=0
+ [ healthy = healthy ]
+ IN_OK=1
+ [ healthy = healthy ]
+ [ healthy = healthy ]
+ [ 1 = 1 ]
+ echo  OK: db=healthy backend=healthy influxdb(health=healthy ping=ok)
 OK: db=healthy backend=healthy influxdb(health=healthy ping=ok)
+ break
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-api-qa
+ BE_ST=healthy
+ docker inspect --format={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} fuc-qa-stack-postgres-qa
+ DB_ST=healthy
+ [ healthy != healthy ]
+ [ healthy != healthy ]
+ echo => Configurando Grafana home dashboard...
=> Configurando Grafana home dashboard...
+ seq 1 20
+ docker exec fuc-qa-stack-influxdb curl -sf http://grafana:3000/api/health
+ grep -q database.*ok
+ sleep 5
+ docker exec fuc-qa-stack-influxdb curl -sf -X PUT -u admin:admin -H Content-Type: application/json -d {"homeDashboardUID":"k6-perf"} http://grafana:3000/api/org/preferences
+ echo   Home dashboard configurado: k6-perf
  Home dashboard configurado: k6-perf
+ break
+ echo => Construyendo QA Runner (Root Context)...
=> Construyendo QA Runner (Root Context)...
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml build qa-runner
 Image qa-pipeline-backend Building 
 Image qa-pipeline-qa-runner Building 
 Image qa-pipeline-frontend Building 
#1 [internal] load local bake definitions
#1 reading from stdin 1.38kB done
#1 DONE 0.0s

#2 [internal] load build definition from Dockerfile.qa
#2 transferring dockerfile: 4.33kB done
#2 DONE 0.0s

#3 [internal] load metadata for docker.io/library/node:20-bookworm
#3 DONE 0.2s

#4 [internal] load .dockerignore
#4 transferring context: 2.33kB done
#4 DONE 0.0s

#5 [stage-0  1/21] FROM docker.io/library/node:20-bookworm@sha256:8f693eaa7e0a8e71560c9a82b55fd54c2ae920a2ba5d2cde28bac7d1c01c9ba5
#5 DONE 0.0s

#6 [internal] load build context
#6 transferring context: 13.19MB 0.1s done
#6 DONE 0.1s

#7 [stage-0 13/21] RUN mkdir -p /opt/zap && cat > /opt/zap/zap-wrapper.sh <<'ZAPWRAPPER'
#7 CACHED

#8 [stage-0 10/21] RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg     && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list     && apt-get update     && apt-get install -y --no-install-recommends google-chrome-stable     && rm -rf /var/lib/apt/lists/*
#8 CACHED

#9 [stage-0  5/21] RUN go install github.com/boumenot/gocover-cobertura@latest     && mv /root/go/bin/gocover-cobertura /usr/local/bin/
#9 CACHED

#10 [stage-0  6/21] RUN corepack enable && corepack prepare pnpm@latest --activate
#10 CACHED

#11 [stage-0  7/21] RUN --mount=type=cache,target=/root/.npm     npm install -g newman
#11 CACHED

#12 [stage-0 16/21] COPY qa/package.json ./
#12 CACHED

#13 [stage-0 17/21] RUN --mount=type=cache,target=/root/.npm     npm install
#13 CACHED

#14 [stage-0 18/21] COPY qa/ /qa/
#14 CACHED

#15 [stage-0 20/21] COPY FRONTEND/ /src/frontend/
#15 CACHED

#16 [stage-0 14/21] RUN chmod +x /opt/zap/zap-wrapper.sh     && ln -sf /opt/zap/zap-wrapper.sh /usr/local/bin/zap-check
#16 CACHED

#17 [stage-0  4/21] RUN curl -sSL https://go.dev/dl/go1.25.0.linux-amd64.tar.gz | tar -C /usr/local -xzf -
#17 CACHED

#18 [stage-0 11/21] RUN curl -sSLo /tmp/k6.deb https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.deb     && dpkg -i /tmp/k6.deb     && rm /tmp/k6.deb
#18 CACHED

#19 [stage-0  9/21] RUN npx playwright install --with-deps chromium
#19 CACHED

#20 [stage-0  8/21] RUN --mount=type=cache,target=/root/.npm     npm install -g playwright
#20 CACHED

#21 [stage-0 15/21] RUN curl -sSLo /tmp/sonar-scanner.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-6.2.1.4610-linux-x64.zip     && unzip /tmp/sonar-scanner.zip -d /opt     && mv /opt/sonar-scanner-* /opt/sonar-scanner     && ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner     && rm /tmp/sonar-scanner.zip
#21 CACHED

#22 [stage-0 19/21] COPY BACKEND/ /src/backend/
#22 CACHED

#23 [stage-0  3/21] RUN --mount=type=cache,target=/var/cache/apt,sharing=locked     --mount=type=cache,target=/var/lib/apt,sharing=locked     apt-get update && apt-get install -y     curl     unzip     wget     default-jre     python3     python3-pip     git     ca-certificates     && rm -rf /var/lib/apt/lists/*
#23 CACHED

#24 [stage-0  2/21] WORKDIR /qa
#24 CACHED

#25 [stage-0 12/21] RUN --mount=type=cache,target=/root/.cache/pip     pip3 install --break-system-packages python-owasp-zap-v2.4 requests
#25 CACHED

#26 [stage-0 21/21] RUN sed -i 's/\r$//' /qa/run-tests.sh /qa/run-tests_fuc.sh     && chmod +x /qa/run-tests.sh /qa/run-tests_fuc.sh
#26 CACHED

#27 exporting to image
#27 exporting layers done
#27 writing image sha256:2c9dd0ede423fe775d04cbb31f70ec3bd03151b01368015232ae3c842fd00107 done
#27 naming to docker.io/library/qa-pipeline-qa-runner done
#27 DONE 0.0s

#28 resolving provenance for metadata file
#28 DONE 0.0s
 Image qa-pipeline-qa-runner Built 
+ echo Entorno listo
Entorno listo
[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Tests en Paralelo)
[Pipeline] parallel
[Pipeline] { (Branch: API (Newman))
[Pipeline] { (Branch: Análisis Estático (SonarQube))
[Pipeline] { (Branch: End-to-End (Playwright))
[Pipeline] { (Branch: Performance (k6))
[Pipeline] { (Branch: Usabilidad (Accesibilidad + Lighthouse))
[Pipeline] { (Branch: Security (OWASP ZAP + CSRF/XSS))
[Pipeline] stage
[Pipeline] { (API (Newman))
[Pipeline] stage
[Pipeline] { (Análisis Estático (SonarQube))
[Pipeline] stage
[Pipeline] { (End-to-End (Playwright))
[Pipeline] stage
[Pipeline] { (Performance (k6))
[Pipeline] stage
[Pipeline] { (Usabilidad (Accesibilidad + Lighthouse))
[Pipeline] stage
[Pipeline] { (Security (OWASP ZAP + CSRF/XSS))
Stage "API (Newman)" skipped due to when conditional
[Pipeline] getContext
[Pipeline] }
Stage "End-to-End (Playwright)" skipped due to when conditional
[Pipeline] getContext
[Pipeline] }
Stage "Performance (k6)" skipped due to when conditional
[Pipeline] getContext
[Pipeline] }
Stage "Usabilidad (Accesibilidad + Lighthouse)" skipped due to when conditional
[Pipeline] getContext
[Pipeline] }
Stage "Security (OWASP ZAP + CSRF/XSS)" skipped due to when conditional
[Pipeline] getContext
[Pipeline] }
[Pipeline] script
[Pipeline] {
[Pipeline] // stage
[Pipeline] // stage
[Pipeline] // stage
[Pipeline] // stage
[Pipeline] // stage
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] echo
=> Ejecutando Análisis SonarQube...
[Pipeline] sh
+ docker compose -p qa-pipeline --env-file /app/.env.qa_fuc -f /app/docker-compose.qa_fuc.yml -f /app/docker-compose.jenkins.yml run --no-deps --name qa-runner-sonar -e REPORTS_DIR=/qa/reports/fuc -e RUN_NEWMAN=false -e RUN_SONAR=true -e RUN_PLAYWRIGHT=false -e RUN_K6=false qa-runner
 Container qa-runner-sonar Creating 
 Container qa-runner-sonar Created 
============================================
 QA Runner - Iniciando
 Backend:    http://backend:8080
 Frontend:   https://ape-fuc.estebandev.tech
 Sonar:      http://sonarqube:9000
--------------------------------------------
 Newman:        RUN_NEWMAN=false
 SonarQube:     RUN_SONAR=true
 Playwright:    RUN_PLAYWRIGHT=false  (video=on)
 k6:            RUN_K6=false
 Accessibility: RUN_ACCESSIBILITY=false
 Security:      RUN_SECURITY=false  (zap_save_session=false)
============================================
[0/6] Preparando carpetas de reportes...
[0.5/6] Ejecutando Tests Unitarios (Backend & Frontend)...
  Running Go tests...
go: downloading github.com/joho/godotenv v1.5.1
go: downloading github.com/go-chi/chi/v5 v5.2.5
go: downloading github.com/golang-migrate/migrate/v4 v4.19.1
go: downloading gorm.io/gorm v1.31.1
go: downloading github.com/go-playground/validator/v10 v10.30.1
go: downloading github.com/jackc/pgx/v5 v5.9.1
go: downloading golang.org/x/crypto v0.46.0
go: downloading github.com/golang-jwt/jwt/v5 v5.3.1
go: downloading gorm.io/driver/postgres v1.6.0
go: downloading go.mongodb.org/mongo-driver v1.17.8
go: downloading github.com/jinzhu/now v1.1.5
go: downloading github.com/go-playground/universal-translator v0.18.1
go: downloading github.com/leodido/go-urn v1.4.0
go: downloading github.com/gabriel-vasile/mimetype v1.4.12
go: downloading golang.org/x/text v0.35.0
go: downloading github.com/lib/pq v1.10.9
go: downloading github.com/jinzhu/inflection v1.0.0
go: downloading github.com/jackc/pgpassfile v1.0.0
go: downloading github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761
go: downloading github.com/go-playground/locales v0.14.1
go: downloading github.com/jackc/puddle/v2 v2.2.2
go: downloading golang.org/x/sync v0.20.0
go: downloading golang.org/x/sys v0.39.0
go: downloading github.com/youmark/pkcs8 v0.0.0-20240726163527-a2c0da244d78
go: downloading github.com/klauspost/compress v1.16.7
go: downloading github.com/golang/snappy v0.0.4
go: downloading github.com/xdg-go/stringprep v1.0.4
go: downloading github.com/xdg-go/scram v1.1.2
go: downloading github.com/montanaflynn/stats v0.7.1
go: downloading github.com/xdg-go/pbkdf2 v1.0.0
  WARN: Algunos tests de Go fallaron.
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x38 pc=0x636bc1]

goroutine 1 [running]:
main.convert({0x722008?, 0xc000122020?}, {0x722028, 0xc000122028}, 0xc000124420)
	/root/go/pkg/mod/github.com/boumenot/gocover-cobertura@v1.4.0/gocover-cobertura.go:73 +0x1a1
main.main()
	/root/go/pkg/mod/github.com/boumenot/gocover-cobertura@v1.4.0/gocover-cobertura.go:54 +0x274
  WARN: gocover-cobertura falló.
  Running Frontend tests...
  Instalando dependencias del frontend (usando pnpm cache)...
Lockfile is up to date, resolution step is skipped
Progress: resolved 1, reused 0, downloaded 0, added 0
Packages: +527
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Progress: resolved 527, reused 527, downloaded 0, added 499
Progress: resolved 527, reused 527, downloaded 0, added 527, done

dependencies:
+ @floating-ui/react 0.27.17
+ @hookform/resolvers 5.2.2
+ @radix-ui/react-dialog 1.1.15
+ @tanstack/react-query 5.90.21
+ @tanstack/react-query-devtools 5.91.3
+ class-variance-authority 0.7.1
+ clsx 2.1.1
+ country-flag-icons 1.6.12
+ input-otp 1.4.2
+ motion 12.33.0
+ next 16.1.6
+ react 19.2.3
+ react-day-picker 9.13.1
+ react-dom 19.2.3
+ react-hook-form 7.71.1
+ react-hot-toast 2.6.0
+ swiper 12.1.0
+ tailwind-merge 3.4.0
+ zod 4.3.6
+ zustand 5.0.11

devDependencies:
+ @tailwindcss/postcss 4.1.18
+ @testing-library/jest-dom 6.9.1
+ @testing-library/react 16.3.2
+ @testing-library/user-event 14.6.1
+ @types/node 20.19.32
+ @types/react 19.2.13
+ @types/react-dom 19.2.3
+ eslint 9.39.2
+ eslint-config-next 16.1.6
+ eslint-config-prettier 10.1.8
+ husky 9.1.7
+ jsdom 28.1.0
+ lint-staged 16.2.7
+ prettier 3.8.1
+ tailwindcss 4.1.18
+ typescript 5.9.3
+ vitest 4.0.18

. prepare$ husky
. prepare: .git can't be found
. prepare: Done
╭ Warning ─────────────────────────────────────────────────────────────────────╮
│                                                                              │
│   Ignored build scripts: esbuild@0.27.3.                                     │
│   Run "pnpm approve-builds" to pick which dependencies should be allowed     │
│   to run scripts.                                                            │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
Done in 1.7s using pnpm v10.33.2

> fuc-app-web-nextjs@0.1.0 test /src/frontend
> vitest run --reporter=junit --outputFile=/qa/reports/fuc/js-test-report.xml

JUNIT report written to /qa/reports/fuc/js-test-report.xml
 ELIFECYCLE  Test failed. See above for more details.
  WARN: Algunos tests de Frontend fallaron.
[1/6] Esperando Backend...
 OK: Backend listo.
[1.5/6] Obteniendo JWT Token real desde login...
  Paso 1: Creando usuario QA (si no existe)...
  Signup response: usuario ya existe o creado
  Paso 2: Iniciando sesión para obtener token...
  Token real obtenido correctamente para usuario: 12345678
[2/6] Newman API Tests...
 SKIP: RUN_NEWMAN=false
[3/6] Analisis SonarQube...
  Esperando a que SonarQube este listo (esto puede tardar 1-2 minutos)...
 OK: SonarQube esta UP y listo.
  --- Debug: Verificando directorios para Sonar ---
drwxr-xr-x 1 root root 4096 Apr 28 15:14 /src
drwxr-xr-x 8 root root 4096 Apr 23 14:49 /src/backend
drwxr-xr-x 1 root root 4096 Apr 28 18:07 /src/frontend
  ------------------------------------------------
  Copiando y corrigiendo rutas en coverage.out (ReadOnly fix)...
  Iniciando sonar-scanner (timeout: 20m)...
18:07:58.149 WARN  Property 'sonar.plugins.downloadOnlyRequired' with value 'true' is overridden with value 'true'
18:07:58.153 INFO  Scanner configuration file: /opt/sonar-scanner/conf/sonar-scanner.properties
18:07:58.154 INFO  Project root configuration file: NONE
18:07:58.163 INFO  SonarScanner CLI 6.2.1.4610
18:07:58.164 INFO  Java 17.0.12 Eclipse Adoptium (64-bit)
18:07:58.164 INFO  Linux 5.15.0-25-generic amd64
18:07:58.165 INFO  SONAR_SCANNER_OPTS=-Dsonar.plugins.downloadOnlyRequired=true -Xmx2048m
18:07:58.180 INFO  User cache: /root/.sonar/cache
18:07:58.475 INFO  Communicating with SonarQube Server 10.4.1.88267
18:07:58.689 INFO  Load global settings
18:07:58.742 INFO  Load global settings (done) | time=53ms
18:07:58.745 INFO  Server id: 74C15348-AZ1uzrDQntr7sh_tKaAX
18:07:58.747 INFO  User cache: /root/.sonar/cache
18:07:58.749 INFO  Loading required plugins
18:07:58.749 INFO  Load plugins index
18:07:58.781 INFO  Load plugins index (done) | time=31ms
18:07:58.781 INFO  Load/download plugins
18:07:58.812 INFO  Load/download plugins (done) | time=31ms
18:07:58.972 INFO  Process project properties
18:07:58.976 INFO  Process project properties (done) | time=4ms
18:07:58.979 INFO  Project key: fuc-sena
18:07:58.979 INFO  Base dir: /src
18:07:58.979 INFO  Working dir: /src/.scannerwork
18:07:58.983 INFO  Load project settings for component key: 'fuc-sena'
18:07:58.998 INFO  Load project settings for component key: 'fuc-sena' (done) | time=15ms
18:07:59.012 INFO  Load quality profiles
18:07:59.051 INFO  Load quality profiles (done) | time=39ms
18:07:59.062 INFO  Load active rules
18:08:00.426 INFO  Load active rules (done) | time=1364ms
18:08:00.430 INFO  Load analysis cache
18:08:00.434 INFO  Load analysis cache (404) | time=4ms
18:08:00.467 INFO  Preprocessing files...
18:08:00.562 INFO  5 languages detected in 268 preprocessed files
18:08:00.562 INFO  270 files ignored because of inclusion/exclusion patterns
18:08:00.564 INFO  Loading plugins for detected languages
18:08:00.564 INFO  Load/download plugins
18:08:00.576 INFO  Load/download plugins (done) | time=12ms
18:08:00.648 INFO  Load project repositories
18:08:00.659 INFO  Load project repositories (done) | time=11ms
18:08:00.668 INFO  Indexing files...
18:08:00.669 INFO  Project configuration:
18:08:00.669 INFO    Excluded sources: **/*.py, **/vendor/**, **/node_modules/**, **/.pnpm/**, **/.next/**, **/dist/**, **/build/**, **/coverage/**, **/.turbo/**, **/.cache/**, **/out/**, **/*.spec.ts, **/*.spec.tsx, **/*.test.ts, **/*.test.tsx, **/*_test.go
18:08:00.669 INFO    Included tests: **/*.spec.ts, **/*.spec.tsx, **/*.test.ts, **/*.test.tsx, **/*_test.go
18:08:00.782 INFO  268 files indexed
18:08:00.783 INFO  Quality profile for css: Sonar way
18:08:00.783 INFO  Quality profile for docker: Sonar way
18:08:00.783 INFO  Quality profile for go: Sonar way
18:08:00.783 INFO  Quality profile for ts: Sonar way
18:08:00.783 INFO  Quality profile for yaml: Sonar way
18:08:00.783 INFO  ------------- Run sensors on module fuc-sena
18:08:00.818 INFO  Load metrics repository
18:08:00.830 INFO  Load metrics repository (done) | time=12ms
18:08:01.279 INFO  Sensor JaCoCo XML Report Importer [jacoco]
18:08:01.280 INFO  'sonar.coverage.jacoco.xmlReportPaths' is not defined. Using default locations: target/site/jacoco/jacoco.xml,target/site/jacoco-it/jacoco.xml,build/reports/jacoco/test/jacocoTestReport.xml
18:08:01.280 INFO  No report imported, no coverage information will be imported by JaCoCo XML Report Importer
18:08:01.280 INFO  Sensor JaCoCo XML Report Importer [jacoco] (done) | time=1ms
18:08:01.280 INFO  Sensor Code Quality and Security for Go [go]
18:08:01.282 INFO  56 source files to be analyzed
18:08:01.789 INFO  56/56 source files have been analyzed
18:08:01.789 INFO  Sensor Code Quality and Security for Go [go] (done) | time=509ms
18:08:01.789 INFO  Sensor Go Unit Test Report [go]
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/auth and test TestService_Signup_DuplicateID
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/auth and test TestService_Signup_DuplicateEmail
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/auth and test TestService_Signup_Success
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Create_Success
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_List_Success
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_List_Error
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Create_InvalidJSON
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Create_AlreadyExists
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Create_ValidationFail
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Get_Success
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Get_NotFound
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Update_Success
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestHandler_Update_InvalidJSON
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestRepository_ExistsByUserID_NotFound
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestRepository_Insert_Integration
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestRepository_FindAll
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestRepository_FindByUserID
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestRepository_UpdateByUserID
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestService_Create_ShouldFailIfAlreadyExists
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestService_Create_ShouldInsertSuccessfully
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestService_List
18:08:01.793 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestService_Get
18:08:01.794 WARN  Failed to find test file for package fuc-sena-backend/internal/modules/geo and test TestService_Update
18:08:01.794 INFO  Sensor Go Unit Test Report [go] (done) | time=5ms
18:08:01.794 INFO  Sensor Go Cover sensor for Go coverage [go]
18:08:01.794 INFO  Load coverage report from '/qa/reports/fuc/coverage-backend.out'
18:08:01.822 INFO  Sensor Go Cover sensor for Go coverage [go] (done) | time=28ms
18:08:01.822 INFO  Sensor IaC CloudFormation Sensor [iac]
18:08:01.824 INFO  0 source files to be analyzed
18:08:01.837 INFO  0/0 source files have been analyzed
18:08:01.837 INFO  Sensor IaC CloudFormation Sensor [iac] (done) | time=15ms
18:08:01.837 INFO  Sensor IaC Kubernetes Sensor [iac]
18:08:01.870 INFO  0 source files to be analyzed
18:08:01.873 INFO  0/0 source files have been analyzed
18:08:01.873 INFO  Sensor IaC Kubernetes Sensor [iac] (done) | time=36ms
18:08:01.873 INFO  Sensor TextAndSecretsSensor [text]
18:08:02.060 INFO  256 source files to be analyzed
18:08:02.882 INFO  256/256 source files have been analyzed
18:08:02.882 INFO  Sensor TextAndSecretsSensor [text] (done) | time=1009ms
18:08:02.883 INFO  Sensor JavaScript/TypeScript analysis [javascript]
18:08:03.809 INFO  Detected os: Linux arch: amd64 alpine: false. Platform: LINUX_X64
18:08:05.594 INFO  Configured Node.js --max-old-space-size=8192.
18:08:05.594 INFO  Using embedded Node.js runtime
18:08:05.594 INFO  Using Node.js executable: '/root/.sonar/js/node-runtime/node'.
18:08:06.788 INFO  Memory configuration: OS (128000 MB), Node.js (8240 MB).
18:08:08.721 INFO  Found 1 tsconfig.json file(s): [/src/frontend/tsconfig.json]
18:08:08.722 INFO  Creating TypeScript program
18:08:08.722 INFO  TypeScript configuration file /src/frontend/tsconfig.json
18:08:08.722 INFO  191 source files to be analyzed
18:08:09.865 INFO  Creating TypeScript program (done) | time=1143ms
18:08:09.865 INFO  Starting analysis with current program
18:08:16.598 INFO  Analyzed 191 file(s) with current program
18:08:16.599 INFO  191/191 source files have been analyzed
18:08:16.600 INFO  Hit the cache for 0 out of 191
18:08:16.601 INFO  Miss the cache for 191 out of 191: ANALYSIS_MODE_INELIGIBLE [191/191]
18:08:16.601 INFO  Sensor JavaScript/TypeScript analysis [javascript] (done) | time=13719ms
18:08:16.601 INFO  Sensor JavaScript inside YAML analysis [javascript]
18:08:16.602 INFO  No input files found for analysis
18:08:16.602 INFO  Hit the cache for 0 out of 0
18:08:16.602 INFO  Miss the cache for 0 out of 0
18:08:16.602 INFO  Sensor JavaScript inside YAML analysis [javascript] (done) | time=1ms
18:08:16.602 INFO  Sensor CSS Rules [javascript]
18:08:16.606 INFO  3 source files to be analyzed
18:08:16.695 INFO  3/3 source files have been analyzed
18:08:16.695 INFO  Hit the cache for 0 out of 0
18:08:16.695 INFO  Miss the cache for 0 out of 0
18:08:16.695 INFO  Sensor CSS Rules [javascript] (done) | time=93ms
18:08:16.695 INFO  Sensor CSS Metrics [javascript]
18:08:16.709 INFO  Sensor CSS Metrics [javascript] (done) | time=14ms
18:08:16.709 INFO  Sensor IaC Docker Sensor [iac]
18:08:16.711 INFO  1 source file to be analyzed
18:08:16.783 INFO  1/1 source file has been analyzed
18:08:16.783 INFO  Sensor IaC Docker Sensor [iac] (done) | time=74ms
18:08:16.785 INFO  ------------- Run sensors on project
18:08:16.796 INFO  Sensor Zero Coverage Sensor
18:08:16.804 INFO  Sensor Zero Coverage Sensor (done) | time=8ms
18:08:16.805 INFO  SCM Publisher is disabled
18:08:16.818 INFO  CPD Executor 33 files had no CPD blocks
18:08:16.818 INFO  CPD Executor Calculating CPD for 210 files
18:08:16.886 INFO  CPD Executor CPD calculation finished (done) | time=34ms
18:08:16.981 INFO  Analysis report generated in 81ms, dir size=1.6 MB
18:08:17.235 INFO  Analysis report compressed in 252ms, zip size=969.1 kB
18:08:17.303 INFO  Analysis report uploaded in 68ms
18:08:17.304 INFO  ANALYSIS SUCCESSFUL, you can find the results at: http://sonarqube:9000/dashboard?id=fuc-sena
18:08:17.304 INFO  Note that you will be able to access the updated dashboard once the server has processed the submitted analysis report
18:08:17.304 INFO  More about the report processing at http://sonarqube:9000/api/ce/task?id=5fd06c62-6506-4c84-9bd6-d5b464cbd07b
18:08:17.799 INFO  Analysis total time: 18.955 s
18:08:17.800 INFO  EXECUTION SUCCESS
18:08:17.800 INFO  Total time: 19.648s
  Validando umbral de cobertura (70%)...
Total Statements:   1475
Covered Statements: 100
Current Coverage:   6.78%
Required Threshold: 70.00%
❌ FAILED: Coverage is below threshold!
[4/6] Ejecutando Playwright...
 SKIP: RUN_PLAYWRIGHT=false
[4.5/6] Pruebas de Accesibilidad (axe-core) + Lighthouse (Core Web Vitals)...
 SKIP: RUN_ACCESSIBILITY=false
[5/6] k6 Performance Tests...
 SKIP: RUN_K6=false
[6/7] Pruebas de Seguridad...
 SKIP: RUN_SECURITY=false
[7/7] Finalizando...
Reportes guardados en /qa/reports/fuc
============================================
[Pipeline] sh
+ mkdir -p qa_reports_ws/
[Pipeline] sh
+ docker cp qa-runner-sonar:/qa/reports/fuc/coverage-backend.out qa_reports_ws/
[Pipeline] sh
+ docker cp qa-runner-sonar:/qa/reports/fuc/coverage-backend.xml qa_reports_ws/
[Pipeline] sh
+ docker cp qa-runner-sonar:/qa/reports/fuc/js-test-report.xml qa_reports_ws/
[Pipeline] sh
+ docker cp qa-runner-sonar:/src/frontend/coverage/lcov.info qa_reports_ws/coverage-frontend.lcov
Error response from daemon: Could not find the file /src/frontend/coverage/lcov.info in container qa-runner-sonar
+ true
[Pipeline] sh
+ docker cp qa-runner-sonar:/qa/reports/fuc/govet.txt qa_reports_ws/
[Pipeline] sh
+ docker rm -f qa-runner-sonar
qa-runner-sonar
[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // parallel
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Declarative: Post Actions)
[Pipeline] script
[Pipeline] {
[Pipeline] sh
+ ls -d qa_reports_ws
qa_reports_ws
+ ls qa_reports_ws/
accessibility-html
coverage-backend.out
coverage-backend.xml
govet.txt
js-test-report.xml
lighthouse
newman
playwright-html
playwright-results
security
[Pipeline] dir
Running in /var/jenkins_home/workspace/fuc-sena
[Pipeline] {
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] publishCoverage
Publishing Coverage report....
No reports were found
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] junit
Recording test results
[Checks API] No suitable checks publisher found.
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] recordIssues
[Go Vet] Searching for all files in '/var/jenkins_home/workspace/fuc-sena' that match the pattern 'qa_reports_ws/govet.txt'
[Go Vet] Traversing of symbolic links: enabled
[Go Vet] -> found 1 file
[Go Vet] Skipping file 'qa_reports_ws/govet.txt' because it's empty
[Go Vet] Skipping post processing
[Go Vet] No filter has been set, publishing all 0 issues
[Go Vet] Repository miner is not configured, skipping repository mining
[Go Vet] Reference build recorder is not configured
[Go Vet] No valid reference build found
[Go Vet] All reported issues will be considered outstanding
[Go Vet] No quality gates have been set - skipping
[Go Vet] Health report is disabled - skipping
[Go Vet] Created analysis result for 0 issues (found 0 new issues, fixed 0 issues)
[Go Vet] Attaching ResultAction with ID 'go-vet' to build 'fuc-sena #105'.
[Checks API] No suitable checks publisher found.
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] publishHTML
[htmlpublisher] Archiving HTML reports...
[htmlpublisher] Archiving at BUILD level /var/jenkins_home/workspace/fuc-sena/qa_reports_ws/playwright-html to Playwright_20E2E_20Report
[htmlpublisher] Copying recursive using current thread
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] publishHTML
[htmlpublisher] Archiving HTML reports...
[htmlpublisher] Archiving at BUILD level /var/jenkins_home/workspace/fuc-sena/qa_reports_ws/newman to Newman_20API_20Report
[htmlpublisher] Copying recursive using current thread
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] publishHTML
[htmlpublisher] Archiving HTML reports...
[htmlpublisher] Archiving at BUILD level /var/jenkins_home/workspace/fuc-sena/qa_reports_ws/accessibility-html to Accessibility_20_26_20Lighthouse_20Report
[htmlpublisher] Copying recursive using current thread
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] publishHTML
[htmlpublisher] Archiving HTML reports...
[htmlpublisher] Archiving at BUILD level /var/jenkins_home/workspace/fuc-sena/qa_reports_ws/security to Security_20Scan_20Report_20_28OWASP_20ZAP_29
[htmlpublisher] Copying recursive using current thread
[Pipeline] }
[Pipeline] // catchError
[Pipeline] catchError
[Pipeline] {
[Pipeline] fileExists
[Pipeline] }
[Pipeline] // catchError
[Pipeline] }
[Pipeline] // dir
[Pipeline] sh
+ grep ^PROJECT_NAME= /app/.env.qa_fuc
+ cut -d= -f2
+ tr -d 
+ PROJECT_NAME=fuc-qa-stack
+ grep ^GRAFANA_HOST_PORT= /app/.env.qa_fuc
+ + cut -d= -f2
tr -d 
+ GRAFANA_PORT=3010
+ GRAFANA_PORT=3010
+ grep ^PROMETHEUS_HOST_PORT= /app/.env.qa_fuc
+ + cut -d= -f2tr
 -d 
+ PROMETHEUS_PORT=
+ PROMETHEUS_PORT=9090
+ grep ^CADVISOR_HOST_PORT= /app/.env.qa_fuc
+ cut -d= -f2
+ tr -d 
+ CADVISOR_PORT=
+ CADVISOR_PORT=8089
+ echo => Aguardando procesamiento CE task de SonarQube...
=> Aguardando procesamiento CE task de SonarQube...
+ sleep 30
+ echo    Servicios activos para revisión (db/backend/frontend siguen arriba; volumenes Docker no se eliminan):
   Servicios activos para revisión (db/backend/frontend siguen arriba; volumenes Docker no se eliminan):
+ echo      - SonarQube    → http://localhost:9000
     - SonarQube    → http://localhost:9000
+ echo      - Grafana      → http://localhost:3010  (k6: Influx | Infra: Prometheus)
     - Grafana      → http://localhost:3010  (k6: Influx | Infra: Prometheus)
+ echo      - Prometheus   → http://localhost:9090
     - Prometheus   → http://localhost:9090
+ echo      - cAdvisor     → http://localhost:8089
     - cAdvisor     → http://localhost:8089
+ echo      - InfluxDB     → http://localhost:8086
     - InfluxDB     → http://localhost:8086
+ echo      - Newman HTML  → http://localhost:8181  (FUC: qa/reports/fuc/newman; RAV: qa/reports/rav/newman; historial en anterior/)
     - Newman HTML  → http://localhost:8181  (FUC: qa/reports/fuc/newman; RAV: qa/reports/rav/newman; historial en anterior/)
+ echo      - Playwright   → http://localhost:8182
     - Playwright   → http://localhost:8182
+ echo      - Accesibility → http://localhost:8183
     - Accesibility → http://localhost:8183
+ echo      - Security     → http://localhost:8184  (OWASP ZAP, CSRF, XSS, SQLi)
     - Security     → http://localhost:8184  (OWASP ZAP, CSRF, XSS, SQLi)
+ echo      - App (db, backend, frontend) → puertos según .env.qa / .env.qa_fuc
     - App (db, backend, frontend) → puertos según .env.qa / .env.qa_fuc
+ echo    Reportes HTML disponibles en Jenkins → Sidebar del build
   Reportes HTML disponibles en Jenkins → Sidebar del build
+ docker rm -f qa-runner-newman qa-runner-sonar qa-runner-e2e qa-runner-k6 qa-runner-a11y qa-runner-security
[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // ansiColor
[Pipeline] }
[Pipeline] // timeout
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: UNSTABLE