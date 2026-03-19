# QA Factory Template

Plantilla genérica con QA integrado para orquestar pruebas automatizadas de cualquier proyecto desde Docker + Jenkins.

---

## Stack Tecnológico

| Componente   | Tecnología                  |
| ------------ | --------------------------- |
| Backend      | Configurable (Go, Node, etc)|
| Frontend     | Configurable (Next.js, etc) |
| Base de datos| MongoDB 7                   |
| API Testing  | Newman (Postman)            |
| UI Testing   | Playwright                  |
| Performance  | k6 (Grafana)                |
| Seguridad    | OWASP ZAP                   |
| Análisis     | SonarQube                   |
| Reportes     | Allure                      |
| CI/CD        | Jenkins + GitHub Actions    |

---

## Estructura del Proyecto

```
plantillaQA/
├── BACKEND/                     # Código del Backend (ignorado en git)
│   ├── ...                      # Estructura propia del proyecto
│   └── Dockerfile
│
├── FRONTEND/                    # Código del Frontend (ignorado en git)
│   ├── src/                     # Código fuente
│   └── Dockerfile
│
├── qa/                          # Suite de QA completa
│   ├── api/collections/         # Colecciones Postman/Newman
│   ├── ui/tests/                # Tests de UI (Playwright)
│   ├── performance/             # Tests de rendimiento (k6)
│   ├── security/                # Config de seguridad (ZAP)
│   ├── reports/                 # Reportes generados
│   ├── Dockerfile.qa            # Imagen Docker del QA Runner
│   └── run-tests.sh             # Script orquestador
│
├── docker-compose.yml           # Desarrollo básico
├── docker-compose.qa.yml        # QA completo
├── docker-compose.jenkins.yml   # Override para Jenkins DinD
├── docker-compose.dev-override.yml # Override para hot-reload local
│
├── .env.dev                     # Variables desarrollo
├── .env.qa                      # Variables QA
├── .env.staging                 # Variables staging
├── .env.example                 # Plantilla de variables
│
├── Jenkinsfile                  # Pipeline Jenkins
├── Dockerfile.jenkins           # Imagen Jenkins personalizada
├── sonar-project.properties     # Configuración SonarQube
└── .github/workflows/
    └── qa-pipeline.yml          # Pipeline CI/CD
```

---

## Inicio Rápido

### Prerrequisitos

- Docker y Docker Compose instalados
- Git

### 1. Clonar y Configurar

```bash
git clone <url-del-repo>
cd plantillaQA

# Copiar y ajustar variables de entorno
cp .env.example .env.dev
cp .env.example .env.qa
```

Edita los archivos `.env.*` y configura:
- `PROJECT_NAME` — nombre de tu proyecto (afecta nombres de contenedores)
- `BACKEND_DIR` — carpeta del backend (default: `BACKEND`)
- `FRONTEND_DIR` — carpeta del frontend (default: `FRONTEND`)

### 2. Levantar en Desarrollo

```bash
docker compose --env-file .env.dev up -d --build
```

| Servicio  | URL                          |
| --------- | ---------------------------- |
| Backend   | http://localhost:8080         |
| Frontend  | http://localhost:3000         |
| MongoDB   | localhost:27017              |

### 3. Ejecutar Suite QA Completa

```bash
docker compose --env-file .env.qa -f docker-compose.qa.yml up --build --abort-on-container-exit
```

| Servicio  | URL                          |
| --------- | ---------------------------- |
| Backend   | http://localhost:8080         |
| Frontend  | http://localhost:3000         |
| Allure UI | http://localhost:5252/allure-docker-service-ui |
| Allure API| http://localhost:5050         |

### 4. Ver Reportes

Después de ejecutar QA, los reportes están en `qa/reports/` y en Allure UI en http://localhost:5252/allure-docker-service-ui (el API de Allure queda en http://localhost:5050).

---

## Ambientes

| Archivo        | Ambiente       | Uso                                |
| -------------- | -------------- | ---------------------------------- |
| `.env.dev`     | Desarrollo     | Local, sin security/perf tests     |
| `.env.qa`      | QA             | Tests completos excepto perf       |
| `.env.staging` | Pre-producción | Todos los tests incluido perf      |

### Cambiar de Ambiente

```bash
# Desarrollo
docker compose --env-file .env.dev up -d --build

# QA
docker compose --env-file .env.qa -f docker-compose.qa.yml up --build --abort-on-container-exit

# Staging (incluye performance)
docker compose --env-file .env.staging -f docker-compose.qa.yml up --build --abort-on-container-exit
```

