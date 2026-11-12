/* Servidor estático LOCAL con fallback SPA para validar Flutter Web.
   - Solo escucha en 127.0.0.1:4400.
   - Sirve apps/fulltech_app/build/web.
   - Cualquier ruta sin archivo devuelve index.html (comportamiento real de
     un hosting SPA), para que recargar /onboarding no dé 404.
   Archivo temporal de QA: se elimina al terminar. */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(
  'c:/Users/pc/DEV/PROYECTOS/PRODUCTOS/finalesdaleventas/apps/fulltech_app/build/web',
);
const PORT = 4400;
const HOST = '127.0.0.1';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.wasm': 'application/wasm',
  '.bin': 'application/octet-stream',
  '.map': 'application/json; charset=utf-8',
  '.env': 'text/plain; charset=utf-8',
};

function send(res, filePath) {
  const ext = path.extname(filePath).toLowerCase();
  res.writeHead(200, {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Cache-Control': 'no-store',
  });
  fs.createReadStream(filePath).pipe(res);
}

http
  .createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
    const candidate = path.join(ROOT, urlPath);

    // Bloquea cualquier intento de salir del directorio del build.
    if (!candidate.startsWith(ROOT)) {
      res.writeHead(403).end('forbidden');
      return;
    }

    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      send(res, candidate);
      return;
    }
    if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      const index = path.join(candidate, 'index.html');
      if (fs.existsSync(index)) {
        send(res, index);
        return;
      }
    }
    send(res, path.join(ROOT, 'index.html'));
  })
  .listen(PORT, HOST, () => {
    console.log(`SPA server for Flutter Web: http://${HOST}:${PORT}/ (root: ${ROOT})`);
  });
