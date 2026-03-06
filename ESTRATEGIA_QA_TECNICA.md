# ESTRATEGIA DE QA TÉCNICA (FÁBRICA DE SOFTWARE)

Como QA Profesional, el objetivo no es solo "que pase la prueba", sino garantizar la **mantenibilidad, escalabilidad y confiabilidad** del código que entregamos al cliente. En una fábrica de software, esto se traduce en métricas de SonarQube que el cliente revisa como indicadores de calidad.

## 1. Implementación de Unit Testing
He creado un ejemplo de arquitectura de pruebas en:
`fuc-app-web/src/components/ui/button/__tests__/Button.spec.tsx`

### ¿Qué archivos se testearon en el ejemplo?
1.  **Button.tsx**: Es el componente principal. Se validan estados críticos: `loading`, `disabled`, `icons` y el renderizado de `children`.
2.  **Button.cva.ts**: (Implícito) Al probar el componente, garantizamos que las variantes de estilo (CVA) se apliquen correctamente.
3.  **class.utils.ts**: (Dependencia) La lógica de concatenación de clases de Tailwind.

## 2. Cómo interpretar los resultados en SonarQube

Tras ejecutar el runner, en la sección de **Frontend** de SonarQube verás:

*   **Líneas Cubiertas (Uncovered Lines):** Si el componente `Button.tsx` muestra líneas en rojo, significa que hay lógica de renderizado (ej: el spinner de carga) que nunca se ejecutó en los tests.
*   **Complejidad Ciclomática:** Si un componente tiene muchos `if` o operadores ternarios (como los iconos o el loader), Sonar nos pedirá más tests para cubrir todas las ramas (Branch Coverage).
*   **Pruebas Unitarias Exitosas:** Verás el conteo exacto de los tests (ej: 45 tests passed). Si un test falla, Sonar marcará el proyecto en rojo (Failed), permitiéndote ver exactamente qué test falló y por qué (stacktrace).

## 3. Estándar de Fábrica de Software (Definición de Hecho)

Para que el equipo de desarrollo cumpla con el estándar QA, deben seguir la estructura que he dejado montada:
1.  **Ubicación:** Guardar los tests en carpetas `__tests__` adyacentes al componente.
2.  **Extensión:** Usar `.spec.tsx` o `.test.tsx`.
3.  **Métrica:** El **Quality Gate** está configurado para un mínimo de **80% de cobertura** en componentes de UI compartidos (`src/components/ui`).

> [!IMPORTANT]
> He configurado el `qa-runner` para que tome el reporte `fuc-app-web/coverage/lcov.info`. He dejado un archivo mock para que puedas verificar que Sonar ya lo reconoce.
## 4. Reportes de Ejecución (Passed/Failed)
He configurado el runner para que genere dos reportes técnicos que Sonar entiende:
*   **Backend:** `go-test-report.json` (formato nativo de Go).
*   **Frontend:** `js-test-report.xml` (formato JUnit).

> [!IMPORTANT]
> He dejado archivos **Mock** en `qa/reports/` para que veas el efecto inmediato. La próxima vez que corras el runner, verás por fin el bloque de "Unit Tests" con números reales en el dashboard de SonarQube.
