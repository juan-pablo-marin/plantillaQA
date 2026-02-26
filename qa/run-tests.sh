#!/bin/bash
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://backend:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://frontend:3000}"
SONAR_URL="${SONAR_HOST_URL:-http://sonarqube:9000}"
REPORTS_DIR="/qa/reports"

mkdir -p "$REPORTS_DIR"

echo "============================================"
echo " FUC QA Runner - Iniciando V4 (CRLF-Fixed)"
echo " Backend:  $BACKEND_URL"
echo " Frontend: $FRONTEND_URL"
echo " Sonar:    $SONAR_URL"
echo "============================================"

# 1. Esperar Backend
echo "[1/4] Esperando Backend..."
for i in $(seq 1 30); do
    if curl -sf "$BACKEND_URL/health" > /dev/null 2>&1; then
        echo " OK: Backend listo."
        break
    fi
    echo "  ... backend no disponible todavia (intento $i/30)"
    sleep 3
done

# 2. Analisis SonarQube
echo "[2/4] Analisis SonarQube..."
echo "  Esperando a que SonarQube este listo (esto puede tardar 1-2 minutos)..."
SONAR_READY=false
for i in $(seq 1 60); do
    STATUS=$(curl -sf "$SONAR_URL/api/system/status" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    if [ "$STATUS" = "UP" ]; then
        echo " OK: SonarQube esta UP y listo."
        SONAR_READY=true
        break
    fi
    echo "  ... SonarQube status: ${STATUS:-DOWN/STARTING} (intento $i/60)"
    sleep 5
done

if [ "$SONAR_READY" = true ] && [ -n "${SONAR_TOKEN:-}" ] && [ "$SONAR_TOKEN" != "your-sonar-token-here" ]; then
    echo "  Iniciando sonar-scanner..."
    sonar-scanner \
        -Dsonar.projectBaseDir=/src \
        -Dsonar.projectKey="${PROJECT_KEY:-fuc-sena}" \
        -Dsonar.host.url="$SONAR_URL" \
        -Dsonar.token="$SONAR_TOKEN" \
        -Dsonar.sources=frontend/src,backend \
        -Dsonar.exclusions="**/node_modules/**,**/.next/**,**/vendor/**,**/*_test.go" \
        -Dsonar.javascript.lcov.reportPaths="$REPORTS_DIR/lcov.info" \
        -Dsonar.go.coverage.reportPaths=backend/coverage.out || echo "  WARN: Fallo el escaneo de Sonar."
else
    echo " SKIP: SonarQube no esta listo o falta SONAR_TOKEN."
fi

# 3. Playwright E2E Tests
echo "[3/4] Ejecutando Playwright..."
cd /qa

if [ -f "playwright.config.ts" ]; then
    echo "  Ejecutando tests desde playwright.config.ts (testDir: ./ui/tests)"
    PLAYWRIGHT_JSON_OUTPUT_NAME=results.json npx playwright test \
        --reporter=list,html \
        --output="$REPORTS_DIR/playwright-results" || echo "  WARN: Algunos tests fallaron."
else
    echo " SKIP: No se encontro playwright.config.ts en /qa."
fi

# 4. Reportes Finales
echo "[4/4] Finalizando..."
echo "Reportes guardados en $REPORTS_DIR"
echo "============================================"
exit 0
