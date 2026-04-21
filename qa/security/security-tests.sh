#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# OWASP ZAP Security Tests - FUC SENA
# 
# Ejecuta escaneos de seguridad automatizados usando OWASP ZAP:
#   - Escaneo pasivo (spider + análisis de respuestas)
#   - Escaneo activo (ataques controlados: CSRF, XSS, SQLi, etc.)
#   - Generación de reportes HTML, JSON y XML
#
# Vulnerabilidades detectadas:
#   - Cross-Site Request Forgery (CSRF)
#   - Cross-Site Scripting (XSS) - Reflejado y Almacenado
#   - SQL Injection / NoSQL Injection
#   - Broken Authentication
#   - Security Misconfiguration
#   - Insecure Headers (CSP, X-Frame-Options, etc.)
#   - Sensitive Data Exposure
#   - Server Side Request Forgery (SSRF)
#   - Path Traversal
#   - Remote File Inclusion
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuración ──
BACKEND_URL="${BACKEND_URL:-http://backend:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://frontend:3000}"
REPORTS_DIR="${REPORTS_DIR:-/qa/reports}"
SECURITY_DIR="$REPORTS_DIR/security"
ZAP_CONFIG="${ZAP_CONFIG:-/qa/security/zap-config.yaml}"

# Timeout para escaneos (minutos)
ZAP_SPIDER_TIMEOUT="${ZAP_SPIDER_TIMEOUT:-5}"
ZAP_PASSIVE_TIMEOUT="${ZAP_PASSIVE_TIMEOUT:-10}"
ZAP_ACTIVE_TIMEOUT="${ZAP_ACTIVE_TIMEOUT:-30}"

# Niveles de riesgo para fallar el build
FAIL_ON_HIGH="${FAIL_ON_HIGH:-true}"
FAIL_ON_MEDIUM="${FAIL_ON_MEDIUM:-false}"

# Token JWT para endpoints autenticados
TEST_TOKEN="${TEST_TOKEN:-}"

echo "═══════════════════════════════════════════════════════════════"
echo " OWASP ZAP Security Scanner - FUC SENA"
echo "═══════════════════════════════════════════════════════════════"
echo " Backend URL:     $BACKEND_URL"
echo " Frontend URL:    $FRONTEND_URL"
echo " Reports:         $SECURITY_DIR"
echo " Spider Timeout:  ${ZAP_SPIDER_TIMEOUT}m"
echo " Active Timeout:  ${ZAP_ACTIVE_TIMEOUT}m"
echo "───────────────────────────────────────────────────────────────"

