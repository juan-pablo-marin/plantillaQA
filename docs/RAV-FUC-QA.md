# Cambiar entre RAV y FUC en QA

## RAV (activo por defecto en repo)

- **Compose:** `docker-compose.qa.yml`
- **Variables:** `.env.qa`
- **App:** PostgreSQL + `victims_backend` + `frontend-rav` (nombres por defecto en `.env.qa`)
- **Scripts QA:** `qa/run-tests.sh`, `qa/api/collections/api.postman_collection.json`, `qa/api/collections/env-qa.json`, `qa/performance/k6-tests.js`
- **Sonar:** `sonar-project.properties`

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml up -d --build
```

Coloca el código fuente de RAV en:

- `victims_backend/` (con `db/migrations`, `.docker/wait-for-db.sh`, `go.mod`, etc.)
- `frontend-rav/` (Next.js con `Dockerfile` etapa `runner`)

Si el build dice **«No hay go.mod»**, la carpeta está vacía o mal nombrada: **[SETUP-RAV-BACKEND.md](SETUP-RAV-BACKEND.md)**.

## FUC (plantilla original Mongo + BACKEND/FRONTEND)

- **Compose:** `docker-compose.qa_fuc.yml`
- **Variables:** `.env.qa_fuc`
- **Scripts QA:** `qa/run-tests_fuc.sh`, `qa/api/collections/api.postman_collection_fuc.json`, `qa/api/collections/env-qa_fuc.json`, `qa/performance/k6-tests_fuc.js`
- **Sonar:** `sonar-project.properties_fuc`

```bash
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml up -d --build
```

## Jenkins

El `Jenkinsfile` usa por defecto `docker-compose.qa.yml` + `.env.qa` (RAV). Para ejecutar FUC en CI, cambia el `-f` y el `--env-file` en la variable `COMPOSE_CMD` del Jenkinsfile.

## Cambio rápido de nombre

Si quieres usar el **mismo** archivo `.env.qa` con otro proyecto:

1. Renombra el activo: `mv .env.qa .env.qa_rav` (o el sufijo que uses).
2. Copia el otro: `cp .env.qa_fuc .env.qa` para volver a FUC.

O usa siempre `--env-file` explícito sin renombrar.

---

## Stack completo desde cero (RAV o FUC)

Misma idea en ambos: el perfil **`all`** activa aplicación, SonarQube, InfluxDB, Grafana (con datasource y dashboard k6 por **bind mount**), Allure, Jenkins, visores Newman/Playwright y el contenedor `qa-runner` (arranca una vez y puede quedar en estado *exited* tras ejecutar el script por defecto).

### 0) Limpieza agresiva de Docker (opcional)

Borra **todo** lo que haya en Docker en esa máquina (imágenes, contenedores, volúmenes). Úsalo solo si quieres un arranque realmente limpio.

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml down -v --remove-orphans 2>/dev/null || true
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml down -v --remove-orphans 2>/dev/null || true
docker system prune -af --volumes
```

### 1) Variables

- **RAV:** copia `docs/templates/env.qa.RAV.example` → `.env.qa` y ajusta `PROJECT_NAME`, `SONAR_TOKEN`, carpetas de código.
- **FUC:** copia `docs/templates/env.qa.FUC.example` → `.env.qa_fuc` (o usa el `.env.qa_fuc` del repo) y ajusta lo mismo.

Sin un `SONAR_TOKEN` válido, el análisis Sonar se omitirá (el script lo indica en log).

### 2) Levantar todo con perfil `all`

**RAV (Postgres + backend/frontend RAV):**

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml --profile all up -d --build
```

**FUC (Mongo + BACKEND/FRONTEND):**

```bash
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml --profile all up -d --build
```

Espera a que SonarQube esté *UP* (varios minutos la primera vez). InfluxDB y Grafana deben quedar *healthy* antes de confiar en k6 → Grafana.

### 3) Ejecutar Newman, Playwright, Sonar y k6 (una pasada)

Con los servicios anteriores en marcha, lanza el runner con los flags que necesites (ajusta el `-f` y `--env-file` al stack que uses):

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml run --rm \
  -e RUN_NEWMAN=true -e RUN_PLAYWRIGHT=true -e RUN_SONAR=true -e RUN_K6=true \
  qa-runner
```

Para **FUC**, cambia a `docker-compose.qa_fuc.yml` y `--env-file .env.qa_fuc`.

### 4) URLs habituales (puertos por defecto)

| Servicio | URL |
|----------|-----|
| Grafana (k6) | http://localhost:3001 |
| InfluxDB | http://localhost:8086 |
| SonarQube | http://localhost:9000 |
| Allure (UI vía nginx) | http://localhost:5252/allure-docker-service-ui |
| Allure API | http://localhost:5050 |
| Newman report | http://localhost:8181 |
| Playwright report | http://localhost:8182 |
| Jenkins | http://localhost:8085 |

Backend y frontend usan `BACKEND_PORT` / `FRONTEND_PORT` de tu `.env` (RAV suele ser 8082 y 3000; FUC 8080 y 3000).

### Solo Allure (sin el resto del perfil `all`)

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml --profile viewers up -d
```

---

## Errores frecuentes (RAV)

### `go.sum` not found / `victims_backend` vacío

El build RAV copia **toda** la carpeta `BACKEND_DIR` y ejecuta `go mod tidy`; no depende de que exista `go.sum` en disco. Si falla antes, suele ser:

- La carpeta **`victims_backend`** (o la que pongas en `BACKEND_DIR`) **no existe** o está vacía.
- **Solución:** copia el repo **victimas** (`victims_backend` + `go.mod` como mínimo) dentro del proyecto QA.

### `MONGO_URI is required` (contenedor backend en bucle)

Eso es el **backend FUC** (Mongo), no RAV (Postgres). Suele pasar si en `victims_backend` o `BACKEND_DIR` pusiste el código de la plantilla FUC por error.

- **Solución RAV:** código fuente del **victimas** (módulo `victims_backend`, Postgres / `pgx`).
- **Solución FUC:** usa solo `docker-compose.qa_fuc.yml` + `.env.qa_fuc` (no mezcles con `docker-compose.qa.yml`).

El `Dockerfile.rav-backend` intenta **detectar** dependencias Mongo / `MONGO_URI` en el código y **falla el build** con mensaje claro en lugar de arrancar un binario equivocado.

### Reconstruir imagen limpia

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml build --no-cache backend
docker compose --env-file .env.qa -f docker-compose.qa.yml up -d
```
