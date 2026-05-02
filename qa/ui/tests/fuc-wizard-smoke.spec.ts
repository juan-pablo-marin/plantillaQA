import { test, expect } from '@playwright/test';
import { FucWizardPage } from '../pages/fuc-wizard.page';

/**
 * Humo del wizard: validaciones rápidas sin recorrer los 6 pasos completos.
 * El happy path largo sigue en fuc-happy-path.spec.ts.
 */
const FRONTEND_URL =
  process.env.PLAYWRIGHT_BASE_URL || process.env.FRONTEND_URL || 'https://apen-fuc.estebandev.tech';

const QA_ID = process.env.QA_USER_ID || '1088236798';
const QA_PASS = process.env.QA_PASSWORD || 'Masterkey123.';

test.describe('FUC Wizard — humo (post-login)', () => {
  test.use({ baseURL: FRONTEND_URL });

  test('muestra el encabezado del wizard tras login', async ({ page }) => {
    test.setTimeout(120_000);
    const wizardPage = new FucWizardPage(page);
    await wizardPage.login(QA_ID, QA_PASS);
    await expect(page.locator('text=Ficha única de caracterización')).toBeVisible({
      timeout: 25_000,
    });
  });

  test('muestra botón Siguiente en el primer paso', async ({ page }) => {
    test.setTimeout(120_000);
    const wizardPage = new FucWizardPage(page);
    await wizardPage.login(QA_ID, QA_PASS);
    await expect(page.getByRole('button', { name: /Siguiente/i }).first()).toBeVisible({
      timeout: 25_000,
    });
  });
});
