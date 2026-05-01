#!/usr/bin/env bash
# Crea (si no existe) un Quality Gate para FUC, añade condición de cobertura global ≥ objetivo
# y lo asocia al proyecto en SonarQube (requiere token con permiso "Administer Quality Gates").
#
# Uso:
#   export SONAR_TOKEN="squ_xxx"
#   export SONAR_URL="http://localhost:9000"
#   ./qa/scripts/sonar-fuc-quality-gate.sh
#
# Opcional: PROJECT_KEY, GATE_NAME, MIN_COVERAGE (default 85).
#
set -euo pipefail

SONAR_URL="${SONAR_URL:-http://localhost:9000}"
SONAR_TOKEN="${SONAR_TOKEN:?Defina SONAR_TOKEN}"
PROJECT_KEY="${PROJECT_KEY:-fuc-sena}"
GATE_NAME="${GATE_NAME:-FUC-SENA-Cobertura-85}"
MIN_COVERAGE="${MIN_COVERAGE:-85}"

curl_auth=(curl -sS -u "${SONAR_TOKEN}:")

echo "══════════════════════════════════════════════════════════════"
echo " SonarQube — Quality Gate FUC (cobertura global ≥ ${MIN_COVERAGE}%)"
echo " Servidor: ${SONAR_URL}"
echo " Proyecto: ${PROJECT_KEY}"
echo " Gate:     ${GATE_NAME}"
echo "══════════════════════════════════════════════════════════════"

echo "=> Creando Quality Gate (error si ya existe es esperable)..."
"${curl_auth[@]}" -X POST "${SONAR_URL}/api/qualitygates/create" \
  --data-urlencode "name=${GATE_NAME}" || true

echo "=> Añadiendo condición: Coverage < ${MIN_COVERAGE}% → gate falla..."
set +e
"${curl_auth[@]}" -X POST "${SONAR_URL}/api/qualitygates/create_condition" \
  --data-urlencode "gateName=${GATE_NAME}" \
  -d "metric=coverage" \
  -d "op=LT" \
  -d "error=${MIN_COVERAGE}"
COND_EXIT=$?
set -e
if [[ "${COND_EXIT}" -ne 0 ]]; then
  echo "   WARN: create_condition devolvió ${COND_EXIT} (p. ej. condición duplicada o API distinta). Compruebe en la UI."
fi

echo "=> Asociando gate al proyecto..."
"${curl_auth[@]}" -X POST "${SONAR_URL}/api/qualitygates/select" \
  --data-urlencode "projectKey=${PROJECT_KEY}" \
  --data-urlencode "gateName=${GATE_NAME}"

echo "=> Listo. El análisis con sonar.qualitygate.wait=true respetará este gate."
echo "   Guía: qa/SONAR_CALIDAD_FUC.md"
