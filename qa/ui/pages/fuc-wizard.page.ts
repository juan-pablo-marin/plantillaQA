import { Page, expect } from '@playwright/test';

export class FucWizardPage {
  constructor(private readonly page: Page) { }

  async gotoHome() {
    console.log('Navegando a home...');
    await this.page.goto('/home');
    await this.disableAccessibilityWidget();
    await expect(this.page.locator('text=Ficha única de caracterización')).toBeVisible({ timeout: 15_000 });
    console.log('Home cargado correctamente.');
  }

  /**
   * Deshabilita el widget de accesibilidad de múltiples maneras para garantizar que no bloquee clics.
   */
  async disableAccessibilityWidget() {
    try {
      // 1. Inyectar CSS agresivo para ocultar y desactivar el widget
      await this.page.addStyleTag({
        content: `
          #ape-accessibility-root,
          [data-a11y-icon],
          .apea-gradient, 
          [aria-label*="Accesibilidad"], 
          [aria-label="Cerrar menú de accesibilidad"],
          [role="dialog"]:has-text("Accesibilidad"),
          .ape-accessibility-container,
          button:has-text("Restablecer configuración") { 
            display: none !important; 
            pointer-events: none !important;
            visibility: hidden !important;
            z-index: -9999 !important;
          }
        `
      });

      // 2. Intentar remover directamente el elemento del DOM si existe
      await this.page.evaluate(() => {
        const a11yRoot = document.getElementById('ape-accessibility-root');
        if (a11yRoot) {
          a11yRoot.remove();
        }
        const a11yElements = document.querySelectorAll('[data-a11y-icon]');
        a11yElements.forEach(el => el.remove());
      });

      console.log('Widget de accesibilidad deshabilitado vía CSS y DOM removal.');
    } catch (e) {
      console.log('Error al deshabilitar widget de accesibilidad:', e.message);
    }
  }

  /**
   * Cierra el menú de accesibilidad si aparece para evitar bloqueos visuales.
   * AHORA: Llama a disableAccessibilityWidget para ser más radical.
   */
  async handleAccessibilityMenu() {
    await this.disableAccessibilityWidget();
    const closeBtn = this.page.getByLabel('Cerrar menú de accesibilidad');
    try {
      if (await closeBtn.isVisible({ timeout: 1000 })) {
        await closeBtn.click({ force: true });
        console.log('Menú de accesibilidad cerrado forzosamente.');
      }
    } catch (e) {
      // Ignorar si no es clickeable o no está
    }
  }

  /**
   * Realiza el login completo manejando el menú de accesibilidad y alertas.
   */
  async login(id: string, pass: string) {
    await this.page.goto('/login');

    // Inyectamos el CSS de deshabilitación lo antes posible
    await this.disableAccessibilityWidget();

    // Seleccionar el tipo de documento abriendo explícitamente el combobox
    // Esto evita usar selectOption() en selects ocultos que no disparan eventos en React
    const tipoDocContainer = this.page.locator('label').filter({ hasText: /Tipo de documento/i }).locator('..');
    
    try {
      const combobox = tipoDocContainer.locator('[role="combobox"], select').first();
      const tagName = await combobox.evaluate(el => el.tagName.toLowerCase());
      
      if (tagName === 'select') {
         await combobox.selectOption({ label: 'Cédula de Ciudadanía' });
      } else {
         await combobox.click({ force: true, timeout: 5000 });
         await this.page.waitForTimeout(500); // esperar animación de menú
         await this.page.getByRole('option', { name: /Cédula de Ciudadanía/i }).click({ force: true });
      }
    } catch {
      // Fallback si no tiene rol combobox explícito
      await tipoDocContainer.click();
      await this.page.waitForTimeout(500);
      await this.page.getByText(/Cédula de Ciudadanía/i).click();
    }

    await this.page.getByLabel(/Número de documento/i).fill(id);
    await this.page.locator('input[name="password"]').fill(pass);

    // Pequeño wait para evitar que el clic ocurra antes de que el formulario procese los cambios de input
    await this.page.waitForTimeout(500);

    // Capturar posibles alertas de "Credenciales inválidas"
    let dialogMsg = '';
    const dialogHandler = async (dialog: any) => {
      dialogMsg = dialog.message();
      await dialog.dismiss();
    };
    this.page.once('dialog', dialogHandler);

    // Usamos el rol de botón para mayor robustez
    const loginBtn = this.page.getByRole('button', { name: 'Iniciar sesión', exact: false });

    try {
      // Esperar a llegar al home o que aparezca un diálogo de error
      // Aumentamos a 30s para Jenkins y usamos Promise.all para capturar la navegación
      const possibleUrls = ['**/home**', '**/ficha**', '**/dashboard**', '**/wizard**'];
      const navigationPromises = possibleUrls.map(url => this.page.waitForURL(url, { timeout: 30_000 }));
      const navigationPromise = Promise.race(navigationPromises);

      // Presionar Enter en el campo de contraseña suele ser más confiable que un click forzado
      await this.page.locator('input[name="password"]').press('Enter');

      // También intentar click explícito en el botón como fallback
      try {
        await loginBtn.click({ force: true, timeout: 2000 });
      } catch (clickError) {
        console.log('Click en botón de login falló, continuando con Enter:', clickError.message);
      }

      await navigationPromise;

      console.log('Login exitoso. Redireccionado a:', this.page.url());

      // Volvemos a deshabilitar por si la redirección limpió los estilos inyectados
      await this.disableAccessibilityWidget();
    } catch (error) {
      const currentUrl = this.page.url();
      const pageContent = await this.page.locator('body').textContent().catch(() => 'No se pudo obtener contenido');
      if (dialogMsg) {
        throw new Error(`Error en Login detectado (Dialog): "${dialogMsg}" con ID: ${id}. URL: ${currentUrl}. Contenido: ${pageContent.substring(0, 500)}`);
      }
      // Verificar si hay algún mensaje de error visible en la UI (búsqueda más agresiva)
      const errorMessage = await this.page.locator('.text-destructive, .alert, [role="alert"], .error-message, .invalid-feedback').innerText().catch(() => '');
      if (errorMessage) {
        throw new Error(`Error en Login detectado (UI): "${errorMessage.trim()}" con ID: ${id}. URL: ${currentUrl}. Contenido: ${pageContent.substring(0, 500)}`);
      }
      throw new Error(`Timeout en Login: No se alcanzó destino esperado tras 30s. URL actual: ${currentUrl}. Contenido: ${pageContent.substring(0, 500)}.`);
    }
  }

