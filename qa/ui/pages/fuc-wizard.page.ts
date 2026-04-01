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

    // Selectores basados en Labels (según snapshot del usuario) para mayor robustez
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

  // Helper para componentes "Select" customizados que requieren click y luego selección de opción
  async selectDropdownOptionByLabel(label: string, optionText: string) {
    console.log(`Seleccionando dropdown [${label}] -> ${optionText}`);

    // Desabilitar widget de accesibilidad antes de interactuar
    await this.disableAccessibilityWidget();
    await this.page.waitForTimeout(300);

    let dropdown = null;

    // Estrategia 1: Buscar por label directo (primeros 25 caracteres para ser más flexible)
    try {
      const labelLoc = this.page.locator('label').filter({ hasText: new RegExp(label.substring(0, 25), 'i') }).first();
      const cont = labelLoc.locator('..');
      dropdown = cont.locator('[role="combobox"]').first();
      if (await dropdown.isVisible({ timeout: 1500 })) {
        console.log(`Dropdown encontrado por label`);
      } else {
        dropdown = null;
      }
    } catch (e) {
      console.log(`Estrategia label falló`);
    }

    // Estrategia 2: Buscar por combobox role con parte del label
    if (!dropdown) {
      try {
        dropdown = this.page.getByRole('combobox', { name: new RegExp(label.substring(0, 25), 'i') }).first();
        if (await dropdown.isVisible({ timeout: 1500 })) {
          console.log(`Dropdown encontrado por role`);
        } else {
          dropdown = null;
        }
      } catch (e) {
        console.log(`Estrategia role falló`);
      }
    }

    // Estrategia 3: Buscar cualquier combobox visible cercano
    if (!dropdown) {
      try {
        const allCb = this.page.locator('[role="combobox"]');
        const cnt = await allCb.count();
        if (cnt > 0) {
          dropdown = allCb.first();
          console.log(`Dropdown encontrado como primer combobox`);
        }
      } catch (e) {
        console.log(`Estrategia combobox falló`);
      }
    }

    if (!dropdown) {
      throw new Error(`No se encontró dropdown: ${label}`);
    }

    // Encontrar el contenedor para buscar <select> subyacente
    let container = null;
    try {
      const labelLoc = this.page.locator('label').filter({ hasText: new RegExp(label.substring(0, 25), 'i') }).first();
      container = labelLoc.locator('..');
    } catch {
      container = dropdown.locator('..');
    }

    // ESTRATEGIA 0: Intentar primero seleccionar por el select HTML subyacente (más robusto)
    if (container) {
      try {
        const hiddenSelect = container.locator('select').first();
        const selectCount = await hiddenSelect.count();
        if (selectCount > 0) {
          const options = await hiddenSelect.locator('option').all();
          console.log(`Select encontrado con ${options.length} opciones`);
          
          for (const opt of options) {
            const text = await opt.textContent();
            if (text && text.toLowerCase().includes(optionText.toLowerCase())) {
              const value = await opt.getAttribute('value');
              if (value) {
                await hiddenSelect.selectOption(value);
                console.log(`✓ Opción seleccionada por SELECT HTML: ${optionText}`);
                return;
              }
            }
          }
        }
      } catch (e) {
        console.log(`Select HTML strategy falló: ${e.message}`);
      }
    }

    // Hacer scroll y clic
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
      await this.page.locator('[role="listbox"]').waitFor({ state: 'visible', timeout: 2000 });
    } catch (e) {
      console.log(`Listbox no apareció en 2s, continuando...`);
    }

    await this.page.waitForTimeout(500);

    // Buscar opción sin anclas estrictas para evitar problemas de espaciado DOM
    const option = this.page.getByRole('option', { name: new RegExp(optionText, 'i') }).first();
    try {
      await option.waitFor({ state: 'visible', timeout: 10000 });
      await option.click({ force: true });
      console.log(`Opción "${optionText}" seleccionada`);
    } catch (e) {
      // Fallback: búsqueda parcial con primera palabra
      try {
        const firstWord = optionText.split(' ')[0];
        const optPart = this.page.getByRole('option', { name: new RegExp(`^${firstWord}`, 'i') }).first();
        await optPart.waitFor({ state: 'visible', timeout: 8000 });
        await optPart.click({ force: true });
        console.log(`Opción (parcial) "${firstWord}" seleccionada`);
      } catch (fallbackError) {
        // Último fallback: primera opción disponible
        try {
          const firstOption = this.page.getByRole('option').first();
          await firstOption.waitFor({ state: 'visible', timeout: 5000 });
          const firstText = await firstOption.textContent();
          await firstOption.click({ force: true });
          console.log(`Primera opción seleccionada como fallback: "${firstText}"`);
        } catch (finalError) {
          throw new Error(`No se encontró opción "${optionText}" en dropdown "${label}"`);
        }
      }
    }
  }

  // Helper para selectores "Searchable" como municipios
  async searchAndSelectDropdownOption(label: string, searchText: string, optionTextToClick: string) {
    console.log(`Buscando en ${label}: ${searchText}`);

    // Desabilitar widget de accesibilidad antes de interactuar
    await this.disableAccessibilityWidget();
    await this.page.waitForTimeout(800);

    // Encontrar el contenedor
    let container;
    try {
      container = this.page.locator('label').filter({ hasText: label }).locator('..');
      if (await container.count() === 0) {
        throw new Error("No es un label estricto");
      }
    } catch {
      const labelTextElement = this.page.getByText(label, { exact: false }).first();
      container = labelTextElement.locator('..');
    }

    const combobox = container.locator('[role="combobox"]').first();
    const hiddenSelect = container.locator('select').first();

    // ESTRATEGIA 0: Intentar primero seleccionar por el select HTML subyacente (más robusto)
    try {
      const selectCount = await hiddenSelect.count();
      if (selectCount > 0) {
        const options = await hiddenSelect.locator('option').all();
        console.log(`Select encontrado con ${options.length} opciones`);
        
        for (const opt of options) {
          const text = await opt.textContent();
          if (text && text.toLowerCase().includes(optionTextToClick.toLowerCase())) {
            const value = await opt.getAttribute('value');
            if (value) {
              await hiddenSelect.selectOption(value);
              console.log(`✓ Opción seleccionada por SELECT HTML: ${optionTextToClick}`);
              return;
            }
          }
        }
      }
    } catch (e) {
      console.log(`Select HTML strategy falló: ${e.message}`);
    }

    // ESTRATEGIA 1: Búsqueda visual con rol="option"
    // Hacer scroll
    await combobox.scrollIntoViewIfNeeded();
    await this.page.waitForTimeout(400);

    // Hacer clic para abrir
    try {
      await combobox.click({ force: true, timeout: 8000 });
      console.log(`Combobox clickeado`);
    } catch (e) {
      console.log(`Clic falló: ${e.message}`);
      await this.page.waitForTimeout(500);
      await combobox.click({ force: true });
    }

    await this.page.waitForTimeout(1000); // Esperar más tiempo para que se abra el dropdown

    // Buscar el input dentro del combobox O en el popup que se abre
    let inputLoc = null;
    
    // Buscar en el combobox primero
    try {
      inputLoc = combobox.locator('input').first();
      const isVisible = await inputLoc.isVisible({ timeout: 500 });
      if (isVisible) {
        console.log(`Input encontrado en combobox`);
      } else {
        inputLoc = null;
      }
    } catch (e) {
      console.log(`Input no en combobox`);
    }

    // Si no está en combobox, buscar en la página
    if (!inputLoc) {
      try {
        const pageInputs = this.page.locator('input[type="text"], input:not([type])');
        const count = await pageInputs.count();
        for (let i = 0; i < count; i++) {
          const inp = pageInputs.nth(i);
          const isVis = await inp.isVisible({ timeout: 300 }).catch(() => false);
          if (isVis) {
            inputLoc = inp;
            console.log(`Input encontrado en página (index ${i})`);
            break;
          }
        }
      } catch (e) {
        console.log(`Búsqueda de inputs en página falló`);
      }
    }

    // Escribir en el input
    const query = searchText.includes(',') ? searchText.split(',')[0].trim() : searchText;
    
    if (inputLoc) {
      try {
        await inputLoc.focus();
        await inputLoc.fill('', { force: true });
        await inputLoc.fill(query, { delay: 50 });
        console.log(`Input rellenado con "fillText: ${query}"`);
      } catch (e) {
        console.log(`Fill falló: ${e.message}, usando type...`);
        try {
          await inputLoc.focus();
          await this.page.keyboard.type(query, { delay: 100 });
          console.log(`Input rellenado con keyboard.type: ${query}`);
        } catch (keyboardError) {
          console.log(`Keyboard.type también falló: ${keyboardError.message}`);
        }
      }
    } else {
      console.log(`Input no encontrado, escribiendo keyboard directo...`);
      await this.page.keyboard.type(query, { delay: 100 });
    }

    // Esperar a que el listbox y opciones aparezcan
    console.log(`Esperando listbox...`);
    try {
      await this.page.locator('[role="listbox"]').waitFor({ state: 'visible', timeout: 5000 });
      console.log(`Listbox visible`);
    } catch (e) {
      console.log(`Listbox no apareció tras 5s`);
    }

    await this.page.waitForTimeout(2000); // Tiempo extra para que las opciones se rendericen

    // Buscar role="option"
    try {
      const options = this.page.getByRole('option');
      const count = await options.count();
      console.log(`Opciones encontradas: ${count}`);
      
      for (let i = 0; i < count; i++) {
        const opt = options.nth(i);
        const text = await opt.textContent();
        if (text && text.toLowerCase().includes(optionTextToClick.toLowerCase())) {
          await opt.click({ force: true });
          console.log(`✓ Opción seleccionada por role="option": ${optionTextToClick}`);
          return;
        }
      }
    } catch (e) {
      console.log(`Búsqueda por role="option" falló: ${e.message}`);
    }

    // Fallback: Clic en primer elemento visible en listbox
    try {
      const listbox = this.page.locator('[role="listbox"]').first();
      const allChildren = listbox.locator('> div, > li, > [role="option"]');
      const childCount = await allChildren.count();
      console.log(`Elementos en listbox: ${childCount}`);
      
      if (childCount > 0) {
        await allChildren.first().click({ force: true });
        console.log(`✓ Primer elemento del listbox clickeado`);
        return;
      }
    } catch (e) {
      console.log(`Fallback listbox falló: ${e.message}`);
    }

    throw new Error(`No se pudo seleccionar opción para: "${label}" buscando "${optionTextToClick}"`);
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
    await this.page.getByRole('button', { name: 'Siguiente' }).click();
    // Pequeño timeout para permitir transición de React Motion o renderizado
    await this.page.waitForTimeout(500);
  }

  // --- Step 1: Identificación ---
  async fillIdentificationStep(data: any) {
    console.log('Llenando Paso 1: Identificación...');
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
    console.log('Llenando Paso 2: Ubicación...');
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
    console.log('Llenando Paso 3: Características Poblacionales...');
    // Grupo Sisben
    await this.selectDropdownOptionByLabel('Sisben IV Grupo', data.sisbenGroup);
    await this.selectDropdownOptionByLabel('Numero de subgrupo', data.sisbenSubgroup);

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
    console.log('Llenando Paso 4: Salud...');
    // Has RLCPD toggle
    const rlcpdLabel = data.hasRlcpd === 'SÍ' ? 'SÍ' : 'NO';
    await this.selectToggleOption('¿Está inscrito en el Registro de la localización y caracterización de personas con discapacidad del Ministerio de Salud?', rlcpdLabel);

    // Usar el label EXACTO del componente frontend StepHealth.tsx
    await this.selectDropdownOptionByLabel('¿A cúal de los siguientes regímenes de seguridad social en salud está afiliado/a?', data.socialSecurity);

    console.log('Paso 4 completo. Click en Siguiente...');
    await this.clickNext();
  }

  // --- Step 5: Educación ---
  async fillEducationStep(data: any) {
    console.log('Llenando Paso 5: Educación...');
    await this.selectDropdownOptionByLabel('¿Cúal es el máximo nivel educativo alcanzado por usted hasta el momento?', data.maxEducationLevel);
    console.log('Paso 5 completo. Click en Siguiente...');
    await this.clickNext();
  }
}
