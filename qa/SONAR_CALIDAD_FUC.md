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

### Tokens `squ_` vs `sqp_` (causa típica de «Insufficient privileges»)

| Prefijo | Uso habitual |
|---------|----------------|
| **`squ_…`** | Token de **usuario** (My Account → Security). Sirve para APIs administrativas si el usuario tiene permisos. **Úsalo para este script.** |
| **`sqp_…`** | Token de **análisis de proyecto** (solo escaneos `sonar-scanner`). **No** puede crear ni editar Quality Gates → API devuelve `Insufficient privileges`. |

Si el script falla con privilegios insuficientes: inicie sesión como **administrador** (o usuario con **Administer Quality Gates** en *Administration → Security → Global Permissions*) y genere un token nuevo **`squ_…`**.
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

## Opción C — Solo Docker (repo en el servidor o en tu PC; Sonar en otro host o en el mismo)

Necesitas: **URL del API de Sonar alcanzable** (no basta con `localhost` del contenedor si ejecutas el script en tu PC) y un **token** (Usuario → **My Account** → **Security** → *Generate token*; el usuario debe poder **Administer Quality Gates**).

### C.1. Desde la misma máquina donde corre `docker compose` (Sonar publica `9000` en el host)

En el host (no dentro del contenedor de Sonar), con el repo clonado en `/ruta/fihacaracterizacion`:

```bash
cd /ruta/fihacaracterizacion
export SONAR_URL="http://127.0.0.1:9000"
export SONAR_TOKEN="squ_xxxxxxxx"
chmod +x qa/scripts/sonar-fuc-quality-gate.sh
./qa/scripts/sonar-fuc-quality-gate.sh
```

### C.2. Desde tu PC hacia el Sonar remoto (Jenkins / VPS en `82.x.x.x:9000` o túnel)

Sustituye `SONAR_URL` por la IP o DNS **y puerto** que uses en el navegador:

```bash
cd /ruta/al/repo-clonado
export SONAR_URL="http://82.197.66.184:9000"
export SONAR_TOKEN="squ_xxxxxxxx"
chmod +x qa/scripts/sonar-fuc-quality-gate.sh
./qa/scripts/sonar-fuc-quality-gate.sh
```

Comprueba antes que desde ese equipo abre `curl -s -o /dev/null -w "%{http_code}" "$SONAR_URL/api/system/status"` → **200**. Si no, abre el puerto **9000** en el firewall o usa VPN/túnel SSH:

```bash
ssh -L 9000:127.0.0.1:9000 usuario@servidor-jenkins
# En otra terminal en tu PC:
export SONAR_URL="http://127.0.0.1:9000"
```

### C.3. Sin Bash nativo: contenedor **solo con bash + curl**

Desde la carpeta raíz del repo (donde existe `qa/scripts/`):

```bash
docker run --rm \
  -e SONAR_TOKEN \
  -e SONAR_URL="http://TU_IP_O_DNS:9000" \
  -e PROJECT_KEY=fuc-sena \
  -v "$(pwd)/qa/scripts:/scripts:ro" \
  bash:5.2 bash /scripts/sonar-fuc-quality-gate.sh
```

Genera el token antes y pásalo:

```bash
export SONAR_TOKEN="squ_xxxxxxxx"
docker run --rm \
  -e SONAR_TOKEN \
  -e SONAR_URL="http://82.197.66.184:9000" \
  -v "$(pwd)/qa/scripts:/scripts:ro" \
  bash:5.2 bash /scripts/sonar-fuc-quality-gate.sh
```

*(En PowerShell Windows usa rutas absolutas en `-v`, por ejemplo `-v C:/Users/.../fihacaracterizacion/qa/scripts:/scripts:ro`.)*

### C.4. Red Docker interna (solo si ejecutas el `docker run` **en el mismo host** que el stack y publicáis Sonar en `9000`)

Desde un contenedor en la misma red que `sonarqube` podrías usar `http://NOMBRE_CONTENEDOR_SONAR:9000` (p. ej. `http://fuc-qa-stack-sonarqube:9000` según tu `PROJECT_NAME`). Para eso hay que unir el contenedor temporal a la red:

```bash
docker network ls   # localizar la red del stack, p. ej. fuc-qa-stack-qa-network
docker run --rm --network NOMBRE_RED_QA \
  -e SONAR_TOKEN \
  -e SONAR_URL="http://fuc-qa-stack-sonarqube:9000" \
  -v "$(pwd)/qa/scripts:/scripts:ro" \
  bash:5.2 bash /scripts/sonar-fuc-quality-gate.sh
```

Confirma el nombre real con `docker ps | grep -i sonar`.
