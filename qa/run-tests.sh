#!/bin/bash

BACKEND_URL="${BACKEND_URL:-http://backend:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://frontend:3000}"
ENVIRONMENT="${ENVIRONMENT:-qa}"
GIT_PULL_ENABLED="${GIT_PULL_ENABLED:-false}"
REPORTS_DIR="/qa/reports"
TOTAL_FAILURES=0

mkdir -p "$REPORTS_DIR"

echo "============================================"
echo " FUC QA Runner — Ambiente: $ENVIRONMENT"
echo " Backend:  $BACKEND_URL"
echo " Frontend: $FRONTEND_URL"
echo " Git Pull: $GIT_PULL_ENABLED"
echo "============================================"

# ------------------------------------------
# [1/8] Git Pull (si esta habilitado)
# ------------------------------------------
echo ""
echo "[1/8] Sincronizacion de repositorios..."

if [ "$GIT_PULL_ENABLED" = "true" ]; then
    for PROJECT_DIR in /src/backend /src/frontend; do
        if [ -d "$PROJECT_DIR/.git" ]; then
            echo "  Git pull en $PROJECT_DIR..."
            cd "$PROJECT_DIR" && git pull --ff-only origin HEAD
            if [ $? -ne 0 ]; then
                echo "  WARN: Git pull fallo en $PROJECT_DIR"
            else
                echo "  OK: $PROJECT_DIR actualizado"
            fi
        else
            echo "  SKIP: $PROJECT_DIR no es un repo git (montado como volumen)"
        fi
    done
else
    echo "  SKIP: GIT_PULL_ENABLED=$GIT_PULL_ENABLED"
fi

# ------------------------------------------
# [2/8] Esperar servicios
# ------------------------------------------
echo ""
echo "[2/8] Esperando que los servicios esten disponibles..."

MAX_RETRIES=40
RETRY_COUNT=0
until curl -sf "$BACKEND_URL/health" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "  ERROR: Backend no respondio despues de $MAX_RETRIES intentos"
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        break
    fi
    echo "  Esperando backend... intento $RETRY_COUNT/$MAX_RETRIES"
    sleep 3
done
if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "  OK: Backend disponible en $BACKEND_URL"
fi

SKIP_UI=""
RETRY_COUNT=0
until curl -sf "$FRONTEND_URL" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "  WARN: Frontend no respondio, se omitiran UI tests"
        SKIP_UI=true
        break
    fi
    echo "  Esperando frontend... intento $RETRY_COUNT/$MAX_RETRIES"
    sleep 3
done
if [ -z "$SKIP_UI" ]; then
    echo "  OK: Frontend disponible en $FRONTEND_URL"
fi

# ------------------------------------------
# [3/8] Tests unitarios del Backend — Go
# ------------------------------------------
echo ""
echo "[3/8] Tests unitarios del Backend (Go)..."

if [ -f "/src/backend/go.mod" ]; then
    cd /src/backend
    go test ./... -v -race -coverprofile="$REPORTS_DIR/backend-coverage.out" -covermode=atomic 2>&1 | tee "$REPORTS_DIR/backend-test-output.txt"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "  FAIL: Algunos tests del backend fallaron"
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
    else
        echo "  OK: Tests del backend pasaron"
    fi
else
    echo "  SKIP: No se encontro go.mod en /src/backend"
fi

# ------------------------------------------
# [4/8] Tests unitarios del Frontend — Vitest
# ------------------------------------------
echo ""
echo "[4/8] Tests unitarios del Frontend (Vitest)..."

if [ -f "/src/frontend/package.json" ] && grep -q '"test"' /src/frontend/package.json; then
    cd /src/frontend

    if command -v pnpm > /dev/null 2>&1; then
        pnpm install --frozen-lockfile 2>/dev/null || pnpm install
        pnpm test -- --coverage 2>&1 | tee "$REPORTS_DIR/frontend-test-output.txt"
    else
        npm install
        npm test -- --coverage 2>&1 | tee "$REPORTS_DIR/frontend-test-output.txt"
    fi

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "  FAIL: Algunos tests del frontend fallaron"
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
    else
        echo "  OK: Tests del frontend pasaron"
    fi

    # Copy coverage for SonarQube
    if [ -f "coverage/lcov.info" ]; then
        cp coverage/lcov.info "$REPORTS_DIR/frontend-coverage.lcov"
    fi
else
    echo "  SKIP: No se encontro script 'test' en /src/frontend/package.json"
fi

cd /qa

# ------------------------------------------
# [5/8] API Tests — Newman
# ------------------------------------------
echo ""
echo "[5/8] Tests de API (Newman)..."

if [ -f "api/collections/fuc-api.postman_collection.json" ]; then
    ENV_FILE="api/collections/env-${ENVIRONMENT}.json"
    if [ ! -f "$ENV_FILE" ]; then
        ENV_FILE="api/collections/env-qa.json"
    fi

    newman run api/collections/fuc-api.postman_collection.json \
        --environment "$ENV_FILE" \
        --reporters cli,allure \
        --reporter-allure-export "$REPORTS_DIR/api-results"

    if [ $? -ne 0 ]; then
        echo "  FAIL: Algunos tests de API fallaron"
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
    else
        echo "  OK: Todos los tests de API pasaron"
    fi
else
    echo "  SKIP: No se encontro coleccion de Postman"
fi

