# Pruebas web FULLTECH, SRL

Fecha: 2026-07-22

## Ejecutadas

| Prueba | Resultado |
| --- | --- |
| Build de produccion `npm run web:build` | Exitoso |
| Generacion de rutas nuevas en `dist/` | Exitoso: politicas, eliminacion de datos, sobre nosotros y tienda generadas |
| Busqueda de datos antiguos en sitio (`829-477`, `fulltech.com.do`, dominio temporal, `Calle Beller #9`) | Sin coincidencias en `apps/web`; solo permanecen en la auditoria como hallazgo historico |
| Verificacion de enlaces internos HTML | Exitoso: 21 HTML revisados |
| `robots.txt` | Apunta a `https://fulltechrd.com/sitemap.xml` |
| `sitemap.xml` | Incluye dominio oficial y rutas legales principales |
| Tienda/POS | No se cambio el endpoint ni el flujo de carga de productos reales |
| WhatsApp | Telefono actualizado a `18295344286` en configuracion y carrito |
| Headers Nginx | Se agrego CSP moderada y headers de seguridad |

## Observaciones del build

Vite muestra advertencias esperadas sobre `<script src="env.js">` sin `type="module"`. Este archivo se carga asi intencionalmente para permitir configuracion runtime antes de `app.js`.

## No ejecutadas en esta pasada

| Prueba | Motivo |
| --- | --- |
| Lighthouse completo | No se ejecuto herramienta de navegador en esta pasada. |
| Validacion HTML externa | No se uso validador externo. |
| Revisión visual con capturas Playwright | No se ejecuto en esta pasada. |
| Prueba real de envio de formulario | Formulario usa `mailto:PENDIENTE_CONFIGURAR` hasta definir correo real o backend. |
| Prueba de aprobacion Meta | Meta no garantiza aprobacion y no existe prueba automatica local para ello. |

## Pruebas recomendadas post-despliegue

- Abrir `https://fulltechrd.com/`, `https://fulltechrd.com/tienda.html` y todas las politicas desde un telefono.
- Revisar consola del navegador en movil y escritorio.
- Confirmar que DNS de `fulltechrd.com` apunta al servicio correcto.
- Ejecutar Lighthouse en produccion.
- Validar datos estructurados con una herramienta de Schema.org/Google.
