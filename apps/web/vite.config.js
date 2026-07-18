import { resolve } from "node:path";
import { defineConfig } from "vite";

const pages = [
  "index",
  "tienda",
  "catalogo",
  "carrito",
  "servicios",
  "nosotros",
  "contacto",
  "privacidad",
  "terminos",
  "envios",
  "devoluciones",
  "garantia",
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