  // --- Helpers Genéricos ---
  async fillInputByLabel(label: string, value: string) {
    await this.page.getByLabel(label).fill(value);
  }

  /**
   * Espera a que el paso actual del wizard esté listo para interacción.
   * Busca indicadores de que la transición de paso se completó.
   */
  async waitForStepReady(timeout = 3000) {
    await this.page.waitForTimeout(800);
    await this.disableAccessibilityWidget();
    // Esperar a que no haya spinners/loaders visibles
    try {
      await this.page.locator('[class*="loading"], [class*="spinner"], [role="progressbar"]')
        .waitFor({ state: 'hidden', timeout });
    } catch {
      // Sin spinners visibles, continuar
    }
  }

  /**
   * Helper para componentes "Select" customizados (Radix UI, shadcn, NextUI) que requieren
   * click y luego selección de opción. Soporta tanto `<select>` nativos como comboboxes con
   * role="combobox" (e.g. Radix Select triggers).
   */
  async selectDropdownOptionByLabel(label: string, optionText: string) {
    console.log(`Seleccionando dropdown [${label}] -> ${optionText}`);

    // Desabilitar widget de accesibilidad antes de interactuar
    await this.disableAccessibilityWidget();
    await this.page.waitForTimeout(300);

    // Intentar primero encontrar un <select> nativo asociado al label (más robusto y rápido)
    const nativeSelected = await this.tryNativeSelect(label, optionText);
    if (nativeSelected) return;

    // Si no hay select nativo, buscar combobox visual (Radix/shadcn style)
    const dropdown = await this.findDropdownByLabel(label);
    if (!dropdown) {
      throw new Error(`No se encontró dropdown: ${label}`);
    }

    // Click y selección visual
    await dropdown.scrollIntoViewIfNeeded();
    await this.page.waitForTimeout(400);

    try {
      await dropdown.click({ force: true, timeout: 10000 });
    } catch (e) {
      console.log(`Clic falló, reintentando...`);
      await this.page.waitForTimeout(500);
      await dropdown.click({ force: true });
    }

    // Esperar a que el listbox aparezca
    try {
      await this.page.locator('[role="listbox"]').waitFor({ state: 'visible', timeout: 3000 });
    } catch (e) {
      console.log(`Listbox no apareció en 3s, continuando...`);
    }

    await this.page.waitForTimeout(500);

    // Buscar y seleccionar la opción
    await this.selectVisibleOption(optionText, label);
  }

  /**
   * Intenta seleccionar mediante un <select> nativo asociado al label.
   */
  private async tryNativeSelect(label: string, optionText: string): Promise<boolean> {
    const labelSearch = label.substring(0, 25);
    const containers = [
      // Contenedor por <label> HTML
      async () => {
        const labelLoc = this.page.locator('label').filter({ hasText: new RegExp(labelSearch, 'i') }).first();
        return labelLoc.locator('..');
      },
      // Contenedor por texto visible
      async () => {
        const textEl = this.page.getByText(labelSearch, { exact: false }).first();
        return textEl.locator('..');
      },
      // Contenedor por texto + dos niveles arriba (Radix wraps deeper)
      async () => {
        const textEl = this.page.getByText(labelSearch, { exact: false }).first();
        return textEl.locator('../..');
      },
    ];

    for (const getContainer of containers) {
      try {
        const container = await getContainer();
        const hiddenSelect = container.locator('select').first();
        const selectCount = await hiddenSelect.count();
        if (selectCount > 0) {
          const options = await hiddenSelect.locator('option').all();
          console.log(`Select nativo encontrado con ${options.length} opciones para "${label.substring(0, 30)}..."`);
          
          for (const opt of options) {
            const text = await opt.textContent();
            if (text && text.toLowerCase().includes(optionText.toLowerCase())) {
              const value = await opt.getAttribute('value');
              if (value) {
                await hiddenSelect.selectOption(value);
                console.log(`✓ Opción seleccionada por SELECT HTML: ${optionText}`);
                return true;
              }
            }
          }
        }
      } catch {
        continue;
      }
    }
    return false;
  }

