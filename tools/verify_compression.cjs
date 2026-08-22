/* Verificación local de la configuración de compresión usada en main.ts.
 * Servidor Express mínimo que replica EXACTAMENTE el bloque de compression. */
const express = require('express');
const compression = require('compression');

const app = express();
app.use(
  compression({
    threshold: 1024,
    filter: (req, res) => {
      const type = res.getHeader('Content-Type');
      if (typeof type !== 'string') return false;
      return /(json|text|javascript|xml|svg)/i.test(type);
    },
  }),
);

app.get('/json', (_req, res) => {
  const big = [];
  for (let i = 0; i < 3000; i++) {
    big.push({ id: i, nombre: `Producto ${i}`, precio: 100 + i, stock: 5, codigo: `SKU-${i}` });
  }
  res.json(big);
});
app.get('/small', (_req, res) => res.json({ status: 'ok' }));
app.get('/image', (_req, res) => {
  const buf = Buffer.alloc(50000, 7);
  res.setHeader('Content-Type', 'image/png');
  res.send(buf);
});
app.get('/pdf', (_req, res) => {
  const buf = Buffer.alloc(50000, 9);
  res.setHeader('Content-Type', 'application/pdf');
  res.send(buf);
});

app.listen(4173, () => console.log('compression-test listening on 4173'));
