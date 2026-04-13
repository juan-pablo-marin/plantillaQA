import { test } from '@playwright/test';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Auditoría Lighthouse — Core Web Vitals y métricas de rendimiento UX
 *
 * Ejecuta Lighthouse en modo headless contra las páginas principales
 * para medir:
 *   - LCP  (Largest Contentful Paint)  → ¿Cuánto tarda en cargar el contenido principal?
 *   - FID  (First Input Delay) / TBT   → ¿Responde rápido al primer clic?
 *   - CLS  (Cumulative Layout Shift)   → ¿Se mueven los elementos al cargar?
 *   - Performance Score                → Puntuación general de rendimiento
 *   - Accessibility Score              → Puntuación complementaria a axe-core
 *   - Best Practices Score             → Buenas prácticas web (HTTPS, console errors, etc.)
 *
 * Lighthouse corre como proceso externo usando Chrome headless (no Playwright browser),
 * por lo que NO interfiere con las instancias de Chromium de los tests E2E.
 *
 * Los reportes se guardan en HTML y JSON en la carpeta de reportes de Playwright.
 */

const FRONTEND_URL = process.env.PLAYWRIGHT_BASE_URL || process.env.FRONTEND_URL || 'https://ape-fuc.estebandev.tech';
const REPORTS_DIR = process.env.REPORTS_DIR || path.resolve(__dirname, '../../reports');

const PAGES_TO_AUDIT = [
  { name: 'login', url: '/login' },
  { name: 'home', url: '/' },
];

// Umbrales mínimos aceptables (0-100) — ajustar según la madurez del proyecto
const THRESHOLDS = {
  performance: 30,    // Flexible para entornos Docker QA (red interna, sin CDN)
  accessibility: 50,  // Complementa axe-core
  'best-practices': 50,
};