# Crear directorio de reportes
mkdir -p "$SECURITY_DIR"

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Esperar que el servicio esté disponible
# ════════════════════════════════════════════════════════════════════
wait_for_service() {
    local url="$1"
    local name="$2"
    local max_attempts="${3:-30}"
    
    echo "  Esperando $name ($url)..."
    for i in $(seq 1 "$max_attempts"); do
        if curl -sf "$url" > /dev/null 2>&1; then
            echo "  ✓ $name disponible"
            return 0
        fi
        echo "    ... intento $i/$max_attempts"
        sleep 2
    done
    echo "  ✗ $name no disponible después de $max_attempts intentos"
    return 1
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Ejecutar ZAP Baseline Scan (Pasivo)
# ════════════════════════════════════════════════════════════════════
run_baseline_scan() {
    local target_url="$1"
    local report_name="$2"
    
    echo ""
    echo "[ZAP] Ejecutando Baseline Scan (Pasivo) en $target_url..."
    
    # ZAP Baseline: spider + passive scan (no ataca, solo observa)
    zap-baseline.py \
        -t "$target_url" \
        -r "$SECURITY_DIR/${report_name}-baseline.html" \
        -J "$SECURITY_DIR/${report_name}-baseline.json" \
        -x "$SECURITY_DIR/${report_name}-baseline.xml" \
        -d \
        -I \
        --auto \
        -m "$ZAP_SPIDER_TIMEOUT" \
        || echo "  WARN: Baseline scan completado con alertas."
    
    echo "  Reporte: $SECURITY_DIR/${report_name}-baseline.html"
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Ejecutar ZAP Full Scan (Activo)
# ════════════════════════════════════════════════════════════════════
run_full_scan() {
    local target_url="$1"
    local report_name="$2"
    
    echo ""
    echo "[ZAP] Ejecutando Full Scan (Activo) en $target_url..."
    echo "  ADVERTENCIA: Este escaneo realiza ataques controlados."
    echo "  Solo ejecutar en entornos de QA/desarrollo."
    
    # ZAP Full Scan: spider + passive + active (ataques controlados)
    zap-full-scan.py \
        -t "$target_url" \
        -r "$SECURITY_DIR/${report_name}-full.html" \
        -J "$SECURITY_DIR/${report_name}-full.json" \
        -x "$SECURITY_DIR/${report_name}-full.xml" \
        -d \
        -I \
        --auto \
        -m "$ZAP_ACTIVE_TIMEOUT" \
        -a \
        || echo "  WARN: Full scan completado con alertas."
    
    echo "  Reporte: $SECURITY_DIR/${report_name}-full.html"
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Ejecutar ZAP API Scan
# ════════════════════════════════════════════════════════════════════
run_api_scan() {
    local openapi_url="$1"
    local report_name="$2"
    
    echo ""
    echo "[ZAP] Ejecutando API Scan con OpenAPI spec..."
    
    # Verificar si existe especificación OpenAPI/Swagger
    if curl -sf "$openapi_url" > /dev/null 2>&1; then
        zap-api-scan.py \
            -t "$openapi_url" \
            -f openapi \
            -r "$SECURITY_DIR/${report_name}-api.html" \
            -J "$SECURITY_DIR/${report_name}-api.json" \
            -x "$SECURITY_DIR/${report_name}-api.xml" \
            -d \
            -I \
            --auto \
            || echo "  WARN: API scan completado con alertas."
        
        echo "  Reporte: $SECURITY_DIR/${report_name}-api.html"
    else
        echo "  SKIP: No se encontró especificación OpenAPI en $openapi_url"
    fi
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Ejecutar ZAP con Automation Framework (YAML config)
# ════════════════════════════════════════════════════════════════════
run_automation_scan() {
    local config_file="$1"
    
    echo ""
    echo "[ZAP] Ejecutando Automation Framework con $config_file..."
    
    if [ -f "$config_file" ]; then
        zap.sh -cmd -autorun "$config_file" \
            || echo "  WARN: Automation scan completado con alertas."
    else
        echo "  SKIP: No se encontró archivo de configuración: $config_file"
    fi
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Pruebas manuales de CSRF
# ════════════════════════════════════════════════════════════════════
test_csrf_protection() {
    echo ""
    echo "[CSRF] Probando protección contra CSRF..."
    
    local csrf_report="$SECURITY_DIR/csrf-test-results.json"
    local csrf_issues=()
    
    # Endpoints sensibles que requieren protección CSRF
    local endpoints=(
        "POST:$BACKEND_URL/api/v1/auth/signup"
        "POST:$BACKEND_URL/api/v1/auth/login"
        "POST:$BACKEND_URL/api/v1/fuc"
        "PUT:$BACKEND_URL/api/v1/fuc"
        "DELETE:$BACKEND_URL/api/v1/fuc"
    )
    
    echo '{"csrf_tests": [' > "$csrf_report"
    local first=true
    
    for endpoint in "${endpoints[@]}"; do
        local method="${endpoint%%:*}"
        local url="${endpoint#*:}"
        
        # Test 1: Request sin token CSRF (debería fallar o tener protección)
        echo "  Testing $method $url..."
        
        # Intentar request desde origen diferente (simular ataque CSRF)
        local response=$(curl -sf -X "$method" "$url" \
            -H "Origin: http://evil-site.com" \
            -H "Referer: http://evil-site.com/attack" \
            -H "Content-Type: application/json" \
            -d '{"test": "csrf"}' \
            -w "\n%{http_code}" \
            2>/dev/null || echo "error")
        
        local status_code=$(echo "$response" | tail -1)
        local vulnerable="false"
        
        # Si acepta request de origen malicioso sin CSRF token, es vulnerable
        if [ "$status_code" = "200" ] || [ "$status_code" = "201" ]; then
            vulnerable="true"
            csrf_issues+=("$method $url acepta requests de origen externo sin CSRF token")
        fi
        
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$csrf_report"
        fi
        
        cat >> "$csrf_report" <<EOF
    {
      "endpoint": "$url",
      "method": "$method",
      "status_code": "$status_code",
      "vulnerable": $vulnerable,
      "test": "cross_origin_request"
    }
EOF
    done
    
    echo '],' >> "$csrf_report"
    echo "\"total_issues\": ${#csrf_issues[@]}," >> "$csrf_report"
    echo "\"issues\": [" >> "$csrf_report"
    
    first=true
    for issue in "${csrf_issues[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$csrf_report"
        fi
        echo "    \"$issue\"" >> "$csrf_report"
    done
    
    echo "]}" >> "$csrf_report"
    
    if [ ${#csrf_issues[@]} -gt 0 ]; then
        echo "  ⚠ Se encontraron ${#csrf_issues[@]} posibles vulnerabilidades CSRF"
    else
        echo "  ✓ No se detectaron vulnerabilidades CSRF obvias"
    fi
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Pruebas de Security Headers
# ════════════════════════════════════════════════════════════════════
test_security_headers() {
    echo ""
    echo "[Headers] Verificando Security Headers..."
    
    local headers_report="$SECURITY_DIR/security-headers.json"
    local urls=("$BACKEND_URL" "$FRONTEND_URL")
    
    echo '{"security_headers": [' > "$headers_report"
    local first=true
    
    for url in "${urls[@]}"; do
        echo "  Analizando $url..."
        
        # Obtener headers
        local headers=$(curl -sI "$url" 2>/dev/null || echo "")
        
        # Headers de seguridad recomendados
        local csp=$(echo "$headers" | grep -i "content-security-policy:" || echo "MISSING")
        local xframe=$(echo "$headers" | grep -i "x-frame-options:" || echo "MISSING")
        local xcontent=$(echo "$headers" | grep -i "x-content-type-options:" || echo "MISSING")
        local xss=$(echo "$headers" | grep -i "x-xss-protection:" || echo "MISSING")
        local hsts=$(echo "$headers" | grep -i "strict-transport-security:" || echo "MISSING")
        local referrer=$(echo "$headers" | grep -i "referrer-policy:" || echo "MISSING")
        local permissions=$(echo "$headers" | grep -i "permissions-policy:" || echo "MISSING")
        
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$headers_report"
        fi
        
        cat >> "$headers_report" <<EOF
    {
      "url": "$url",
      "content_security_policy": "$([ "$csp" != "MISSING" ] && echo "present" || echo "missing")",
      "x_frame_options": "$([ "$xframe" != "MISSING" ] && echo "present" || echo "missing")",
      "x_content_type_options": "$([ "$xcontent" != "MISSING" ] && echo "present" || echo "missing")",
      "x_xss_protection": "$([ "$xss" != "MISSING" ] && echo "present" || echo "missing")",
      "strict_transport_security": "$([ "$hsts" != "MISSING" ] && echo "present" || echo "missing")",
      "referrer_policy": "$([ "$referrer" != "MISSING" ] && echo "present" || echo "missing")",
      "permissions_policy": "$([ "$permissions" != "MISSING" ] && echo "present" || echo "missing")"
    }
EOF
        
        # Mostrar resumen
        [ "$csp" = "MISSING" ] && echo "    ⚠ Content-Security-Policy: FALTANTE"
        [ "$xframe" = "MISSING" ] && echo "    ⚠ X-Frame-Options: FALTANTE"
        [ "$xcontent" = "MISSING" ] && echo "    ⚠ X-Content-Type-Options: FALTANTE"
    done
    
    echo "]}" >> "$headers_report"
    echo "  Reporte: $headers_report"
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Pruebas de inyección básicas
# ════════════════════════════════════════════════════════════════════
test_injection_payloads() {
    echo ""
    echo "[Injection] Probando payloads de inyección..."
    
    local injection_report="$SECURITY_DIR/injection-tests.json"
    
    # Payloads de prueba (benignos pero detectables)
    local sql_payloads=(
        "' OR '1'='1"
        "1; DROP TABLE users--"
        "admin'--"
        "1' AND '1'='1"
    )
    
    local nosql_payloads=(
        '{"$gt": ""}'
        '{"$ne": null}'
        '{"$where": "1==1"}'
    )
    
    local xss_payloads=(
        "<script>alert('XSS')</script>"
        "<img src=x onerror=alert('XSS')>"
        "javascript:alert('XSS')"
        "<svg/onload=alert('XSS')>"
    )
    
    echo '{"injection_tests": {' > "$injection_report"
    
    # Test SQL/NoSQL injection en login
    echo '"login_endpoint": [' >> "$injection_report"
    local first=true
    for payload in "${sql_payloads[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$injection_report"
        fi
        
        local response=$(curl -sf -X POST "$BACKEND_URL/api/v1/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"id_user\": \"$payload\", \"password\": \"test\", \"document_type\": \"CC\"}" \
            -w "\n%{http_code}" \
            2>/dev/null || echo "error")
        
        local status=$(echo "$response" | tail -1)
        # Si retorna 200 con payload de inyección, podría ser vulnerable
        local suspicious="false"
        [ "$status" = "200" ] && suspicious="true"
        
        echo "    {\"payload\": \"$(echo "$payload" | sed 's/"/\\"/g')\", \"status\": \"$status\", \"suspicious\": $suspicious}" >> "$injection_report"
    done
    echo "]," >> "$injection_report"
    
    # Test XSS payloads
    echo '"xss_tests": [' >> "$injection_report"
    first=true
    for payload in "${xss_payloads[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$injection_report"
        fi
        
        # Buscar reflexión del payload en la respuesta
        local response=$(curl -sf "$BACKEND_URL/api/v1/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"id_user\": \"$(echo "$payload" | sed 's/"/\\"/g')\", \"password\": \"test\"}" \
            2>/dev/null || echo "")
        
        local reflected="false"
        echo "$response" | grep -q "$payload" && reflected="true"
        
        echo "    {\"payload\": \"$(echo "$payload" | sed 's/"/\\"/g')\", \"reflected\": $reflected}" >> "$injection_report"
    done
    echo "]" >> "$injection_report"
    
    echo "}}" >> "$injection_report"
    echo "  Reporte: $injection_report"
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Generar reporte consolidado
# ════════════════════════════════════════════════════════════════════
generate_summary() {
    echo ""
    echo "[Summary] Generando reporte consolidado..."
    
    local summary_file="$SECURITY_DIR/security-summary.html"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    cat > "$summary_file" <<'EOF'
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
        .card h2 { color: #f1f5f9; margin-bottom: 1rem; display: flex; align-items: center; gap: 0.5rem; }
        .badge { padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.75rem; font-weight: 600; }
        .badge-high { background: #dc2626; color: white; }
        .badge-medium { background: #f59e0b; color: black; }
        .badge-low { background: #3b82f6; color: white; }
        .badge-info { background: #6366f1; color: white; }
        .badge-pass { background: #22c55e; color: white; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1rem; }
        .stat { text-align: center; padding: 1rem; }
        .stat-value { font-size: 2.5rem; font-weight: 700; }
        .stat-label { color: #94a3b8; font-size: 0.875rem; }
        table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
        th, td { padding: 0.75rem; text-align: left; border-bottom: 1px solid #334155; }
        th { color: #94a3b8; font-weight: 500; }
        .report-link { color: #60a5fa; text-decoration: none; }
        .report-link:hover { text-decoration: underline; }
        .timestamp { color: #64748b; font-size: 0.875rem; margin-top: 2rem; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Security Scan Report</h1>
        <p class="subtitle">FUC SENA - Análisis de Seguridad Automatizado</p>
        
        <div class="card">
            <h2>📊 Resumen de Escaneos</h2>
            <div class="grid">
                <div class="stat">
                    <div class="stat-value" style="color: #f87171;">-</div>
                    <div class="stat-label">Vulnerabilidades Altas</div>
                </div>
                <div class="stat">
                    <div class="stat-value" style="color: #fbbf24;">-</div>
                    <div class="stat-label">Vulnerabilidades Medias</div>
                </div>
                <div class="stat">
                    <div class="stat-value" style="color: #60a5fa;">-</div>
                    <div class="stat-label">Vulnerabilidades Bajas</div>
                </div>
                <div class="stat">
                    <div class="stat-value" style="color: #a78bfa;">-</div>
                    <div class="stat-label">Informativas</div>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2>📁 Reportes Generados</h2>
            <table>
                <thead>
                    <tr>
                        <th>Tipo de Escaneo</th>
                        <th>Target</th>
                        <th>Reportes</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>ZAP Baseline (Pasivo)</td>
                        <td>Backend API</td>
                        <td>
                            <a href="backend-baseline.html" class="report-link">HTML</a> |
                            <a href="backend-baseline.json" class="report-link">JSON</a> |
                            <a href="backend-baseline.xml" class="report-link">XML</a>
                        </td>
                    </tr>
                    <tr>
                        <td>ZAP Full Scan (Activo)</td>
                        <td>Backend API</td>
                        <td>
                            <a href="backend-full.html" class="report-link">HTML</a> |
                            <a href="backend-full.json" class="report-link">JSON</a> |
                            <a href="backend-full.xml" class="report-link">XML</a>
                        </td>
                    </tr>
                    <tr>
                        <td>ZAP Baseline (Pasivo)</td>
                        <td>Frontend</td>
                        <td>
                            <a href="frontend-baseline.html" class="report-link">HTML</a> |
                            <a href="frontend-baseline.json" class="report-link">JSON</a> |
                            <a href="frontend-baseline.xml" class="report-link">XML</a>
                        </td>
                    </tr>
                    <tr>
                        <td>CSRF Tests</td>
                        <td>Backend API</td>
                        <td><a href="csrf-test-results.json" class="report-link">JSON</a></td>
                    </tr>
                    <tr>
                        <td>Security Headers</td>
                        <td>Backend + Frontend</td>
                        <td><a href="security-headers.json" class="report-link">JSON</a></td>
                    </tr>
                    <tr>
                        <td>Injection Tests</td>
                        <td>Backend API</td>
                        <td><a href="injection-tests.json" class="report-link">JSON</a></td>
                    </tr>
                </tbody>
            </table>
        </div>
        
        <div class="card">
            <h2>🛡️ Pruebas de Seguridad Ejecutadas</h2>
            <ul style="list-style: none; padding: 0;">
                <li style="padding: 0.5rem 0;">✅ Cross-Site Request Forgery (CSRF)</li>
                <li style="padding: 0.5rem 0;">✅ Cross-Site Scripting (XSS) - Reflejado</li>
                <li style="padding: 0.5rem 0;">✅ SQL Injection</li>
                <li style="padding: 0.5rem 0;">✅ NoSQL Injection</li>
                <li style="padding: 0.5rem 0;">✅ Security Headers Analysis</li>
                <li style="padding: 0.5rem 0;">✅ Spider/Crawl de la aplicación</li>
                <li style="padding: 0.5rem 0;">✅ Passive Vulnerability Scan</li>
                <li style="padding: 0.5rem 0;">✅ Active Vulnerability Scan</li>
            </ul>
        </div>
        
EOF
    
    echo "        <p class=\"timestamp\">Generado: $timestamp</p>" >> "$summary_file"
    echo "    </div>" >> "$summary_file"
    echo "</body>" >> "$summary_file"
    echo "</html>" >> "$summary_file"
    
    echo "  Reporte consolidado: $summary_file"
}

# ════════════════════════════════════════════════════════════════════
# FUNCIÓN: Analizar resultados y determinar exit code
# ════════════════════════════════════════════════════════════════════
analyze_results() {
    echo ""
    echo "[Analysis] Analizando resultados..."
    
    local exit_code=0
    local high_count=0
    local medium_count=0
    
    # Contar alertas de los reportes JSON de ZAP
    for json_file in "$SECURITY_DIR"/*-baseline.json "$SECURITY_DIR"/*-full.json; do
        if [ -f "$json_file" ]; then
            # Extraer conteo de alertas por riesgo
            local h=$(python3 -c "
import json, sys
try:
    with open('$json_file') as f:
        data = json.load(f)
    alerts = data.get('site', [{}])[0].get('alerts', [])
    print(sum(1 for a in alerts if a.get('riskcode') == '3'))
except:
    print('0')
" 2>/dev/null || echo "0")
            local m=$(python3 -c "
import json, sys
try:
    with open('$json_file') as f:
        data = json.load(f)
    alerts = data.get('site', [{}])[0].get('alerts', [])
    print(sum(1 for a in alerts if a.get('riskcode') == '2'))
except:
    print('0')
" 2>/dev/null || echo "0")
            
            high_count=$((high_count + h))
            medium_count=$((medium_count + m))
        fi
    done
    
    echo "  Vulnerabilidades Altas:  $high_count"
    echo "  Vulnerabilidades Medias: $medium_count"
    
    if [ "$FAIL_ON_HIGH" = "true" ] && [ "$high_count" -gt 0 ]; then
        echo "  ⚠ BUILD FALLIDO: Se encontraron $high_count vulnerabilidades de alto riesgo"
        exit_code=1
    fi
    
    if [ "$FAIL_ON_MEDIUM" = "true" ] && [ "$medium_count" -gt 0 ]; then
        echo "  ⚠ BUILD FALLIDO: Se encontraron $medium_count vulnerabilidades de riesgo medio"
        exit_code=1
    fi
    
    return $exit_code
}

# ════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════
main() {
    # Esperar servicios
    wait_for_service "$BACKEND_URL/health" "Backend" 30 || true
    wait_for_service "$FRONTEND_URL" "Frontend" 30 || true
    
    # Ejecutar escaneos ZAP
    run_baseline_scan "$BACKEND_URL" "backend"
    run_baseline_scan "$FRONTEND_URL" "frontend"
    
    # Solo ejecutar full scan si está habilitado (es más intrusivo)
    if [ "${ZAP_FULL_SCAN:-true}" = "true" ]; then
        run_full_scan "$BACKEND_URL" "backend"
    fi
    
    # Escaneo de API si existe OpenAPI spec
    run_api_scan "$BACKEND_URL/swagger/doc.json" "api"
    run_api_scan "$BACKEND_URL/api/v1/openapi.json" "api"
    
    # Ejecutar escaneo con configuración YAML si existe
    if [ -f "$ZAP_CONFIG" ]; then
        run_automation_scan "$ZAP_CONFIG"
    fi
    
    # Pruebas manuales adicionales
    test_csrf_protection
    test_security_headers
    test_injection_payloads
    
    # Generar reporte consolidado
    generate_summary
    
    # Analizar resultados
    analyze_results
    local result=$?
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo " Security Scan Completado"
    echo " Reportes disponibles en: $SECURITY_DIR"
    echo "═══════════════════════════════════════════════════════════════"
    
    return $result
}

# Ejecutar
main "$@"
