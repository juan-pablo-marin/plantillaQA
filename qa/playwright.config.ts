import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './ui/tests',
  fullyParallel: false,
  forbidOnly: true,
  retries: 1,
  workers: 1,
  timeout: 60_000,
  // Guardar artefactos (screenshots, videos, traces) en una ruta montada por Docker
  // para que el reporte HTML pueda referenciarlos y queden como evidencia en el host.
  outputDir: process.env.REPORTS_DIR ? `${process.env.REPORTS_DIR}/playwright-results` : './reports/playwright-results',

  reporter: [
    ['list'],
    ['html', { outputFolder: process.env.REPORTS_DIR ? `${process.env.REPORTS_DIR}/playwright-html` : './reports/playwright-html', open: 'never' }],
  ],

  use: {
    baseURL: process.env.FRONTEND_URL || 'http://frontend:3000',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