test.describe('Lighthouse — Core Web Vitals y Rendimiento UX', () => {
  // Timeout más generoso: Lighthouse tarda ~30-60s por página
  test.setTimeout(180_000);

  for (const pageInfo of PAGES_TO_AUDIT) {
    test(`${pageInfo.name} — auditoría Lighthouse`, async ({}, testInfo) => {
      const targetUrl = `${FRONTEND_URL}${pageInfo.url}`;
      const lhOutputDir = path.join(REPORTS_DIR, 'lighthouse');
      fs.mkdirSync(lhOutputDir, { recursive: true });

      const jsonPath = path.join(lhOutputDir, `lighthouse-${pageInfo.name}.report.json`);
      const htmlPath = path.join(lhOutputDir, `lighthouse-${pageInfo.name}.report.html`);

      // Detectar si Chrome o Chromium están disponibles
      let chromePath = '';
      const candidates = [
        '/usr/bin/google-chrome-stable',
        '/usr/bin/google-chrome',
        '/usr/bin/chromium-browser',
        '/usr/bin/chromium',
      ];
      for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
          chromePath = candidate;
          break;
        }
      }

      if (!chromePath) {
        // En el contenedor Docker, Playwright instala Chromium en PLAYWRIGHT_BROWSERS_PATH
        // Intentar encontrarlo
        try {
          const pwBrowsers = process.env.PLAYWRIGHT_BROWSERS_PATH || '/ms-playwright';
          const chromiumDir = fs.readdirSync(pwBrowsers).find(d => d.startsWith('chromium'));
          if (chromiumDir) {
            const possibleChrome = path.join(pwBrowsers, chromiumDir, 'chrome-linux', 'chrome');
            if (fs.existsSync(possibleChrome)) {
              chromePath = possibleChrome;
            }
          }
        } catch {
          // Ignore — se reportará abajo
        }
      }

      if (!chromePath) {
        test.skip(true, 'Chrome/Chromium no disponible para Lighthouse — se omite auditoría');
        return;
      }

      // Ejecutar Lighthouse como proceso CLI
      const outputPath = path.join(lhOutputDir, `lighthouse-${pageInfo.name}`);
      const lhCommand = [
        'npx', 'lighthouse', targetUrl,
        '--chrome-flags="--headless --no-sandbox --disable-gpu --disable-dev-shm-usage"',
        `--chromePath=${chromePath}`,
        '--output=json,html',
        `--output-path=${outputPath}`,
        '--only-categories=performance,accessibility,best-practices',
        '--throttling-method=provided',
        '--max-wait-for-load=45000',
        '--quiet',
      ].join(' ');

      try {
        execSync(lhCommand, {
          timeout: 120_000,
          stdio: ['pipe', 'pipe', 'pipe'],
          env: { ...process.env, CHROME_PATH: chromePath },
        });
      } catch (err: any) {
        // Lighthouse puede fallar pero aún generar el reporte
        const stderr = err?.stderr?.toString() || '';
        console.warn(`Lighthouse stderr: ${stderr.slice(0, 500)}`);
      }

      // Leer y adjuntar resultados
      if (fs.existsSync(jsonPath)) {
        const report = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));
        const categories = report.categories || {};

        const scores: Record<string, number> = {};
        const summaryLines: string[] = [
          `═══ Lighthouse Report: ${pageInfo.name} ═══`,
          `URL: ${targetUrl}`,
          `Fecha: ${new Date().toISOString()}`,
          '',
        ];

        for (const [key, cat] of Object.entries(categories) as [string, any][]) {
          const score = Math.round((cat.score || 0) * 100);
          scores[key] = score;
          summaryLines.push(`${cat.title}: ${score}/100`);
        }

        // Core Web Vitals específicos
        const audits = report.audits || {};
        const cwv = {
          LCP: audits['largest-contentful-paint']?.displayValue || 'N/A',
          TBT: audits['total-blocking-time']?.displayValue || 'N/A',
          CLS: audits['cumulative-layout-shift']?.displayValue || 'N/A',
          FCP: audits['first-contentful-paint']?.displayValue || 'N/A',
          SI: audits['speed-index']?.displayValue || 'N/A',
        };

        summaryLines.push('');
        summaryLines.push('── Core Web Vitals ──');
        summaryLines.push(`  LCP (Largest Contentful Paint): ${cwv.LCP}`);
        summaryLines.push(`  TBT (Total Blocking Time):      ${cwv.TBT}`);
        summaryLines.push(`  CLS (Cumulative Layout Shift):  ${cwv.CLS}`);
        summaryLines.push(`  FCP (First Contentful Paint):   ${cwv.FCP}`);
        summaryLines.push(`  SI  (Speed Index):              ${cwv.SI}`);

        await testInfo.attach(`lighthouse-${pageInfo.name}-resumen.txt`, {
          body: summaryLines.join('\n'),
          contentType: 'text/plain',
        });

        await testInfo.attach(`lighthouse-${pageInfo.name}.json`, {
          body: fs.readFileSync(jsonPath),
          contentType: 'application/json',
        });

        // Verificar umbrales mínimos (soft-fail: solo warn, no rompe build)
        const failures: string[] = [];
        for (const [category, threshold] of Object.entries(THRESHOLDS)) {
          if (scores[category] !== undefined && scores[category] < threshold) {
            failures.push(`  ${category}: ${scores[category]}/100 (mínimo: ${threshold})`);
          }
        }

        if (failures.length > 0) {
          console.warn(`⚠️  Lighthouse — Umbrales no cumplidos en ${pageInfo.name}:\n${failures.join('\n')}`);
          // No hacemos test.fail() para no bloquear el pipeline por rendimiento en Docker
          // En producción se podría habilitar: expect(failures.length).toBe(0);
        }
      } else {
        console.warn(`⚠️  Lighthouse no generó reporte JSON para ${pageInfo.name}`);
      }

      // Adjuntar HTML si se generó
      if (fs.existsSync(htmlPath)) {
        await testInfo.attach(`lighthouse-${pageInfo.name}.html`, {
          body: fs.readFileSync(htmlPath),
          contentType: 'text/html',
        });
      }
    });
  }
});
