#!/usr/bin/env bash
# Reinicio completo stack RAV (equivalente a RESET_DOCKER_STACK en Jenkins).
# Uso: desde la raíz del repo: bash qa/scripts/rav-docker-full-reset.sh
#      UP=1 bash qa/scripts/rav-docker-full-reset.sh   # además levanta servicios base

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export COMPOSE_PROFILES="test-e2e,sonar"
export DOCKER_BUILDKIT=1

COMPOSE=(docker compose --env-file .env.qa -f docker-compose.qa.yml -f docker-compose.jenkins.yml)

echo "=> Raiz: $ROOT"
echo "=> Down: qa-pipeline..."
"${COMPOSE[@]}" down --remove-orphans || true

echo "=> Down: victimasrav..."
docker compose -p victimasrav --env-file .env.qa -f docker-compose.qa.yml -f docker-compose.jenkins.yml down --remove-orphans 2>/dev/null || true

echo "=> Down: fuc-dev (compose raiz)..."
docker compose -p fuc-dev --env-file .env.dev -f docker-compose.yml down --remove-orphans 2>/dev/null || true
docker compose -p fuc-dev down --remove-orphans 2>/dev/null || true

echo "=> rm contenedores rav-qa-stack..."
while read -r cid; do [ -z "$cid" ] || docker rm -f "$cid" || true; done < <(docker ps -aq --filter "name=rav-qa-stack" 2>/dev/null || true)

docker rm -f qa-runner-newman qa-runner-sonar qa-runner-e2e qa-runner-k6 2>/dev/null || true
echo "=> Down completado."

if [ "${UP:-0}" = "1" ]; then
  echo "=> Up servicios..."
  "${COMPOSE[@]}" --profile sonar up -d sonar-db sonarqube influxdb
  "${COMPOSE[@]}" up -d newman-viewer playwright-viewer
  PN="$(grep '^PROJECT_NAME=' .env.qa | cut -d= -f2 | tr -d '\r')"
  docker rm -f "${PN}-grafana" 2>/dev/null || true
  "${COMPOSE[@]}" up -d --build grafana
  "${COMPOSE[@]}" --profile sonar up -d db backend frontend
  echo "=> Listo."
fi
