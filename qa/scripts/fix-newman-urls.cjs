/**
 * Newman 6.x + colecciones exportadas desde Insomnia: URLs como { raw: "{{baseUrl}}/..." }
 * pueden quedar vacías en runtime ("request url is empty"). Normalizar a string URL (v2.1).
 */
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'api', 'collections', 'api.postman_collection.json');
const col = JSON.parse(fs.readFileSync(file, 'utf8'));

function fixUrl(req) {
  if (!req || !req.url || typeof req.url === 'string') return;
  const u = req.url;
  if (typeof u.raw === 'string' && u.raw.length > 0) {
    req.url = u.raw;
  }
}

function walk(items) {
  if (!items) return;
  for (const it of items) {
    if (it.item) walk(it.item);
    if (it.request) fixUrl(it.request);
  }
}

walk(col.item);
fs.writeFileSync(file, JSON.stringify(col, null, 2) + '\n');
console.log('OK:', file);
