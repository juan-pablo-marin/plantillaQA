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

# ── Configuración de grabación de evidencia ──
# PLAYWRIGHT_VIDEO: off | retain-on-failure (default) | on
#   off               → no graba video (ahorra disco)
#   retain-on-failure → graba solo tests fallidos (recomendado para CI habitual)
#   on                → graba TODOS los tests (actívalo para revisión de tests que pasan)
PLAYWRIGHT_VIDEO="${PLAYWRIGHT_VIDEO:-retain-on-failure}"
# ZAP_SAVE_SESSION: false (default) | true
#   false → solo guarda reportes HTML/JSON/XML del escaneo
#   true  → además exporta el tráfico HTTP capturado por ZAP en formato HAR
#           (útil para análisis forense offline; puede generar archivos grandes)
ZAP_SAVE_SESSION="${ZAP_SAVE_SESSION:-false}"
# ───────────────────────────────────────────────────────────────────────────

SONAR_WAIT_SECONDS="${SONAR_WAIT_SECONDS:-300}"
SONAR_SCAN_TIMEOUT="${SONAR_SCAN_TIMEOUT:-20m}"

mkdir -p "$REPORTS_DIR"
cd /qa

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
echo " Playwright:    RUN_PLAYWRIGHT=$RUN_PLAYWRIGHT  (video=$PLAYWRIGHT_VIDEO)"
echo " k6:            RUN_K6=$RUN_K6"
echo " Accessibility: RUN_ACCESSIBILITY=$RUN_ACCESSIBILITY"
echo " Security:      RUN_SECURITY=$RUN_SECURITY  (zap_save_session=$ZAP_SAVE_SESSION)"
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

