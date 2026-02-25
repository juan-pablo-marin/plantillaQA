# 🏗️ QA & DevOps Infrastructure Template

Esta es una plantilla de infraestructura estandarizada para proyectos de desarrollo. Está diseñada para proporcionar un entorno profesional de **QA, Análisis de Calidad (SonarQube) y Despliegue con Docker** desde el primer día.

## 📂 Contenido de la Plantilla

- **`.github/`**: Workflows de GitHub Actions para CI/CD.
- **`qa/`**: Estructura para planes de prueba, reportes e infraestructura de testing.
- **`docker-compose.yml`**: Orquestación de servicios base (Databases, Redis, etc.).
- **`docker-compose.qa.yml`**: Entorno específico para ejecución de pruebas y SonarQube.
- **Archivos `.env.*`**: Plantillas de configuración para ambientes `dev`, `qa`, `staging` y `prod`.
- **`sonar-project.properties`**: Configuración predefinida para análisis estático de código.

---

## 🚀 Cómo usar esta plantilla en un proyecto nuevo

### 1. Clonar la plantilla
Clona este repositorio como base para tu nueva carpeta de proyecto:
```powershell
git clone <url-de-este-repo> mi-nuevo-proyecto
cd mi-nuevo-proyecto
```

### 2. Inicializar tus subproyectos
Coloca tus carpetas de aplicación (frontend, backend, etc.) dentro de la raíz. 
*Nota: Si usas esta plantilla como un "Orquestador", agrega tus subproyectos como sub-módulos o simplemente carpetas independientes.*

### 3. Configurar el archivo `.gitignore` local
Si decides que tus aplicaciones vivan dentro de esta estructura, recuerda quitar las carpetas del `.gitignore` de la raíz o manejar sus propios repositorios de forma independiente.

### 4. Levantar el entorno de desarrollo
Configura tus variables en los archivos `.env` y levanta los servicios:
```powershell
docker-compose up -d
```

### 5. Análisis de Calidad (SonarQube)
Para ejecutar un análisis local:
```powershell
docker-compose -f docker-compose.qa.yml up -d
# Ejecutar el scanner después de que SonarQube esté arriba
```

---

## 🛠️ Estándares de QA
- **Pruebas E2E**: Se recomienda usar Playwright dentro de la carpeta `qa/`.
- **Reportes**: Los reportes se generan en `qa/reports/` y están ignorados por defecto para no ensuciar el repo.
- **Manual**: Los casos de prueba manuales deben documentarse en `qa/test-cases/`.

---
**Mantenido por:** [Tu Nombre/Equipo]
**Versión:** 1.0.0