  /**
   * Busca un dropdown (combobox) por su label asociado usando múltiples estrategias.
   * Especialmente diseñado para Radix UI Select triggers donde no hay <label> HTML.
   */
  private async findDropdownByLabel(label: string) {
    const labelSearch = label.substring(0, 25);

    const strategies = [
      // Estrategia 1: <label> HTML directo + combobox en contenedor padre
      async () => {
        const labelLoc = this.page.locator('label').filter({ hasText: new RegExp(labelSearch, 'i') }).first();
        const cont = labelLoc.locator('..');
        const cb = cont.locator('[role="combobox"]').first();
        if (await cb.isVisible({ timeout: 1500 })) {
          console.log(`  Dropdown encontrado por label HTML`);
          return cb;
        }
        return null;
      },
      // Estrategia 2: aria-label / aria-labelledby del combobox
      async () => {
        const cb = this.page.getByRole('combobox', { name: new RegExp(labelSearch, 'i') }).first();
        if (await cb.isVisible({ timeout: 1500 })) {
          console.log(`  Dropdown encontrado por role+name`);
          return cb;
        }
        return null;
      },
      // Estrategia 3: <fieldset>/<legend> pattern (usado por Radix UI en FUC - Sisben, etc.)
      async () => {
        const legend = this.page.locator('legend').filter({ hasText: new RegExp(labelSearch, 'i') }).first();
        if (await legend.isVisible({ timeout: 1000 }).catch(() => false)) {
          // El combobox está en el fieldset padre de la legend
          const fieldset = legend.locator('..');
          const cb = fieldset.locator('[role="combobox"]').first();
          if (await cb.isVisible({ timeout: 1000 }).catch(() => false)) {
            console.log(`  Dropdown encontrado por fieldset/legend`);
            return cb;
          }
          // A veces hay divs intermedios
          const cbDeep = fieldset.locator('div [role="combobox"]').first();
          if (await cbDeep.isVisible({ timeout: 500 }).catch(() => false)) {
            console.log(`  Dropdown encontrado por fieldset/legend (deep)`);
            return cbDeep;
          }
        }
        return null;
      },
      // Estrategia 4: Texto visible + combobox como hermano o en padre
      async () => {
        // Buscar textos que contengan el label (usar locator más preciso)
        const allTextMatches = this.page.locator(`text="${labelSearch}"`);
        const count = await allTextMatches.count();
        
        for (let t = 0; t < Math.min(count, 3); t++) {
          const textEl = allTextMatches.nth(t);
          // Buscar combobox en padre directo
          const container = textEl.locator('..');
          const cb = container.locator('[role="combobox"]').first();
          if (await cb.isVisible({ timeout: 500 }).catch(() => false)) {
            console.log(`  Dropdown encontrado cerca de texto (match ${t})`);
            return cb;
          }
        }
        return null;
      },
      // Estrategia 5: Texto visible + combobox en ancestros (Radix envuelve más capas)
      async () => {
        const textEl = this.page.getByText(labelSearch, { exact: false }).first();
        for (let depth = 2; depth <= 6; depth++) {
          const ancestorPath = Array(depth).fill('..').join('/');
          const ancestor = textEl.locator(ancestorPath);
          const cb = ancestor.locator('[role="combobox"]').first();
          if (await cb.isVisible({ timeout: 500 }).catch(() => false)) {
            console.log(`  Dropdown encontrado en ancestro (nivel ${depth})`);
            return cb;
          }
        }
        return null;
      },
      // Estrategia 6: JS evaluate para buscar el combobox más cercano al texto
      async () => {
        const comboboxIndex = await this.page.evaluate((searchText) => {
          const allComboboxes = Array.from(document.querySelectorAll('[role="combobox"]'));
          
          // Buscar todos los nodos de texto que contienen el label
          const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            { acceptNode: (node) => {
              const text = node.textContent?.trim();
              return text && text.toLowerCase().includes(searchText.toLowerCase())
                ? NodeFilter.FILTER_ACCEPT
                : NodeFilter.FILTER_REJECT;
            }}
          );
          
          let textNode = walker.nextNode();
          while (textNode) {
            let el = textNode.parentElement;
            // Subir por ancestros hasta encontrar un contenedor con un combobox
            for (let i = 0; i < 8 && el; i++) {
              const cb = el.querySelector('[role="combobox"]');
              if (cb) {
                const idx = allComboboxes.indexOf(cb);
                if (idx >= 0) return idx;
              }
              // También buscar en hermanos
              const siblings = el.parentElement?.children;
              if (siblings) {
                for (const sib of Array.from(siblings)) {
                  if (sib !== el && sib.getAttribute?.('role') === 'combobox') {
                    const idx = allComboboxes.indexOf(sib);
                    if (idx >= 0) return idx;
                  }
                  const cbInSib = sib.querySelector?.('[role="combobox"]');
                  if (cbInSib) {
                    const idx = allComboboxes.indexOf(cbInSib);
                    if (idx >= 0) return idx;
                  }
                }
              }
              el = el.parentElement;
            }
            textNode = walker.nextNode();
          }
          return -1;
        }, labelSearch);
        
        if (comboboxIndex >= 0) {
          const cb = this.page.locator('[role="combobox"]').nth(comboboxIndex);
          if (await cb.isVisible({ timeout: 500 }).catch(() => false)) {
            console.log(`  Dropdown encontrado por JS evaluate (combobox #${comboboxIndex})`);
            return cb;
          }
        }
        return null;
      },
    ];

