import { defineConfig, devices } from '@playwright/test';
import type { VideoMode } from '@playwright/test';

// PLAYWRIGHT_VIDEO controla cuándo se graba video:
//   'off'               → nunca (ahorra disco, builds rápidos)
//   'retain-on-failure' → solo guarda el video si el test falla (valor por defecto)
//   'on'                → graba y guarda video de TODOS los tests (incluidos los que pasan)
// Se activa desde Jenkins con el parámetro PLAYWRIGHT_VIDEO_ALL=true → pasa 'on',
// o manualmente exportando PLAYWRIGHT_VIDEO=on antes de correr los tests.
const videoMode = (process.env.PLAYWRIGHT_VIDEO as VideoMode) || 'retain-on-failure';

export default defineConfig({
  testDir: './ui/tests',
  fullyParallel: false,
  forbidOnly: true,
  retries: 1,
  workers: 1,
  timeout: 120_000,
  // Guardar artefactos (screenshots, videos, traces) en una ruta montada por Docker
  // para que el reporte HTML pueda referenciarlos y queden como evidencia en el host.
  outputDir: process.env.PLAYWRIGHT_RESULTS_DIR || (process.env.REPORTS_DIR ? `${process.env.REPORTS_DIR}/playwright-results` : './reports/playwright-results'),

  reporter: [
    ['list'],
    ['html', { outputFolder: process.env.PLAYWRIGHT_HTML_DIR || (process.env.REPORTS_DIR ? `${process.env.REPORTS_DIR}/playwright-html` : './reports/playwright-html'), open: 'never' }],
  ],

  use: {
    baseURL: process.env.FRONTEND_URL || 'https://ape-fuc.estebandev.tech',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: videoMode,
    navigationTimeout: 45_000,
    actionTimeout: 15_000,
  },

  projects: [
    // ── Proyecto principal: Tests E2E funcionales ──
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      testIgnore: ['**/accessibility.spec.ts', '**/lighthouse.spec.ts', '**/security.spec.ts'],
    },

    // ── Proyecto de Accesibilidad: axe-core WCAG 2.1 AA ──
    {
      name: 'accessibility',
      use: { ...devices['Desktop Chrome'] },
      testMatch: '**/accessibility.spec.ts',
      retries: 0,  // Accesibilidad no necesita reintentos — el resultado es determinístico
    },

    // ── Proyecto Lighthouse: Core Web Vitals y rendimiento UX ──
    {
      name: 'lighthouse',
      use: { ...devices['Desktop Chrome'] },
      testMatch: '**/lighthouse.spec.ts',
      retries: 0,
      timeout: 180_000,  // Lighthouse necesita más tiempo por auditoría
    },

    // ── Proyecto Security: Pruebas de seguridad (CSRF, XSS, Headers, etc.) ──
    {
      name: 'security',
      use: { ...devices['Desktop Chrome'] },
      testMatch: '**/security.spec.ts',
      retries: 0,
      timeout: 120_000,
    },
  ],
});
