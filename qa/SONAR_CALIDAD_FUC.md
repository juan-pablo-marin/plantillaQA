# SonarQube FUC — siguiente paso: Quality Gate 85 %

Ya están aplicadas en CI las **exclusiones de cobertura** (`qa/sonar-fuc-coverage-exclusions.properties`) y el análisis espera al Quality Gate (`sonar.qualitygate.wait=true` en `sonar-project.properties_fuc`). Falta definir en el **servidor Sonar** una puerta de calidad que exija **cobertura global ≥ 85 %** para el proyecto `fuc-sena`.

## Opción A — Automática (recomendada)

Desde la máquina que llegue al API de Sonar (mismo host que usa Jenkins o `docker compose`):

```bash
cd /ruta/al/repo
export SONAR_URL="http://localhost:9000"
export SONAR_TOKEN="squ_xxxxxxxx"
chmod +x qa/scripts/sonar-fuc-quality-gate.sh
./qa/scripts/sonar-fuc-quality-gate.sh
```

El token debe tener permiso **Administer Quality Gates** (y proyecto visible).

Personalización:

| Variable       | Default                  |
|----------------|--------------------------|
| `PROJECT_KEY`  | `fuc-sena`               |
| `GATE_NAME`    | `FUC-SENA-Cobertura-85`  |
| `MIN_COVERAGE` | `85`                     |

## Opción B — Manual en la UI

1. Iniciar sesión en SonarQube como administrador.
2. **Administration** → **Quality Gates** → **Copy** sobre **Sonar way** (o **Create**) → nombre p. ej. `FUC-SENA-Cobertura-85`.
3. **Unlock editing** → **Add Condition**:
   - **Where?** Overall Code (código total).
   - **Quality Gate fails when**: Coverage — **is less than** — **85 %**.
4. Guardar.
5. Abrir el proyecto **fuc-sena** → **Project Settings** → **Quality Gate** → asignar `FUC-SENA-Cobertura-85`.

## Pipeline Jenkins / Docker

1. Reconstruir la imagen del runner tras cambios en `qa/`:  
   `docker compose ... build qa-runner`
2. Opcional: parámetro **`COV_THRESHOLD`** en Jenkins (validación del perfil **Go** en `coverage_checker`; por defecto **70**). No sustituye la métrica de Sonar; sirve para alinear avisos cuando subáis cobertura backend pura.

Tras asignar el gate, el siguiente build de análisis debe mostrar en Sonar **Passed/Failed** según cobertura tras exclusiones.
