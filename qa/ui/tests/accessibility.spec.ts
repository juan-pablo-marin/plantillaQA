import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

/**
 * Pruebas de Accesibilidad (Usabilidad) con axe-core
 *
 * Escanea las pantallas principales de la aplicación buscando violaciones
 * del estándar WCAG 2.1 AA, incluyendo:
 *   - Contraste de colores insuficiente
 *   - Elementos interactivos sin etiquetas
 *   - Estructura de encabezados incorrecta
 *   - Imágenes sin texto alternativo
 *   - Formularios sin labels asociados
 *
 * Este test NO modifica ni interfiere con los flujos E2E existentes
 * (login.spec.ts, fuc-happy-path.spec.ts). Opera como una auditoría
 * independiente que navega las pantallas y genera un reporte JSON.
 */

const FRONTEND_URL = process.env.PLAYWRIGHT_BASE_URL || process.env.FRONTEND_URL || 'https://ape-fuc.estebandev.tech';

// Páginas públicas que se pueden auditar sin autenticación
const PUBLIC_PAGES = [
  { name: 'Login', path: '/login' },
  { name: 'Página Principal', path: '/' },
];

test.describe('Auditoría de Accesibilidad (WCAG 2.1 AA)', () => {

  for (const pageInfo of PUBLIC_PAGES) {
    test(`${pageInfo.name} — debe cumplir criterios WCAG 2.1 AA`, async ({ page }, testInfo) => {
      await page.goto(`${FRONTEND_URL}${pageInfo.path}`, { waitUntil: 'networkidle' });

      const results = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
        .analyze();

      // Adjuntar reporte completo como evidencia en el HTML report de Playwright
      await testInfo.attach(`axe-${pageInfo.name.toLowerCase().replace(/\s+/g, '-')}.json`, {
        body: JSON.stringify(results, null, 2),
        contentType: 'application/json',
      });

      // Adjuntar resumen legible
      const summary = [
        `Página: ${pageInfo.name} (${pageInfo.path})`,
        `Violaciones: ${results.violations.length}`,
        `Aprobados: ${results.passes.length}`,
        `Incompletos: ${results.incomplete.length}`,
        `Inaplicables: ${results.inapplicable.length}`,
        '',
        ...results.violations.map(v =>
          `[${v.impact?.toUpperCase()}] ${v.id}: ${v.description} (${v.nodes.length} elemento(s))`
        ),
      ].join('\n');

      await testInfo.attach(`axe-resumen-${pageInfo.name.toLowerCase().replace(/\s+/g, '-')}.txt`, {
        body: summary,
        contentType: 'text/plain',
      });

      // Solo hacemos fallar el test si hay violaciones CRITICAL o SERIOUS
      const critical = results.violations.filter(
        v => v.impact === 'critical' || v.impact === 'serious'
      );

      if (critical.length > 0) {
        const details = critical.map(v =>
          `  → [${v.impact?.toUpperCase()}] ${v.id}: ${v.description}`
        ).join('\n');
        expect(critical.length, `Violaciones críticas/serias de accesibilidad:\n${details}`).toBe(0);
      }
    });
  }

  test('Home autenticado — debe cumplir criterios WCAG 2.1 AA', async ({ page }, testInfo) => {
    // Login para acceder a pantallas protegidas
    await page.goto(`${FRONTEND_URL}/login`, { waitUntil: 'networkidle' });

    // Manejar posibles diálogos
    page.on('dialog', async (dialog) => {
      await dialog.dismiss();
    });

    // Intentar autenticación
    try {
      await page.getByLabel(/Número de documento/i).fill('1088236798');
      await page.locator('input[name="password"]').fill('Masterkey123.');
      await page.locator('input[name="password"]').press('Enter');
      await page.waitForURL('**/home**', { timeout: 30_000 });
    } catch {
      // Si no se puede autenticar, omitir esta prueba sin fallar
      test.skip(true, 'No se pudo autenticar — se omite auditoría de pantalla protegida');
      return;
    }

    // Esperar carga completa
    await page.waitForLoadState('networkidle');

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
      .analyze();

    await testInfo.attach('axe-home-autenticado.json', {
      body: JSON.stringify(results, null, 2),
      contentType: 'application/json',
    });

    const summary = [
      `Página: Home Autenticado`,
      `Violaciones: ${results.violations.length}`,
      `Aprobados: ${results.passes.length}`,
      '',
      ...results.violations.map(v =>
        `[${v.impact?.toUpperCase()}] ${v.id}: ${v.description} (${v.nodes.length} elemento(s))`
      ),
    ].join('\n');

    await testInfo.attach('axe-resumen-home-autenticado.txt', {
      body: summary,
      contentType: 'text/plain',
    });

    const critical = results.violations.filter(
      v => v.impact === 'critical' || v.impact === 'serious'
    );

    if (critical.length > 0) {
      const details = critical.map(v =>
        `  → [${v.impact?.toUpperCase()}] ${v.id}: ${v.description}`
      ).join('\n');
      expect(critical.length, `Violaciones críticas/serias de accesibilidad:\n${details}`).toBe(0);
    }
  });
});
