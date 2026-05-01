#!/usr/bin/env bash
# Crea (si no existe) un Quality Gate para FUC, añade condición de cobertura global ≥ objetivo
# y lo asocia al proyecto en SonarQube (requiere token con permiso "Administer Quality Gates").
#
# IMPORTANTE: Use un token de USUARIO (prefijo squ_…), no un token de análisis de proyecto (sqp_…).
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

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ "${SONAR_TOKEN}" == sqp_* ]]; then
  echo "══════════════════════════════════════════════════════════════"
  echo " AVISO: El token empieza por sqp_ — suele ser token de ANÁLISIS DE PROYECTO."
  echo " No puede crear Quality Gates. Genere un token de USUARIO (squ_…) en:"
  echo " My Account → Security → Generate Token (usuario con permiso"
  echo " «Administer Quality Gates» o administrador global)."
  echo "══════════════════════════════════════════════════════════════"
  die "Use un token de usuario (squ_…), no sqp_…"
fi

echo "══════════════════════════════════════════════════════════════"
echo " SonarQube — Quality Gate FUC (cobertura global ≥ ${MIN_COVERAGE}%)"
echo " Servidor: ${SONAR_URL}"
echo " Proyecto: ${PROJECT_KEY}"
echo " Gate:     ${GATE_NAME}"
echo "══════════════════════════════════════════════════════════════"

echo "=> Creando Quality Gate (si ya existe, Sonar puede devolver error JSON; se comprueba)..."
CREATE_BODY=$("${curl_auth[@]}" -X POST "${SONAR_URL}/api/qualitygates/create" \
  --data-urlencode "name=${GATE_NAME}" || true)
if echo "${CREATE_BODY}" | grep -q 'Insufficient privileges'; then
  die "Sin permisos para crear el gate. Revoca este token y usa squ_… de un administrador."
fi

echo "=> Añadiendo condición: Coverage < ${MIN_COVERAGE}% → gate falla..."
COND_BODY=$("${curl_auth[@]}" -X POST "${SONAR_URL}/api/qualitygates/create_condition" \
  --data-urlencode "gateName=${GATE_NAME}" \
  -d "metric=coverage" \
  -d "op=LT" \
  -d "error=${MIN_COVERAGE}" || true)

if echo "${COND_BODY}" | grep -q 'Insufficient privileges'; then
  die "Insufficient privileges: el token no puede editar Quality Gates. Use squ_… de usuario admin."
fi
if echo "${COND_BODY}" | grep -q '"errors"'; then
  if echo "${COND_BODY}" | grep -qi 'already exists\|duplicate'; then
    echo "   (condición posiblemente ya existía; continuar)"
  elif echo "${COND_BODY}" | grep -qi 'No quality gate'; then
    die "No existe el gate '${GATE_NAME}'. ¿Falló el paso de creación? Respuesta: ${COND_BODY}"
  else
    echo "WARN API create_condition: ${COND_BODY}"
  fi
fi

echo "=> Asociando gate al proyecto..."
SEL_BODY=$("${curl_auth[@]}" -X POST "${SONAR_URL}/api/qualitygates/select" \
  --data-urlencode "projectKey=${PROJECT_KEY}" \
  --data-urlencode "gateName=${GATE_NAME}" || true)

if echo "${SEL_BODY}" | grep -q 'Insufficient privileges'; then
  die "Sin permisos para asociar el gate al proyecto."
fi
if echo "${SEL_BODY}" | grep -q '"errors"'; then
  die "Fallo al asociar gate: ${SEL_BODY}"
fi

echo "=> Listo. El análisis con sonar.qualitygate.wait=true usará este gate."
echo "   Guía: qa/SONAR_CALIDAD_FUC.md"
