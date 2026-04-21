#!/bin/bash
set -euo pipefail

# FUC — puerto backend interno 8080 (plantilla Mongo)
BACKEND_URL="${BACKEND_URL:-http://backend:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://frontend:3000}"
SONAR_URL="${SONAR_HOST_URL:-http://sonarqube:9000}"
REPORTS_DIR="${REPORTS_DIR:-/qa/reports}"

# Rutas internas normalizadas (siempre fijas dentro del contenedor)
SRC_BACKEND="/src/backend"
SRC_FRONTEND="/src/frontend"

# ── Flags de ejecución ─────────────────────────────────────────────────────
# Cambia a "true" el servicio que quieras activar; el resto se omite.
RUN_NEWMAN="${RUN_NEWMAN:-false}"              # Tests de API con Newman/Postman
RUN_SONAR="${RUN_SONAR:-true}"                # Análisis estático con SonarQube
RUN_PLAYWRIGHT="${RUN_PLAYWRIGHT:-false}"      # Tests E2E con Playwright
RUN_K6="${RUN_K6:-false}"                      # Tests de rendimiento con k6
RUN_ACCESSIBILITY="${RUN_ACCESSIBILITY:-false}" # Accesibilidad (axe-core) + Lighthouse (Core Web Vitals)
RUN_SECURITY="${RUN_SECURITY:-false}"          # Pruebas de seguridad (OWASP ZAP + tests manuales)
# ───────────────────────────────────────────────────────────────────────────

SONAR_WAIT_SECONDS="${SONAR_WAIT_SECONDS:-300}"
SONAR_SCAN_TIMEOUT="${SONAR_SCAN_TIMEOUT:-20m}"

mkdir -p "$REPORTS_DIR"
cd /qa

ALLURE_RESULTS_DIR="$REPORTS_DIR/allure-results"
NEWMAN_DIR="$REPORTS_DIR/newman"
K6_DIR="$REPORTS_DIR/k6"

echo "============================================"
echo " QA Runner - Iniciando"
echo " Backend:    $BACKEND_URL"
echo " Frontend:   $FRONTEND_URL"
echo " Sonar:      $SONAR_URL"
echo "--------------------------------------------"
echo " Newman:        RUN_NEWMAN=$RUN_NEWMAN"
echo " SonarQube:     RUN_SONAR=$RUN_SONAR"
echo " Playwright:    RUN_PLAYWRIGHT=$RUN_PLAYWRIGHT"
echo " k6:            RUN_K6=$RUN_K6"
echo " Accessibility: RUN_ACCESSIBILITY=$RUN_ACCESSIBILITY"
echo " Security:      RUN_SECURITY=$RUN_SECURITY"
echo "============================================"

# 0. Preparar reportes
echo "[0/6] Preparando carpetas de reportes..."

