# Auditoria web Meta y WhatsApp - FULLTECH, SRL

Fecha: 2026-07-22

## Estado actual

El proyecto publico esta en `apps/web` y usa Vite con HTML estatico, CSS y JavaScript modular. La tienda se carga desde el endpoint real del POS/API en `https://fulltech-tienda-fulltechapppwa.gcdndd.easypanel.host/website/public` con fallback local en `data.js`. El despliegue publico usa Docker/Nginx en EasyPanel.

Rutas publicas encontradas: `index.html`, `tienda.html`, `contacto.html`, `nosotros.html`, `servicios.html`, `carrito.html`, `privacidad.html`, `terminos.html`, `garantia.html`, `devoluciones.html`, `envios.html`, `pagos.html`, `cookies.html`, `catalogo.html`.

## Problemas encontrados

| Gravedad | Problema | Archivos afectados | Riesgo |
| --- | --- | --- | --- |
| Critico | Datos de contacto inconsistentes: telefono anterior `829-477-0756`, direccion incompleta y dominio canonico incorrecto `fulltech.com.do`. | `apps/web/*.html`, `apps/web/app.js`, `apps/web/data.js`, `public/sitemap.xml`, `public/robots.txt` | Alto para verificacion de Meta por inconsistencias de identidad. |
| Critico | Faltan rutas legales con nombres solicitados: `politica-de-privacidad.html`, `terminos-y-condiciones.html`, `politica-de-garantia.html`, `politica-de-cambios-y-devoluciones.html`, `politica-de-envios.html`, `sobre-nosotros.html`, `eliminacion-de-datos.html`. | `apps/web` | Medio si se agregan aliases sin tocar rutas existentes. |
| Alto | Politica de privacidad no explica suficientemente uso de WhatsApp, retencion, proveedores, derechos y eliminacion de datos. | `privacidad.html` | Bajo si se amplia contenido estatico. |
| Alto | No existe pagina publica de eliminacion de datos, requerida para integraciones Meta/WhatsApp. | `apps/web` | Bajo si se crea pagina estatica. |
| Alto | Sitemap y robots apuntan al dominio temporal de EasyPanel, no a `https://fulltechrd.com/`. | `apps/web/public/robots.txt`, `apps/web/public/sitemap.xml` | Bajo. |
| Alto | Headers de seguridad Nginx basicos no configurados. | `apps/web/nginx.conf` | Medio por CSP si se hace demasiado estricta. Se recomienda CSP razonable sin romper API/imagenes. |
| Medio | Footer no incluye todos los enlaces legales, redes sociales, horario y dato de eliminacion de datos. | `apps/web/*.html` | Bajo. |
| Medio | Contacto usa `mailto:ventas@fulltech.com.do`, correo no confirmado. | `contacto.html`, `data.js`, `app.js` | Bajo. Se marca como `PENDIENTE_CONFIGURAR` hasta tener correo real. |
| Medio | Falta metadato Open Graph/Twitter completo y Schema.org consistente en todas las paginas. | `apps/web/*.html` | Bajo. |
| Medio | Formularios no muestran consentimiento claro para contacto por WhatsApp y comunicaciones comerciales separadas. | `contacto.html` | Bajo. |
| Bajo | Textos con acentos omitidos por codificacion ASCII. No bloquea, pero reduce calidad percibida. | `apps/web/*.html` | Bajo. Se mantiene ASCII por consistencia tecnica actual. |
| Bajo | Catalogo contiene productos de seguridad. Deben describirse siempre para usos legitimos: hogares, comercios, supervision autorizada y control de acceso. | `tienda.html`, API POS | Medio: revisar nombres/descripciones en POS de forma continua. |

## Cambios recomendados

1. Centralizar datos de empresa en JavaScript y HTML estatico: FULLTECH, SRL, FullTech, `https://fulltechrd.com/`, telefono `+1 829-534-4286`, direccion completa y horario.
2. Crear paginas legales completas y aliases con nombres limpios.
3. Actualizar footer global con enlaces legales, redes sociales y contacto.
4. Actualizar robots, sitemap, canonical, Open Graph, Twitter Cards y Schema.org.
5. Mantener la tienda dinamica conectada al POS, sin alterar endpoint ni carrito WhatsApp.
6. Agregar pagina de eliminacion de datos con formulario estatico y aviso de privacidad.
7. Agregar consentimiento de contacto por WhatsApp en formularios.
8. Configurar headers de seguridad en Nginx sin incluir secretos en frontend.
9. Documentar pendientes manuales: correo empresarial real, revision legal profesional y verificacion de datos en Meta Business.

## Riesgo de romper funcionalidades

Riesgo bajo si los cambios se limitan a `apps/web`, mantienen `app.js` compatible con el endpoint POS, no eliminan rutas existentes y se agregan aliases en lugar de renombrar de forma destructiva. El principal riesgo tecnico es una CSP demasiado restrictiva; por eso se aplicara una politica moderada que permita `self`, HTTPS, imagenes externas y API actual.

## Plan de implementacion

1. Actualizar datos empresariales y rutas de contacto.
2. Crear/renovar paginas legales publicas y aliases.
3. Actualizar footer, metadatos, schema, sitemap y robots.
4. Fortalecer Nginx con headers seguros.
5. Crear documentos de Meta/WhatsApp y pruebas.
6. Ejecutar build, revisar enlaces, verificar rutas publicas y desplegar en EasyPanel.

## Notas pendientes

- Correo empresarial real pendiente: se usara `PENDIENTE_CONFIGURAR` como marcador tecnico hasta que FULLTECH confirme un correo oficial.
- RNC y registro mercantil no fueron provistos; no se inventan.
- Se recomienda revision legal profesional de politicas antes de uso definitivo.
- No se garantiza aprobacion de Meta; el objetivo es mejorar claridad, transparencia y verificabilidad.
