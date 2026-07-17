# FULLTECH Web

Sitio web publico y tienda online de FULLTECH SRL.

Incluye paginas visibles para revision comercial:

- Inicio
- Catalogo
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

Healthcheck:

```text
/healthz
```