# ------------------------------------------
# [6/8] UI Tests — Playwright
# ------------------------------------------
echo ""
echo "[6/8] Tests de UI (Playwright)..."

if [ -z "$SKIP_UI" ] && [ -d "ui/tests" ]; then
    FRONTEND_URL="$FRONTEND_URL" npx playwright test --config=playwright.config.ts

    if [ $? -ne 0 ]; then
        echo "  FAIL: Algunos tests de UI fallaron"
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
    else
        echo "  OK: Todos los tests de UI pasaron"
    fi
else
    echo "  SKIP: Tests de UI no disponibles o frontend no accesible"
fi

# ------------------------------------------
# [7/8] Performance Tests — k6
# ------------------------------------------
echo ""
echo "[7/8] Tests de rendimiento (k6)..."

if [ "$ENVIRONMENT" = "staging" ] || [ "$ENVIRONMENT" = "prod" ]; then
    if [ -f "performance/k6-tests.js" ]; then
        k6 run performance/k6-tests.js \
            --out json="$REPORTS_DIR/k6-results.json" \
            -e BACKEND_URL="$BACKEND_URL"

        if [ $? -ne 0 ]; then
            echo "  FAIL: Tests de rendimiento no cumplieron umbrales"
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        else
            echo "  OK: Tests de rendimiento pasaron"
        fi
    else
        echo "  SKIP: Archivo k6-tests.js no encontrado"
    fi
else
    echo "  SKIP: Performance tests solo se ejecutan en staging/prod (actual: $ENVIRONMENT)"
fi

# ------------------------------------------
# [8/8] Security Scan — ZAP
# ------------------------------------------
echo ""
echo "[8/8] Escaneo de seguridad (ZAP)..."

if [ "$ENVIRONMENT" != "dev" ]; then
    if command -v zap-baseline.py > /dev/null 2>&1; then
        zap-baseline.py -t "$BACKEND_URL" \
            -r "$REPORTS_DIR/zap-report.html" \
            -I
        if [ $? -ne 0 ]; then
            echo "  WARN: Escaneo de seguridad encontro alertas"
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        else
            echo "  OK: Escaneo de seguridad completado sin alertas criticas"
        fi
    elif command -v zap > /dev/null 2>&1; then
        echo "  INFO: ZAP disponible pero zap-baseline.py no encontrado, ejecutando scan basico..."
        zap -quickurl "$BACKEND_URL" -quickout "$REPORTS_DIR/zap-report.html" -cmd
    else
        echo "  SKIP: ZAP no esta instalado en este contenedor"
    fi
else
    echo "  SKIP: Security scan no se ejecuta en ambiente dev"
fi

# ------------------------------------------
# [Bonus] Analisis estatico — SonarQube
# ------------------------------------------
echo ""
echo "[+] Analisis estatico (SonarQube)..."

if [ -n "$SONAR_HOST_URL" ] && [ -n "$SONAR_TOKEN" ] && [ "$SONAR_TOKEN" != "your-sonar-token-here" ]; then
    SONAR_READY=false
    for i in $(seq 1 20); do
        if curl -sf "$SONAR_HOST_URL/api/system/status" 2>/dev/null | grep -q '"status":"UP"'; then
            SONAR_READY=true
            break
        fi
        echo "  Esperando SonarQube... intento $i/20"
        sleep 10
    done

    if [ "$SONAR_READY" = true ]; then
        SONAR_EXTRA_ARGS=""
        if [ -f "$REPORTS_DIR/backend-coverage.out" ]; then
            SONAR_EXTRA_ARGS="$SONAR_EXTRA_ARGS -Dsonar.go.coverage.reportPaths=$REPORTS_DIR/backend-coverage.out"
        fi
        if [ -f "$REPORTS_DIR/frontend-coverage.lcov" ]; then
            SONAR_EXTRA_ARGS="$SONAR_EXTRA_ARGS -Dsonar.javascript.lcov.reportPaths=$REPORTS_DIR/frontend-coverage.lcov"
        fi

        sonar-scanner \
            -Dsonar.projectKey="$PROJECT_KEY" \
            -Dsonar.projectName="FUC SENA" \
            -Dsonar.sources=/src/backend,/src/frontend/src \
            -Dsonar.exclusions="**/node_modules/**,**/.next/**,**/vendor/**,**/*_test.go,**/.pnpm/**" \
            -Dsonar.host.url="$SONAR_HOST_URL" \
            -Dsonar.token="$SONAR_TOKEN" \
            -Dsonar.projectBaseDir=/src \
            $SONAR_EXTRA_ARGS

        if [ $? -ne 0 ]; then
            echo "  WARN: SonarQube finalizo con errores"
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        else
            echo "  OK: Analisis SonarQube completado"
        fi
    else
        echo "  WARN: SonarQube no esta listo, omitiendo..."
    fi
else
    echo "  SKIP: Variables SONAR_HOST_URL o SONAR_TOKEN no configuradas"
fi

# ------------------------------------------
# Resumen
# ------------------------------------------
echo ""
echo "============================================"
if [ $TOTAL_FAILURES -eq 0 ]; then
    echo " QA COMPLETADO EXITOSAMENTE"
else
    echo " QA COMPLETADO CON $TOTAL_FAILURES FALLO(S)"
fi
echo " Ambiente: $ENVIRONMENT"
echo " Reportes: $REPORTS_DIR"
echo " Allure UI: http://localhost:5050"
echo "============================================"

exit $TOTAL_FAILURES