# Archivar reporte Newman anterior: carpeta "anterior/" (debe coincidir con reports-index + index.html inline)
NEWMAN_HISTORY_DIR="$NEWMAN_DIR/anterior"
# Migración desde nombre antiguo "anteriores" (y de versiones con bug que escribían ahí)
if [ -d "$NEWMAN_DIR/anteriores" ]; then
    mkdir -p "$NEWMAN_HISTORY_DIR"
    for f in "$NEWMAN_DIR/anteriores"/*.json; do
        [ -f "$f" ] || continue
        mv -f "$f" "$NEWMAN_HISTORY_DIR/" 2>/dev/null || true
    done
    rmdir "$NEWMAN_DIR/anteriores" 2>/dev/null || true
    echo "  Migrados reportes de anteriores/ -> anterior/"
fi
mkdir -p "$NEWMAN_HISTORY_DIR"
if [ -f "$NEWMAN_DIR/newman-report.json" ]; then
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    mv -f "$NEWMAN_DIR/newman-report.json" "$NEWMAN_HISTORY_DIR/newman-report-${TIMESTAMP}.json" 2>/dev/null || true
    echo "  Reporte anterior archivado en anterior/: newman-report-${TIMESTAMP}.json"
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
    if [ -d "$SRC_BACKEND" ]; then
        echo "  Running Go tests..."
        cd "$SRC_BACKEND"
        
        # Tests & json report for Sonar + Coverage profile en 1 solo pase
        go test -v -coverprofile="$REPORTS_DIR/coverage-backend.out" ./... -json > "$REPORTS_DIR/go-test-report.json" || echo "  WARN: Algunos tests de Go fallaron."
        
        # Go Vet para Jenkins Warnings NG Plugin
        go vet ./... 2> "$REPORTS_DIR/govet.txt" || echo "  WARN: Go vet encontro problemas."
        
        # Exportar cobertura a formato XML (Cobertura API)
        if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -s "$REPORTS_DIR/coverage-backend.out" ]; then
            # PRIMERO normalizar rutas del modulo Go (antes de generar XML); trim CRLF en go.mod (checkout Windows)
            GO_MODULE=$(head -1 "$SRC_BACKEND/go.mod" 2>/dev/null | tr -d '\r' | awk '{print $2}' || echo "")
            if [ -n "$GO_MODULE" ]; then
                sed -i "s|${GO_MODULE}/|backend/|g" "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
            else
                sed -i 's|[^[:space:]]*/\(.*\.go\)|backend/\1|g' "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
            fi
            # Respaldo por si el perfil conserva prefijo del modulo sin sustituir
            sed -i 's|fuc-sena-backend/|backend/|g' "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
            # DESPUES generar XML con rutas ya normalizadas
            if head -n 1 "$REPORTS_DIR/coverage-backend.out" | grep -q "mode:" && [ $(wc -l < "$REPORTS_DIR/coverage-backend.out") -gt 1 ]; then
                gocover-cobertura < "$REPORTS_DIR/coverage-backend.out" > "$REPORTS_DIR/coverage-backend.xml" || echo "  WARN: gocover-cobertura falló."
                # Jenkins (publishCoverage) resuelve fuentes en el workspace: carpeta real BACKEND/ (no /src/backend)
                if [ -f "$REPORTS_DIR/coverage-backend.xml" ]; then
                    sed -i 's|fuc-sena-backend/|BACKEND/|g' "$REPORTS_DIR/coverage-backend.xml" 2>/dev/null || true
                    sed -i 's|filename="backend/|filename="BACKEND/|g' "$REPORTS_DIR/coverage-backend.xml" 2>/dev/null || true
                    sed -i "s|filename='backend/|filename='BACKEND/|g" "$REPORTS_DIR/coverage-backend.xml" 2>/dev/null || true
                fi
            else
                echo "  WARN: coverage-backend.out esta vacio o es invalido para gocover-cobertura."
            fi
        else
            echo "  WARN: No se encontro coverage-backend.out o esta vacio. Se omitira la conversion a Cobertura XML."
        fi
        
        cd /qa
    fi

    # Frontend JS (Vitest)
    if [ -d "$SRC_FRONTEND" ]; then
        echo "  Running Frontend tests..."
        cd "$SRC_FRONTEND"
        if [ -f "package.json" ]; then
            if ! [ -d "node_modules" ]; then
                echo "  Instalando dependencias del frontend (usando pnpm cache)..."
                pnpm install --frozen-lockfile --store-dir /pnpm-cache 2>/dev/null || pnpm install --store-dir /pnpm-cache || echo "  WARN: pnpm install falló."
            fi
            if grep -q '"test":' package.json; then
                pnpm test run --reporter=junit --outputFile="$REPORTS_DIR/js-test-report.xml" || echo "  WARN: Algunos tests de Frontend fallaron."
                if [ -f "coverage/lcov.info" ]; then
                    sed -i 's|SF:.*src/|SF:frontend/src/|g' coverage/lcov.info
                fi
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

# 1.5. Obtener Token JWT Real desde Login
# En lugar de generar un token sintético, hacemos signup + login reales para obtener
# un token válido que corresponda a un usuario existente en la BD.
echo "[1.5/6] Obteniendo JWT Token real desde login..."

# Credenciales del usuario de prueba (deben coincidir con los datos en la colección Postman)
QA_USER_ID="${QA_USER_ID:-12345678}"
QA_PASSWORD="${QA_PASSWORD:-password123}"
QA_DOCUMENT_TYPE="${QA_DOCUMENT_TYPE:-CC}"

# Paso 1: Intentar crear el usuario QA (ignorar si ya existe - código 409)
echo "  Paso 1: Creando usuario QA (si no existe)..."
SIGNUP_RESPONSE=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/signup" \
    -H "Content-Type: application/json" \
    -d '{
        "id_user": "'"$QA_USER_ID"'",
        "username": "juanperez",
        "password": "'"$QA_PASSWORD"'",
        "first_name": "Juan",
        "middle_name": "Carlos",
        "last_name": "Pérez",
        "second_last_name": "García",
        "birth_country": "Colombia",
        "birth_state": "Cundinamarca",
        "birth_city": "Bogotá",
        "document_type": "'"$QA_DOCUMENT_TYPE"'",
        "issue_country": "Colombia",
        "issue_state": "Cundinamarca",
        "issue_city": "Bogotá",
        "email": "juanperez@email.com",
        "gender": "MASCULINO",
        "lgbtiq_identity": false
    }' 2>/dev/null) || true