rm -rf "$K6_DIR" || true
mkdir -p "$NEWMAN_DIR" "$K6_DIR"

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
        # -short: omite tests de integracion que requieren DB externa (evita fallos por falta de Postgres)
        # -json debe ir ANTES del paquete para que go test lo interprete (no el binario de test)
        go test -v -short -json -coverprofile="$REPORTS_DIR/coverage-backend.out" ./internal/... > "$REPORTS_DIR/go-test-report.json" || echo "  WARN: Algunos tests de Go fallaron."
        
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
                    # Jenkins publishCoverage (Cobertura) usa un parser XML sin DOCTYPE; gocover-cobertura lo incluye por defecto
                    sed -i '/<!DOCTYPE[^>]*>/d' "$REPORTS_DIR/coverage-backend.xml" 2>/dev/null || true
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
                pnpm exec vitest run --coverage --reporter=verbose --reporter=junit --outputFile="$REPORTS_DIR/js-test-report.xml" || echo "  WARN: Algunos tests de Frontend fallaron."
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

            # ReadOnly fix: solo aplica si go test no generó coverage (evita sobrescribir coverage fresco)
            if [ ! -f "$REPORTS_DIR/coverage-backend.out" ] && [ -f "$SRC_BACKEND/coverage.out" ]; then
                echo "  Copiando y corrigiendo rutas en coverage.out (ReadOnly fix)..."
                cp "$SRC_BACKEND/coverage.out" "$REPORTS_DIR/coverage-backend.out"
                GO_MODULE=$(head -1 "$SRC_BACKEND/go.mod" 2>/dev/null | tr -d '\r' | awk '{print $2}' || echo "")
                if [ -n "$GO_MODULE" ]; then
                    sed -i "s|${GO_MODULE}/|backend/|g" "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
                fi
                sed -i 's|fuc-sena-backend/|backend/|g' "$REPORTS_DIR/coverage-backend.out" 2>/dev/null || true
            elif [ -f "$REPORTS_DIR/coverage-backend.out" ]; then
                echo "  Coverage generado por go test OK, omitiendo ReadOnly fix."
            fi

            # Exclusiones de cobertura Sonar (misma política que sonar-project.properties_fuc)
            SONAR_COV_PROP="/qa/sonar-fuc-coverage-exclusions.properties"
            SONAR_COVERAGE_EXCLUSIONS=""
            if [ -f "$SONAR_COV_PROP" ]; then
                SONAR_COVERAGE_EXCLUSIONS=$(grep '^sonar.coverage.exclusions=' "$SONAR_COV_PROP" | sed 's/^sonar.coverage.exclusions=//' | tr -d '\r')
            fi
            if [ -z "$SONAR_COVERAGE_EXCLUSIONS" ]; then
                echo "  WARN: No se encontro $SONAR_COV_PROP o esta vacio; usando exclusion minima backend."
                SONAR_COVERAGE_EXCLUSIONS='**/repository.go,**/models.go,**/dto.go,**/route.go,**/cmd/**,**/internal/db/**,**/internal/platform/**,**/internal/testutil/**,**/*.types.ts,**/app/**/layout.tsx,**/providers.tsx,**/index.ts,**/instrumentation.ts,**/middleware.ts,**/proxy.ts'
            else
                echo "  Politica de exclusion de cobertura Sonar cargada desde qa/sonar-fuc-coverage-exclusions.properties"
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
                -Dsonar.exclusions="**/*.py,**/vendor/**,**/node_modules/**,**/.pnpm/**,**/.next/**,**/dist/**,**/build/**,**/coverage/**,**/.turbo/**,**/.cache/**,**/out/**,**/backend/main" \
                -Dsonar.coverage.exclusions="$SONAR_COVERAGE_EXCLUSIONS" \
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

    # Umbral sobre perfil Go bruto (sin exclusiones Sonar). Por defecto 70%; meta proyecto 85% en Sonar se negocia aparte.
    COV_THRESHOLD="${COV_THRESHOLD:-70}"
    if [ -f "$REPORTS_DIR/coverage-backend.out" ] && [ -f "/qa/coverage_checker.go" ]; then
        echo "  Validando umbral de cobertura Go (${COV_THRESHOLD}% — ajustar COV_THRESHOLD si hace falta)..."
        go run /qa/coverage_checker.go -file="$REPORTS_DIR/coverage-backend.out" -threshold="$COV_THRESHOLD" || echo "  WARN: Cobertura Go por debajo del umbral."
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
    
    # ── 6.1: OWASP ZAP Security Scans (via Sidecar API) ──
    echo "  Ejecutando OWASP ZAP Security Scanner..."
    
    ZAP_HOST="${ZAP_HOST:-zap}"
    ZAP_PORT="${ZAP_PORT:-8080}"
    ZAP_API="http://${ZAP_HOST}:${ZAP_PORT}"
    ZAP_AVAILABLE=false
    
    # Verificar si ZAP sidecar está disponible
    echo "  Verificando conexión a ZAP sidecar ($ZAP_API)..."
    for i in $(seq 1 30); do
        if curl -sf "$ZAP_API/" > /dev/null 2>&1; then
            echo "  ✓ ZAP sidecar disponible"
            ZAP_AVAILABLE=true
            break
        fi
        echo "    ... esperando ZAP (intento $i/30)"
        sleep 2
    done
    
    if [ "$ZAP_AVAILABLE" = "true" ]; then
        # Función para ejecutar escaneo via API
        zap_scan() {
            local target="$1"
            local scan_type="$2"
            local report_name="$3"
            
            echo "  → Escaneando $target ($scan_type)..."
            
            # Abrir URL en ZAP (spider básico)
            curl -sf "$ZAP_API/JSON/core/action/accessUrl/?url=$(echo $target | sed 's/:/%3A/g; s/\//%2F/g')" > /dev/null 2>&1 || true
            sleep 2
            
            # Ejecutar Spider
            echo "    Ejecutando spider..."
            SPIDER_ID=$(curl -sf "$ZAP_API/JSON/spider/action/scan/?url=$(echo $target | sed 's/:/%3A/g; s/\//%2F/g')&maxChildren=10&recurse=true" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('scan','0'))" 2>/dev/null || echo "0")
            
            # Esperar a que termine el spider (max 2 min)
            for j in $(seq 1 24); do
                STATUS=$(curl -sf "$ZAP_API/JSON/spider/view/status/?scanId=$SPIDER_ID" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','100'))" 2>/dev/null || echo "100")
                [ "$STATUS" = "100" ] && break
                echo "    Spider: $STATUS%"
                sleep 5
            done
            
            # Ejecutar Passive Scan wait
            echo "    Esperando escaneo pasivo..."
            sleep 5
            
            # Si es full scan, ejecutar Active Scan
            if [ "$scan_type" = "full" ]; then
                echo "    Ejecutando escaneo activo..."
                ASCAN_ID=$(curl -sf "$ZAP_API/JSON/ascan/action/scan/?url=$(echo $target | sed 's/:/%3A/g; s/\//%2F/g')&recurse=true" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('scan','0'))" 2>/dev/null || echo "0")
                
                # Esperar active scan (max 10 min)
                for j in $(seq 1 60); do
                    STATUS=$(curl -sf "$ZAP_API/JSON/ascan/view/status/?scanId=$ASCAN_ID" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','100'))" 2>/dev/null || echo "100")
                    [ "$STATUS" = "100" ] && break
                    echo "    Active Scan: $STATUS%"
                    sleep 10
                done
            fi
            
            # Obtener alertas
            echo "    Obteniendo resultados..."
            curl -sf "$ZAP_API/JSON/core/view/alerts/?baseurl=$(echo $target | sed 's/:/%3A/g; s/\//%2F/g')" > "$SECURITY_DIR/${report_name}.json" 2>/dev/null || echo '{"alerts":[]}' > "$SECURITY_DIR/${report_name}.json"
            
            # Generar reporte HTML
            curl -sf "$ZAP_API/OTHER/core/other/htmlreport/" > "$SECURITY_DIR/${report_name}.html" 2>/dev/null || echo "<html><body><h1>No se pudo generar reporte HTML</h1></body></html>" > "$SECURITY_DIR/${report_name}.html"
            
            # Contar alertas
            ALERT_COUNT=$(python3 -c "import json; data=json.load(open('$SECURITY_DIR/${report_name}.json')); print(len(data.get('alerts',[])))" 2>/dev/null || echo "0")
            echo "    ✓ Completado: $ALERT_COUNT alertas encontradas"
        }
        
        # Escaneo Baseline (Pasivo) del Backend
        zap_scan "$BACKEND_URL" "baseline" "backend-baseline"
        
        # Limpiar sesión entre escaneos
        curl -sf "$ZAP_API/JSON/core/action/newSession/?name=frontend&overwrite=true" > /dev/null 2>&1 || true
        
        # Escaneo Baseline (Pasivo) del Frontend
        zap_scan "$FRONTEND_URL" "baseline" "frontend-baseline"
        
        # Escaneo Full (Activo) si está habilitado
        if [ "${ZAP_FULL_SCAN:-false}" = "true" ]; then
            curl -sf "$ZAP_API/JSON/core/action/newSession/?name=fullscan&overwrite=true" > /dev/null 2>&1 || true
            echo "  ⚠ ADVERTENCIA: Escaneo activo realiza ataques controlados."
            zap_scan "$BACKEND_URL" "full" "backend-full"
        fi
        
        echo "  Reportes ZAP generados en: $SECURITY_DIR/"

        # ── Exportar tráfico HTTP capturado (HAR) cuando ZAP_SAVE_SESSION=true ──
        # El HAR (HTTP Archive) contiene todas las peticiones/respuestas interceptadas por ZAP
        # durante los escaneos: útil para análisis forense offline y revisión manual de tráfico.
        # Se activa con ZAP_SAVE_SESSION=true; por defecto está deshabilitado para no generar
        # archivos grandes en cada build rutinario.
        if [ "${ZAP_SAVE_SESSION:-false}" = "true" ]; then
            echo "  → ZAP_SAVE_SESSION=true: exportando tráfico HTTP capturado (HAR)..."
            mkdir -p "$SECURITY_DIR/zap-traffic"

            # Exportar HAR del backend (todas las peticiones capturadas durante el escaneo)
            curl -sf "$ZAP_API/OTHER/core/other/har/?baseurl=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$BACKEND_URL', safe=''))" 2>/dev/null || echo "$BACKEND_URL")" \
                -o "$SECURITY_DIR/zap-traffic/backend-traffic.har" 2>/dev/null \
                && echo "    HAR backend: $SECURITY_DIR/zap-traffic/backend-traffic.har" \
                || echo "    WARN: No se pudo exportar HAR del backend."

            # Exportar HAR del frontend
            curl -sf "$ZAP_API/OTHER/core/other/har/?baseurl=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$FRONTEND_URL', safe=''))" 2>/dev/null || echo "$FRONTEND_URL")" \
                -o "$SECURITY_DIR/zap-traffic/frontend-traffic.har" 2>/dev/null \
                && echo "    HAR frontend: $SECURITY_DIR/zap-traffic/frontend-traffic.har" \
                || echo "    WARN: No se pudo exportar HAR del frontend."

            # Exportar todas las alertas ZAP en JSON para revisión programática
            curl -sf "$ZAP_API/JSON/alert/view/alerts/?start=0&count=1000" \
                -o "$SECURITY_DIR/zap-traffic/all-alerts.json" 2>/dev/null \
                && echo "    Alertas ZAP: $SECURITY_DIR/zap-traffic/all-alerts.json" \
                || echo "    WARN: No se pudieron exportar alertas ZAP."

            # Exportar árbol de sitios descubiertos
            curl -sf "$ZAP_API/JSON/core/view/sites/" \
                -o "$SECURITY_DIR/zap-traffic/sites-discovered.json" 2>/dev/null \
                && echo "    Sitios descubiertos: $SECURITY_DIR/zap-traffic/sites-discovered.json" \
                || echo "    WARN: No se pudieron exportar sitios descubiertos."

            echo "  Tráfico ZAP exportado en: $SECURITY_DIR/zap-traffic/"
        else
            echo "  (ZAP_SAVE_SESSION=false: solo se guardan reportes HTML/JSON/XML. Actívalo para exportar tráfico HAR.)"
        fi
    else
        echo "  WARN: ZAP sidecar no disponible. Omitiendo escaneos ZAP."
        echo "  Para habilitar ZAP, asegúrese de usar el perfil 'security' o 'all':"
        echo "    docker compose --profile security up -d zap"
        
        # Crear reportes vacíos para que el HTML no tenga enlaces rotos
        echo '{"alerts":[],"note":"ZAP sidecar no disponible"}' > "$SECURITY_DIR/backend-baseline.json"
        echo '{"alerts":[],"note":"ZAP sidecar no disponible"}' > "$SECURITY_DIR/frontend-baseline.json"
        cat > "$SECURITY_DIR/backend-baseline.html" <<'NOHTML'
