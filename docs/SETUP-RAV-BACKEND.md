# Cómo poner el backend RAV en esta plantilla

El error **`No hay go.mod en la carpeta indicada por BACKEND_DIR`** significa que Docker **no encuentra** `go.mod` dentro de la carpeta que defines en **`.env.qa`** (`BACKEND_DIR`, por defecto `victims_backend`).

## Qué hacer

1. Copia **toda** la carpeta **`victims_backend`** del proyecto victimas (repo RAV) dentro de la raíz de **FICHA CARACTERIZACION V1**, de modo que exista:

   `FICHA CARACTERIZACION V1\victims_backend\go.mod`

2. O usa otra carpeta (por ejemplo `BACKEND`) y en **`.env.qa`** pon:

   ```env
   BACKEND_DIR=BACKEND
   ```

   (y dentro de `BACKEND` debe estar el mismo código RAV con `go.mod` en la raíz de esa carpeta).

## PowerShell (ejemplo de ruta)

Ajusta la ruta origen a donde tengas **victimas v3**:

```powershell
$origen  = "C:\Users\Windows\Documents\PROYECTOS\victimas v3\victims_backend"
$destino = "C:\Users\Windows\Documents\PROYECTOS\FICHA CARACTERIZACION V1\victims_backend"

New-Item -ItemType Directory -Force -Path $destino | Out-Null
Copy-Item -Path "$origen\*" -Destination $destino -Recurse -Force

Test-Path "$destino\go.mod"   # debe ser True
```

Luego:

```powershell
docker compose --env-file .env.qa -f docker-compose.qa.yml build --no-cache backend
docker compose --env-file .env.qa -f docker-compose.qa.yml up -d
```

## Nota

La carpeta `victims_backend/` suele estar en **`.gitignore`** (no se sube al repo); hay que copiarla en cada máquina o clonar el repo victimas al lado y copiar.