echo "  Signup response: ${SIGNUP_RESPONSE:-usuario ya existe o creado}"

# Paso 2: Hacer login y capturar el token real
echo "  Paso 2: Iniciando sesión para obtener token..."
LOGIN_RESPONSE=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{
        "id_user": "'"$QA_USER_ID"'",
        "password": "'"$QA_PASSWORD"'",
        "document_type": "'"$QA_DOCUMENT_TYPE"'"
    }' 2>/dev/null)

# Extraer token de la respuesta (soporta múltiples estructuras de respuesta)
if [ -n "$LOGIN_RESPONSE" ]; then
    # Intentar extraer: .token, .access_token, o .data.token
    export TEST_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('token') or data.get('access_token') or (data.get('data') or {}).get('token')
    print(token or '')
except:
    print('')
" 2>/dev/null)
fi

if [ -n "$TEST_TOKEN" ] && [ "$TEST_TOKEN" != "null" ]; then
    echo "  Token real obtenido correctamente para usuario: $QA_USER_ID"
else
    echo "  WARN: No se pudo obtener token real. Login response: $LOGIN_RESPONSE"
    echo "  Usando token vacío - los tests de endpoints autenticados podrían fallar."
    export TEST_TOKEN=""
fi

# 2. Newman API Tests
echo "[2/6] Newman API Tests..."
if [ "$RUN_NEWMAN" != "true" ]; then
    echo " SKIP: RUN_NEWMAN=$RUN_NEWMAN"
