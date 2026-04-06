# Reinicio completo del stack QA RAV en Windows (alineado con RESET_DOCKER_STACK en Jenkins).
# Uso (desde la raiz del repo victimasrav):
#   .\qa\scripts\rav-docker-full-reset.ps1
#   .\qa\scripts\rav-docker-full-reset.ps1 -Up

param([switch]$Up)

$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

$env:COMPOSE_PROFILES = "test-e2e,sonar"
$env:DOCKER_BUILDKIT = "1"

function Invoke-RavCompose {
    param([Parameter(Mandatory = $true)][string[]]$ComposeArgs)
    & docker compose --env-file .env.qa -f docker-compose.qa.yml -f docker-compose.jenkins.yml @ComposeArgs
}

Write-Host "=> Raiz: $Root"
Write-Host "=> Down: proyecto qa-pipeline (COMPOSE_PROJECT_NAME en .env.qa)..."
Invoke-RavCompose -ComposeArgs @("down", "--remove-orphans") 2>$null

Write-Host "=> Down: proyecto victimasrav..."
docker compose -p victimasrav --env-file .env.qa -f docker-compose.qa.yml -f docker-compose.jenkins.yml down --remove-orphans 2>$null

Write-Host "=> Down: proyecto fuc-dev (docker-compose.yml raiz — evita backend Mongo mezclado con RAV)..."
docker compose -p fuc-dev --env-file .env.dev -f docker-compose.yml down --remove-orphans 2>$null
docker compose -p fuc-dev down --remove-orphans 2>$null

Write-Host "=> Eliminando contenedores name=*rav-qa-stack*..."
docker ps -aq --filter "name=rav-qa-stack" | ForEach-Object { docker rm -f $_ 2>$null }

Write-Host "=> Eliminando runners nombrados..."
docker rm -f qa-runner-newman qa-runner-sonar qa-runner-e2e qa-runner-k6 2>$null

Write-Host "=> Reinicio (down) completado."

if ($Up) {
    Write-Host "=> Up: influx, sonar, db, backend, viewers, grafana..."
    Invoke-RavCompose -ComposeArgs @("--profile", "sonar", "up", "-d", "sonar-db", "sonarqube", "influxdb")
    Invoke-RavCompose -ComposeArgs @("up", "-d", "newman-viewer", "playwright-viewer")
    $pn = (Select-String -Path .env.qa -Pattern '^PROJECT_NAME=' | ForEach-Object { ($_ -split '=', 2)[1].Trim() })
    if ($pn) { docker rm -f "${pn}-grafana" 2>$null }
    Invoke-RavCompose -ComposeArgs @("up", "-d", "--build", "grafana")
    Invoke-RavCompose -ComposeArgs @("--profile", "sonar", "up", "-d", "db", "backend", "frontend")
    Write-Host "=> Listo. Estado: docker ps"
}
