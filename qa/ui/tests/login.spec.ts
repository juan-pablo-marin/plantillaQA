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

  test('debe mostrar error con credenciales inválidas', async ({ page }) => {
    await page.fill('input[type="email"], input[name="email"]', 'invalid@test.com');
    await page.fill('input[type="password"], input[name="password"]', 'wrongpass');
    await page.click('button[type="submit"]');

    await expect(page.locator('[role="alert"], .error, .toast')).toBeVisible({ timeout: 5000 });
  });

  test('debe redirigir al home tras login exitoso', async ({ page }) => {
    await page.fill('input[type="email"], input[name="email"]', 'admin@sena.edu.co');
    await page.fill('input[type="password"], input[name="password"]', 'admin123');
    await page.click('button[type="submit"]');

    await page.waitForURL('**/home**', { timeout: 10000 });
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
