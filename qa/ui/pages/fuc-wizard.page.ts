import { Page, expect } from '@playwright/test';

export class FucWizardPage {
  constructor(private readonly page: Page) {}

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
    await this.page.waitForTimeout(200);
    
    let dropdown = null;
    
    // Estrategia 1: Buscar por label directo
    try {
      const labelLoc = this.page.locator('label').filter({ hasText: new RegExp(label.substring(0, 20), 'i') }).first();
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
    
    // Estrategia 2: Buscar por combobox role
    if (!dropdown) {
      try {
        dropdown = this.page.getByRole('combobox', { name: new RegExp(label.substring(0, 20), 'i') }).first();
        if (await dropdown.isVisible({ timeout: 1500 })) {
          console.log(`Dropdown encontrado por role`);
        } else {
          dropdown = null;
        }
      } catch (e) {
        console.log(`Estrategia role falló`);
      }
    }
    
    // Estrategia 3: Buscar cualquier combobox visible
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
    
    // Hacer scroll y clic
    await dropdown.scrollIntoViewIfNeeded();
    await this.page.waitForTimeout(300);
    
    try {
      await dropdown.click({ force: true, timeout: 10000 });
    } catch (e) {
      console.log(`Clic falló, reintentando...`);
      await this.page.waitForTimeout(500);
      await dropdown.click({ force: true });
    }
    
    await this.page.waitForTimeout(300);
    
    // Buscar opción sin anclas estrictas para evitar problemas de espaciado DOM
    const option = this.page.getByRole('option', { name: new RegExp(optionText, 'i') }).first();
    try {
      await option.waitFor({ state: 'visible', timeout: 8000 });
      await option.click({ force: true });
      console.log(`Opción "${optionText}" seleccionada`);
    } catch (e) {
      // Fallback: búsqueda parcial
      const optPart = this.page.getByRole('option', { name: new RegExp(optionText.split(' ')[0], 'i') }).first();
      await optPart.waitFor({ state: 'visible', timeout: 5000 });
      await optPart.click({ force: true });
      console.log(`Opción (parcial) "${optionText}" seleccionada`);
    }
  }

  // Helper para selectores "Searchable" como municipios
  async searchAndSelectDropdownOption(label: string, searchText: string, optionTextToClick: string) {
    console.log(`Buscando en ${label}: ${searchText}`);
    
    // Desabilitar widget de accesibilidad antes de interactuar
    await this.disableAccessibilityWidget();
    await this.page.waitForTimeout(200);
    
    const container = this.page.locator('label').filter({ hasText: label }).locator('..');
    const combobox = container.locator('[role="combobox"]');
    
    // Hacer scroll y esperar visibilidad
    await combobox.scrollIntoViewIfNeeded();
    await this.page.waitForTimeout(300);
    
    // Hacer clic para abrir
    try {
      await combobox.click({ force: true, timeout: 8000 });
    } catch (e) {
      console.log(`Clic inicial falló`);  
      await this.page.waitForTimeout(500);
      await combobox.click({ force: true });
    }
    
    await this.page.waitForTimeout(400);
    
    // Intente escribir en el search input (que puede estar en un portal)
    const query = searchText.includes(',') ? searchText.split(',')[0].trim() : searchText;
    
    try {
      let inputLoc = combobox.locator('input').first();
      try {
        await inputLoc.waitFor({ state: 'visible', timeout: 1000 });
      } catch (e) {
        // En lugar de .last(), le pedimos a Playwright que espere a que cualquier input portalled sea visible
        inputLoc = this.page.locator('[cmdk-input], [role="dialog"] input, .popover input, [role="listbox"] input');
        // Buscamos cuál de todos es el que realmente está visible actualmente en el DOM tras la apertura
        let visibleFound = false;
        for (let i = 0; i < 5; i++) {
          const count = await inputLoc.count();
          for (let j = 0; j < count; j++) {
            if (await inputLoc.nth(j).isVisible()) {
              inputLoc = inputLoc.nth(j);
              visibleFound = true;
              break;
            }
          }
          if (visibleFound) break;
          await this.page.waitForTimeout(500); // 5 retries of 500ms = 2.5s anidado
        }
      }
      
      try {
        await inputLoc.waitFor({ state: 'visible', timeout: 1500 });
        await inputLoc.fill('', { force: true });
        await inputLoc.fill(query);
        console.log(`Input portal rellenado: ${query}`);
      } catch (e) {
        // Si no se encuentra input visualmente, emitir teclas nativas asumiendo que tiene autofocus
        console.log(`No se halló input visible tras esperar. Emitiendo teclas al aire...`);
        await this.page.keyboard.type(query, { delay: 50 });
      }
      
      // Aumentamos a 1500ms para permitir debounce de la API de lista de ciudades
      await this.page.waitForTimeout(1500);
    } catch (e) {
      console.log(`Excepción al escribir. Fallback de teclado nativo...`);
      await this.page.keyboard.type(query, { delay: 50 });
      await this.page.waitForTimeout(1500);
    }
    
    // Buscar y seleccionar la opción exacta
    try {
      // Remover anclas '^' para evitar fallos por espacios en blanco o DOM nodes extra
      const option = this.page.getByRole('option', { name: new RegExp(optionTextToClick, 'i') }).first();
      await option.waitFor({ state: 'visible', timeout: 6000 });
      await option.click({ force: true });
      console.log(`Opción seleccionada: ${optionTextToClick}`);
      return;
    } catch (e) {
      console.log(`No encontrada opción exacta, buscando por primer match`);
    }
    
    // Fallback: clic en la primera opción disponible
    try {
      const firstOption = this.page.getByRole('option').first();
      await firstOption.waitFor({ state: 'visible', timeout: 6000 });
      await firstOption.click({ force: true });
      console.log(`Primera opción seleccionada como fallback`);
    } catch (err) {
      console.log(`Ninguna opción disponible`);
      throw new Error(`No se pudo seleccionar opción para: ${label}`);
    }
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

    // Usar una parte única de la pregunta para evitar fallos por prefijos largos
    await this.selectDropdownOptionByLabel('regímenes de seguridad social en salud está afiliado/a', data.socialSecurity);

    console.log('Paso 4 completo. Click en Siguiente...');
    await this.clickNext();
  }

  // --- Step 5: Educación ---
  async fillEducationStep(data: any) {
    console.log('Llenando Paso 5: Educación...');
    await this.selectDropdownOptionByLabel('máximo nivel educativo alcanzado por usted', data.maxEducationLevel);
    console.log('Paso 5 completo. Click en Siguiente...');
    await this.clickNext();
  }
}
