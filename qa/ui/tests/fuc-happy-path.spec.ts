import { test, expect } from '@playwright/test';
import { FucWizardPage } from '../pages/fuc-wizard.page';

// Credenciales y base URL provistas por el usuario
const FRONTEND_URL = process.env.PLAYWRIGHT_BASE_URL || 'https://ape-fuc.estebandev.tech';

test.describe('FUC Wizard - Happy Path Completo', () => {

  // Configuramos el baseUrl para esta suite si se corre de forma aislada
  test.use({ baseURL: FRONTEND_URL });

  let wizardPage: FucWizardPage;

  test.beforeEach(async ({ page }) => {
    wizardPage = new FucWizardPage(page);

    // 1. Iniciamos sesión con manejo de accesibilidad y alertas centralizado
    await wizardPage.login('1088236798', 'Masterkey123.');

    // Mute de posibles alertas o snacks informativos en el Home post-login
    page.on('dialog', async (dialog) => {
      console.log(`Dialog detectado en Home: ${dialog.message()}`);
      await dialog.dismiss();
    });
  });

  test('Debe diligenciar el wizard del FUC completo usando el Happy Path', async ({ page }) => {
    // 2. Nos aseguramos de estar en la interfaz del Wizard (que debe cargar después del login)
    await expect(page.locator('text=Ficha única de caracterización')).toBeVisible({ timeout: 15_000 });

    // --- STEP 1: IDENTIFICACIÓN ---
    await wizardPage.fillIdentificationStep({
      nombre1: 'Sandra',
      apellido1: 'Sánchez',
      fechanacimiento: '15/05/1995',
      munnacimiento: 'Pereira, Risaralda, Colombia',
      dptoregistro: 'Pereira, Risaralda, Colombia',
      fecharegistro: '15/05/2015',
      isMobile: true,
      numerocel: '3001234567',
      generoText: 'Masculino',
      isLgbtiqPlus: false
    });

    // --- STEP 2: UBICACIÓN ---
    await wizardPage.fillLocationStep({
      location: 'Pereira, Risaralda, Colombia',
      areaResidence: 'urbana',
      mainAvenue: 'Avenida',
      mainStreetNumber: '12',
    });

    // --- STEP 3: POBLACIÓN ---
    await wizardPage.fillPopulationSpecifics({
      sisbenGroup: 'Grupo A - Pobreza extrema',
      sisbenSubgroup: 'A1',
      ethnicGroup: 'Ninguno',
      hasDisability: false,
      isVictim: false,
      isPeasant: false,
      peasantCommunity: false,
      headOfHousehold: 'Soy yo',
      maritalStatus: 'Está soltero/a'
    });

    // --- STEP 4: SALUD ---
    await wizardPage.fillHealthStep({
      hasRlcpd: 'NO',
      socialSecurity: 'Contributivo',
    });

    // --- STEP 5: EDUCACIÓN ---
    await wizardPage.fillEducationStep({
      maxEducationLevel: 'Ninguno' // Omite validación de ICFES para happy path rápido
    });

    // --- STEP 6: ÉXITO ---
    // Verificar que aparece el mensaje de éxito (detectado por subagent)
    await expect(page.locator('text=Completado exitosamente')).toBeVisible({ timeout: 15_000 });
    
    // Opcional: Clic en Finalizar si existe
    const finalBtn = page.getByRole('button', { name: 'Finalizar' });
    if (await finalBtn.isVisible()) {
      await finalBtn.click();
    }
  });

});
