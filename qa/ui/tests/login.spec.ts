import { test, expect } from '@playwright/test';

const FRONTEND_URL = process.env.PLAYWRIGHT_BASE_URL || process.env.FRONTEND_URL || 'https://apen-fuc.estebandev.tech';

test.describe('Login — Ficha Única de Caracterización', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(`${FRONTEND_URL}/login`);
  });

  test('debe mostrar el formulario de login', async ({ page }) => {
    await expect(page).toHaveTitle(/FUC|Ficha|Caracterización/i);
    await expect(page.locator('form')).toBeVisible();
  });

  test('debe mostrar error con credenciales inválidas', async ({ page }, testInfo) => {
    const tipoDocContainer = page.locator('label').filter({ hasText: /Tipo de documento/i }).locator('..');
    
    try {
      const combobox = tipoDocContainer.locator('[role="combobox"], select').first();
      const tagName = await combobox.evaluate(el => el.tagName.toLowerCase());
      
      if (tagName === 'select') {
         await combobox.selectOption({ label: 'Cédula de Ciudadanía' });
      } else {
         await combobox.click({ force: true, timeout: 5000 });
         await page.waitForTimeout(500); 
         await page.getByRole('option', { name: /Cédula de Ciudadanía/i }).click({ force: true });
      }
    } catch {
      await tipoDocContainer.click();
      await page.waitForTimeout(500);
      await page.getByText(/Cédula de Ciudadanía/i).click();
    }

    await page.getByLabel(/Número de documento/i).fill('1234567890');
    await page.locator('input[name="password"]').fill('wrongpass');

    // Preparar captura de diálogo nativo (si el frontend usa window.alert)
    let dialogCaptured = false;
    page.once('dialog', async (dialog) => {
      dialogCaptured = true;
      await testInfo.attach('login-invalid-dialog.txt', {
        body: `${dialog.type()}: ${dialog.message()}`,
        contentType: 'text/plain',
      });
      await dialog.dismiss();
    });

    await page.locator('input[name="password"]').press('Enter');

    // Esperar a que aparezca CUALQUIERA de estos indicadores de error:
    // 1. Un diálogo nativo (window.alert)
    // 2. Un mensaje de error inline en la UI
    // 3. Que la URL no cambie (seguimos en /login)
    const errorIndicators = page.locator(
      '.text-destructive, [role="alert"], .alert, .error-message, .invalid-feedback, .toast, [class*="error"], [class*="toast"]'
    );

    try {
      // Dar tiempo al frontend para responder (dialog o UI)
      await Promise.race([
        page.waitForEvent('dialog', { timeout: 15_000 }).catch(() => null),
        errorIndicators.first().waitFor({ state: 'visible', timeout: 15_000 }).catch(() => null),
        page.waitForTimeout(15_000),
      ]);
    } catch {
      // Timeout silencioso — verificaremos abajo
    }

    // Verificar que se mostró algún tipo de error
    if (dialogCaptured) {
      console.log('✓ Error de credenciales inválidas mostrado como diálogo nativo');
    } else if (await errorIndicators.first().isVisible({ timeout: 1000 }).catch(() => false)) {
      const errorText = await errorIndicators.first().textContent();
      await testInfo.attach('login-invalid-error-ui.txt', {
        body: `Error UI: ${errorText?.trim()}`,
        contentType: 'text/plain',
      });
      console.log(`✓ Error de credenciales inválidas mostrado en UI: "${errorText?.trim()}"`);
    } else {
      // Verificar que seguimos en /login (no se redirigió a /home)
      const currentUrl = page.url();
      expect(currentUrl).toContain('login');
      console.log(`✓ Verificado: seguimos en /login tras credenciales inválidas (URL: ${currentUrl})`);
    }
  });

  test('debe redirigir al home tras login exitoso', async ({ page }, testInfo) => {
    // Credenciales válidas para el entorno QA / Dev
    const tipoDocContainer = page.locator('label').filter({ hasText: /Tipo de documento/i }).locator('..');
    
    try {
      const combobox = tipoDocContainer.locator('[role="combobox"], select').first();
      const tagName = await combobox.evaluate(el => el.tagName.toLowerCase());
      
      if (tagName === 'select') {
         await combobox.selectOption({ label: 'Cédula de Ciudadanía' });
      } else {
         await combobox.click({ force: true, timeout: 5000 });
         await page.waitForTimeout(500); 
         await page.getByRole('option', { name: /Cédula de Ciudadanía/i }).click({ force: true });
      }
    } catch {
      await tipoDocContainer.click();
      await page.waitForTimeout(500);
      await page.getByText(/Cédula de Ciudadanía/i).click();
    }

    await page.getByLabel(/Número de documento/i).fill('1088236798');
    await page.locator('input[name="password"]').fill('Masterkey123.');

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

    await page.locator('input[name="password"]').press('Enter');

    try {
      await page.waitForURL('**/home**', { timeout: 30_000 });
    } catch (err) {
      await testInfo.attach('login-failed-url.txt', { body: page.url(), contentType: 'text/plain' });
      await testInfo.attach('login-failed-content.html', { body: await page.content(), contentType: 'text/html' });
      if (dialogMessage) {
        throw new Error(`No redirigió a /home. Se mostró un diálogo: "${dialogMessage}". URL: ${page.url()}`);
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
