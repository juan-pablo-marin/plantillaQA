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
    # Ignoramos error si otro proceso ya lo movio o si no existe
    mv -f "$NEWMAN_DIR/newman-report.json" "$NEWMAN_HISTORY_DIR/newman-report-${TIMESTAMP}.json" 2>/dev/null || true
    echo "  Reporte anterior archivado: newman-report-${TIMESTAMP}.json"
fi

rm -rf "$ALLURE_RESULTS_DIR" "$K6_DIR" || true
mkdir -p "$ALLURE_RESULTS_DIR" "$NEWMAN_DIR" "$K6_DIR"

# 0.5. Ejecutar Tests Unitarios (para métricas de Sonar)
echo "[0.5/6] Ejecutando Tests Unitarios (Backend & Frontend)..."

# --- AISLAMIENTO DE RACE CONDITION PARA JENKINS PARALELO ---
# Las pruebas unitarias y cobertura de codigo solo deben generarse 
# por el worker encargado de SonarQube. Si Newman, k6 y Playwright
# tambien las corren al mismo tiempo, sobreescribiran coverage.out 
# simultaneamente causando Segmentation Faults.
if [ "$RUN_SONAR" = "true" ]; then

    # Backend Go
    if [ -d "/src/fuc-sena" ]; then
        echo "  Running Go tests..."
        cd /src/fuc-sena
        
        # 1. Tests & json report for Sonar + Coverage profile en 1 solo pase
        go test -v -coverprofile="$REPORTS_DIR/coverage-backend.out" ./... -json > "$REPORTS_DIR/go-test-report.json" || echo "  WARN: Algunos tests de Go fallaron."
        sed -i 's|fuc-sena/|fuc-sena/|g' "$REPORTS_DIR/go-test-report.json"
        
        # 2. Go Vet para Jenkins Warnings NG Plugin
        go vet ./... 2> "$REPORTS_DIR/govet.txt" || echo "  WARN: Go vet encontro problemas."
        
        # 3. Exportar cobertura a formato XML (Cobertura API)
        if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -s "$REPORTS_DIR/coverage-backend.out" ]; then
            # Eliminar prefijo del modulo Go (fuc-sena-backend/)
            sed -i 's|fuc-sena-backend/||g' "$REPORTS_DIR/coverage-backend.out"
            # Validacion adicional: gocover-cobertura suele fallar si el archivo no es valido o esta casi vacio
            if head -n 1 "$REPORTS_DIR/coverage-backend.out" | grep -q "mode:" && [ $(wc -l < "$REPORTS_DIR/coverage-backend.out") -gt 1 ]; then
                gocover-cobertura < "$REPORTS_DIR/coverage-backend.out" > "$REPORTS_DIR/coverage-backend.xml" || echo "  WARN: gocover-cobertura falló."
            else
                echo "  WARN: coverage-backend.out esta vacio o es invalido para gocover-cobertura."
            fi
        else
            echo "  WARN: No se encontro coverage-backend.out o esta vacio. Se omitira la conversion a Cobertura XML."
        fi
        
        cd /qa
    fi

    # Frontend JS (Vitest)
    if [ -d "/src/fuc-app-web" ]; then
        echo "  Running Frontend tests..."
        cd /src/fuc-app-web
        # Intentamos ejecutar vitest si esta configurado
        if [ -f "package.json" ]; then
            # Verificamos si existe el script de test
            if grep -q '"test":' package.json; then
                # Generamos JUnit para Sonar
                pnpm test run --reporter=junit --outputFile="$REPORTS_DIR/js-test-report.xml" || echo "  WARN: Algunos tests de Frontend fallaron."
104:                 # Corregir rutas en lcov.info para Sonar 
105:                 # Vitest puede usar 'src/' o 'frontend/' segun el contexto; forzamos a 'fuc-app-web/src/'
106:                 if [ -f "coverage/lcov.info" ]; then
107:                     sed -i 's|SF:.*src/|SF:fuc-app-web/src/|g' coverage/lcov.info
108:                 fi
            else
                echo "  SKIP: No se encontro script 'test' en package.json de frontend."
            fi
        fi
        cd /qa
    fi

