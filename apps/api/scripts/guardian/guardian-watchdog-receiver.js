/**
 * Fase 3 — Receptor local del canal de respaldo del watchdog.
 *
 * Servidor HTTP mínimo que simula el canal independiente (webhook) para probar
 * el aviso real del watchdog sin usar WhatsApp, correo ni ningún proveedor
 * externo. Guarda cada aviso recibido en memoria y los expone en `GET /alerts`.
 *
 * Uso:
 *   node scripts/guardian/guardian-watchdog-receiver.js 4501
 *
 * Solo escucha en 127.0.0.1.
 */
const http = require('node:http');

const port = Number.parseInt(process.argv[2] || '4501', 10);
const received = [];

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/alert') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 256 * 1024) req.destroy();
    });
    req.on('end', () => {
      let parsed = null;
      try {
        parsed = JSON.parse(body);
      } catch {
        parsed = { raw: body.slice(0, 500) };
      }
      received.push({ at: new Date().toISOString(), payload: parsed });
      res.writeHead(202, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, stored: received.length }));
    });
    return;
  }

  if (req.method === 'GET' && req.url === '/alerts') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ count: received.length, alerts: received }, null, 2));
    return;
  }

  if (req.method === 'DELETE' && req.url === '/alerts') {
    received.length = 0;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ ok: false, error: 'not_found' }));
});

server.listen(port, '127.0.0.1', () => {
  // eslint-disable-next-line no-console
  console.log(`[watchdog-receiver] escuchando en http://127.0.0.1:${port}/alert`);
});
