import { test, expect } from '@playwright/test';

const FRONTEND_URL = process.env.PLAYWRIGHT_BASE_URL || 'https://ape-fuc.estebandev.tech';

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
    await page.locator('input[name="password"]').press('Enter');

    // El frontend actual usa window.alert(); capturamos el diálogo como evidencia en el HTML report.
    const dialog = await page.waitForEvent('dialog', { timeout: 10_000 });
    await testInfo.attach('login-invalid-dialog.txt', {
      body: `${dialog.type()}: ${dialog.message()}`,
      contentType: 'text/plain',
    });
    await dialog.dismiss();
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
