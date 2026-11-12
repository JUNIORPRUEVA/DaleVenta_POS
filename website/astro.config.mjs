// @ts-check
import { defineConfig } from 'astro/config';

/**
 * Sitio publico estatico de FullPOS Cloud.
 *
 * Dockerfile.public-web publica este sitio en la portada y las rutas publicas.
 * Flutter conserva sus rutas operativas y su shell independiente (pos.html).
 */
export default defineConfig({
  site: 'https://fullposcloud.fulltechrd.com',
  output: 'static',
  build: {
    inlineStylesheets: 'auto',
  },
  compressHTML: true,
});
