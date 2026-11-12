// @ts-check
import { defineConfig } from 'astro/config';

/**
 * Sitio publico estatico de FullPOS Cloud.
 *
 * Nota de convivencia: la web actual (apps/fulltech_app/web) sigue intacta.
 * Este proyecto NO la reemplaza, NO se despliega y NO toca rutas de produccion.
 * El `base` se deja raiz porque cuando se publique tomara el dominio publico.
 */
export default defineConfig({
  site: 'https://fullposcloud.fulltechrd.com',
  output: 'static',
  build: {
    inlineStylesheets: 'auto',
  },
  compressHTML: true,
});