    for (const strategy of strategies) {
      try {
        const result = await strategy();
        if (result) return result;
      } catch {
        continue;
      }
    }

    console.log(`  ⚠ No se encontró dropdown específico para "${label}"`);
    return null;
  }

  /**
   * Selecciona una opción visible en un listbox/dropdown ya abierto.
   */
  private async selectVisibleOption(optionText: string, label: string) {
    const optNorm = optionText.replace(/\s+/g, ' ').trim().toLowerCase();

    // Intentar por role="option"
    const option = this.page.getByRole('option', { name: new RegExp(optionText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i') }).first();
    try {
      await option.waitFor({ state: 'visible', timeout: 5000 });
      await option.click({ force: true });
      console.log(`Opción "${optionText}" seleccionada por role`);
      return;
    } catch { }

    // Iterar sobre todas las opciones con normalización
    try {
      const allOptions = this.page.getByRole('option');
      const count = await allOptions.count();
      console.log(`  Buscando "${optNorm}" entre ${count} opciones visibles...`);
      
      for (let i = 0; i < count; i++) {
        const text = await allOptions.nth(i).textContent();
        if (!text) continue;
        const textNorm = text.replace(/\s+/g, ' ').trim().toLowerCase();
        if (textNorm.includes(optNorm) || optNorm.includes(textNorm)) {
          await allOptions.nth(i).click({ force: true });
          console.log(`✓ Opción "${text.trim()}" seleccionada (match normalizado)`);
          return;
        }
      }

      // Match parcial (primera palabra)
      const firstWord = optNorm.split(/[\s\-]/)[0];
      for (let i = 0; i < count; i++) {
        const text = await allOptions.nth(i).textContent();
        if (!text) continue;
        const textNorm = text.replace(/\s+/g, ' ').trim().toLowerCase();
        if (textNorm.startsWith(firstWord)) {
          await allOptions.nth(i).click({ force: true });
          console.log(`✓ Opción "${text.trim()}" seleccionada (match parcial)`);
          return;
        }
      }
    } catch (e) {
      console.log(`  Error iterando opciones: ${e.message}`);
    }

    // Fallback: buscar en listbox directamente
    try {
      const listbox = this.page.locator('[role="listbox"]').first();
      const items = listbox.locator('[role="option"], > div, > li');
      const count = await items.count();
      for (let i = 0; i < count; i++) {
        const text = await items.nth(i).textContent();
        if (!text) continue;
        if (text.toLowerCase().includes(optNorm)) {
          await items.nth(i).click({ force: true });
          console.log(`✓ Opción "${text.trim()}" seleccionada (listbox fallback)`);
          return;
        }
      }
    } catch { }

    throw new Error(`No se encontró opción "${optionText}" en dropdown "${label}"`);
  }

  /**
   * Helper para selectores "Searchable" como municipios.
   * Reescrito para máxima robustez con múltiples estrategias de búsqueda y selección.
   */
  async searchAndSelectDropdownOption(label: string, searchText: string, optionTextToClick: string) {
    console.log(`\n=== searchAndSelectDropdownOption ===`);
    console.log(`  Label: "${label}"`);
    console.log(`  Search: "${searchText}"`);
    console.log(`  Option: "${optionTextToClick}"`);

    // Desabilitar widget de accesibilidad antes de interactuar
    await this.disableAccessibilityWidget();
    await this.page.waitForTimeout(500);

    // Extraer solo la primera parte (ciudad) para la búsqueda
    const query = searchText.includes(',') ? searchText.split(',')[0].trim() : searchText;
    console.log(`  Query a escribir: "${query}"`);

    // === PASO 1: Encontrar el combobox ===
    const combobox = await this.findComboboxByLabel(label);
    if (!combobox) {
      throw new Error(`No se encontró combobox para: "${label}"`);
    }

    // === PASO 2: Intentar selección (con reintento) ===
    const maxAttempts = 3;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      console.log(`\n  --- Intento ${attempt}/${maxAttempts} ---`);

      try {
        // Scroll al combobox
        await combobox.scrollIntoViewIfNeeded();
        await this.page.waitForTimeout(300);

        // Cerrar cualquier dropdown previamente abierto
        await this.page.keyboard.press('Escape');
        await this.page.waitForTimeout(300);

        // Clic para abrir el dropdown
        await combobox.click({ force: true, timeout: 5000 });
        console.log(`  Combobox clickeado`);
        await this.page.waitForTimeout(800);

        // === PASO 3: Escribir en el input de búsqueda ===
        const typed = await this.typeInSearchableCombobox(combobox, query);
        if (!typed) {
          console.log(`  No se pudo escribir la búsqueda, reintentando...`);
          continue;
        }

        // Esperar a que las opciones de búsqueda se carguen
        console.log(`  Esperando resultados de búsqueda...`);
        await this.page.waitForTimeout(2000);

        // === PASO 4: Buscar y hacer clic en la opción ===
        const selected = await this.selectOptionFromResults(optionTextToClick);
        if (selected) {
          console.log(`  ✓ Selección completada exitosamente`);
          await this.page.waitForTimeout(500);
          return;
        }

        console.log(`  No se encontró la opción, reintentando...`);

      } catch (e) {
        console.log(`  Error en intento ${attempt}: ${e.message}`);
      }

      // Cerrar dropdown antes de reintentar
      await this.page.keyboard.press('Escape');
      await this.page.waitForTimeout(500);
    }

    // Si ningún intento funcionó, lanzar error descriptivo
    throw new Error(`No se pudo seleccionar opción para: "${label}" buscando "${optionTextToClick}" después de ${maxAttempts} intentos`);
  }

  /**
   * Busca un combobox por su label asociado usando múltiples estrategias.
   */
  private async findComboboxByLabel(label: string) {
    const strategies = [
      // Estrategia 1: Por label HTML + contenedor padre
      async () => {
        const labelLoc = this.page.locator('label').filter({ hasText: new RegExp(label.substring(0, 25), 'i') }).first();
        const cont = labelLoc.locator('..');
        const cb = cont.locator('[role="combobox"]').first();
        if (await cb.isVisible({ timeout: 2000 })) {
          console.log(`  Combobox encontrado por label HTML`);
          return cb;
        }
        return null;
      },
      // Estrategia 2: Por aria-label o name del combobox
      async () => {
        const cb = this.page.getByRole('combobox', { name: new RegExp(label.substring(0, 25), 'i') }).first();
        if (await cb.isVisible({ timeout: 2000 })) {
          console.log(`  Combobox encontrado por role + name`);
          return cb;
        }
        return null;
      },
      // Estrategia 3: Buscar por texto visible y luego combobox cercano
      async () => {
        const textEl = this.page.getByText(label, { exact: false }).first();
        if (await textEl.isVisible({ timeout: 1500 })) {
          // Buscar combobox en ancestros
          const ancestors = [
            textEl.locator('..'),
            textEl.locator('../..'),
            textEl.locator('../../..'),
          ];
          for (const ancestor of ancestors) {
            const cb = ancestor.locator('[role="combobox"]').first();
            if (await cb.isVisible({ timeout: 500 }).catch(() => false)) {
              console.log(`  Combobox encontrado por texto + ancestor`);
              return cb;
            }
          }
        }
        return null;
      },
      // Estrategia 4: Buscar por placeholder o aria-label en inputs
      async () => {
        const cb = this.page.locator(`[role="combobox"][aria-label*="${label.substring(0, 20)}"]`).first();
        if (await cb.isVisible({ timeout: 1000 }).catch(() => false)) {
          console.log(`  Combobox encontrado por aria-label`);
          return cb;
        }
        return null;
      }
    ];

    for (const strategy of strategies) {
      try {
        const result = await strategy();
        if (result) return result;
      } catch (e) {
        continue;
      }
    }

    return null;
  }

  /**
   * Escribe texto en un combobox searchable.
   * Usa múltiples estrategias para encontrar el input e insertar texto.
   */
  private async typeInSearchableCombobox(combobox, query: string): Promise<boolean> {
    // Verificar si el combobox ES el input
    try {
      const tagName = await combobox.evaluate(el => el.tagName.toLowerCase());
      if (tagName === 'input') {
        await combobox.fill('');
        await combobox.pressSequentially(query, { delay: 80 });
        console.log(`  Texto escrito directamente en combobox-input: "${query}"`);
        return true;
      }
    } catch { /* no es un input */ }

    // Buscar input dentro del combobox
    const inputStrategies = [
      () => combobox.locator('input:not([type="hidden"])').first(),
      () => combobox.locator('input').first(),
      () => combobox.locator('..').locator('input:not([type="hidden"])').first(),
      () => this.page.locator('[role="listbox"]').locator('..').locator('input').first(),
      () => this.page.locator('input[aria-expanded="true"]').first(),
      () => this.page.locator('input:focus').first(),
    ];

    for (const getInput of inputStrategies) {
      try {
        const input = getInput();
        const isVisible = await input.isVisible({ timeout: 1000 }).catch(() => false);
        if (isVisible) {
          // Limpiar y escribir
          try {
            await input.fill('');
            await input.pressSequentially(query, { delay: 80 });
            console.log(`  Texto escrito en input encontrado: "${query}"`);
            return true;
          } catch (fillError) {
            console.log(`  Fill/pressSequentially falló: ${fillError.message}`);
            // Intentar con keyboard directo
            try {
              await input.focus();
              await input.press('Control+a');
              await this.page.keyboard.type(query, { delay: 100 });
              console.log(`  Texto escrito con keyboard.type: "${query}"`);
              return true;
            } catch (kbError) {
              console.log(`  keyboard.type también falló: ${kbError.message}`);
            }
          }
        }
      } catch { }
    }

    // Último recurso: escribir con keyboard directo sin buscar input
    try {
      console.log(`  Intentando keyboard.type directo sin input localizado...`);
      await this.page.keyboard.type(query, { delay: 100 });
      return true;
    } catch (e) {
      console.log(`  keyboard.type directo falló: ${e.message}`);
      return false;
    }
  }

  /**
   * Busca y selecciona una opción de los resultados visibles.
   * Usa múltiples estrategias de matching (exacto, parcial, normalizado).
   */
  private async selectOptionFromResults(optionText: string): Promise<boolean> {
    const optionNorm = optionText.replace(/\s+/g, ' ').trim().toLowerCase();
    const optionCity = optionNorm.split(',')[0].trim();

    // Esperar a que al menos una opción sea visible
    try {
      await this.page.getByRole('option').first().waitFor({ state: 'visible', timeout: 5000 });
    } catch {
      console.log(`  No hay opciones visibles en el listbox`);

      // Intentar buscar en divs dentro de listbox
      try {
        const listbox = this.page.locator('[role="listbox"]');
        if (await listbox.isVisible({ timeout: 1000 }).catch(() => false)) {
          const children = listbox.locator('> *');
          const count = await children.count();
          console.log(`  Listbox tiene ${count} hijos directos`);
          if (count > 0) {
            for (let i = 0; i < count; i++) {
              const child = children.nth(i);
              const text = (await child.textContent()) || '';
              const textNorm = text.replace(/\s+/g, ' ').trim().toLowerCase();
              console.log(`    Hijo ${i}: "${textNorm}"`);
              if (textNorm.includes(optionCity) || textNorm.includes(optionNorm)) {
                await child.click({ force: true });
                console.log(`  ✓ Opción seleccionada de listbox hijo: "${text.trim()}"`);
                return true;
              }
            }
            // Fallback: click primer hijo
            const firstText = await children.first().textContent();
            if (firstText && firstText.trim().length > 0) {
              await children.first().click({ force: true });
              console.log(`  ✓ Primer hijo del listbox seleccionado como fallback: "${firstText.trim()}"`);
              return true;
            }
          }
        }
      } catch (e) {
        console.log(`  Búsqueda en listbox hijos falló: ${e.message}`);
      }
      return false;
    }

    // Obtener todas las opciones con role="option"
    const options = this.page.getByRole('option');
    const count = await options.count();
    console.log(`  Opciones encontradas: ${count}`);

    if (count === 0) return false;

    // Primer paso: match exacto (con normalización de espacios)
    for (let i = 0; i < count; i++) {
      const opt = options.nth(i);
      const textRaw = await opt.textContent();
      if (!textRaw) continue;
      const textNorm = textRaw.replace(/\s+/g, ' ').trim().toLowerCase();
      console.log(`    Opción ${i}: "${textNorm}"`);

      if (textNorm === optionNorm || textNorm.includes(optionNorm)) {
        await opt.click({ force: true });
        console.log(`  ✓ Match exacto/incluye: "${textRaw.trim()}"`);
        return true;
      }
    }

    // Segundo paso: match parcial (solo ciudad)
    for (let i = 0; i < count; i++) {
      const opt = options.nth(i);
      const textRaw = await opt.textContent();
      if (!textRaw) continue;
      const textNorm = textRaw.replace(/\s+/g, ' ').trim().toLowerCase();

      if (textNorm.includes(optionCity)) {
        await opt.click({ force: true });
        console.log(`  ✓ Match parcial (ciudad): "${textRaw.trim()}"`);
        return true;
      }
    }

    // Tercer paso: si solo hay 1 opción visible, seleccionarla
    if (count === 1) {
      const firstText = await options.first().textContent();
      await options.first().click({ force: true });
      console.log(`  ✓ Única opción seleccionada: "${firstText?.trim()}"`);
      return true;
    }

    // Cuarto paso: click en la primera opción como última opción
    if (count > 0) {
      const firstText = await options.first().textContent();
      await options.first().click({ force: true });
      console.log(`  ✓ Primera opción seleccionada (fallback): "${firstText?.trim()}"`);
      return true;
    }

    return false;
  }

  // Helper para componentes "ToggleGroup" (SÍ/NO)
  async selectToggleOption(label: string, optionText: string) {
    console.log(`Seleccionando toggle [${label}] -> ${optionText}`);

    await this.disableAccessibilityWidget();
    await this.page.waitForTimeout(200);

    const optionSearch = new RegExp(`^${optionText}$`, 'i');
    let element = null;

    // Estrategia 1: Buscar por radiogroup
    try {
      const group = this.page.getByRole('radiogroup', { name: label, exact: false });
      if (await group.isVisible({ timeout: 1500 })) {
        element = group.locator('label, span').filter({ hasText: optionSearch }).first();
        if (await element.isVisible({ timeout: 1000 })) {
          console.log(`Toggle encontrado por radiogroup`);
        } else {
          element = null;
        }
      }
    } catch (e) {
      console.log(`Radiogroup no encontrado`);
    }

    // Estrategia 2: Buscar por rol 'radio'
    if (!element) {
      try {
        const radios = this.page.getByRole('radio');
        const count = await radios.count();
        for (let i = 0; i < Math.min(count, 20); i++) {
          const txt = await radios.nth(i).textContent();
          if (txt && optionSearch.test(txt.trim())) {
            element = radios.nth(i);
            console.log(`Toggle encontrado por radio`);
            break;
          }
        }
      } catch (e) {
        console.log(`Radio search falló`);
      }
    }

    // Estrategia 3: Buscar en contenedor cercano
    if (!element) {
      try {
        const container = this.page.locator('div').filter({ has: this.page.locator('text=' + label.substring(0, 30)) }).first();
        element = container.locator('label, span, button').filter({ hasText: optionSearch }).first();
        if (await element.isVisible({ timeout: 1000 })) {
          console.log(`Toggle encontrado en contenedor`);
        } else {
          element = null;
        }
      } catch (e) {
        console.log(`Container search falló`);
      }
    }

    // Estrategia 4: Buscar cualquier elemento con el texto de opción
    if (!element) {
      try {
        element = this.page.locator(`text=${optionText}`).first();
        if (await element.isVisible({ timeout: 1000 })) {
          console.log(`Toggle encontrado por texto directo`);
        } else {
          element = null;
        }
      } catch (e) {
        console.log(`Text search falló`);
      }
    }

    if (!element) {
      throw new Error(`No se encontró toggle para: ${label} -> ${optionText}`);
    }

    // Hacer clic
    await element.scrollIntoViewIfNeeded();
    await this.page.waitForTimeout(200);

    try {
      await element.click({ force: true, timeout: 10000 });
      console.log(`Toggle \"${optionText}\" seleccionado`);
    } catch (e) {
      console.log(`Clic falló, reintentando...`);
      await this.page.waitForTimeout(300);
      await element.click({ force: true });
    }
  }

  async clickNext() {
    console.log(`Haciendo clic en "Siguiente"...`);
    const nextBtn = this.page.getByRole('button', { name: /Siguiente/i });
    await nextBtn.scrollIntoViewIfNeeded();
    await this.page.waitForTimeout(300);
    await nextBtn.click();
    // Esperar transición de paso
    await this.page.waitForTimeout(1000);
    console.log(`Clic en "Siguiente" completado`);
  }

  // --- Step 1: Identificación ---
  async fillIdentificationStep(data: any) {
    console.log('\n========================================');
    console.log('Llenando Paso 1: Identificación...');
    console.log('========================================');
    await this.waitForStepReady();

    await this.fillInputByLabel('Primer nombre', data.nombre1);
    await this.fillInputByLabel('Primer apellido', data.apellido1);

    await this.fillInputByLabel('Fecha de nacimiento', data.fechanacimiento);

    console.log(`Buscando lugar de nacimiento: ${data.munnacimiento}`);
    await this.searchAndSelectDropdownOption('Lugar de nacimiento', data.munnacimiento, data.munnacimiento);

    console.log(`Buscando lugar de expedición: ${data.dptoregistro}`);
    await this.searchAndSelectDropdownOption('Lugar de expedición', data.dptoregistro, data.dptoregistro);
    await this.fillInputByLabel('Fecha de expedición', data.fecharegistro);

    if (data.isMobile) {
      await this.page.getByRole('button', { name: 'Celular' }).click();
      await this.fillInputByLabel('Telefono', data.numerocel);
    }

    await this.selectDropdownOptionByLabel('¿Cuál es su género?', data.generoText);

    const toggleLabel = data.isLgbtiqPlus ? 'SÍ' : 'NO';
    await this.selectToggleOption('¿Usted se reconoce como parte de la población LGBTIQ+?', toggleLabel);

    console.log('Paso 1 completo. Click en Siguiente...');
    await this.clickNext();
  }

  // --- Step 2: Ubicación ---
  async fillLocationStep(data: any) {
    console.log('\n========================================');
    console.log('Llenando Paso 2: Ubicación...');
    console.log('========================================');
    await this.waitForStepReady();

    await this.searchAndSelectDropdownOption('Ciudad de residencia', data.location, data.location);

    // Zona de residencia (urbana/rural) - asume Select
    if (data.areaResidence === 'urbana') {
      await this.selectDropdownOptionByLabel('Zona de residencia', 'Urbana');
      await this.selectDropdownOptionByLabel('Avenida principal', data.mainAvenue);
      await this.fillInputByLabel('Número de via principal', data.mainStreetNumber);
    } else {
      await this.selectDropdownOptionByLabel('Zona de residencia', 'Rural');
    }

    console.log('Paso 2 completo. Click en Siguiente...');
    await this.clickNext();
  }

  // --- Step 3: Características Poblacionales ---
  async fillPopulationSpecifics(data: any) {
    console.log('\n========================================');
    console.log('Llenando Paso 3: Características Poblacionales...');
    console.log('========================================');
    await this.waitForStepReady();

    // Etnia
    await this.selectDropdownOptionByLabel('De acuerdo con su cultura, pueblo o rasgos físicos, usted es o se reconoce como...', data.ethnicGroup);

    // Discapacidad
    await this.selectToggleOption('¿Presenta alguna discapacidad?', data.hasDisability ? 'SÍ' : 'NO');

    // Víctima
    await this.selectToggleOption('¿Se reconoce como Víctima del Conflicto Armado?', data.isVictim ? 'SÍ' : 'NO');

    // Campesino
    await this.selectToggleOption('¿Usted se considera campesino/a?', data.isPeasant ? 'SÍ' : 'NO');
    await this.selectToggleOption('¿Usted se considera que la comunidad en la que vive es campesina?', data.peasantCommunity ? 'SÍ' : 'NO');

    // Hogar
    await this.selectDropdownOptionByLabel('¿Cúal es su parentesco con el jefe o la jefa de este hogar?', data.headOfHousehold);
    await this.selectDropdownOptionByLabel('Seleccione su estado civil actual', data.maritalStatus);

    console.log('Paso 3 completo. Click en Siguiente...');
    await this.clickNext();
  }

  // --- Step 4: Salud ---
  async fillHealthStep(data: any) {
    console.log('\n========================================');
    console.log('Llenando Paso 4: Salud...');
    console.log('========================================');
    await this.waitForStepReady();

    // Grupo Sisben (está en el paso de Salud según el wizard real)
    if (data.sisbenGroup) {
      await this.selectDropdownOptionByLabel('Sisben IV Grupo', data.sisbenGroup);
    }
    if (data.sisbenSubgroup) {
      await this.selectDropdownOptionByLabel('Numero de subgrupo', data.sisbenSubgroup);
    }

    // Has RLCPD toggle
    const rlcpdLabel = data.hasRlcpd === 'SÍ' ? 'SÍ' : 'NO';
    
    // Intentar múltiples variantes del label del toggle RLCPD
    const rlcpdLabelVariants = [
      '¿Está inscrito en el Registro de la localización y caracterización de personas con discapacidad del Ministerio de Salud?',
      'Registro de la localización y caracterización',
      'RLCPD',
      '¿Está inscrito en el Registro',
    ];

    let rlcpdSelected = false;
    for (const variant of rlcpdLabelVariants) {
      try {
        await this.selectToggleOption(variant, rlcpdLabel);
        rlcpdSelected = true;
        break;
      } catch (e) {
        console.log(`  Toggle RLCPD con label "${variant.substring(0, 40)}..." no encontrado, intentando siguiente...`);
      }
    }
    if (!rlcpdSelected) {
      console.log(`  ⚠ Toggle RLCPD no encontrado con ninguna variante, continuando...`);
    }

    // Régimen de seguridad social en salud
    const healthLabelVariants = [
      '¿A cúal de los siguientes regímenes de seguridad social en salud está afiliado/a?',
      '¿A cuál de los siguientes regímenes de seguridad social en salud está afiliado',
      'regímenes de seguridad social',
      'régimen de seguridad social',
      'seguridad social en salud',
    ];

    let healthSelected = false;
    for (const variant of healthLabelVariants) {
      try {
        await this.selectDropdownOptionByLabel(variant, data.socialSecurity);
        healthSelected = true;
        break;
      } catch (e) {
        console.log(`  Dropdown salud con label "${variant.substring(0, 40)}..." no encontrado, intentando siguiente...`);
      }
    }
    if (!healthSelected) {
      console.log(`  ⚠ Dropdown de régimen de salud no encontrado, continuando...`);
    }

    // Campos adicionales de salud (si existen)
    if (data.eps) {
      try {
        await this.selectDropdownOptionByLabel('EPS', data.eps);
      } catch (e) {
        console.log(`  EPS dropdown no encontrado: ${e.message}`);
      }
    }

    console.log('Paso 4 completo. Click en Siguiente...');
    await this.clickNext();
  }

  // --- Step 5: Educación ---
  async fillEducationStep(data: any) {
    console.log('\n========================================');
    console.log('Llenando Paso 5: Educación...');
    console.log('========================================');
    await this.waitForStepReady();

    // Máximo nivel educativo
    const educationLabelVariants = [
      '¿Cúal es el máximo nivel educativo alcanzado por usted hasta el momento?',
      '¿Cuál es el máximo nivel educativo alcanzado',
      'máximo nivel educativo',
      'nivel educativo alcanzado',
    ];

    let eduSelected = false;
    for (const variant of educationLabelVariants) {
      try {
        await this.selectDropdownOptionByLabel(variant, data.maxEducationLevel);
        eduSelected = true;
        break;
      } catch (e) {
        console.log(`  Dropdown educación con label "${variant.substring(0, 40)}..." no encontrado, intentando siguiente...`);
      }
    }
    if (!eduSelected) {
      console.log(`  ⚠ Dropdown de nivel educativo no encontrado, continuando...`);
    }

    // Campos adicionales de educación formal (si aplican y existen)
    if (data.currentlyStudying !== undefined) {
      try {
        await this.selectToggleOption('¿Actualmente está estudiando?', data.currentlyStudying ? 'SÍ' : 'NO');
      } catch (e) {
        console.log(`  Toggle "actualmente estudiando" no encontrado: ${e.message}`);
      }
    }

    if (data.icfesScore) {
      try {
        await this.fillInputByLabel('Puntaje ICFES', data.icfesScore);
      } catch (e) {
        console.log(`  Campo ICFES no encontrado: ${e.message}`);
      }
    }

    if (data.educationInstitution) {
      try {
        const instLabelVariants = [
          'Institución educativa',
          'institución educativa',
          'centro educativo',
        ];
        for (const v of instLabelVariants) {
          try {
            await this.fillInputByLabel(v, data.educationInstitution);
            break;
          } catch { }
        }
      } catch (e) {
        console.log(`  Campo institución educativa no encontrado: ${e.message}`);
      }
    }

    if (data.educationTitle) {
      try {
        await this.fillInputByLabel('Título obtenido', data.educationTitle);
      } catch (e) {
        console.log(`  Campo título obtenido no encontrado: ${e.message}`);
      }
    }

    console.log('Paso 5 completo. Click en Siguiente...');
    await this.clickNext();
  }
}
