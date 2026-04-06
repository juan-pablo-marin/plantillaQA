/**
 * Convierte export Insomnia REST 5 (YAML) → Postman Collection v2.1 JSON.
 * Uso: node scripts/insomnia-to-postman.cjs <entrada.yaml> <salida.json>
 */
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const inputPath = process.argv[2] || path.join(process.env.USERPROFILE || '', 'Desktop', 'Insomnia_2026-04-05.yaml');
const outputPath = process.argv[3] || path.join(__dirname, '..', 'api', 'collections', 'api.postman_collection.json');

function insomniaUrlToPath(url) {
  if (!url) return '';
  return url
    .replace(/\{\{\s*_\s*\.\s*base_url\s*\}\}/gi, '{{baseUrl}}/api/v1')
    .replace(/\{\{\s*_\s*\.\s*token\s*\}\}/gi, '{{token}}');
}

function buildQuery(params) {
  if (!params || !params.length) return '';
  const parts = [];
  for (const p of params) {
    if (p.disabled === true) continue;
    parts.push(`${encodeURIComponent(p.name)}=${encodeURIComponent(String(p.value ?? ''))}`);
  }
  return parts.length ? `?${parts.join('&')}` : '';
}

function requestToItem(req) {
  const rawUrl = insomniaUrlToPath(req.url) + buildQuery(req.parameters);
  const item = {
    name: req.name,
    request: {
      method: (req.method || 'GET').toUpperCase(),
      header: [],
      url: { raw: rawUrl },
    },
  };

  if (req.authentication && req.authentication.type === 'bearer') {
    item.request.auth = {
      type: 'bearer',
      bearer: [{ key: 'token', value: '{{token}}', type: 'string' }],
    };
  }

  if (req.headers) {
    for (const h of req.headers) {
      if (h.disabled) continue;
      item.request.header.push({ key: h.name, value: h.value, type: 'text' });
    }
  }

  if (req.body) {
    const mime = req.body.mimeType || '';
    if (mime.includes('json') && req.body.text != null) {
      item.request.body = { mode: 'raw', raw: req.body.text };
      if (!item.request.header.some((h) => h.key.toLowerCase() === 'content-type')) {
        item.request.header.push({ key: 'Content-Type', value: 'application/json', type: 'text' });
      }
    } else if (mime.includes('multipart') && req.body.params) {
      item.request.body = {
        mode: 'formdata',
        formdata: req.body.params.map((p) => {
          if (p.type === 'file') {
            return {
              key: p.name,
              type: 'file',
              src: [],
              disabled: true,
              description: 'Deshabilitado en CI/Newman; subir archivo manualmente en Postman/Insomnia.',
            };
          }
          return { key: p.name, type: 'text', value: String(p.value ?? '') };
        }),
      };
    }
  }

  return item;
}

function folderItems(folder) {
  const out = [];
  for (const child of folder.children || []) {
    if (child.method) {
      out.push(requestToItem(child));
    }
  }
  return out;
}

const raw = fs.readFileSync(inputPath, 'utf8');
const doc = yaml.load(raw);

const collection = {
  info: {
    name: doc.name || 'Victims Backend API',
    description:
      'Exportado desde Insomnia (YAML). Variables de entorno Newman: baseUrl (p. ej. http://backend:8082), token (JWT). Rutas bajo /api/v1.',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    _postman_id: 'rav-victims-backend-insomnia',
  },
  item: [
    {
      name: '00 — Smoke',
      item: [
        {
          name: 'GET / — servidor activo',
          request: { method: 'GET', header: [], url: { raw: '{{baseUrl}}/' } },
          event: [
            {
              listen: 'test',
              script: {
                type: 'text/javascript',
                exec: [
                  "pm.test('Servidor responde (404 o 200 en raíz)', function () {",
                  '    pm.expect(pm.response.code).to.be.oneOf([404, 200]);',
                  '});',
                ],
              },
            },
          ],
        },
      ],
    },
  ],
  variable: [
    { key: 'baseUrl', value: 'http://backend:8082' },
    { key: 'token', value: '' },
  ],
};

for (const folder of doc.collection || []) {
  const items = folderItems(folder);
  if (items.length) {
    collection.item.push({
      name: folder.name,
      item: items,
    });
  }
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(collection, null, 2), 'utf8');
console.log('OK:', outputPath, 'carpetas:', collection.item.length);
