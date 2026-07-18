# FULLTECH Web

Sitio web publico y tienda online de FULLTECH SRL.

Incluye paginas visibles para revision comercial:

- Inicio
- Tienda online
- Servicios
- Nosotros
- Contacto
- Carrito y pedido por WhatsApp
- Politica de privacidad
- Terminos y condiciones
- Politica de envios y entregas
- Politica de devoluciones y reembolsos
- Politica de garantia
- Politica de pagos
- Politica de cookies

## Desarrollo

```bash
npm --workspace apps/web run dev
```

## Produccion

```bash
npm --workspace apps/web run build
```

## Docker / EasyPanel

Usa el repositorio completo como build context y este Dockerfile:

```text
apps/web/Dockerfile
```

Variable recomendada:

```text
FULLTECH_API_BASE_URL=https://TU-DOMINIO-DE-API.com
```

Si la API y la web se sirven bajo el mismo dominio, deja `FULLTECH_API_BASE_URL`
vacia y la tienda consultara `/website/public` en el mismo host.

La pagina `tienda.html` consume `/website/public`, que el backend arma desde el
modulo de productos de FULLTECH. En produccion, configura `FULLTECH_API_BASE_URL`
para apuntar al API que tiene los productos del punto de venta/inventario.

Healthcheck:

```text
/healthz
```