---

## Tests por Tipo

### API Tests (Newman)

Las colecciones están en `qa/api/collections/`. Para ejecutar manualmente:

```bash
newman run qa/api/collections/api.postman_collection.json \
  --environment qa/api/collections/env-dev.json
```

### UI Tests (Playwright)

Los tests de UI están en `qa/ui/tests/`. Para ejecutar manualmente:

```bash
cd qa
PLAYWRIGHT_BASE_URL=http://localhost:3000 npx playwright test ui/tests/
```

### Performance Tests (k6)

Solo se ejecutan en ambientes `staging` y `prod`:

```bash
k6 run qa/performance/k6-tests.js -e BACKEND_URL=http://localhost:8080
```

### Security Scan (ZAP)

No se ejecuta en ambiente `dev`:

```bash
zap-baseline.py -t http://localhost:8080 -c qa/security/zap-config.yaml
```

---

## SonarQube

### Configuración

1. Instalar SonarQube (local o servidor):
   ```bash
   docker run -d --name sonarqube -p 9000:9000 sonarqube:community
   ```

2. Crear un proyecto en SonarQube con key que coincida con `PROJECT_KEY` del `.env`

3. Generar un token de autenticación

4. Configurar las variables en el archivo `.env` correspondiente:
   ```
   SONAR_HOST_URL=http://localhost:9000
   SONAR_TOKEN=tu-token-aqui
   PROJECT_KEY=mi-proyecto
   ```

5. Para CI/CD, configurar los secrets en GitHub:
   - `SONAR_HOST_URL`
   - `SONAR_TOKEN`

---

## Variables de Entorno Clave

| Variable          | Descripción                                    | Default      |
| ----------------- | ---------------------------------------------- | ------------ |
| `PROJECT_NAME`    | Nombre del proyecto (prefijo de contenedores)  | `qa-project` |
| `BACKEND_DIR`     | Carpeta del backend en el host                 | `BACKEND`    |
| `FRONTEND_DIR`    | Carpeta del frontend en el host                | `FRONTEND`   |
| `PROJECT_KEY`     | Key del proyecto en SonarQube                  | `qa-project` |
| `RUN_NEWMAN`      | Habilitar tests de API                         | `false`      |
| `RUN_SONAR`       | Habilitar análisis estático                    | `false`      |
| `RUN_PLAYWRIGHT`  | Habilitar tests E2E                            | `false`      |
| `RUN_K6`          | Habilitar tests de rendimiento                 | `false`      |

---

## Pipeline CI/CD

El pipeline se ejecuta automáticamente en:
- **Pull Requests** a las ramas `qa`, `staging`, `main`
- **Push** a la rama `qa`

### Jobs del Pipeline

1. **Build & Lint** — Compila backend y frontend
2. **QA Suite** — Ejecuta la suite completa de tests
3. **SonarQube** — Análisis estático de código (solo en PRs)

Los reportes se guardan como artifacts de GitHub Actions por 30 días.

---

## Adaptar a un Nuevo Proyecto

1. Clonar la plantilla
2. Colocar el código backend en `BACKEND/` y frontend en `FRONTEND/`
3. Copiar `.env.example` a `.env.dev`, `.env.qa`, `.env.staging`
4. Ajustar `PROJECT_NAME`, `BACKEND_DIR`, `FRONTEND_DIR` en los `.env`
5. Actualizar `.gitignore` si cambias los nombres de carpetas
6. Personalizar las colecciones Postman en `qa/api/collections/`
7. Ajustar los tests Playwright en `qa/ui/tests/`

---

## Política de Calidad

| Métrica                    | Umbral mínimo |
| -------------------------- | ------------- |
| Cobertura de código        | >= 80%        |
| Duplicación                | <= 3%         |
| Issues críticos (Sonar)    | 0             |
| Vulnerabilidades (Sonar)   | 0             |
| API Tests passing          | 100%          |
| UI Tests passing           | >= 95%        |
| Performance p95            | < 500ms       |
| Errores bajo carga         | < 10%         |
| Vulnerabilidades ZAP High  | 0             |

---

## Comandos Útiles

```bash
# Levantar desarrollo
docker compose --env-file .env.dev up -d --build

# Ejecutar QA completo
docker compose --env-file .env.qa -f docker-compose.qa.yml up --build --abort-on-container-exit

# Ver logs del backend
docker compose logs -f backend

# Detener todo
docker compose down -v --remove-orphans

# Rebuild solo el QA runner
docker compose -f docker-compose.qa.yml build qa-runner
```