else
    echo "  SKIP: Pruebas unitarias ignoradas (Solo el worker de SonarQube debe generarlas para evitar Race Conditions)."
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
    # --- Paso 1: CLI + JSON (garantiza que el JSON se genere siempre) ---
    # Newman escribe el JSON en /tmp y luego lo copiamos al volumen montado.
    # Docker Desktop for Windows no siempre sincroniza writes programaticos al host;
    # cp SI funciona de forma confiable en bind mounts.
    newman run api/collections/fuc-api.postman_collection.json \
        --environment api/collections/env-qa.json \
        --env-var "baseUrl=$BACKEND_URL" \
        --env-var "token=$TEST_TOKEN" \
        --reporters cli,json \
        --reporter-json-export /tmp/newman-report.json \
        --color on \
        --delay-request 100 || echo "  WARN: Algunos tests de API fallaron."

    # Copiar JSON al volumen montado (cp funciona de forma confiable en Docker bind mounts)
    if [ -f /tmp/newman-report.json ]; then
        cp /tmp/newman-report.json "$NEWMAN_DIR/newman-report.json"
        echo "  JSON report copiado: $NEWMAN_DIR/newman-report.json ($(wc -c < /tmp/newman-report.json) bytes)"
    else
        echo "  ERROR: Newman no genero /tmp/newman-report.json"
    fi

    # --- Paso 2: Allure (independiente, puede fallar sin afectar el JSON) ---
    echo "  Generando resultados Allure..."
    rm -rf /tmp/allure-results
    newman run api/collections/fuc-api.postman_collection.json \
        --environment api/collections/env-qa.json \
        --env-var "baseUrl=$BACKEND_URL" \
        --env-var "token=$TEST_TOKEN" \
        --reporters allure \
        --reporter-allure-export /tmp/allure-results \
        --color on \
        --delay-request 100 || echo "  WARN: Newman (Allure) reporto fallas."
    
    # Copiar resultados Allure al volumen montado
    if [ -d /tmp/allure-results ]; then
        cp -r /tmp/allure-results/* "$ALLURE_RESULTS_DIR/" 2>/dev/null || true
    else
        echo "  WARN: Allure reporter no genero /tmp/allure-results"
    fi
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
      // Escribir a /tmp primero (Docker bind mount workaround)
      fs.writeFileSync('/tmp/reports-index.json', JSON.stringify(reports, null, 2));
      console.log('    Indice generado con ' + reports.length + ' reporte(s).');
    "
    # Copiar indice al volumen montado
    if [ -f /tmp/reports-index.json ]; then
        cp /tmp/reports-index.json "$NEWMAN_DIR/reports-index.json"
    fi

    # --- Paso 3: Hacer HTML auto-contenido (inyectar JSON inline) ---
    # Esto permite que Jenkins HTML Publisher muestre el reporte sin servidor,
    # y tambien funciona al abrir index.html directamente con file://
    echo "  Inyectando datos inline en el HTML (auto-contenido)..."
    if [ -f "$NEWMAN_DIR/index.html" ] && [ -f "$NEWMAN_DIR/newman-report.json" ]; then
        node -e "
          const fs = require('fs');
          const path = require('path');
          const dir = '$NEWMAN_DIR';
          const htmlFile = path.join(dir, 'index.html');
          const indexFile = path.join(dir, 'reports-index.json');
          const reportFile = path.join(dir, 'newman-report.json');

          let html = fs.readFileSync(htmlFile, 'utf8');
          const reportIndex = fs.existsSync(indexFile) ? fs.readFileSync(indexFile, 'utf8') : '[]';
          const reportData = fs.readFileSync(reportFile, 'utf8');

          // Build inline data map: { 'filename': jsonObject, ... }
          const idx = JSON.parse(reportIndex);
          const dataMap = {};
          // Main report
          dataMap['newman-report.json'] = JSON.parse(reportData);
          // Load previous reports if they exist
          const histDir = path.join(dir, 'anteriores');
          if (fs.existsSync(histDir)) {
            fs.readdirSync(histDir).filter(f => f.endsWith('.json')).forEach(f => {
              try {
                dataMap['anteriores/' + f] = JSON.parse(fs.readFileSync(path.join(histDir, f), 'utf8'));
              } catch(e) { /* skip corrupt files */ }
            });
          }

          const scriptTag = '<script>window.__REPORT_INDEX__=' + JSON.stringify(idx) + ';window.__REPORT_DATA__=' + JSON.stringify(dataMap) + ';<\/script>';
          html = html.replace('<!-- __INLINE_DATA__ -->', scriptTag);

          // Write to /tmp first then copy (Docker bind mount workaround)
          fs.writeFileSync('/tmp/index-inline.html', html);
          console.log('    HTML auto-contenido generado (' + Buffer.byteLength(html) + ' bytes)');
        "
        if [ -f /tmp/index-inline.html ]; then
            cp /tmp/index-inline.html "$NEWMAN_DIR/index.html"
            echo "  HTML auto-contenido copiado a $NEWMAN_DIR/index.html"
        else
            echo "  WARN: No se pudo generar el HTML auto-contenido"
        fi
    else
        echo "  WARN: Faltan archivos para generar HTML auto-contenido"
    fi

    # Se ha removido el comando sync porque causaba bloqueos infinitos en Docker Desktop for Windows.
    # La extraccion ahora se maneja de forma segura por el Jenkinsfile usando docker cp.
    echo "  --- DEBUG: Contenido de $NEWMAN_DIR/ ---"
    ls -la "$NEWMAN_DIR/" 2>/dev/null || echo "  ERROR: No se pudo listar $NEWMAN_DIR"
    echo "  -------------------------------------------"
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
            ls -ld /src/fuc-sena || echo "  ERROR: /src/fuc-sena no existe"
            ls -ld /src/fuc-app-web || echo "  ERROR: /src/fuc-app-web no existe"
            echo "  ------------------------------------------------"

            # Redundante si ya se corrigio arriba, pero lo mantenemos como seguridad 
            # asegurandonos que el path de origen sea el correcto del modulo
            if [ -f "/src/fuc-sena/coverage.out" ]; then
                echo "  Copiando y corrigiendo rutas en coverage.out (ReadOnly fix)..."
                cp /src/fuc-sena/coverage.out "$REPORTS_DIR/coverage-backend.out"
                # Asegurar que las rutas empiecen con fuc-sena/ para que Sonar las encuentre
                sed -i 's|fuc-sena-backend/|fuc-sena/|g' "$REPORTS_DIR/coverage-backend.out"
                # Si las rutas no tienen prefijo, agregarlo
                if ! grep -q "fuc-sena/" "$REPORTS_DIR/coverage-backend.out"; then
                    sed -i 's|^|fuc-sena/|' "$REPORTS_DIR/coverage-backend.out"
                    sed -i 's|fuc-sena/mode:|mode:|' "$REPORTS_DIR/coverage-backend.out"
                fi
            fi

            # Construccion dinamica de argumentos para evitar fallos por archivos faltantes
            SONAR_ARGS=""
            
            if [ -f "fuc-app-web/coverage/lcov.info" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.javascript.lcov.reportPaths=fuc-app-web/coverage/lcov.info"
            fi
            
            if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -s "$REPORTS_DIR/coverage-backend.out" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.go.coverage.reportPaths=$REPORTS_DIR/coverage-backend.out"
            fi
            
            if [ -f "$REPORTS_DIR/go-test-report.json" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.go.tests.reportPaths=$REPORTS_DIR/go-test-report.json"
            fi
            
            if [ -f "$REPORTS_DIR/js-test-report.xml" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.testExecutionReportPaths=$REPORTS_DIR/js-test-report.xml"
            fi

            echo "  Iniciando sonar-scanner (timeout: $SONAR_SCAN_TIMEOUT)..."
            # Optimizamos paths: 
            # sources: codigo real (fuc-app-web/src y fuc-sena)
            # tests: carpetas de tests (fuc-app-web/src y fuc-sena)
            timeout "$SONAR_SCAN_TIMEOUT" sonar-scanner \
                -Dsonar.projectBaseDir=/src \
                -Dsonar.projectKey="${PROJECT_KEY:-fuc-sena}" \
                -Dsonar.host.url="$SONAR_URL" \
                -Dsonar.token="$SONAR_TOKEN" \
                -Dsonar.sources=fuc-app-web/src,fuc-sena \
                -Dsonar.tests=fuc-app-web/src,fuc-sena \
                -Dsonar.test.inclusions="**/*.spec.ts,**/*.spec.tsx,**/*.test.ts,**/*.test.tsx,**/*_test.go" \
                -Dsonar.exclusions="**/*.py,**/node_modules/**,**/.next/**,**/vendor/**,**/dist/**,**/build/**,**/coverage/**,**/.turbo/**,**/.cache/**,**/out/**" \
                -Dsonar.scm.disabled=true \
                -Dsonar.javascript.node.maxspace=4096 \
                -Dsonar.javascript.node.bridge.timeout=2400 \
                $SONAR_ARGS \
                || echo "  WARN: Fallo o timeout el escaneo de Sonar."
    else
        echo " SKIP: SonarQube no esta listo o falta SONAR_TOKEN."
    fi

    # --- Nueva validacion de Cobertura Go ---
    if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -f "/qa/coverage_checker.go" ]; then
        echo "  Validando umbral de cobertura (70%)..."
        # Usamos || true para que el pipeline NO se bloquee y permita ver los resultados en Sonar
        go run /qa/coverage_checker.go -file="$REPORTS_DIR/coverage-backend.out" -threshold=70 || echo "  WARN: Cobertura insuficiente."
    elif [ -f "$REPORTS_DIR/coverage-backend.out" ]; then
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
      --out influxdb=http://influxdb:8086/k6 \
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