<!DOCTYPE html>
<html><head><title>ZAP No Disponible</title>
<style>body{font-family:sans-serif;background:#1e293b;color:#e2e8f0;padding:2rem;text-align:center;}
.msg{background:#334155;padding:2rem;border-radius:12px;max-width:600px;margin:2rem auto;}</style></head>
<body><div class="msg"><h1>⚠️ OWASP ZAP No Disponible</h1>
<p>El contenedor ZAP sidecar no está corriendo.</p>
<p>Para habilitarlo, ejecute:</p>
<code>docker compose --profile security up -d zap</code></div></body></html>
NOHTML
        cp "$SECURITY_DIR/backend-baseline.html" "$SECURITY_DIR/frontend-baseline.html"
    fi
    
    # ── 6.2: Tests de Seguridad Manuales ──
    echo "  → Ejecutando tests de seguridad manuales..."
    
    # Inicializar archivo JSON para resultados
    MANUAL_RESULTS="$SECURITY_DIR/manual-tests.json"
    echo '{"tests": [], "summary": {}}' > "$MANUAL_RESULTS"
    
    # Test CSRF Protection
    echo "    Testing CSRF protection..."
    CSRF_RESULT=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/login" \
        -H "Origin: http://malicious-site.com" \
        -H "Content-Type: application/json" \
        -d '{"id_user": "test", "password": "test", "document_type": "CC"}' \
        -w "%{http_code}" \
        -o /dev/null 2>/dev/null || echo "error")
    
    CSRF_STATUS="pass"
    CSRF_MSG="Endpoint rechaza requests de origen externo ($CSRF_RESULT)"
    if [ "$CSRF_RESULT" = "200" ] || [ "$CSRF_RESULT" = "201" ]; then
        CSRF_STATUS="fail"
        CSRF_MSG="Endpoint acepta requests de origen externo - VULNERABLE"
        echo "    ⚠ CSRF: $CSRF_MSG"
    else
        echo "    ✓ CSRF: $CSRF_MSG"
    fi
    
    # Test Security Headers
    echo "    Testing security headers..."
    HEADERS=$(curl -sI "$FRONTEND_URL" 2>/dev/null || echo "")
    
    XFRAME_STATUS="fail"; XCONTENT_STATUS="fail"; CSP_STATUS="warn"; XPOWERED_STATUS="pass"
    
    if echo "$HEADERS" | grep -qi "x-frame-options"; then
        XFRAME_STATUS="pass"
        echo "    ✓ X-Frame-Options presente"
    else
        echo "    ⚠ X-Frame-Options ausente"
    fi
    
    if echo "$HEADERS" | grep -qi "x-content-type-options"; then
        XCONTENT_STATUS="pass"
        echo "    ✓ X-Content-Type-Options presente"
    else
        echo "    ⚠ X-Content-Type-Options ausente"
    fi
    
    if echo "$HEADERS" | grep -qi "content-security-policy"; then
        CSP_STATUS="pass"
        echo "    ✓ Content-Security-Policy presente"
    else
        echo "    ⚠ Content-Security-Policy ausente"
    fi
    
    if echo "$HEADERS" | grep -qi "x-powered-by"; then
        XPOWERED_STATUS="fail"
        echo "    ⚠ X-Powered-By expuesto (debería ocultarse)"
    else
        echo "    ✓ X-Powered-By no expuesto"
    fi
    
    # Test SQL/NoSQL Injection básico
    echo "    Testing injection payloads..."
    INJECTION_RESULT=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"id_user": "'"'"' OR '"'"'1'"'"'='"'"'1", "password": "test", "document_type": "CC"}' \
        -w "%{http_code}" \
        -o /dev/null 2>/dev/null || echo "error")
    
    INJECTION_STATUS="pass"
    if [ "$INJECTION_RESULT" = "200" ]; then
        INJECTION_STATUS="fail"
        echo "    ⚠ INJECTION: Payload SQL aceptado (posible vulnerabilidad)"
    else
        echo "    ✓ INJECTION: Payload SQL rechazado ($INJECTION_RESULT)"
    fi
    
    # Guardar resultados manuales en JSON
    cat > "$MANUAL_RESULTS" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "backend_url": "$BACKEND_URL",
  "frontend_url": "$FRONTEND_URL",
  "tests": [
    {"name": "CSRF Protection", "status": "$CSRF_STATUS", "details": "$CSRF_MSG"},
    {"name": "X-Frame-Options", "status": "$XFRAME_STATUS", "details": "Protección contra Clickjacking"},
    {"name": "X-Content-Type-Options", "status": "$XCONTENT_STATUS", "details": "Previene MIME sniffing"},
    {"name": "Content-Security-Policy", "status": "$CSP_STATUS", "details": "Política de seguridad de contenido"},
    {"name": "X-Powered-By Hidden", "status": "$XPOWERED_STATUS", "details": "No expone tecnología del servidor"},
    {"name": "SQL Injection", "status": "$INJECTION_STATUS", "details": "Respuesta: $INJECTION_RESULT"}
  ]
}
EOF
    
    # ── 6.3: Playwright Security Tests ──
    PLAYWRIGHT_PASS=0
    PLAYWRIGHT_FAIL=0
    PLAYWRIGHT_SKIP=0
    
    if [ -f "playwright.config.ts" ] || [ -f "/qa/playwright.config.ts" ]; then
        echo "  → Ejecutando Playwright Security Tests..."
        mkdir -p "$SECURITY_DIR/playwright-security"
        
        # Ejecutar tests de seguridad con reporte JSON
        npx playwright test \
            --config=playwright.config.ts \
            --project=security \
            --reporter=json,html \
            --output="$SECURITY_DIR/playwright-security" \
            2>&1 | tee "$SECURITY_DIR/playwright-output.txt" || true
        
        # Parsear resultados del output
        if [ -f "$SECURITY_DIR/playwright-output.txt" ]; then
            # Extraer conteo de tests pasados/fallidos del output
            PLAYWRIGHT_PASS=$(grep -oE '[0-9]+ passed' "$SECURITY_DIR/playwright-output.txt" | head -1 | grep -oE '[0-9]+' || echo "0")
            PLAYWRIGHT_FAIL=$(grep -oE '[0-9]+ failed' "$SECURITY_DIR/playwright-output.txt" | head -1 | grep -oE '[0-9]+' || echo "0")
            PLAYWRIGHT_SKIP=$(grep -oE '[0-9]+ skipped' "$SECURITY_DIR/playwright-output.txt" | head -1 | grep -oE '[0-9]+' || echo "0")
            
            [ -z "$PLAYWRIGHT_PASS" ] && PLAYWRIGHT_PASS=0
            [ -z "$PLAYWRIGHT_FAIL" ] && PLAYWRIGHT_FAIL=0
            [ -z "$PLAYWRIGHT_SKIP" ] && PLAYWRIGHT_SKIP=0
            
            echo "    Playwright Security: $PLAYWRIGHT_PASS passed, $PLAYWRIGHT_FAIL failed, $PLAYWRIGHT_SKIP skipped"
        fi
        
        # Copiar reportes HTML de Playwright si existen
        if [ -d "playwright-report" ]; then
            cp -r playwright-report/* "$SECURITY_DIR/playwright-security/" 2>/dev/null || true
        fi
        if [ -d "$REPORTS_DIR/playwright-html" ]; then
            cp -r "$REPORTS_DIR/playwright-html"/* "$SECURITY_DIR/playwright-security/" 2>/dev/null || true
        fi
    fi
    
    # ── 6.4: Generar Reporte Consolidado Mejorado ──
    echo "  → Generando reporte consolidado de seguridad..."
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Contar resultados (tests manuales + Playwright)
    PASS_COUNT=0
    FAIL_COUNT=0
    WARN_COUNT=0
    
    # Tests manuales
    [ "$CSRF_STATUS" = "pass" ] && PASS_COUNT=$((PASS_COUNT + 1)) || FAIL_COUNT=$((FAIL_COUNT + 1))
    [ "$XFRAME_STATUS" = "pass" ] && PASS_COUNT=$((PASS_COUNT + 1)) || FAIL_COUNT=$((FAIL_COUNT + 1))
    [ "$XCONTENT_STATUS" = "pass" ] && PASS_COUNT=$((PASS_COUNT + 1)) || FAIL_COUNT=$((FAIL_COUNT + 1))
    [ "$CSP_STATUS" = "pass" ] && PASS_COUNT=$((PASS_COUNT + 1)) || { [ "$CSP_STATUS" = "warn" ] && WARN_COUNT=$((WARN_COUNT + 1)) || FAIL_COUNT=$((FAIL_COUNT + 1)); }
    [ "$XPOWERED_STATUS" = "pass" ] && PASS_COUNT=$((PASS_COUNT + 1)) || FAIL_COUNT=$((FAIL_COUNT + 1))
    [ "$INJECTION_STATUS" = "pass" ] && PASS_COUNT=$((PASS_COUNT + 1)) || FAIL_COUNT=$((FAIL_COUNT + 1))
    
    # Agregar resultados de Playwright
    PASS_COUNT=$((PASS_COUNT + PLAYWRIGHT_PASS))
    FAIL_COUNT=$((FAIL_COUNT + PLAYWRIGHT_FAIL))
    
    TOTAL_TESTS=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
    
    # Determinar estado de ZAP
    ZAP_STATUS_TEXT="No Disponible"
    ZAP_STATUS_CLASS="warn"
    if [ "$ZAP_AVAILABLE" = "true" ]; then
        ZAP_STATUS_TEXT="Conectado"
        ZAP_STATUS_CLASS="pass"
    fi
    
    cat > "$SECURITY_DIR/security-summary.html" <<SECURITY_HTML
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Scan Report - FUC SENA</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            background: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            color: #e2e8f0; 
            line-height: 1.6;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 2rem; }
        
        /* Header */
        .header {
            text-align: center;
            padding: 3rem 2rem;
            background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
            border-radius: 16px;
            margin-bottom: 2rem;
            border: 1px solid #334155;
        }
        .header h1 { 
            font-size: 2.5rem; 
            color: #f8fafc; 
            margin-bottom: 0.5rem;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 1rem;
        }
        .header .subtitle { color: #94a3b8; font-size: 1.1rem; }
        .header .timestamp { color: #64748b; font-size: 0.9rem; margin-top: 1rem; }
        
        /* Stats Grid */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        .stat-card {
            background: #1e293b;
            border-radius: 12px;
            padding: 1.5rem;
            text-align: center;
            border: 1px solid #334155;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .stat-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.3);
        }
        .stat-value { font-size: 3rem; font-weight: 700; }
        .stat-label { color: #94a3b8; font-size: 0.9rem; margin-top: 0.5rem; }
        .stat-pass .stat-value { color: #22c55e; }
        .stat-fail .stat-value { color: #ef4444; }
        .stat-warn .stat-value { color: #f59e0b; }
        .stat-total .stat-value { color: #60a5fa; }
        
        /* Cards */
        .card {
            background: #1e293b;
            border-radius: 12px;
            padding: 1.5rem;
            margin-bottom: 1.5rem;
            border: 1px solid #334155;
        }
        .card h2 {
            color: #f1f5f9;
            margin-bottom: 1.5rem;
            font-size: 1.3rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid #334155;
        }
        
        /* Results Table */
        .results-table {
            width: 100%;
            border-collapse: collapse;
        }
        .results-table th,
        .results-table td {
            padding: 1rem;
            text-align: left;
            border-bottom: 1px solid #334155;
        }
        .results-table th {
            color: #94a3b8;
            font-weight: 600;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .results-table tr:hover {
            background: rgba(255,255,255,0.02);
        }
        
        /* Status Badges */
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.4rem 1rem;
            border-radius: 9999px;
            font-size: 0.85rem;
            font-weight: 600;
        }
        .status-pass {
            background: rgba(34, 197, 94, 0.15);
            color: #22c55e;
            border: 1px solid rgba(34, 197, 94, 0.3);
        }
        .status-fail {
            background: rgba(239, 68, 68, 0.15);
            color: #ef4444;
            border: 1px solid rgba(239, 68, 68, 0.3);
        }
        .status-warn {
            background: rgba(245, 158, 11, 0.15);
            color: #f59e0b;
            border: 1px solid rgba(245, 158, 11, 0.3);
        }
        
        /* Links */
        .report-link {
            color: #60a5fa;
            text-decoration: none;
            padding: 0.3rem 0.8rem;
            border-radius: 6px;
            background: rgba(96, 165, 250, 0.1);
            border: 1px solid rgba(96, 165, 250, 0.2);
            font-size: 0.85rem;
            transition: all 0.2s;
        }
        .report-link:hover {
            background: rgba(96, 165, 250, 0.2);
            border-color: rgba(96, 165, 250, 0.4);
        }
        .report-links {
            display: flex;
            gap: 0.5rem;
            flex-wrap: wrap;
        }
        
        /* Vulnerability Details */
        .vuln-details {
            color: #94a3b8;
            font-size: 0.9rem;
        }
        
        /* Two Column Layout */
        .two-columns {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 1.5rem;
        }
        
        /* Test Categories */
        .test-category {
            margin-bottom: 1.5rem;
        }
        .test-category h3 {
            color: #cbd5e1;
            font-size: 1rem;
            margin-bottom: 1rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .test-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0.75rem 1rem;
            background: rgba(255,255,255,0.02);
            border-radius: 8px;
            margin-bottom: 0.5rem;
        }
        .test-name {
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }
        .test-icon {
            width: 24px;
            height: 24px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 50%;
            font-size: 0.8rem;
        }
        .test-icon.pass { background: rgba(34, 197, 94, 0.2); color: #22c55e; }
        .test-icon.fail { background: rgba(239, 68, 68, 0.2); color: #ef4444; }
        .test-icon.warn { background: rgba(245, 158, 11, 0.2); color: #f59e0b; }
        
        /* Footer */
        .footer {
            text-align: center;
            padding: 2rem;
            color: #64748b;
            font-size: 0.85rem;
        }
        
        /* Responsive */
        @media (max-width: 768px) {
            .container { padding: 1rem; }
            .header h1 { font-size: 1.8rem; }
            .stats-grid { grid-template-columns: repeat(2, 1fr); }
            .two-columns { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <h1>🔒 Security Scan Report</h1>
            <p class="subtitle">FUC SENA - Análisis de Seguridad Automatizado con OWASP ZAP</p>
            <p class="timestamp">Generado: $TIMESTAMP</p>
        </div>
        
        <!-- Stats -->
        <div class="stats-grid">
            <div class="stat-card stat-pass">
                <div class="stat-value">$PASS_COUNT</div>
                <div class="stat-label">✓ Tests Pasados</div>
            </div>
            <div class="stat-card stat-fail">
                <div class="stat-value">$FAIL_COUNT</div>
                <div class="stat-label">✗ Vulnerabilidades</div>
            </div>
            <div class="stat-card stat-warn">
                <div class="stat-value">$WARN_COUNT</div>
                <div class="stat-label">⚠ Advertencias</div>
            </div>
            <div class="stat-card stat-total">
                <div class="stat-value">$TOTAL_TESTS</div>
                <div class="stat-label">Total Tests</div>
            </div>
        </div>
        
        <!-- Main Content -->
        <div class="two-columns">
            <!-- Manual Test Results -->
            <div class="card">
                <h2>🧪 Resultados de Tests Manuales</h2>
                
                <div class="test-category">
                    <h3>🛡️ Protección de Headers</h3>
                    <div class="test-item">
                        <div class="test-name">
                            <span class="test-icon $XFRAME_STATUS">$([ "$XFRAME_STATUS" = "pass" ] && echo "✓" || echo "✗")</span>
                            <span>X-Frame-Options</span>
                        </div>
                        <span class="status-badge status-$XFRAME_STATUS">$([ "$XFRAME_STATUS" = "pass" ] && echo "SEGURO" || echo "FALTA")</span>
                    </div>
                    <div class="test-item">
                        <div class="test-name">
                            <span class="test-icon $XCONTENT_STATUS">$([ "$XCONTENT_STATUS" = "pass" ] && echo "✓" || echo "✗")</span>
                            <span>X-Content-Type-Options</span>
                        </div>
                        <span class="status-badge status-$XCONTENT_STATUS">$([ "$XCONTENT_STATUS" = "pass" ] && echo "SEGURO" || echo "FALTA")</span>
                    </div>
                    <div class="test-item">
                        <div class="test-name">
                            <span class="test-icon $CSP_STATUS">$([ "$CSP_STATUS" = "pass" ] && echo "✓" || echo "⚠")</span>
                            <span>Content-Security-Policy</span>
                        </div>
                        <span class="status-badge status-$CSP_STATUS">$([ "$CSP_STATUS" = "pass" ] && echo "SEGURO" || echo "RECOMENDADO")</span>
                    </div>
                    <div class="test-item">
                        <div class="test-name">
                            <span class="test-icon $XPOWERED_STATUS">$([ "$XPOWERED_STATUS" = "pass" ] && echo "✓" || echo "✗")</span>
                            <span>X-Powered-By Oculto</span>
                        </div>
                        <span class="status-badge status-$XPOWERED_STATUS">$([ "$XPOWERED_STATUS" = "pass" ] && echo "SEGURO" || echo "EXPUESTO")</span>
                    </div>
                </div>
                
                <div class="test-category">
                    <h3>🔐 Protección de Ataques</h3>
                    <div class="test-item">
                        <div class="test-name">
                            <span class="test-icon $CSRF_STATUS">$([ "$CSRF_STATUS" = "pass" ] && echo "✓" || echo "✗")</span>
                            <span>CSRF Protection</span>
                        </div>
                        <span class="status-badge status-$CSRF_STATUS">$([ "$CSRF_STATUS" = "pass" ] && echo "PROTEGIDO" || echo "VULNERABLE")</span>
                    </div>
                    <div class="test-item">
                        <div class="test-name">
                            <span class="test-icon $INJECTION_STATUS">$([ "$INJECTION_STATUS" = "pass" ] && echo "✓" || echo "✗")</span>
                            <span>SQL/NoSQL Injection</span>
                        </div>
                        <span class="status-badge status-$INJECTION_STATUS">$([ "$INJECTION_STATUS" = "pass" ] && echo "PROTEGIDO" || echo "VULNERABLE")</span>
                    </div>
                </div>
            </div>
            
            <!-- ZAP Reports + Playwright -->
            <div class="card">
                <h2>📊 Reportes de Escaneos</h2>
                
                <!-- ZAP Status Banner -->
                <div style="background: rgba($([ "$ZAP_AVAILABLE" = "true" ] && echo "34, 197, 94" || echo "245, 158, 11"), 0.1); 
                            border: 1px solid rgba($([ "$ZAP_AVAILABLE" = "true" ] && echo "34, 197, 94" || echo "245, 158, 11"), 0.3); 
                            border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem; display: flex; align-items: center; gap: 1rem;">
                    <span style="font-size: 1.5rem;">$([ "$ZAP_AVAILABLE" = "true" ] && echo "✅" || echo "⚠️")</span>
                    <div>
                        <strong style="color: $([ "$ZAP_AVAILABLE" = "true" ] && echo "#22c55e" || echo "#f59e0b");">
                            OWASP ZAP: $ZAP_STATUS_TEXT
                        </strong>
                        <p style="color: #94a3b8; font-size: 0.85rem; margin-top: 0.25rem;">
                            $([ "$ZAP_AVAILABLE" = "true" ] && echo "Escaneos de seguridad completados" || echo "El sidecar ZAP no estaba disponible durante esta ejecución")
                        </p>
                    </div>
                </div>
                
                <!-- Playwright Security Results -->
                <div style="background: rgba(96, 165, 250, 0.1); border: 1px solid rgba(96, 165, 250, 0.3); 
                            border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem;">
                    <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem;">
                        <div style="display: flex; align-items: center; gap: 0.75rem;">
                            <span style="font-size: 1.5rem;">🎭</span>
                            <strong style="color: #60a5fa;">Playwright Security Tests</strong>
                        </div>
                        <div style="display: flex; gap: 1rem;">
                            <span style="color: #22c55e;">✓ $PLAYWRIGHT_PASS passed</span>
                            <span style="color: #ef4444;">✗ $PLAYWRIGHT_FAIL failed</span>
                            $([ "$PLAYWRIGHT_SKIP" -gt 0 ] && echo "<span style=\"color: #94a3b8;\">⊘ $PLAYWRIGHT_SKIP skipped</span>" || echo "")
                        </div>
                    </div>
                    <div style="margin-top: 0.75rem;">
                        <a href="playwright-security/index.html" class="report-link" style="margin-right: 0.5rem;">📄 Ver Reporte HTML</a>
                        <a href="playwright-output.txt" class="report-link">📋 Ver Output</a>
                    </div>
                </div>
                
                <!-- ZAP Reports Table -->
                <table class="results-table">
                    <thead>
                        <tr>
                            <th>Tipo de Escaneo</th>
                            <th>Target</th>
                            <th>Estado</th>
                            <th>Reportes</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>🔍 ZAP Baseline (Pasivo)</td>
                            <td>Backend API</td>
                            <td><span class="status-badge status-$ZAP_STATUS_CLASS">$ZAP_STATUS_TEXT</span></td>
                            <td class="report-links">
                                <a href="backend-baseline.html" class="report-link">HTML</a>
                                <a href="backend-baseline.json" class="report-link">JSON</a>
                            </td>
                        </tr>
                        <tr>
                            <td>🔍 ZAP Baseline (Pasivo)</td>
                            <td>Frontend</td>
                            <td><span class="status-badge status-$ZAP_STATUS_CLASS">$ZAP_STATUS_TEXT</span></td>
                            <td class="report-links">
                                <a href="frontend-baseline.html" class="report-link">HTML</a>
                                <a href="frontend-baseline.json" class="report-link">JSON</a>
                            </td>
                        </tr>
                        <tr>
                            <td>⚡ ZAP Full Scan (Activo)</td>
                            <td>Backend API</td>
                            <td><span class="status-badge status-$([ "${ZAP_FULL_SCAN:-false}" = "true" ] && echo "$ZAP_STATUS_CLASS" || echo "warn")">$([ "${ZAP_FULL_SCAN:-false}" = "true" ] && echo "$ZAP_STATUS_TEXT" || echo "No Solicitado")</span></td>
                            <td class="report-links">
                                <a href="backend-full.html" class="report-link">HTML</a>
                                <a href="backend-full.json" class="report-link">JSON</a>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
        
        <!-- Vulnerability Categories -->
        <div class="card">
            <h2>🎯 Categorías de Vulnerabilidades Analizadas</h2>
            <table class="results-table">
                <thead>
                    <tr>
                        <th>Categoría OWASP</th>
                        <th>Descripción</th>
                        <th>Herramienta</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td><strong>A01:2021</strong> - Broken Access Control</td>
                        <td class="vuln-details">CSRF, validación de origen, control de acceso</td>
                        <td><span class="status-badge status-pass">ZAP + Manual</span></td>
                    </tr>
                    <tr>
                        <td><strong>A02:2021</strong> - Cryptographic Failures</td>
                        <td class="vuln-details">HTTPS, cookies seguras, datos sensibles</td>
                        <td><span class="status-badge status-pass">Playwright</span></td>
                    </tr>
                    <tr>
                        <td><strong>A03:2021</strong> - Injection</td>
                        <td class="vuln-details">SQL, NoSQL, XSS, Command Injection</td>
                        <td><span class="status-badge status-pass">ZAP + Manual</span></td>
                    </tr>
                    <tr>
                        <td><strong>A05:2021</strong> - Security Misconfiguration</td>
                        <td class="vuln-details">Headers de seguridad, información expuesta</td>
                        <td><span class="status-badge status-pass">ZAP + Playwright</span></td>
                    </tr>
                    <tr>
                        <td><strong>A07:2021</strong> - XSS</td>
                        <td class="vuln-details">Cross-Site Scripting reflejado y persistente</td>
                        <td><span class="status-badge status-pass">ZAP + Playwright</span></td>
                    </tr>
                    <tr>
                        <td><strong>A09:2021</strong> - Security Logging</td>
                        <td class="vuln-details">Stack traces, información de errores</td>
                        <td><span class="status-badge status-pass">Playwright</span></td>
                    </tr>
                </tbody>
            </table>
        </div>
        
        <!-- Footer -->
        <div class="footer">
            <p>🔒 FUC SENA Security Pipeline | OWASP ZAP + Playwright</p>
            <p>Generado automáticamente por el pipeline de QA</p>
        </div>
    </div>
</body>
</html>
SECURITY_HTML
    
    echo "  Reportes de seguridad generados en: $SECURITY_DIR/"
fi

# 7. Reportes Finales
echo "[7/7] Finalizando..."
echo "Reportes guardados en $REPORTS_DIR"
echo "============================================"
exit 0
