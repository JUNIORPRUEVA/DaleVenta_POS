# Cambios realizados - FULLTECH, SRL

Fecha: 2026-07-22

## Identidad y contacto

- Se unifico el nombre visible a `FULLTECH, SRL`.
- Se actualizo telefono y WhatsApp a `+1 829-534-4286`.
- Se actualizo direccion publica: Calle Beller num. 9, centro de Higuey, detras del Banco BHD principal, Higuey, La Altagracia, Republica Dominicana.
- Se actualizo horario: lunes a sabado de 9:00 a.m. a 6:00 p.m.
- Se agregaron enlaces de Facebook e Instagram en footer.
- Correo queda marcado como `PENDIENTE_CONFIGURAR` para no inventar un dato no confirmado.

## Paginas publicas y legales

- Se crearon rutas nuevas:
  - `sobre-nosotros.html`
  - `politica-de-privacidad.html`
  - `terminos-y-condiciones.html`
  - `politica-de-garantia.html`
  - `politica-de-cambios-y-devoluciones.html`
  - `politica-de-envios.html`
  - `eliminacion-de-datos.html`
- Se mantuvieron rutas antiguas como compatibilidad: `nosotros.html`, `privacidad.html`, `terminos.html`, `garantia.html`, `devoluciones.html`, `envios.html`.
- Se amplio el footer global con politicas, contacto, horario, redes y eliminacion de datos.

## Meta, WhatsApp y formularios

- La politica de privacidad incluye seccion especifica de uso de WhatsApp.
- La pagina de eliminacion de datos explica proceso, verificacion, plazos y datos que podrian conservarse.
- El formulario de contacto incluye consentimiento obligatorio para responder solicitudes por llamada, correo o WhatsApp.
- El consentimiento comercial por WhatsApp queda separado y no marcado automaticamente.
- Se agrego campo honeypot anti-spam en formularios estaticos.

## SEO y seguridad

- Se actualizo `robots.txt` para `https://fulltechrd.com/sitemap.xml`.
- Se reemplazo `sitemap.xml` con rutas publicas principales del dominio oficial.
- Se agregaron canonical, Open Graph y Twitter Card en paginas principales y legales nuevas.
- Se agrego Schema.org en la pagina principal para Organization, Store, LocalBusiness y WebSite.
- Se fortalecio Nginx con CSP moderada, X-Content-Type-Options, X-Frame-Options, Referrer-Policy y Permissions-Policy.

## Tienda

- Se mantuvo la tienda conectada al POS/API real.
- No se altero el carrito ni el flujo de pedido por WhatsApp.
- Se agregaron metadatos sociales y canonical a `tienda.html`.
