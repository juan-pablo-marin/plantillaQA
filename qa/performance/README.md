# Guía de Pruebas de Rendimiento con k6

**Proyecto:** fihacaracterizacion  
**Carpeta:** `qa/performance/`  
**Herramienta:** [k6](https://k6.io/) — Open-source performance testing  
**Audiencia:** Equipo de QA, proveedor de la aplicación, cualquier persona que deba ejecutar o reproducir las pruebas

---

## Tabla de contenido

1. [Descripción general y scripts disponibles](#1-descripción-general-y-scripts-disponibles)
2. [Criterios de aceptación (umbrales definidos)](#2-criterios-de-aceptación-umbrales-definidos)
3. [Prerrequisitos del entorno](#3-prerrequisitos-del-entorno)
4. [Ejecución vía Docker Compose — modo recomendado](#4-ejecución-vía-docker-compose--modo-recomendado)
5. [Ejecución directa con k6 — modo debug/local](#5-ejecución-directa-con-k6--modo-debuglocal)
6. [Variables de configuración y sus efectos](#6-variables-de-configuración-y-sus-efectos)
7. [Escenarios de prueba](#7-escenarios-de-prueba)
8. [Interpretación de resultados y Grafana](#8-interpretación-de-resultados-y-grafana)
9. [Recolección de evidencia para el documento de entrega](#9-recolección-de-evidencia-para-el-documento-de-entrega)
10. [Solución de problemas frecuentes](#10-solución-de-problemas-frecuentes)
11. [Brechas identificadas en el documento Word y acciones correctivas](#11-brechas-identificadas-en-el-documento-word-y-acciones-correctivas)

---

## 1. Descripción general y scripts disponibles

Esta carpeta contiene dos scripts k6 que cubren los perfiles de prueba del sistema:

| Script | Perfil | Descripción | VUs máximos | Variables clave |
|--------|--------|-------------|-------------|-----------------|
| `k6-tests.js` | **RAV** | Prueba básica del endpoint raíz (`GET /`). Valida que el backend responda bajo carga moderada. | 30 VUs fijo | `BACKEND_URL` |
| `k6-tests_fuc.js` | **FUC** | Prueba integral con autenticación JWT, tres módulos críticos (`/health`, `/api/v1/users/`, `/api/v1/geo/`) y pico de VUs configurable. | Configurable por `K6_PEAK_VUS` (default 100, hasta 10 000+) | `BACKEND_URL`, `K6_PEAK_VUS`, `K6_AUTH_ID_USER`, `K6_AUTH_PASSWORD` |

> **Para el plan de pruebas formal se usa `k6-tests_fuc.js`**, ya que cubre módulos críticos, autenticación y escenarios de carga variable.

---

## 2. Criterios de aceptación (umbrales definidos)

Los siguientes umbrales están codificados directamente en los scripts. Una ejecución **FALLA** si cualquier umbral no se cumple; el resultado aparece en consola y en el reporte JUnit.

### Perfil FUC (`k6-tests_fuc.js`)

| Métrica | Descripción | Umbral | Consecuencia si se supera |
|---------|-------------|--------|--------------------------|
| `http_req_duration` p(95) | 95% de todas las peticiones HTTP | **< 500 ms** | Prueba FALLA |
| `errors` rate | Tasa de peticiones con error | **< 10%** | Prueba FALLA |
| `health_latency` p(99) | Latencia del endpoint `/health` | **< 200 ms** | Prueba FALLA |
| `geo_latency` p(95) | Latencia del endpoint `/api/v1/geo/` | **< 800 ms** | Prueba FALLA |
| `users_latency` p(95) | Latencia del endpoint `/api/v1/users/` | < 500 ms (check interno) | Reportado en summary |

### Perfil RAV (`k6-tests.js`)

| Métrica | Descripción | Umbral |
|---------|-------------|--------|
| `http_req_duration` p(95) | 95% de peticiones | **< 800 ms** |
| `errors` rate | Tasa de error | **< 20%** |
| `root_latency` p(99) | Latencia del endpoint raíz | **< 500 ms** |

---

## 3. Prerrequisitos del entorno

### Software requerido

| Herramienta | Versión mínima | Verificación |
|-------------|----------------|--------------|
| Docker Desktop | 24.x o superior | `docker --version` |
| Docker Compose v2 | 2.20+ | `docker compose version` |
| Git | 2.x | `git --version` |
| k6 (solo para modo debug) | 0.48+ | `k6 version` |

> En el modo Docker Compose (recomendado), k6 corre **dentro del contenedor** — no necesitas instalar k6 localmente.

### Puertos que deben estar libres en el host

| Puerto | Servicio |
|--------|---------|
| 8088 | Backend (API) |
| 3002 | Frontend |
| 8086 | InfluxDB (métricas k6) |
| 3010 | Grafana (dashboards) |
| 9090 | Prometheus (métricas infra) |
| 8089 | cAdvisor (métricas contenedores) |

Verificar puertos ocupados en Windows:
```powershell
netstat -ano | findstr "8088 8086 3010 9090"
```

### Recursos de hardware recomendados para el host de pruebas

| Componente | Mínimo recomendado | Observaciones |
|------------|-------------------|---------------|
| CPU | 4 cores | k6 con 10 000 VUs puede saturar CPUs de 2 cores |
| RAM | 8 GB | InfluxDB + Grafana + app + k6 requieren ~4-6 GB |
| Almacenamiento | 10 GB libres | Para imágenes Docker y datos de InfluxDB |
| Red | 100 Mbps | Pruebas locales no dependen de red externa |

> Para pruebas con `K6_PEAK_VUS` superior a 50 000, se requiere ejecución distribuida (k6 cloud o varios runners). En una sola máquina con 8 GB se recomienda no superar 10 000 VUs.

---

## 4. Ejecución vía Docker Compose — modo recomendado

Este modo levanta todo el stack (base de datos, backend, frontend, InfluxDB, Grafana, Prometheus, cAdvisor) y ejecuta k6 de forma orquestada. Es el modo validado y el que se usa en el pipeline Jenkins.

### Paso 1 — Clonar el repositorio

```bash
git clone <URL_DEL_REPOSITORIO>
cd fihacaracterizacion
```

Si ya tienes el repositorio clonado, asegúrate de estar en la rama correcta y tener los últimos cambios:

```bash
git checkout main
git pull origin main
```

### Paso 2 — Preparar el archivo de variables de entorno

Copia la plantilla de variables del perfil FUC:

```bash
# En Linux/Mac
cp .env.qa_fuc .env.local.qa_fuc

# En Windows PowerShell
Copy-Item .env.qa_fuc .env.local.qa_fuc
```

Abre `.env.local.qa_fuc` y configura como mínimo:

```dotenv
# Pico de usuarios virtuales para las pruebas de carga
K6_PEAK_VUS=100          # Usar 100 para prueba básica; 10000 para prueba de estrés

# Credenciales del usuario de prueba para autenticación JWT
K6_AUTH_ID_USER=12345678
K6_AUTH_PASSWORD=password123

# Habilitar la prueba k6 (por defecto está desactivado)
RUN_K6=true

# El resto de pruebas se puede dejar en false para esta ejecución
RUN_NEWMAN=false
RUN_SONAR=false
RUN_PLAYWRIGHT=false
```

> **Nota de seguridad:** nunca comitas el archivo `.env.local.qa_fuc` con credenciales reales al repositorio.

### Paso 3 — Levantar el stack de infraestructura (base de datos + observabilidad)

Primero levanta los servicios de soporte sin ejecutar las pruebas todavía:

```bash
docker compose --env-file .env.local.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile test-e2e up -d --build
```

Verifica que los servicios estén en estado `healthy` antes de continuar:

```bash
docker compose --env-file .env.local.qa_fuc -f docker-compose.qa_fuc.yml ps
```

Debes ver algo similar a:

```
NAME                         STATUS
fuc-qa-stack-backend         running (healthy)
fuc-qa-stack-frontend        running
fuc-qa-stack-db              running (healthy)
fuc-qa-stack-influxdb        running (healthy)
fuc-qa-stack-grafana         running (healthy)
fuc-qa-stack-prometheus      running
fuc-qa-stack-cadvisor        running
```

> Si algún servicio está en `starting`, espera 30-60 segundos y vuelve a ejecutar el comando `ps`.

### Paso 4 — Verificar que Grafana y el backend están listos

Antes de correr k6, confirma que puedes acceder a:

- **Backend health:** http://localhost:8088/health → debe responder `{"status":"ok"}` o similar
- **Grafana:** http://localhost:3010 → usuario `admin`, contraseña `changeme`

```bash
# Verificar backend desde consola
curl -s http://localhost:8088/health
```

### Paso 5 — Ejecutar las pruebas k6

#### Opción A: Usando el perfil `perf` de Docker Compose (k6-runner dedicado)

```bash
docker compose --env-file .env.local.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile perf run --rm k6-runner
```

Este comando levanta el contenedor `k6-runner`, ejecuta `k6-tests_fuc.js` y envía las métricas a InfluxDB. El contenedor se elimina automáticamente al terminar.

#### Opción B: Usando el qa-runner general con RUN_K6=true

```bash
docker compose --env-file .env.local.qa_fuc -f docker-compose.qa_fuc.yml \
  run --rm \
  -e RUN_K6=true \
  -e K6_PEAK_VUS=100 \
  qa-runner
```

### Paso 6 — Monitorear la ejecución en tiempo real en Grafana

1. Abre el navegador en **http://localhost:3010**
2. Inicia sesión con `admin` / `changeme`
3. Ve a **Dashboards → k6** (o busca "k6-perf")
4. Los datos aparecen en tiempo real durante la ejecución

Paneles clave a observar:

| Panel | Qué indica |
|-------|-----------|
| **Virtual Users** | Rampa de usuarios activos (debe seguir la curva 10%→50%→100%→0) |
| **Request Rate** | Peticiones por segundo enviadas al backend |
| **Response Time (p95)** | Latencia del percentil 95 — no debe superar 500 ms |
| **Error Rate** | Porcentaje de errores — no debe superar 10% |
| **HTTP Status Codes** | Distribución de códigos 2xx, 4xx, 5xx |

### Paso 7 — Consultar los artefactos generados

Al finalizar la ejecución, los reportes se guardan en:

```
qa/reports/k6/
├── summary.json    ← Resumen completo de todas las métricas
└── junit.xml       ← Reporte en formato JUnit (compatible Jenkins)
```

Visualizar el resumen desde consola:

```bash
# Windows PowerShell
Get-Content qa\reports\k6\summary.json | python -m json.tool | Select-Object -First 80

# Alternativa con Docker
docker run --rm -v ${PWD}/qa/reports:/reports alpine cat /reports/k6/summary.json
```

### Paso 8 — Apagar el stack al terminar

```bash
docker compose --env-file .env.local.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile test-e2e down
```

Para eliminar también los volúmenes de datos (InfluxDB, Grafana):

```bash
docker compose --env-file .env.local.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile test-e2e down -v
```

---

## 5. Ejecución directa con k6 — modo debug/local

Usa este modo cuando quieras depurar el script, probar un cambio rápido o ejecutar contra un backend que ya está corriendo.

### Paso 1 — Instalar k6 localmente

**Windows (con Chocolatey):**
```powershell
choco install k6
```

**Windows (con Winget):**
```powershell
winget install k6 --source winget
```

**Linux/Mac:**
```bash
# Mac
brew install k6

# Linux (Debian/Ubuntu)
sudo apt-get install k6
```

Verifica la instalación:
```bash
k6 version
# Debe mostrar: k6 v0.5x.x (...)
```

### Paso 2 — Levantar solo InfluxDB para recibir métricas

Si quieres ver las métricas en Grafana durante la ejecución local, levanta solo InfluxDB:

```bash
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile test-e2e up -d influxdb grafana prometheus cadvisor
```

Si no necesitas Grafana y solo quieres ver la salida en consola, puedes omitir este paso.

### Paso 3 — Ejecutar k6 con variables de entorno

```bash
# Desde la raíz del repositorio — prueba básica (100 VUs, con métricas en InfluxDB)
k6 run \
  -e BACKEND_URL=http://localhost:8088 \
  -e K6_PEAK_VUS=100 \
  -e K6_AUTH_ID_USER=12345678 \
  -e K6_AUTH_PASSWORD=password123 \
  --out influxdb=http://localhost:8086/k6 \
  qa/performance/k6-tests_fuc.js

# Sin InfluxDB (solo salida en consola)
k6 run \
  -e BACKEND_URL=http://localhost:8088 \
  -e K6_PEAK_VUS=50 \
  qa/performance/k6-tests_fuc.js
```

### Paso 4 — Interpretar la salida de consola

Durante la ejecución verás algo similar a:

```
          /\      |‾‾| /‾‾/   /‾‾/
     /\  /  \     |  |/  /   /  /
    /  \/    \    |     (   /   ‾‾\
   /          \   |  |\  \ |  (‾)  |
  / __________ \  |__| \__\ \_____/ .io

  execution: local
     script: qa/performance/k6-tests_fuc.js
     output: influxdb=http://localhost:8086/k6

  scenarios: (100.00%) 1 scenario, 100 max VUs, 3m30s max duration
           * default: Up to 100 looping VUs for 3m0s over 4 stages

running (2m30s), 100/100 VUs, 7213 complete iterations

✓ health status 200
✓ health response < 100ms
✓ users status 200
✗ users response < 500ms    ← indica que este check falló en algunos casos

checks.........................: 98.12% ✓ 21240 ✗ 412
data_received..................: 4.8 MB 32 kB/s
data_sent......................: 1.9 MB 13 kB/s
http_req_duration...............: avg=123ms  min=12ms med=89ms max=1.2s  p(90)=287ms p(95)=412ms
  { expected_response:true }...: avg=121ms  ...
http_req_failed.................: 1.87% ✓ 412  ✗ 21652

✓ errors........................: 1.87% < 10% ← PASA
✓ health_latency................: p(99)=187ms < 200ms ← PASA
✓ http_req_duration.............: p(95)=412ms < 500ms ← PASA
✗ geo_latency...................: p(95)=823ms > 800ms ← FALLA
```

**Interpretación del resultado final:**
- `✓` en la sección de thresholds → el umbral se cumplió
- `✗` en la sección de thresholds → la prueba FALLÓ ese criterio
- Si todos son `✓`, k6 termina con **exit code 0** (éxito)
- Si alguno es `✗`, k6 termina con **exit code 99** (fallo de threshold)

---

## 6. Variables de configuración y sus efectos

| Variable | Valor por defecto | Valores típicos | Efecto |
|----------|-------------------|-----------------|--------|
| `BACKEND_URL` | `http://backend:8080` (Docker) | `http://localhost:8088` (local) | URL base del API a probar |
| `K6_PEAK_VUS` | `100` | `10`, `100`, `1000`, `10000` | Pico máximo de usuarios virtuales simultáneos |
| `K6_AUTH_ID_USER` | _(vacío)_ | `12345678` | ID del usuario para login JWT. Si está vacío, el grupo `API - Listar usuarios` se omite |
| `K6_AUTH_PASSWORD` | _(vacío)_ | `password123` | Contraseña del usuario de prueba |
| `K6_INFLUXDB_PUSH_INTERVAL` | Auto-calculado | `1s`, `2s`, `3s` | Frecuencia de envío de métricas a InfluxDB. k6 lo ajusta automáticamente según el número de VUs |
| `K6_INFLUXDB_CONCURRENT_WRITES` | `4` | `1`, `4`, `8` | Escrituras concurrentes a InfluxDB |
| `K6_DIR` | `/qa/reports/k6` | Cualquier ruta | Carpeta donde se guardan `summary.json` y `junit.xml` |

### Lógica automática de `K6_INFLUXDB_PUSH_INTERVAL`

El sistema ajusta automáticamente el intervalo de envío para evitar errores 413 (payload demasiado grande) en InfluxDB:

| `K6_PEAK_VUS` | `K6_INFLUXDB_PUSH_INTERVAL` automático |
|--------------|----------------------------------------|
| < 3 000 | `1s` |
| 3 000 – 7 999 | `250ms` |
| 8 000 – 49 999 | `2s` |
| ≥ 50 000 | `3s` |

Para anular este comportamiento, define `K6_INFLUXDB_PUSH_INTERVAL` explícitamente en el archivo `.env`.

---

## 7. Escenarios de prueba

Los scripts implementan una **rampa de carga progresiva** para todos los escenarios:

```
Etapa 1 (30s): 0 → 10% del pico   [calentamiento]
Etapa 2 (60s): 10% → 50% del pico [carga sostenida media]
Etapa 3 (30s): 50% → 100% del pico [carga máxima]
Etapa 4 (30s): 100% → 0           [enfriamiento]
Duración total: ~2 minutos 30 segundos
```

### Escenario 1 — Prueba de carga (Load Testing)

Evalúa el comportamiento en condiciones normales de operación.

| Parámetro | Valor |
|-----------|-------|
| `K6_PEAK_VUS` | `100` |
| Objetivo | Verificar que los umbrales de respuesta se cumplen bajo carga esperada |
| Criterio de aceptación | p(95) < 500 ms, tasa de error < 10% |

```bash
K6_PEAK_VUS=100 k6 run -e BACKEND_URL=http://localhost:8088 qa/performance/k6-tests_fuc.js
```

**Módulos evaluados:**

| Módulo / Endpoint | Flujo evaluado | Criterio específico |
|-------------------|---------------|---------------------|
| `GET /health` | Health check del sistema | p(99) < 200 ms |
| `GET /api/v1/users/` | Listar usuarios autenticados (requiere JWT) | p(95) < 500 ms |
| `GET /api/v1/geo/` | Consulta de datos geográficos (sin autenticación) | p(95) < 800 ms |

### Escenario 2 — Prueba de estrés (Stress Testing)

Supera progresivamente la carga máxima para identificar el punto de quiebre.

| Parámetro | Valor |
|-----------|-------|
| `K6_PEAK_VUS` | `1000` → `5000` → `10000` (incrementar gradualmente) |
| Objetivo | Determinar cuántos VUs soporta el sistema antes de degradar |
| Criterio de quiebre | Tasa de error > 10% o p(95) > 500 ms sostenido |

```bash
# Ejecutar en tres corridas sucesivas, aumentando VUs
K6_PEAK_VUS=1000  k6 run -e BACKEND_URL=http://localhost:8088 qa/performance/k6-tests_fuc.js
K6_PEAK_VUS=5000  k6 run -e BACKEND_URL=http://localhost:8088 qa/performance/k6-tests_fuc.js
K6_PEAK_VUS=10000 k6 run -e BACKEND_URL=http://localhost:8088 qa/performance/k6-tests_fuc.js
```

Registra para cada corrida: VUs pico, p(95), tasa de error. El punto de quiebre es la corrida donde algún umbral deja de cumplirse.

### Escenario 3 — Prueba de concurrencia (Concurrency Testing)

Evalúa operaciones simultáneas mixtas (lectura y escritura) sobre recursos compartidos.

| Parámetro | Valor |
|-----------|-------|
| `K6_PEAK_VUS` | `200` |
| Objetivo | Verificar que no hay condiciones de carrera ni bloqueos bajo acceso simultáneo |
| Escenarios mixtos | `/health` (lectura) + `/api/v1/users/` (lectura autenticada) + `/api/v1/geo/` (lectura) |

```bash
K6_PEAK_VUS=200 \
K6_AUTH_ID_USER=12345678 \
K6_AUTH_PASSWORD=password123 \
k6 run -e BACKEND_URL=http://localhost:8088 qa/performance/k6-tests_fuc.js
```

> El script `k6-tests_fuc.js` ejecuta los tres grupos en cada iteración de VU, simulando concurrencia mixta de forma nativa.

### Escenario 4 — Prueba de resistencia (Endurance Testing)

Evalúa estabilidad bajo carga sostenida durante un período prolongado para detectar degradación progresiva o fugas de memoria.

> **Nota:** El script actual tiene una duración de ~2.5 minutos. Para una prueba de resistencia real, se recomienda modificar temporalmente las etapas del script:

Modificación temporal en `k6-tests_fuc.js` para endurance (no hacer commit de este cambio):

```javascript
// stages para endurance (30 minutos de carga sostenida)
stages: [
  { duration: '2m',  target: stage50 },   // calentamiento
  { duration: '30m', target: stage50 },   // carga sostenida al 50%
  { duration: '2m',  target: 0 },         // enfriamiento
],
```

```bash
K6_PEAK_VUS=100 k6 run -e BACKEND_URL=http://localhost:8088 qa/performance/k6-tests_fuc.js
```

Monitorear durante la ejecución en Grafana: tendencia creciente de latencia o de uso de CPU en el tiempo indica degradación.

---

## 8. Interpretación de resultados y Grafana

### Lectura del archivo `summary.json`

El archivo `qa/reports/k6/summary.json` contiene el resumen completo. Los campos más importantes:

```json
{
  "metrics": {
    "http_req_duration": {
      "values": {
        "avg": 123.4,     ← Promedio en ms
        "min": 11.2,
        "med": 89.1,      ← Mediana
        "max": 1204.5,
        "p(90)": 287.3,   ← Percentil 90
        "p(95)": 412.1,   ← Percentil 95 → comparar contra umbral 500ms
        "p(99)": 678.9
      }
    },
    "http_req_failed": {
      "values": {
        "rate": 0.0187    ← 1.87% de errores → comparar contra umbral 10%
      }
    },
    "vus_max": {
      "values": {
        "value": 100      ← Pico de VUs alcanzado
      }
    }
  }
}
```

### Dashboards de Grafana

Accede a **http://localhost:3010** y abre el dashboard **k6**:

| Panel | Umbral visual | Cuándo preocuparse |
|-------|--------------|-------------------|
| Response Time (p95) | Línea roja en 500 ms | Si la línea azul cruza la roja sostenidamente |
| Error Rate | 10% | Si supera el 10% durante más de 10s |
| Virtual Users | — | Debe seguir la rampa definida sin caídas abruptas |
| Request Rate (RPS) | — | Si cae mientras los VUs siguen altos, indica saturación |
| HTTP Status 5xx | 0 | Cualquier 5xx merece investigación |

### Dashboard cAdvisor (infraestructura)

En el dashboard **cAdvisor** puedes ver el consumo de recursos por contenedor:

| Métrica | Contenedor clave | Señal de alerta |
|---------|------------------|-----------------|
| CPU Usage | `backend` | > 80% sostenido |
| Memory Usage | `backend` / `db` | Crecimiento continuo sin estabilizarse (posible fuga) |
| Network I/O | `backend` | Saturación de ancho de banda |

---

## 9. Recolección de evidencia para el documento de entrega

Al finalizar cada tipo de prueba, el ejecutor debe recolectar la siguiente evidencia y registrarla en el documento Word:

### Tabla de evidencias por escenario

| Evidencia | Fuente | Cómo obtenerla | Dónde incluirla en el documento |
|-----------|--------|---------------|---------------------------------|
| Tabla de métricas (avg, p95, p99, error rate) | `qa/reports/k6/summary.json` | Abrir con un editor de texto o procesador JSON | Sección "Criterios de aceptación — resultados" |
| Captura del dashboard k6 en Grafana | http://localhost:3010 | Captura de pantalla del navegador durante/después de la prueba | Sección "Latencia HTTP — Individual" |
| Captura de CPU/Memoria por contenedor | Dashboard cAdvisor en Grafana | Captura de pantalla del panel cAdvisor | Sección "Infraestructura — CPU por servicio" |
| Reporte JUnit con resultado PASS/FAIL | `qa/reports/k6/junit.xml` | Adjuntar el archivo o captura del reporte en Jenkins | Sección "Estado del plan v/s ejecución" |
| Configuración de la ejecución | Archivo `.env.local.qa_fuc` | Captura de los valores de `K6_PEAK_VUS`, `BACKEND_URL`, ambiente | Sección "Configuración de la ejecución" |
| Salida de consola de k6 | Terminal durante la ejecución | Captura de pantalla de la consola al finalizar | Sección "Tablas en emulador" |

### Checklist de evidencia mínima por tipo de prueba

- [ ] Prueba de carga (100 VUs): métricas + captura Grafana + resultado PASS/FAIL
- [ ] Prueba de estrés (1 000 / 5 000 / 10 000 VUs): tabla comparativa de las 3 corridas
- [ ] Prueba de concurrencia (200 VUs): métricas + captura estado de la BD durante la prueba
- [ ] Prueba de resistencia: gráfica de latencia a lo largo del tiempo (tendencia)

---

## 10. Solución de problemas frecuentes

### Problema: Error 413 en InfluxDB durante la prueba

**Síntoma:** La consola de k6 muestra mensajes `can't write stats, error: 413 Request Entity Too Large`.

**Causa:** El volumen de métricas enviadas en cada lote supera el límite de InfluxDB.

**Solución:**
```bash
# Aumentar el intervalo de push manualmente
K6_INFLUXDB_PUSH_INTERVAL=3s k6 run ...

# O recrear el volumen de InfluxDB (limpia datos anteriores)
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile test-e2e down -v
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml \
  --profile test-e2e up -d influxdb grafana
```

---

### Problema: Backend no disponible al iniciar k6

**Síntoma:** Todos los checks fallan con `connection refused` o `EOF`.

**Causa:** El backend no completó su inicio antes de que k6 comenzara a enviar peticiones.

**Solución:** Verificar el health check del backend antes de lanzar k6:

```bash
# Esperar manualmente a que el backend esté listo
for i in {1..30}; do
  curl -sf http://localhost:8088/health && echo "Backend listo" && break
  echo "Intento $i/30 — esperando..."
  sleep 3
done
```

---

### Problema: InfluxDB no recibe los datos de k6

**Síntoma:** La ejecución termina correctamente pero Grafana no muestra datos.

**Causa:** k6 no puede alcanzar InfluxDB por diferencia de red Docker.

**Solución:**
```bash
# Verificar que InfluxDB está corriendo
docker ps | grep influxdb

# Verificar conectividad (dentro del contenedor qa-runner o desde host)
curl -s http://localhost:8086/ping
# Debe responder: HTTP 204

# Verificar que la base de datos 'k6' existe
curl -s "http://localhost:8086/query?q=SHOW+DATABASES"
```

---

### Problema: Grafana muestra "No data" en el dashboard

**Síntoma:** El dashboard k6 en Grafana está vacío aunque k6 ejecutó correctamente.

**Causa:** El datasource de InfluxDB no apunta a la base de datos `k6`, o el rango de tiempo del dashboard no incluye la ejecución reciente.

**Solución:**
1. Ir a **Grafana → Configuration → Data Sources → influxdb**
2. Verificar que `Database` dice `k6`
3. Hacer clic en **Save & Test** (debe mostrar "Data source is working")
4. En el dashboard, cambiar el rango de tiempo a **Last 15 minutes**

---

### Problema: k6 sale con exit code 99 (fallo de threshold)

**Síntoma:** La prueba termina con `FAIL` y un mensaje de `thresholds on metrics 'X' have been crossed`.

**Esto es esperado cuando el sistema no cumple los criterios de aceptación.** No es un error del script.

**Acción:** Revisar qué métrica falló (aparece marcada con `✗` al final de la salida de consola), capturar la evidencia y registrarla en el documento de entrega como hallazgo con el valor obtenido vs. el umbral esperado.

---

## 11. Brechas identificadas en el documento Word y acciones correctivas

Esta sección lista las brechas detectadas al comparar el documento de entrega actual ("PRUEBA DE RENDIMIENTO Y USO DE RECURSOS") contra los 8 criterios de aceptación de la historia de usuario formal.

> **Referencia de la historia:** `log19mar.groovy` — Historia de usuario: Plan de Pruebas de Rendimiento y Estrés.

### Tabla de brechas y acciones

| # | Criterio de aceptación | Estado en el documento actual | Acción correctiva requerida en el Word |
|---|------------------------|-------------------------------|----------------------------------------|
| 1 | Tiempos de respuesta y uso de recursos en carga documentados | **Parcial** — muestra resultados pero no define los umbrales como criterios previos a la ejecución | Agregar tabla de umbrales formales (copiar de la sección 2 de este README). Incluir umbrales de CPU (< 80%), memoria y ancho de banda además de latencia HTTP |
| 2 | Cantidad de usuarios estimados en operación normal documentada | **Parcial** — muestra los VUs configurados pero sin justificación | Agregar sección que justifique por qué se eligió el valor de `K6_PEAK_VUS=10000` como pico. Incluir la distribución estimada de carga por módulo (`/health` 60%, `/geo/` 30%, `/users/` 10%) |
| 3 | Cantidad máxima de usuarios soportados con criterio de tiempo de respuesta | **Parcial** — hay resultados de estrés pero falta el procedimiento formal | Agregar subsección "Punto de quiebre": describir el procedimiento de las 3 corridas sucesivas (1 000 → 5 000 → 10 000 VUs) y documentar en qué corrida comenzaron a fallar los umbrales |
| 4 | Usuarios concurrentes soportados documentados | **Parcial** — no hay escenarios de lectura/escritura/mixtos definidos explícitamente | Agregar tabla de escenarios de concurrencia: (a) solo lectura, (b) lectura autenticada, (c) mixto. Incluir criterios de aceptación por escenario |
| 5 | Requerimientos mínimos de hardware y comunicaciones documentados | **Parcial** — muestra uso observado, no especificaciones mínimas formales | Agregar tabla de especificaciones mínimas requeridas (copiar de la sección 3 de este README). Incluir: CPU (4 cores mínimo), RAM (8 GB), red (100 Mbps), almacenamiento (10 GB libres para Docker) |
| 6 | Escenarios de prueba por módulo crítico definidos | **Parcial** — cubre 3 endpoints pero sin descripción completa de flujo, datos de entrada y criterios individuales | Agregar tabla por endpoint: `GET /health`, `GET /api/v1/users/`, `GET /api/v1/geo/`. Incluir flujo, datos de entrada, volumen de peticiones esperado y criterio de aceptación individual (copiar de la sección 7 de este README) |
| 7 | Procedimiento de ejecución documentado | **AUSENTE** en el documento Word | Incluir en el documento Word un resumen del procedimiento de 8 pasos descrito en la sección 4 de este README. Referenciar este archivo para el detalle técnico completo |
| 8 | Documento aprobado y disponible para el proveedor | **AUSENTE** | Agregar al documento Word una página de firmas con: (a) nombre, cargo, firma y fecha del líder técnico, (b) nombre, cargo, firma y fecha del arquitecto de infraestructura. El documento no debe entregarse al proveedor sin esta página completada |

### Checklist de cumplimiento final

Antes de entregar el documento al proveedor, verificar:

- [ ] Las 8 secciones de criterios de aceptación tienen contenido completo (no solo resultados)
- [ ] La tabla de umbrales coincide con los valores en el script `k6-tests_fuc.js`
- [ ] La justificación de los 10 000 VUs está documentada con base en proyecciones de uso real
- [ ] El procedimiento de ejecución de la sección 4 (o un resumen) está incluido en el Word
- [ ] Las capturas de evidencia están adjuntas en el Word (ver sección 9 de este README)
- [ ] La página de firmas está completada por ambos aprobadores
- [ ] El documento está guardado en formato oficial y entregado al proveedor antes del inicio de la ejecución

---

*Documento generado para el proyecto fihacaracterizacion | Perfil FUC | Herramienta: k6 v0.48+*
