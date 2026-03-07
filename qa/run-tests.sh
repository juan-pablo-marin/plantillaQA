#!/bin/bash
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://backend:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://frontend:3000}"
SONAR_URL="${SONAR_HOST_URL:-http://sonarqube:9000}"
REPORTS_DIR="/qa/reports"

# ── Flags de ejecución ─────────────────────────────────────────────────────
# Cambia a "true" el servicio que quieras activar; el resto se omite.
RUN_NEWMAN="${RUN_NEWMAN:-false}"          # Tests de API con Newman/Postman
RUN_SONAR="${RUN_SONAR:-true}"            # Análisis estático con SonarQube
RUN_PLAYWRIGHT="${RUN_PLAYWRIGHT:-false}"  # Tests E2E con Playwright
RUN_K6="${RUN_K6:-false}"                  # Tests de rendimiento con k6
# ───────────────────────────────────────────────────────────────────────────

SONAR_WAIT_SECONDS="${SONAR_WAIT_SECONDS:-300}"
SONAR_SCAN_TIMEOUT="${SONAR_SCAN_TIMEOUT:-20m}"

mkdir -p "$REPORTS_DIR"
cd /qa

ALLURE_RESULTS_DIR="$REPORTS_DIR/allure-results"
NEWMAN_DIR="$REPORTS_DIR/newman"
K6_DIR="$REPORTS_DIR/k6"

echo "============================================"
echo " FUC QA Runner - Iniciando V5"
echo " Backend:    $BACKEND_URL"
echo " Frontend:   $FRONTEND_URL"
echo " Sonar:      $SONAR_URL"
echo "--------------------------------------------"
echo " Newman:     RUN_NEWMAN=$RUN_NEWMAN"
echo " SonarQube:  RUN_SONAR=$RUN_SONAR"
echo " Playwright: RUN_PLAYWRIGHT=$RUN_PLAYWRIGHT"
echo " k6:         RUN_K6=$RUN_K6"
echo "============================================"

# 0. Preparar reportes
echo "[0/6] Preparando carpetas de reportes..."

# Archivar reporte Newman anterior antes de borrarlo
NEWMAN_HISTORY_DIR="$NEWMAN_DIR/anteriores"
mkdir -p "$NEWMAN_HISTORY_DIR"
if [ -f "$NEWMAN_DIR/newman-report.json" ]; then
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    mv "$NEWMAN_DIR/newman-report.json" "$NEWMAN_HISTORY_DIR/newman-report-${TIMESTAMP}.json"
    echo "  Reporte anterior archivado: newman-report-${TIMESTAMP}.json"
fi

rm -rf "$ALLURE_RESULTS_DIR" "$K6_DIR" || true
mkdir -p "$ALLURE_RESULTS_DIR" "$NEWMAN_DIR" "$K6_DIR"

# 0.5. Ejecutar Tests Unitarios (para métricas de Sonar)
echo "[0.5/6] Ejecutando Tests Unitarios (Backend & Frontend)..."

# Backend Go
if [ -d "/src/backend" ]; then
    echo "  Running Go tests..."
    cd /src/backend
    
    # 1. Tests & json report for Sonar + Coverage profile en 1 solo pase
    go test -v -coverprofile="$REPORTS_DIR/coverage-backend.out" ./... -json > "$REPORTS_DIR/go-test-report.json" || echo "  WARN: Algunos tests de Go fallaron."
    sed -i 's|fuc-sena-backend/|backend/|g' "$REPORTS_DIR/go-test-report.json"
    
    # 2. Go Vet para Jenkins Warnings NG Plugin
    go vet ./... 2> "$REPORTS_DIR/govet.txt" || echo "  WARN: Go vet encontro problemas."
    
    # 3. Exportar cobertura a formato XML (Cobertura API)
    if [ -f "$REPORTS_DIR/coverage-backend.out" ]; then
        sed -i 's|fuc-sena-backend/|backend/|g' "$REPORTS_DIR/coverage-backend.out"
        gocover-cobertura < "$REPORTS_DIR/coverage-backend.out" > "$REPORTS_DIR/coverage-backend.xml"
    fi
    
    cd /qa
fi

# Frontend JS (Vitest)
if [ -d "/src/frontend" ]; then
    echo "  Running Frontend tests..."
    cd /src/frontend
    # Intentamos ejecutar vitest si esta configurado
    if [ -f "package.json" ]; then
        # Generamos JUnit para Sonar
        pnpm test run --reporter=junit --outputFile="$REPORTS_DIR/js-test-report.xml" || echo "  WARN: Algunos tests de Frontend fallaron o Vitest no esta configurado."
    fi
    cd /qa
fi

# 1. Esperar Backend
echo "[1/6] Esperando Backend..."
for i in $(seq 1 30); do
    if curl -sf "$BACKEND_URL/health" > /dev/null 2>&1; then
        echo " OK: Backend listo."
        break
    fi
    echo "  ... backend no disponible todavia (intento $i/30)"
    sleep 3
