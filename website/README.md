# FullPOS Cloud — sitio público Astro

Sitio estático publicado junto al POS Flutter mediante `Dockerfile.public-web`,
con contexto de build en la raíz del repositorio. Node 22+ y npm se necesitan
solo para construir y verificar; Nginx sirve los archivos de la imagen final.

## Desarrollo y validación

Desde `website`:

```sh
npm ci
npm test
npm run check
npm run build
npm run preview
```

`preview` sirve solo Astro. Para API y Flutter juntos, usar la imagen combinada
con un backend local aislado. La comprobación siguiente crea una cuenta ficticia
y rechaza destinos que no sean localhost:

```sh
PUBLIC_WEB_TEST_URL=http://127.0.0.1:4016 node tests/public-web-smoke.mjs
```

## Navegación y registro

- Astro: portada, login, registro, negocio, preparando, bienvenida, recuperar,
  precios, funciones, descargas, soporte y páginas legales.
- Flutter conserva `/home`, rutas del POS, `/reset-password`, `/ecf` y el portal
  de certificación. Su shell se conserva como `pos.html`.
- Los formularios usan `/api` y el proxy existente.
- `PUBLIC_APP_URL` se compila como `/home`: nunca enviar el ticket a la portada.
  `PUBLIC_API_BASE_URL` también es configuración de build, no de runtime.
- Paso 1: nombre, correo y contraseña; borrador temporal por pestaña.
- Paso 2: negocio, nicho y WhatsApp. **Finalizar** crea cuenta y empresa juntas.
  El primer paso todavía no crea una cuenta persistente.
- Un ticket de un solo uso (dos minutos) traspasa la sesión. Flutter lo consume
  antes de iniciar y lo elimina de la URL.
- Flutter abre la bienvenida nueva y el panel «Activa tu FullPOS». Los datos de
  empresa, impuestos, logo y e-CF se completan en las pantallas reales enlazadas
  desde ese panel; `/onboarding` antiguo redirige al POS. El estado legacy del
  backend se conserva para clientes anteriores y no decide el progreso nuevo.
- Registro y login generan el ticket desde el formulario y abren Flutter
  directamente, con el mismo logo de carga; `/preparando` queda como ruta de
  compatibilidad. `/bienvenida` permite revisar el perfil si se abre explícitamente.
- El selector de negocio es un diálogo centrado con buscador y opciones por
  teclado. Las transiciones respetan la preferencia de movimiento reducido.
- Las cuentas antiguas con empresa activa pueden acceder aunque no tengan las
  membresías nuevas. El cliente actual no tiene selector de empresa: si falta
  empresa activa, muestra soporte en lugar de abrir una sesión incompleta.

## Publicación

Seguir `docs/RELEASE.md`, sección Astro + POS. No cambiar el contexto de
EasyPanel a `website`: perdería las rutas de Flutter y el proxy.
El Dockerfile anterior de Flutter continúa disponible para sus consumidores.

## Dependencias

Se conserva Astro 5.18.2 del lockfile. `npm audit` informa cinco dependencias
afectadas, incluida una crítica en Astro, y propone una actualización mayor.
La imagen final no ejecuta Astro/Node ni usa SSR, server islands, transformación
de imágenes solicitada por usuarios, MDX/JSX o `define:vars`. Genera contenido
versionado y lo sirve con Nginx. La actualización mayor requiere una revisión
separada de compatibilidad y seguridad; no ejecutar automáticamente
`npm audit fix --force`.
