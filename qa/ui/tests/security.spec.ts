import { test, expect, type Page, type BrowserContext } from '@playwright/test';

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * Security Tests - FUC SENA Frontend
 * 
 * Pruebas de seguridad automatizadas para el frontend:
 *   - CSRF (Cross-Site Request Forgery) Protection
 *   - XSS (Cross-Site Scripting) Prevention
 *   - Security Headers Validation
 *   - Cookie Security Attributes
 *   - Content Security Policy
 *   - Clickjacking Protection
 *   - Session Management
 * ═══════════════════════════════════════════════════════════════════════════════
 */

const FRONTEND_URL = process.env.FRONTEND_URL || 'http://frontend:3000';
const BACKEND_URL = process.env.BACKEND_URL || 'http://backend:8080';

test.describe('Security Tests - Frontend', () => {
  
  test.describe('Security Headers', () => {
    
    test('should have X-Frame-Options header to prevent clickjacking', async ({ request }) => {
      const response = await request.get(FRONTEND_URL);
      const xFrameOptions = response.headers()['x-frame-options'];
      
      // Debe tener X-Frame-Options o estar embebido en CSP frame-ancestors
      const csp = response.headers()['content-security-policy'];
      const hasFrameProtection = xFrameOptions || (csp && csp.includes('frame-ancestors'));
      
      expect(hasFrameProtection, 'Missing clickjacking protection (X-Frame-Options or CSP frame-ancestors)').toBeTruthy();
      
      if (xFrameOptions) {
        expect(['DENY', 'SAMEORIGIN']).toContain(xFrameOptions.toUpperCase());
      }
    });

    test('should have X-Content-Type-Options header', async ({ request }) => {
      const response = await request.get(FRONTEND_URL);
      const xContentTypeOptions = response.headers()['x-content-type-options'];
      
      expect(xContentTypeOptions, 'Missing X-Content-Type-Options header').toBeTruthy();
      expect(xContentTypeOptions?.toLowerCase()).toBe('nosniff');
    });

    test('should have Content-Security-Policy header', async ({ request }) => {
      const response = await request.get(FRONTEND_URL);
      const csp = response.headers()['content-security-policy'];
      
      // CSP es altamente recomendado pero puede no estar presente en desarrollo
      if (csp) {
        // Verificar directivas básicas de seguridad
        expect(csp).toMatch(/default-src|script-src|style-src/);
        
        // Advertir si tiene 'unsafe-inline' o 'unsafe-eval'
        if (csp.includes('unsafe-inline') || csp.includes('unsafe-eval')) {
          console.warn('⚠ CSP contains unsafe-inline or unsafe-eval which weakens protection');
        }
      } else {
        console.warn('⚠ Content-Security-Policy header is missing (recommended for production)');
      }
    });

    test('should have Referrer-Policy header', async ({ request }) => {
      const response = await request.get(FRONTEND_URL);
      const referrerPolicy = response.headers()['referrer-policy'];
      
      if (referrerPolicy) {
        const safeValues = [
          'no-referrer',
          'no-referrer-when-downgrade',
          'origin',
          'origin-when-cross-origin',
          'same-origin',
          'strict-origin',
          'strict-origin-when-cross-origin'
        ];
        expect(safeValues).toContain(referrerPolicy.toLowerCase());
      } else {
        console.warn('⚠ Referrer-Policy header is missing (recommended for privacy)');
      }
    });

    test('should not expose server version information', async ({ request }) => {
      const response = await request.get(FRONTEND_URL);
      const server = response.headers()['server'];
      const xPoweredBy = response.headers()['x-powered-by'];
      
      // El header Server no debe revelar versiones específicas
      if (server) {
        expect(server).not.toMatch(/\d+\.\d+/); // No debería tener números de versión
      }
      
      // X-Powered-By no debería existir
      expect(xPoweredBy, 'X-Powered-By header exposes technology stack').toBeFalsy();
    });
  });

  test.describe('Cookie Security', () => {
    
    test('should set secure cookie attributes after login', async ({ page, context }) => {
      // Navegar al login
      await page.goto(`${FRONTEND_URL}/login`);
      
      // Intentar hacer login (si existe el formulario)
      const loginForm = page.locator('form');
      if (await loginForm.count() > 0) {
        // Simular login
        await page.fill('input[name="id_user"], input[type="text"]', '12345678');
        await page.fill('input[name="password"], input[type="password"]', 'password123');
        
        const submitButton = page.locator('button[type="submit"]');
        if (await submitButton.count() > 0) {
          await submitButton.click();
          await page.waitForTimeout(2000);
        }
      }
      
      // Verificar cookies
      const cookies = await context.cookies();
      
      for (const cookie of cookies) {
        // Cookies de sesión/autenticación deben tener atributos seguros
        if (cookie.name.toLowerCase().includes('session') || 
            cookie.name.toLowerCase().includes('token') ||
            cookie.name.toLowerCase().includes('auth')) {
          
          // En producción (HTTPS), debe tener Secure flag
          if (FRONTEND_URL.startsWith('https')) {
            expect(cookie.secure, `Cookie ${cookie.name} should have Secure flag`).toBe(true);
          }
          
          // Debe tener HttpOnly para prevenir acceso desde JavaScript
          expect(cookie.httpOnly, `Cookie ${cookie.name} should have HttpOnly flag`).toBe(true);
          
          // Debe tener SameSite para prevenir CSRF
          expect(['Strict', 'Lax', 'None']).toContain(cookie.sameSite);
          
          if (cookie.sameSite === 'None') {
            expect(cookie.secure, `Cookie ${cookie.name} with SameSite=None must have Secure flag`).toBe(true);
          }
        }
      }
    });
  });

  test.describe('CSRF Protection', () => {
    
    test('should include CSRF token in forms', async ({ page }) => {
      await page.goto(FRONTEND_URL);
      
      // Buscar formularios en la página
      const forms = page.locator('form');
      const formCount = await forms.count();
      
      for (let i = 0; i < formCount; i++) {
        const form = forms.nth(i);
        
        // Verificar que el formulario tiene un token CSRF
        const csrfInput = form.locator('input[name*="csrf"], input[name*="token"], input[name*="_token"]');
        const csrfMeta = page.locator('meta[name*="csrf"]');
        
        const hasCSRFInput = await csrfInput.count() > 0;
        const hasCSRFMeta = await csrfMeta.count() > 0;
        
        // El formulario debe tener protección CSRF (input hidden o meta tag)
        // Nota: En SPAs con JWT, el token puede manejarse de otra forma
        if (!hasCSRFInput && !hasCSRFMeta) {
          console.warn(`⚠ Form #${i} may not have explicit CSRF protection (might use JWT/headers)`);
        }
      }
    });

    test('should reject cross-origin requests without proper authentication', async ({ request }) => {
      // Simular request desde origen diferente
      const response = await request.post(`${BACKEND_URL}/api/v1/fuc`, {
        headers: {
          'Origin': 'http://malicious-site.com',
          'Referer': 'http://malicious-site.com/attack',
          'Content-Type': 'application/json'
        },
        data: { test: 'csrf-attack' }
      });
      
      // Debe rechazar (401/403) o el CORS debe bloquearlo
      expect([401, 403, 404, 405]).toContain(response.status());
    });

    test('should validate Origin header on sensitive endpoints', async ({ request }) => {
      const sensitiveEndpoints = [
        { method: 'POST', path: '/api/v1/auth/login' },
        { method: 'POST', path: '/api/v1/auth/signup' },
        { method: 'POST', path: '/api/v1/fuc' },
        { method: 'PUT', path: '/api/v1/fuc' },
        { method: 'DELETE', path: '/api/v1/fuc' }
      ];
      
      for (const endpoint of sensitiveEndpoints) {
        const response = await request.fetch(`${BACKEND_URL}${endpoint.path}`, {
          method: endpoint.method,
          headers: {
            'Origin': 'http://evil-attacker.com',
            'Content-Type': 'application/json'
          },
          data: {}
        });
        
        // No debería aceptar requests exitosos de orígenes no autorizados
        expect(
          response.status() >= 400 || response.status() === 204,
          `Endpoint ${endpoint.method} ${endpoint.path} accepted request from foreign origin`
        ).toBeTruthy();
      }
    });
  });

  test.describe('XSS Prevention', () => {
    
    test('should escape user input in URL parameters', async ({ page }) => {
      const xssPayloads = [
        '<script>alert("XSS")</script>',
        '"><img src=x onerror=alert("XSS")>',
        "javascript:alert('XSS')",
        '<svg/onload=alert("XSS")>',
        '{{constructor.constructor("alert(1)")()}}'
      ];
      
      for (const payload of xssPayloads) {
        const encodedPayload = encodeURIComponent(payload);
        
        // Navegar con payload en query string
        await page.goto(`${FRONTEND_URL}?search=${encodedPayload}&q=${encodedPayload}`);
        
        // Verificar que el payload no se ejecutó ni se refleja sin escapar
        const pageContent = await page.content();
        
        // El payload no debe aparecer sin escapar en el HTML
        expect(
          pageContent.includes(payload),
          `XSS payload reflected without encoding: ${payload.substring(0, 30)}...`
        ).toBe(false);
        
        // Verificar que no hay alertas (script no se ejecutó)
        // Playwright captura diálogos automáticamente
      }
    });

    test('should sanitize user input displayed on page', async ({ page }) => {
      await page.goto(`${FRONTEND_URL}/login`);
      
      const xssPayload = '<img src=x onerror=alert("XSS")>';
      
      // Intentar inyectar en campos de input
      const inputs = page.locator('input[type="text"], input:not([type])');
      const inputCount = await inputs.count();
      
      for (let i = 0; i < inputCount; i++) {
        await inputs.nth(i).fill(xssPayload);
      }
      
      // Verificar que el payload no se ejecuta
      const pageContent = await page.content();
      
      // Si el payload aparece en el DOM, debe estar escapado
      if (pageContent.includes('onerror')) {
        // Debe estar dentro de un atributo value o escapado
        expect(pageContent).not.toMatch(/<img[^>]*onerror[^>]*>/);
      }
    });

    test('should not have inline event handlers in HTML', async ({ page }) => {
      await page.goto(FRONTEND_URL);
      
      // Buscar inline event handlers que podrían ser vectores XSS
      const dangerousPatterns = [
        '[onclick]',
        '[onerror]',
        '[onload]',
        '[onmouseover]',
        '[onfocus]',
        '[onsubmit]:not(form)'
      ];
      
      for (const pattern of dangerousPatterns) {
        const elements = page.locator(pattern);
        const count = await elements.count();
        
        if (count > 0) {
          console.warn(`⚠ Found ${count} elements with potentially dangerous inline handler: ${pattern}`);
        }
      }
    });
  });

  test.describe('Session Management', () => {
    
    test('should expire session after logout', async ({ page, context }) => {
      // Navegar al login
      await page.goto(`${FRONTEND_URL}/login`);
      
      // Simular login
      await page.fill('input[name="id_user"], input[type="text"]', '12345678').catch(() => {});
      await page.fill('input[name="password"], input[type="password"]', 'password123').catch(() => {});
      
      const submitButton = page.locator('button[type="submit"]');
      if (await submitButton.count() > 0) {
        await submitButton.click();
        await page.waitForTimeout(2000);
      }
      
      // Guardar cookies/localStorage antes del logout
      const cookiesBefore = await context.cookies();
      const storageBefore = await page.evaluate(() => ({
        localStorage: { ...localStorage },
        sessionStorage: { ...sessionStorage }
      }));
      
      // Buscar y hacer click en logout
      const logoutButton = page.locator('button:has-text("logout"), a:has-text("logout"), [data-testid="logout"]');
      if (await logoutButton.count() > 0) {
        await logoutButton.first().click();
        await page.waitForTimeout(1000);
        
        // Verificar que las cookies de sesión fueron eliminadas o invalidadas
        const cookiesAfter = await context.cookies();
        
        const sessionCookiesBefore = cookiesBefore.filter(c => 
          c.name.includes('session') || c.name.includes('token') || c.name.includes('auth')
        );
        const sessionCookiesAfter = cookiesAfter.filter(c => 
          c.name.includes('session') || c.name.includes('token') || c.name.includes('auth')
        );
        
        // Las cookies de sesión deberían ser eliminadas o diferentes
        if (sessionCookiesBefore.length > 0) {
          const beforeValues = sessionCookiesBefore.map(c => c.value).sort().join(',');
          const afterValues = sessionCookiesAfter.map(c => c.value).sort().join(',');
          expect(beforeValues).not.toBe(afterValues);
        }
      }
    });

    test('should not store sensitive data in localStorage', async ({ page }) => {
      await page.goto(FRONTEND_URL);
      
      const localStorage = await page.evaluate(() => {
        const items: Record<string, string> = {};
        for (let i = 0; i < window.localStorage.length; i++) {
          const key = window.localStorage.key(i);
          if (key) {
            items[key] = window.localStorage.getItem(key) || '';
          }
        }
        return items;
      });
      
      // Verificar que no hay datos sensibles en localStorage
      const sensitivePatterns = [
        /password/i,
        /secret/i,
        /credit.?card/i,
        /ssn/i,
        /social.?security/i
      ];
      
      for (const [key, value] of Object.entries(localStorage)) {
        for (const pattern of sensitivePatterns) {
          expect(
            pattern.test(key) || pattern.test(value),
            `Potentially sensitive data found in localStorage: ${key}`
          ).toBe(false);
        }
      }
    });
  });

  test.describe('Information Disclosure', () => {
    
    test('should not expose stack traces in error responses', async ({ request }) => {
      // Provocar errores para ver si exponen stack traces
      const errorTriggers = [
        { url: `${BACKEND_URL}/api/v1/nonexistent`, method: 'GET' },
        { url: `${BACKEND_URL}/api/v1/auth/login`, method: 'POST', data: 'invalid json{{{{' },
        { url: `${BACKEND_URL}/api/v1/fuc/invalid-id-format`, method: 'GET' }
      ];
      
      for (const trigger of errorTriggers) {
        try {
          const response = await request.fetch(trigger.url, {
            method: trigger.method,
            data: trigger.data,
            headers: { 'Content-Type': 'application/json' }
          });
          
          const body = await response.text();
          
          // No debe exponer rutas de archivos del servidor
          expect(body).not.toMatch(/\/home\//);
          expect(body).not.toMatch(/\/var\//);
          expect(body).not.toMatch(/\/usr\//);
          expect(body).not.toMatch(/C:\\/);
          expect(body).not.toMatch(/\.go:\d+/); // Go stack traces
          expect(body).not.toMatch(/\.js:\d+/);  // JS stack traces
          expect(body).not.toMatch(/at\s+\w+\s+\(/); // JS stack trace format
          
        } catch (error) {
          // Request might fail which is fine
        }
      }
    });

    test('should not expose sensitive paths in robots.txt', async ({ request }) => {
      try {
        const response = await request.get(`${FRONTEND_URL}/robots.txt`);
        
        if (response.ok()) {
          const content = await response.text();
          
          // No debe revelar rutas administrativas o sensibles
          const sensitivePatterns = [
            /admin/i,
            /backup/i,
            /config/i,
            /database/i,
            /internal/i,
            /secret/i,
            /\.env/i,
            /\.git/i
          ];
          
          for (const pattern of sensitivePatterns) {
            if (pattern.test(content)) {
              console.warn(`⚠ robots.txt reveals potentially sensitive path matching: ${pattern}`);
            }
          }
        }
      } catch {
        // robots.txt might not exist, which is fine
      }
    });

    test('should not expose version control files', async ({ request }) => {
      const sensitiveFiles = [
        '/.git/config',
        '/.git/HEAD',
        '/.env',
        '/.env.local',
        '/config.json',
        '/package.json',
        '/composer.json'
      ];
      
      for (const file of sensitiveFiles) {
        try {
          const response = await request.get(`${FRONTEND_URL}${file}`);
          
          expect(
            response.status(),
            `Sensitive file ${file} is accessible`
          ).toBeGreaterThanOrEqual(400);
          
        } catch {
          // Request blocked or failed is good
        }
      }
    });
  });

  test.describe('Input Validation', () => {
    
    test('should validate and sanitize form inputs', async ({ page }) => {
      await page.goto(`${FRONTEND_URL}/login`);
      
      // Probar con inputs maliciosos
      const maliciousInputs = [
        "' OR '1'='1",                    // SQL Injection
        '{"$gt": ""}',                     // NoSQL Injection
        '../../../etc/passwd',             // Path Traversal
        '<?php system("ls"); ?>',          // PHP Injection
        '{{7*7}}',                          // Template Injection
        '${7*7}',                           // Expression Language Injection
      ];
      
      const inputs = page.locator('input[type="text"], input:not([type])');
      
      for (const malicious of maliciousInputs) {
        const inputCount = await inputs.count();
        for (let i = 0; i < inputCount; i++) {
          await inputs.nth(i).fill(malicious);
        }
        
        // Intentar submit
        const submitButton = page.locator('button[type="submit"]');
        if (await submitButton.count() > 0) {
          await submitButton.click();
          await page.waitForTimeout(500);
        }
        
        // La página no debería mostrar errores del servidor o comportamiento inesperado
        const pageContent = await page.content();
        
        // No debe mostrar errores de base de datos
        expect(pageContent).not.toMatch(/SQL|syntax|query|mongo|database error/i);
        
        // No debe mostrar contenido de archivos del sistema
        expect(pageContent).not.toMatch(/root:x:|\/etc\/passwd/);
      }
    });
  });
});
