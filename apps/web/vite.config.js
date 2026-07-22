import { resolve } from "node:path";
import { defineConfig } from "vite";

const pages = [
  "index",
  "tienda",
  "catalogo",
  "carrito",
  "servicios",
  "nosotros",
  "sobre-nosotros",
  "contacto",
  "privacidad",
  "politica-de-privacidad",
  "terminos",
  "terminos-y-condiciones",
  "envios",
  "politica-de-envios",
  "devoluciones",
  "politica-de-cambios-y-devoluciones",
  "garantia",
  "politica-de-garantia",
  "eliminacion-de-datos",
  "pagos",
  "cookies"
];

export default defineConfig({
  build: {
    rollupOptions: {
      input: Object.fromEntries(
        pages.map((page) => [page, resolve(__dirname, `${page}.html`)])
      )
    }
  }
});