done

# 1.5. Generar Token JWT de Prueba
echo "[1.5/6] Generando JWT Token para pruebas backend..."
export TEST_USER_ID="${TEST_USER_ID:-qa_test_user}"
export JWT_SECRET="${JWT_SECRET:-secret-key-for-development}"

export TEST_TOKEN=$(python3 -c "import time, hmac, hashlib, base64, json, os;\
secret=os.environ.get('JWT_SECRET').encode();\
header={'alg': 'HS256', 'typ': 'JWT'};\
payload={'user_id': os.environ.get('TEST_USER_ID'), 'exp': int(time.time()) + 86400};\
b64_header=base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip('=');\
b64_payload=base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=');\
sig=base64.urlsafe_b64encode(hmac.new(secret, (b64_header + '.' + b64_payload).encode(), hashlib.sha256).digest()).decode().rstrip('=');\
print(f'{b64_header}.{b64_payload}.{sig}')")

echo "  Token generado correctamente para el usuario: $TEST_USER_ID"

# 2. Newman API Tests
echo "[2/6] Newman API Tests..."
if [ "$RUN_NEWMAN" != "true" ]; then
    echo " SKIP: RUN_NEWMAN=$RUN_NEWMAN"
elif [ -f "api/collections/fuc-api.postman_collection.json" ]; then
    newman run api/collections/fuc-api.postman_collection.json \
        --environment api/collections/env-qa.json \
        --env-var "baseUrl=$BACKEND_URL" \
        --env-var "token=$TEST_TOKEN" \
        --reporters cli,json,allure \
        --reporter-json-export "$NEWMAN_DIR/newman-report.json" \
        --reporter-allure-resultsDir "$ALLURE_RESULTS_DIR" \
        --color on \
        --delay-request 100 || echo "  WARN: Algunos tests de API fallaron."
    # Copiar plantilla HTML del reporte al lado del JSON
    if [ -f "newman-report-template.html" ]; then
        cp newman-report-template.html "$NEWMAN_DIR/index.html"
        echo "  HTML report: $NEWMAN_DIR/index.html"
    fi
    # Generar manifiesto de reportes (latest + anteriores)
    echo "  Generando indice de reportes..."
    node -e "
      const fs = require('fs');
      const path = require('path');
      const dir = '$NEWMAN_DIR';
      const histDir = path.join(dir, 'anteriores');
      const reports = [];
      // Ultimo reporte
      if (fs.existsSync(path.join(dir, 'newman-report.json'))) {
        const st = fs.statSync(path.join(dir, 'newman-report.json'));
        reports.push({ file: 'newman-report.json', label: 'Última ejecución', date: st.mtime.toISOString(), latest: true });
      }
      // Anteriores
      if (fs.existsSync(histDir)) {
        fs.readdirSync(histDir).filter(f => f.endsWith('.json')).sort().reverse().forEach(f => {
          const m = f.match(/newman-report-(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.json/);
          const label = m ? m[1] + ' ' + m[2].replace(/-/g, ':') : f;
          const st = fs.statSync(path.join(histDir, f));
          reports.push({ file: 'anteriores/' + f, label: label, date: st.mtime.toISOString(), latest: false });
        });
      }
      fs.writeFileSync(path.join(dir, 'reports-index.json'), JSON.stringify(reports, null, 2));
      console.log('    Indice generado con ' + reports.length + ' reporte(s).');
    "
else
    echo " SKIP: No se encontro la coleccion de Postman."
fi

# 3. Analisis SonarQube
echo "[3/6] Analisis SonarQube..."
echo "  Esperando a que SonarQube este listo (esto puede tardar 1-2 minutos)..."
if [ "$RUN_SONAR" != "true" ]; then
    echo " SKIP: RUN_SONAR=$RUN_SONAR"
else
    SONAR_READY=false
    SLEEP_SECONDS=5
    MAX_ATTEMPTS=$(( (SONAR_WAIT_SECONDS + SLEEP_SECONDS - 1) / SLEEP_SECONDS ))
    for i in $(seq 1 "$MAX_ATTEMPTS"); do
        STATUS=$(curl -sf "$SONAR_URL/api/system/status" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)
        if [ "${STATUS:-}" = "UP" ]; then
            echo " OK: SonarQube esta UP y listo."
            SONAR_READY=true
            break
        fi
        echo "  ... SonarQube status: ${STATUS:-DOWN/STARTING} (intento $i/$MAX_ATTEMPTS)"
        sleep "$SLEEP_SECONDS"
    done

    if [ "$SONAR_READY" = true ] && [ -n "${SONAR_TOKEN:-}" ] && [ "$SONAR_TOKEN" != "your-sonar-token-here" ]; then
        echo "  --- Debug: Verificando directorios para Sonar ---"
        ls -ld /src || echo "  ERROR: /src no existe"
        ls -ld /src/backend || echo "  ERROR: /src/backend no existe"
        ls -ld /src/frontend || echo "  ERROR: /src/frontend no existe"
        ls -ld /src/frontend/src || echo "  ERROR: /src/frontend/src no existe"
        echo "  ------------------------------------------------"

        if [ -f "/src/backend/coverage.out" ]; then
            echo "  Copiando y corrigiendo rutas en coverage.out (ReadOnly fix)..."
            cp /src/backend/coverage.out "$REPORTS_DIR/coverage-backend.out"
            sed -i 's|fuc-sena-backend/|backend/|g' "$REPORTS_DIR/coverage-backend.out"
        fi

        echo "  Iniciando sonar-scanner (timeout: $SONAR_SCAN_TIMEOUT)..."
        # Optimizamos paths: 
        # sources: codigo real (backend e frontend/src)
        # tests: carpetas de tests (frontend/tests e backend para *.test.go)
        timeout "$SONAR_SCAN_TIMEOUT" sonar-scanner \
            -Dsonar.projectBaseDir=/src \
            -Dsonar.projectKey="${PROJECT_KEY:-fuc-sena}" \
            -Dsonar.host.url="$SONAR_URL" \
            -Dsonar.token="$SONAR_TOKEN" \
            -Dsonar.sources=frontend/src,backend \
            -Dsonar.tests=frontend/tests,backend \
            -Dsonar.test.inclusions="**/*.spec.ts,**/*.spec.tsx,**/*.test.ts,**/*.test.tsx,**/*_test.go" \
            -Dsonar.exclusions="**/*.py,**/node_modules/**,**/.next/**,**/vendor/**,**/dist/**,**/build/**,**/coverage/**,**/.turbo/**,**/.cache/**,**/out/**" \
            -Dsonar.scm.disabled=true \
            -Dsonar.javascript.lcov.reportPaths="frontend/coverage/lcov.info" \
            -Dsonar.go.coverage.reportPaths="$REPORTS_DIR/coverage-backend.out" \
            -Dsonar.go.tests.reportPaths="$REPORTS_DIR/go-test-report.json" \
            -Dsonar.testExecutionReportPaths="$REPORTS_DIR/js-test-report.xml" \
            -Dsonar.javascript.node.maxspace=4096 \
            || echo "  WARN: Fallo o timeout el escaneo de Sonar."
    else
        echo " SKIP: SonarQube no esta listo o falta SONAR_TOKEN."
    fi

    # --- Nueva validacion de Cobertura Go ---
    if [ -f "/src/backend/coverage.out" ] && [ -f "/qa/coverage_checker.go" ]; then
        echo "  Validando umbral de cobertura (70%)..."
        go run /qa/coverage_checker.go -file=/src/backend/coverage.out -threshold=70 || echo "  WARN: Cobertura insuficiente."
    elif [ -f "/src/backend/coverage.out" ]; then
        echo "  SKIP: coverage_checker.go no encontrado, omitiendo validacion de umbral."
    fi
fi

# 4. Playwright E2E Tests
echo "[4/6] Ejecutando Playwright..."

if [ "$RUN_PLAYWRIGHT" != "true" ]; then
    echo " SKIP: RUN_PLAYWRIGHT=$RUN_PLAYWRIGHT"
elif [ -f "playwright.config.ts" ]; then
    echo "  Ejecutando tests desde playwright.config.ts (testDir: ./ui/tests)"
    echo "  Limpiando reportes anteriores (HTML + artefactos)..."
    rm -rf "$REPORTS_DIR/playwright-html" "$REPORTS_DIR/playwright-results" || true
    mkdir -p "$REPORTS_DIR/playwright-html" "$REPORTS_DIR/playwright-results"

    # No sobreescribir reporter/output por CLI: el config ya define
    # - reporter HTML -> ./reports/playwright-html
    # - outputDir (artefactos) -> ./reports/playwright-results
    # Así el reporte HTML queda con evidencias (screenshots/videos/traces) en rutas montadas al host.
    PLAYWRIGHT_JSON_OUTPUT_NAME=results.json npx playwright test --config=playwright.config.ts || echo "  WARN: Algunos tests fallaron."
else
    echo " SKIP: No se encontro playwright.config.ts en /qa."
fi

# 5. k6 (carga/estrés)
echo "[5/6] k6 Performance Tests..."
if [ "$RUN_K6" != "true" ]; then
    echo " SKIP: RUN_K6=$RUN_K6"
elif [ -f "performance/k6-tests.js" ]; then
    k6 run performance/k6-tests.js -e BACKEND_URL="$BACKEND_URL" -e TEST_TOKEN="$TEST_TOKEN" \
      --summary-export "$K6_DIR/summary.json" \
      || echo "  WARN: k6 fallo o no cumplio thresholds."
else
    echo " SKIP: No se encontro performance/k6-tests.js"
fi

# 6. Reportes Finales
echo "[6/6] Finalizando..."
echo "Reportes guardados en $REPORTS_DIR"
echo "============================================"
exit 0
