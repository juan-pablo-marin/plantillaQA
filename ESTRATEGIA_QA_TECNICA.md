# 🧪 Instructivo Técnico: Implementación y Regresión de QA

Este documento detalla el estándar para el equipo de QA sobre cómo crear, organizar y ejecutar pruebas profesionales en el ecosistema de 3 repositorios.

## 🏗️ 1. Estándar de Ramas
Para no ensuciar las ramas de desarrollo (`dev`, `main`), todo el código de QA debe vivir en:
- **Frontend:** Rama `test/qa-fichasp1`
- **Backend:** Rama `test/qa-api`

## 🛠️ 2. Creación de Pruebas por Sprints

### En Frontend (Playwright)
Las pruebas deben organizarse por módulos y sprints para facilitar la regresión:
```text
tests/
├── sprint-1/
│   ├── login.spec.ts
│   └── dashboard.spec.ts
└── sprint-2/
    └── caracterizacion-v1.spec.ts
```
**Para crear una nueva prueba:**
1. Crear el archivo `.spec.ts` en la carpeta del sprint correspondiente.
2. Usar **Page Object Models (POM)** para que si el front cambia, solo actualices un archivo y no todas las pruebas.

### En Backend (API Testing)
1. Usar la infraestructura de Docker de la **Plantilla** para levantar la DB local.
2. Implementar pruebas de endpoints validando: Status Code, Estructura de JSON y Lógica de Negocio.

---

## 🔄 3. Flujo de Regresión (Nuevos Sprints)

Cuando un nuevo Sprint termina y los desarrolladores suben cambios a `dev`, el equipo de QA debe:

1. **Traer cambios nuevos:**
   ```bash
   git checkout test/qa-fichasp1
   git merge dev
   ```
2. **Ejecutar Regresión (Lo antiguo):**
   ```bash
   npx playwright test
   ```
   *Si alguna prueba del Sprint 1 falla con el código del Sprint 2, se reporta un **bug de regresión**.*

3. **Implementar lo nuevo:**
   Crear la carpeta `tests/sprint-X/` y añadir los nuevos casos.

---

## 📊 4. Análisis de Calidad (SonarQube)
Cada vez que se complete un Sprint, se debe correr el scanner:
1. Levantar SonarQube desde la **Plantilla** (`docker-compose.qa.yml`).
2. Ejecutar `sonar-scanner` en el Front y el Back usando los archivos `sonar-project.properties` ya configurados.

---
**Nota:** Este flujo garantiza que la rama `dev` nunca tenga archivos de prueba, pero que el equipo de QA siempre tenga un entorno robusto y actualizado.
