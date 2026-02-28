#!/bin/bash
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://backend:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://frontend:3000}"
SONAR_URL="${SONAR_HOST_URL:-http://sonarqube:9000}"
REPORTS_DIR="/qa/reports"
RUN_SONAR="${RUN_SONAR:-false}"
SONAR_WAIT_SECONDS="${SONAR_WAIT_SECONDS:-300}"
SONAR_SCAN_TIMEOUT="${SONAR_SCAN_TIMEOUT:-15m}"
RUN_K6="${RUN_K6:-true}"

mkdir -p "$REPORTS_DIR"
cd /qa

ALLURE_RESULTS_DIR="$REPORTS_DIR/allure-results"
NEWMAN_DIR="$REPORTS_DIR/newman"
K6_DIR="$REPORTS_DIR/k6"

echo "============================================"
echo " FUC QA Runner - Iniciando V4 (CRLF-Fixed)"
echo " Backend:  $BACKEND_URL"
echo " Frontend: $FRONTEND_URL"
echo " Sonar:    $SONAR_URL"
echo " k6:       RUN_K6=$RUN_K6"
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
if [ -f "api/collections/fuc-api.postman_collection.json" ]; then
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
        cp newman-report-template.html "$NEWMAN_DIR/newman-report.html"
        echo "  HTML report: $NEWMAN_DIR/newman-report.html"
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
        echo "  Iniciando sonar-scanner (timeout: $SONAR_SCAN_TIMEOUT)..."
        timeout "$SONAR_SCAN_TIMEOUT" sonar-scanner \
            -Dsonar.projectBaseDir=/src \
            -Dsonar.projectKey="${PROJECT_KEY:-fuc-sena}" \
            -Dsonar.host.url="$SONAR_URL" \
            -Dsonar.token="$SONAR_TOKEN" \
            -Dsonar.sources=frontend/src,backend \
            -Dsonar.exclusions="**/node_modules/**,**/.next/**,**/vendor/**,**/*_test.go,**/dist/**,**/build/**,**/coverage/**,**/.turbo/**,**/.cache/**,**/out/**" \
            -Dsonar.scm.disabled=true \
            -Dsonar.javascript.lcov.reportPaths="$REPORTS_DIR/lcov.info" \
            -Dsonar.go.coverage.reportPaths=backend/coverage.out \
            || echo "  WARN: Fallo o timeout el escaneo de Sonar."
    else
        echo " SKIP: SonarQube no esta listo o falta SONAR_TOKEN."
    fi
fi

# 4. Playwright E2E Tests
echo "[4/6] Ejecutando Playwright..."

if [ -f "playwright.config.ts" ]; then
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
if [ "$RUN_K6" = "true" ]; then
    if [ -f "performance/k6-tests.js" ]; then
        k6 run performance/k6-tests.js -e BACKEND_URL="$BACKEND_URL" -e TEST_TOKEN="$TEST_TOKEN" \
          --summary-export "$K6_DIR/summary.json" \
          || echo "  WARN: k6 fallo o no cumplio thresholds."
    else
        echo " SKIP: No se encontro performance/k6-tests.js"
    fi
else
    echo " SKIP: RUN_K6=$RUN_K6"
fi

# 6. Reportes Finales
echo "[6/6] Finalizando..."
echo "Reportes guardados en $REPORTS_DIR"
echo "============================================"
echo "Servidor de reportes Newman iniciado en http://localhost:8181"
echo "Presiona Ctrl+C para detener (o detén el contenedor)"
npx http-server "$NEWMAN_DIR" -p 8181 -c-1 --cors