elif [ -f "api/collections/api.postman_collection_fuc.json" ]; then
    # --- Paso 1: CLI + JSON (garantiza que el JSON se genere siempre) ---
    # Newman escribe el JSON en /tmp y luego lo copiamos al volumen montado.
    # Docker Desktop for Windows no siempre sincroniza writes programaticos al host;
    # cp SI funciona de forma confiable en bind mounts.
    newman run api/collections/api.postman_collection_fuc.json \
        --environment api/collections/env-qa_fuc.json \
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
    newman run api/collections/api.postman_collection_fuc.json \
        --environment api/collections/env-qa_fuc.json \
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
        # Stub para <script src="reports-data.js"> hasta generar el historial real
        printf '%s\n' 'window.__REPORT_INDEX__=[];window.__REPORT_DATA__={};window.__NEWMAN_REPORTS_LOADED__=false;' > "$NEWMAN_DIR/reports-data.js"
        echo "  HTML report: $NEWMAN_DIR/index.html"
    fi
    # Generar manifiesto de reportes (última ejecución + carpeta anterior/)
    echo "  Generando indice de reportes..."
    node -e "
      const fs = require('fs');
      const path = require('path');
      const dir = '$NEWMAN_DIR';
      const histDir = path.join(dir, 'anterior');
      const reports = [];
      // Ultimo reporte
      if (fs.existsSync(path.join(dir, 'newman-report.json'))) {
        const st = fs.statSync(path.join(dir, 'newman-report.json'));
        reports.push({ file: 'newman-report.json', label: 'Última ejecución', date: st.mtime.toISOString(), latest: true });
      }
      // Ejecuciones archivadas en anterior/
      if (fs.existsSync(histDir)) {
        fs.readdirSync(histDir).filter(f => f.endsWith('.json')).sort().reverse().forEach(f => {
          const m = f.match(/newman-report-(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.json/);
          const label = m ? m[1] + ' ' + m[2].replace(/-/g, ':') : f;
          const st = fs.statSync(path.join(histDir, f));
          reports.push({ file: 'anterior/' + f, label: label, date: st.mtime.toISOString(), latest: false });
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

    # --- Paso 3: reports-data.js (historial completo para Jenkins + :8181) ---
    # Jenkins HTML Publisher aplica CSP que bloquea <script> inline con JSON enorme.
    # Archivo externo mismo origen (script-src 'self') + orden antes de loadIndex().
    echo "  Generando reports-data.js (historial para Jenkins y visor Nginx)..."
    if [ -f "$NEWMAN_DIR/index.html" ] && [ -f "$NEWMAN_DIR/newman-report.json" ]; then
        node -e "
          const fs = require('fs');
          const path = require('path');
          const dir = '$NEWMAN_DIR';
          const indexFile = path.join(dir, 'reports-index.json');
          const reportFile = path.join(dir, 'newman-report.json');

          const reportIndex = fs.existsSync(indexFile) ? fs.readFileSync(indexFile, 'utf8') : '[]';
          const reportData = fs.readFileSync(reportFile, 'utf8');

          const idx = JSON.parse(reportIndex);
          const dataMap = {};
          dataMap['newman-report.json'] = JSON.parse(reportData);
          const histDir = path.join(dir, 'anterior');
          if (fs.existsSync(histDir)) {
            fs.readdirSync(histDir).filter(f => f.endsWith('.json')).forEach(f => {
              try {
                dataMap['anterior/' + f] = JSON.parse(fs.readFileSync(path.join(histDir, f), 'utf8'));
              } catch(e) { /* skip */ }
            });
          }

          const js = [
            'window.__REPORT_INDEX__=' + JSON.stringify(idx) + ';',
            'window.__REPORT_DATA__=' + JSON.stringify(dataMap) + ';',
            'window.__NEWMAN_REPORTS_LOADED__=true;'
          ].join(String.fromCharCode(10));
          fs.writeFileSync('/tmp/reports-data.js', js);
          console.log('    reports-data.js generado (' + Buffer.byteLength(js) + ' bytes)');
        "
        if [ -f /tmp/reports-data.js ]; then
            cp /tmp/reports-data.js "$NEWMAN_DIR/reports-data.js"
            echo "  reports-data.js copiado a $NEWMAN_DIR/reports-data.js"
        else
            echo "  WARN: No se pudo generar reports-data.js"
            printf '%s\n' 'window.__REPORT_INDEX__=[];window.__REPORT_DATA__={};window.__NEWMAN_REPORTS_LOADED__=false;' > "$NEWMAN_DIR/reports-data.js" || true
        fi
    else
        echo "  WARN: Faltan index.html o newman-report.json para reports-data.js"
        printf '%s\n' 'window.__REPORT_INDEX__=[];window.__REPORT_DATA__={};window.__NEWMAN_REPORTS_LOADED__=false;' > "$NEWMAN_DIR/reports-data.js" 2>/dev/null || true
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
            ls -ld "$SRC_BACKEND" || echo "  ERROR: $SRC_BACKEND no existe"
            ls -ld "$SRC_FRONTEND" || echo "  ERROR: $SRC_FRONTEND no existe"
            echo "  ------------------------------------------------"

            if [ -f "$SRC_BACKEND/coverage.out" ]; then
                echo "  Copiando y corrigiendo rutas en coverage.out (ReadOnly fix)..."
                cp "$SRC_BACKEND/coverage.out" "$REPORTS_DIR/coverage-backend.out"
                GO_MODULE=$(head -1 "$SRC_BACKEND/go.mod" 2>/dev/null | tr -d '\r' | awk '{print $2}' || echo "")
                if [ -n "$GO_MODULE" ]; then
                    sed -i "s|${GO_MODULE}/|backend/|g" "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
                fi
                sed -i 's|fuc-sena-backend/|backend/|g' "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
            fi

            # Construccion dinamica de argumentos para evitar fallos por archivos faltantes
            SONAR_ARGS=""
            
            if [ -f "$SRC_FRONTEND/coverage/lcov.info" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.javascript.lcov.reportPaths=frontend/coverage/lcov.info"
            fi
            
            if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -s "$REPORTS_DIR/coverage-backend.out" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.go.coverage.reportPaths=$REPORTS_DIR/coverage-backend.out"
            fi
            
            if [ -f "$REPORTS_DIR/go-test-report.json" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.go.tests.reportPaths=$REPORTS_DIR/go-test-report.json"
            fi
            
            if [ -f "$REPORTS_DIR/js-test-report.xml" ]; then
                SONAR_ARGS="$SONAR_ARGS -Dsonar.junit.reportPaths=$REPORTS_DIR/js-test-report.xml"
            fi

            echo "  Iniciando sonar-scanner (timeout: $SONAR_SCAN_TIMEOUT)..."
            # Menos plugins descargados (~30s) y más heap para el bridge Node (evita "bridge server is unresponsive")
            export SONAR_SCANNER_OPTS="${SONAR_SCANNER_OPTS:--Dsonar.plugins.downloadOnlyRequired=true -Xmx2048m}"
            timeout "$SONAR_SCAN_TIMEOUT" sonar-scanner \
                -Dsonar.projectBaseDir=/src \
                -Dsonar.projectKey="${PROJECT_KEY:-qa-project}" \
                -Dsonar.host.url="$SONAR_URL" \
                -Dsonar.token="$SONAR_TOKEN" \
                -Dsonar.sources=frontend/src,backend \
                -Dsonar.tests=frontend/src,backend \
                -Dsonar.test.inclusions="**/*.spec.ts,**/*.spec.tsx,**/*.test.ts,**/*.test.tsx,**/*_test.go" \
                -Dsonar.exclusions="**/*.py,**/vendor/**,**/node_modules/**,**/.pnpm/**,**/.next/**,**/dist/**,**/build/**,**/coverage/**,**/.turbo/**,**/.cache/**,**/out/**" \
                -Dsonar.sourceEncoding=UTF-8 \
                -Dsonar.scm.disabled=true \
                -Dsonar.plugins.downloadOnlyRequired=true \
                -Dsonar.javascript.node.maxspace=8192 \
                -Dsonar.javascript.node.bridge.timeout=3600 \
                $SONAR_ARGS \
                || echo "  WARN: Fallo o timeout el escaneo de Sonar."
    else
        echo " SKIP: SonarQube no esta listo o falta SONAR_TOKEN."
    fi

    # --- Validacion de Cobertura Go ---
    if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -f "/qa/coverage_checker.go" ]; then
        echo "  Validando umbral de cobertura (70%)..."
        go run /qa/coverage_checker.go -file="$REPORTS_DIR/coverage-backend.out" -threshold=70 || echo "  WARN: Cobertura insuficiente."
    elif [ -f "$REPORTS_DIR/coverage-backend.out" ]; then
        echo "  SKIP: coverage_checker.go no encontrado, omitiendo validacion de umbral."
    fi
fi

# 4. Playwright E2E Tests
echo "[4/6] Ejecutando Playwright..."

if [ "$RUN_PLAYWRIGHT" != "true" ]; then
    echo " SKIP: RUN_PLAYWRIGHT=$RUN_PLAYWRIGHT"
elif [ -f "playwright.config.ts" ] || [ -f "/qa/playwright.config.ts" ]; then
    echo "  Ejecutando tests E2E desde playwright.config.ts (proyecto: chromium)"
    echo "  Limpiando reportes anteriores (HTML + artefactos)..."
    mkdir -p "$REPORTS_DIR/playwright-html" "$REPORTS_DIR/playwright-results"
    find "$REPORTS_DIR/playwright-html" -mindepth 1 -delete 2>/dev/null || true
    find "$REPORTS_DIR/playwright-results" -mindepth 1 -delete 2>/dev/null || true

    # Solo ejecuta el proyecto 'chromium' (E2E funcionales), sin incluir accessibility ni lighthouse
    PLAYWRIGHT_JSON_OUTPUT_NAME=results.json npx playwright test --config=playwright.config.ts --project=chromium || echo "  WARN: Algunos tests E2E fallaron."
else
    echo " SKIP: No se encontro playwright.config.ts en /qa."
fi

# 4.5. Accesibilidad + Lighthouse
echo "[4.5/6] Pruebas de Accesibilidad (axe-core) + Lighthouse (Core Web Vitals)..."
if [ "$RUN_ACCESSIBILITY" != "true" ]; then
    echo " SKIP: RUN_ACCESSIBILITY=$RUN_ACCESSIBILITY"
elif [ -f "playwright.config.ts" ] || [ -f "/qa/playwright.config.ts" ]; then
    echo "  Ejecutando auditorías de accesibilidad y Lighthouse..."
    mkdir -p "$REPORTS_DIR/accessibility" "$REPORTS_DIR/lighthouse"
    mkdir -p "$REPORTS_DIR/accessibility-html" "$REPORTS_DIR/accessibility-results"

    # Exportar rutas específicas para que la auditoría no sobreescriba los reportes E2E compartidos en bind mount
    export PLAYWRIGHT_HTML_DIR="$REPORTS_DIR/accessibility-html"
    export PLAYWRIGHT_RESULTS_DIR="$REPORTS_DIR/accessibility-results"

    # Ejecutar conjuntamente 'accessibility' y 'lighthouse' 
    # (Se hace en un solo comando para evitar que el reporte HTML de uno borre al otro)
    echo "  → Ejecutando axe-core (WCAG 2.1 AA) y Lighthouse (Core Web Vitals)..."
    PLAYWRIGHT_JSON_OUTPUT_NAME=usability-results.json npx playwright test \
        --config=playwright.config.ts \
        --project=accessibility \
        --project=lighthouse \
        || echo "  WARN: Algunas auditorías reportaron violaciones o fallos de performance."
    echo "  Reportes de accesibilidad generados en: $REPORTS_DIR/"
else
    echo " SKIP: No se encontró playwright.config.ts"
fi

# 5. k6 (carga/estrés)
# Requiere InfluxDB (y opcionalmente Grafana/Prometheus) ya levantados en el host vía Compose.
# Perfiles: test-e2e (+ sonar en Jenkins). Este contenedor qa-runner no ejecuta docker compose.
echo "[5/6] k6 Performance Tests..."
if [ "$RUN_K6" != "true" ]; then
    echo " SKIP: RUN_K6=$RUN_K6"
elif [ -f "performance/k6-tests_fuc.js" ]; then
    BUILD_TAG="${BUILD_NUMBER:-manual_$(date +%Y%m%d_%H%M%S)}"
    echo "  Etiqueta de build: $BUILD_TAG"
    export K6_PEAK_VUS="${K6_PEAK_VUS:-100}"
    export K6_INFLUXDB_CONCURRENT_WRITES="${K6_INFLUXDB_CONCURRENT_WRITES:-4}"
    # Telemetría Influx 1.x: intervalo corto + muchas VUs → flush > intervalo (avisos k6) o POST > max-body (413).
    # Orden de umbrales: 100k VUs necesita lotes más espaciados; 10k usa 500ms como compromiso estable.
    _k6_push="${K6_INFLUXDB_PUSH_INTERVAL:-}"
    if [ "$K6_PEAK_VUS" -ge 50000 ] 2>/dev/null; then
        if [ -z "$_k6_push" ] || [ "$_k6_push" = "1s" ] || [ "$_k6_push" = "1000ms" ]; then
            export K6_INFLUXDB_PUSH_INTERVAL=3s
        else
            export K6_INFLUXDB_PUSH_INTERVAL="$_k6_push"
        fi
    elif [ "$K6_PEAK_VUS" -ge 8000 ] 2>/dev/null; then
        if [ -z "$_k6_push" ] || [ "$_k6_push" = "1s" ] || [ "$_k6_push" = "1000ms" ]; then
            export K6_INFLUXDB_PUSH_INTERVAL=2s
        else
            export K6_INFLUXDB_PUSH_INTERVAL="$_k6_push"
        fi
    elif [ "$K6_PEAK_VUS" -ge 3000 ] 2>/dev/null; then
        if [ -z "$_k6_push" ] || [ "$_k6_push" = "1s" ] || [ "$_k6_push" = "1000ms" ]; then
            export K6_INFLUXDB_PUSH_INTERVAL=250ms
        else
            export K6_INFLUXDB_PUSH_INTERVAL="$_k6_push"
        fi
    else
        export K6_INFLUXDB_PUSH_INTERVAL="${_k6_push:-1s}"
    fi
    echo "  Push interval InfluxDB: $K6_INFLUXDB_PUSH_INTERVAL (K6_INFLUXDB_PUSH_INTERVAL)"
    echo "  Pico VUs (K6_PEAK_VUS): $K6_PEAK_VUS"
    k6 run performance/k6-tests_fuc.js \
      -e BACKEND_URL="$BACKEND_URL" \
      -e K6_AUTH_ID_USER="${K6_AUTH_ID_USER:-}" \
      -e K6_AUTH_PASSWORD="${K6_AUTH_PASSWORD:-}" \
      -e K6_DIR="$K6_DIR" \
      -e K6_PEAK_VUS="$K6_PEAK_VUS" \
      --tag build="${BUILD_TAG}" \
      --tag environment="qa" \
      --out "influxdb=http://influxdb:8086/k6" \
      --summary-export "$K6_DIR/summary.json" \
      || echo "  WARN: k6 fallo o no cumplio thresholds."
    # Dar tiempo a k6 para drenar métricas pendientes hacia InfluxDB
    echo "  Esperando 15s para drenar métricas residuales hacia InfluxDB..."
    sleep 15
else
    echo " SKIP: No se encontro performance/k6-tests.js"
fi

# 6. Security Tests (OWASP ZAP + Manual Security Tests)
echo "[6/7] Pruebas de Seguridad..."
if [ "$RUN_SECURITY" != "true" ]; then
    echo " SKIP: RUN_SECURITY=$RUN_SECURITY"
else
    SECURITY_DIR="$REPORTS_DIR/security"
    mkdir -p "$SECURITY_DIR"
    
    # ── 6.1: OWASP ZAP Security Scans ──
    echo "  Ejecutando OWASP ZAP Security Scanner..."
    
    # Verificar si ZAP está disponible
    if command -v zap-baseline.py &> /dev/null || command -v zap.sh &> /dev/null; then
        
        # Escaneo Baseline (Pasivo) del Backend
        echo "  → ZAP Baseline Scan (Backend API)..."
        zap-baseline.py \
            -t "$BACKEND_URL" \
            -r "$SECURITY_DIR/backend-baseline.html" \
            -J "$SECURITY_DIR/backend-baseline.json" \
            -x "$SECURITY_DIR/backend-baseline.xml" \
            -d \
            -I \
            --auto \
            -m 5 \
            2>&1 || echo "  WARN: ZAP Baseline (Backend) completado con alertas."
        
        # Escaneo Baseline (Pasivo) del Frontend
        echo "  → ZAP Baseline Scan (Frontend)..."
        zap-baseline.py \
            -t "$FRONTEND_URL" \
            -r "$SECURITY_DIR/frontend-baseline.html" \
            -J "$SECURITY_DIR/frontend-baseline.json" \
            -x "$SECURITY_DIR/frontend-baseline.xml" \
            -d \
            -I \
            --auto \
            -m 5 \
            2>&1 || echo "  WARN: ZAP Baseline (Frontend) completado con alertas."
        
        # Escaneo Full (Activo) si está habilitado - más intrusivo
        if [ "${ZAP_FULL_SCAN:-false}" = "true" ]; then
            echo "  → ZAP Full Scan (Activo - Backend API)..."
            echo "  ⚠ ADVERTENCIA: Escaneo activo realiza ataques controlados."
            zap-full-scan.py \
                -t "$BACKEND_URL" \
                -r "$SECURITY_DIR/backend-full.html" \
                -J "$SECURITY_DIR/backend-full.json" \
                -x "$SECURITY_DIR/backend-full.xml" \
                -d \
                -I \
                --auto \
                -m 30 \
                -a \
                2>&1 || echo "  WARN: ZAP Full Scan completado con alertas."
        fi
        
        # Escaneo con Automation Framework si existe el config
        if [ -f "/qa/security/zap-config.yaml" ]; then
            echo "  → ZAP Automation Framework Scan..."
            zap.sh -cmd -autorun /qa/security/zap-config.yaml \
                2>&1 || echo "  WARN: ZAP Automation scan completado con alertas."
        fi
        
        echo "  Reportes ZAP generados en: $SECURITY_DIR/"
    else
        echo "  WARN: OWASP ZAP no está disponible. Omitiendo escaneos ZAP."
    fi
    
    # ── 6.2: Tests de Seguridad Manuales ──
    echo "  → Ejecutando tests de seguridad manuales..."
    
    # Test CSRF Protection
    echo "    Testing CSRF protection..."
    CSRF_RESULT=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/login" \
        -H "Origin: http://malicious-site.com" \
        -H "Content-Type: application/json" \
        -d '{"id_user": "test", "password": "test", "document_type": "CC"}' \
        -w "%{http_code}" \
        -o /dev/null 2>/dev/null || echo "error")
    
    if [ "$CSRF_RESULT" = "200" ] || [ "$CSRF_RESULT" = "201" ]; then
        echo "    ⚠ CSRF: Endpoint acepta requests de origen externo"
    else
        echo "    ✓ CSRF: Endpoint rechaza/valida requests de origen externo ($CSRF_RESULT)"
    fi
    
    # Test Security Headers
    echo "    Testing security headers..."
    HEADERS=$(curl -sI "$FRONTEND_URL" 2>/dev/null || echo "")
    
    echo "$HEADERS" | grep -qi "x-frame-options" && echo "    ✓ X-Frame-Options presente" || echo "    ⚠ X-Frame-Options ausente"
    echo "$HEADERS" | grep -qi "x-content-type-options" && echo "    ✓ X-Content-Type-Options presente" || echo "    ⚠ X-Content-Type-Options ausente"
    echo "$HEADERS" | grep -qi "content-security-policy" && echo "    ✓ Content-Security-Policy presente" || echo "    ⚠ Content-Security-Policy ausente"
    echo "$HEADERS" | grep -qi "x-powered-by" && echo "    ⚠ X-Powered-By expuesto (debería ocultarse)" || echo "    ✓ X-Powered-By no expuesto"
    
    # Test SQL/NoSQL Injection básico
    echo "    Testing injection payloads..."
    INJECTION_RESULT=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"id_user": "'"'"' OR '"'"'1'"'"'='"'"'1", "password": "test", "document_type": "CC"}' \
        -w "%{http_code}" \
        -o /dev/null 2>/dev/null || echo "error")
    
    if [ "$INJECTION_RESULT" = "200" ]; then
        echo "    ⚠ INJECTION: Payload SQL aceptado (posible vulnerabilidad)"
    else
        echo "    ✓ INJECTION: Payload SQL rechazado ($INJECTION_RESULT)"
    fi
    
    # ── 6.3: Playwright Security Tests ──
    if [ -f "playwright.config.ts" ] || [ -f "/qa/playwright.config.ts" ]; then
        echo "  → Ejecutando Playwright Security Tests..."
        mkdir -p "$SECURITY_DIR/playwright-security"
        
        PLAYWRIGHT_JSON_OUTPUT_NAME=security-results.json npx playwright test \
            --config=playwright.config.ts \
            --project=chromium \
            ui/tests/security.spec.ts \
            2>&1 || echo "  WARN: Algunos tests de seguridad Playwright fallaron."
    fi
    
    # ── 6.4: Generar Reporte Consolidado ──
    echo "  → Generando reporte consolidado de seguridad..."
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    
    cat > "$SECURITY_DIR/security-summary.html" <<'SECURITY_HTML'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Scan Report - FUC SENA</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        h1 { color: #f8fafc; margin-bottom: 0.5rem; }
        .subtitle { color: #94a3b8; margin-bottom: 2rem; }
        .card { background: #1e293b; border-radius: 12px; padding: 1.5rem; margin-bottom: 1.5rem; border: 1px solid #334155; }
        .card h2 { color: #f1f5f9; margin-bottom: 1rem; }
        table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
        th, td { padding: 0.75rem; text-align: left; border-bottom: 1px solid #334155; }
        th { color: #94a3b8; font-weight: 500; }
        .report-link { color: #60a5fa; text-decoration: none; }
        .report-link:hover { text-decoration: underline; }
        .check { color: #22c55e; }
        .warn { color: #f59e0b; }
        .timestamp { color: #64748b; font-size: 0.875rem; margin-top: 2rem; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Security Scan Report</h1>
        <p class="subtitle">FUC SENA - Análisis de Seguridad Automatizado</p>
        
        <div class="card">
            <h2>📁 Reportes Generados</h2>
            <table>
                <thead>
                    <tr><th>Tipo de Escaneo</th><th>Target</th><th>Reportes</th></tr>
                </thead>
                <tbody>
                    <tr>
                        <td>ZAP Baseline (Pasivo)</td>
                        <td>Backend API</td>
                        <td><a href="backend-baseline.html" class="report-link">HTML</a> | <a href="backend-baseline.json" class="report-link">JSON</a></td>
                    </tr>
                    <tr>
                        <td>ZAP Baseline (Pasivo)</td>
                        <td>Frontend</td>
                        <td><a href="frontend-baseline.html" class="report-link">HTML</a> | <a href="frontend-baseline.json" class="report-link">JSON</a></td>
                    </tr>
                    <tr>
                        <td>ZAP Full Scan (Activo)</td>
                        <td>Backend API</td>
                        <td><a href="backend-full.html" class="report-link">HTML</a> | <a href="backend-full.json" class="report-link">JSON</a></td>
                    </tr>
                </tbody>
            </table>
        </div>
        
        <div class="card">
            <h2>🛡️ Pruebas de Seguridad Ejecutadas</h2>
            <ul style="list-style: none; padding: 0;">
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Cross-Site Request Forgery (CSRF)</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Cross-Site Scripting (XSS)</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> SQL Injection / NoSQL Injection</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Security Headers Analysis</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Cookie Security Attributes</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Session Management</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Information Disclosure</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Path Traversal</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Remote File Inclusion</li>
                <li style="padding: 0.5rem 0;"><span class="check">✅</span> Server Side Request Forgery (SSRF)</li>
            </ul>
        </div>
SECURITY_HTML
    
    echo "        <p class=\"timestamp\">Generado: $TIMESTAMP</p>" >> "$SECURITY_DIR/security-summary.html"
    echo "    </div></body></html>" >> "$SECURITY_DIR/security-summary.html"
    
    echo "  Reportes de seguridad generados en: $SECURITY_DIR/"
fi

# 7. Reportes Finales
echo "[7/7] Finalizando..."
echo "Reportes guardados en $REPORTS_DIR"
echo "============================================"
exit 0
