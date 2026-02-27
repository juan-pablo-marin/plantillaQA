import { test, expect } from '@playwright/test';

const FRONTEND_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://frontend:3000';

test.describe('Login — Ficha Única de Caracterización', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(`${FRONTEND_URL}/login`);
  });

  test('debe mostrar el formulario de login', async ({ page }) => {
    await expect(page).toHaveTitle(/FUC|Ficha|Caracterización/i);
    await expect(page.locator('form')).toBeVisible();
  });

  test('debe mostrar error con credenciales inválidas', async ({ page }, testInfo) => {
    await page.fill('input[type="email"], input[name="email"]', 'invalid@test.com');
    await page.fill('input[type="password"], input[name="password"]', 'wrongpass');
    await page.click('button[type="submit"]');

    // El frontend actual usa window.alert(); capturamos el diálogo como evidencia en el HTML report.
    const dialog = await page.waitForEvent('dialog', { timeout: 10_000 });
    await testInfo.attach('login-invalid-dialog.txt', {
      body: `${dialog.type()}: ${dialog.message()}`,
      contentType: 'text/plain',
    });
    await dialog.dismiss();
  });

  test('debe redirigir al home tras login exitoso', async ({ page }, testInfo) => {
    // Credenciales que coinciden con el "mock" actual del frontend (ver fuc-app-web/src/app/(auth)/login/page.tsx)
    await page.fill('input[type="email"], input[name="email"]', 'test1@sena.com');
    await page.fill('input[type="password"], input[name="password"]', '123456!@#');

    // Si aparece un alert, lo adjuntamos y lo descartamos para que no bloquee el flujo.
    let dialogMessage: string | null = null;
    page.once('dialog', async (dialog) => {
      dialogMessage = dialog.message();
      await testInfo.attach('login-success-dialog.txt', {
        body: `${dialog.type()}: ${dialog.message()}`,
        contentType: 'text/plain',
      });
      await dialog.dismiss();
    });

    await page.click('button[type="submit"]');

    try {
      await page.waitForURL('**/home**', { timeout: 10_000 });
    } catch (err) {
      if (dialogMessage) {
        throw new Error(`No redirigió a /home. Se mostró un diálogo: "${dialogMessage}"`);
      }
      throw err;
    }

    await expect(page).toHaveURL(/home/);
  });

});

test.describe('Navegación general', () => {

  test('la página principal carga correctamente', async ({ page }) => {
    const response = await page.goto(FRONTEND_URL);
    expect(response?.status()).toBeLessThan(400);
  });

  test('las imágenes institucionales cargan', async ({ page }) => {
    await page.goto(FRONTEND_URL);
    const images = page.locator('img');
    const count = await images.count();
    expect(count).toBeGreaterThan(0);
  });

});
