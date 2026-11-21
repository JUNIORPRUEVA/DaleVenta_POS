// Loopback-only, simulated Flutter preview. No API or private file proxy.
const http = require('node:http'), fs = require('node:fs/promises'), path = require('node:path');
const base = path.resolve(__dirname, '../../.uat/plans-payment/design-web');
const types = {'.html':'text/html', '.js':'application/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.svg':'image/svg+xml', '.ttf':'font/ttf', '.woff2':'font/woff2'};
http.createServer(async (req, res) => {
  if (req.headers.host !== '127.0.0.1:4495') { res.writeHead(403); res.end(); return; }
  try {
    const url = new URL(req.url, 'http://127.0.0.1:4495');
    res.setHeader('cache-control', 'no-store');
    if (url.pathname === '/') {
      res.setHeader('content-type', 'text/html');
      res.end('<!doctype html><html lang="es"><head><base href="/"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FullPOS · Planes de demostración</title></head><body><script src="flutter_bootstrap.js" async></script></body></html>');
      return;
    }
    const file = path.resolve(base, '.' + path.sep + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname).replace(/^[/\\]+/, ''));
    if (!file.startsWith(base + path.sep)) throw Error('Invalid path');
    res.setHeader('cache-control', 'no-store');
    res.setHeader('content-type', types[path.extname(file)] || 'application/octet-stream');
    const content = await fs.readFile(file);
    res.end(url.pathname === '/flutter_bootstrap.js'
      ? content.toString().replace('_flutter.loader.load({', '_flutter.loader.load({config: {canvasKitBaseUrl: "/canvaskit/"},')
      : content);
  } catch (_) { res.writeHead(404); res.end('Unavailable'); }
}).listen(4495, '127.0.0.1', () => console.log('Plans preview: http://127.0.0.1:4495/#/planes/catalogo'));
