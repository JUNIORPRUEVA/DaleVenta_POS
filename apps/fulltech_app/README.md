# FullTech App (Flutter + PWA)

App mobile-first (Android/iOS) y Web (PWA) consumiendo un backend cloud.

## Requisitos

- Flutter 3.x

## Variables de entorno

La app carga configuración desde `apps/fulltech_app/.env` (ver `.env.example`).

- `API_BASE_URL` (ej: `https://api.midominio.com`)
- `API_TIMEOUT_MS` (opcional)

## Ejecutar

Desde `apps/fulltech_app/`:

- Web: `flutter run -d chrome`
- Android: `flutter run -d android`
- iOS: `flutter run -d ios`

## Build PWA (Web Release)

Desde `apps/fulltech_app/`:

- Generar build instalable (PWA): `flutter build web --release`

Salida: `apps/fulltech_app/build/web/` (incluye `manifest.json` y `flutter_service_worker.js`).

### Comportamiento PWA reforzado

- La shell web ahora muestra sugerencia de instalacion cuando el navegador expone `beforeinstallprompt`.
- En iPhone/iPad Safari, la app muestra una guia breve para `Anadir a pantalla de inicio`, donde Apple no expone ese evento.
- Si el service worker detecta una version nueva, la PWA avisa y permite recargar para evitar que los usuarios sigan con shell vieja.
- `manifest.json` queda preparado con `id`, `scope`, `display_override`, colores y accesos rapidos para que la instalacion sea mas consistente.

### Hosting

- La PWA requiere servir por **HTTPS** (excepto `localhost`).
- Si sirves la app bajo un sub-path (ej. `/fulltech/`), usa: `flutter build web --release --base-href /fulltech/`
- Si tu hosting es “static only”, el modo por defecto con hash URLs evita configuraciones extra para refresh.

## Deploy en EasyPanel (desde Git + Dockerfile)

Esta app incluye un Dockerfile listo para EasyPanel que:
- Compila Flutter Web en modo release.
- Sirve `build/web` con Nginx.

Archivos:
- `apps/fulltech_app/Dockerfile`
- `apps/fulltech_app/nginx.conf`

Pasos (resumen):
1) Sube el repo a Git (GitHub/GitLab).
2) En EasyPanel crea una nueva App desde Git.
3) Selecciona:
	- Build context: `apps/fulltech_app`
	- Dockerfile: `Dockerfile`
	- Puerto: `80`
4) Asigna el dominio genérico de EasyPanel y despliega.

Nota de configuración:
- En **Web/PWA**, EasyPanel debe inyectar `API_BASE_URL` como variable de entorno del contenedor.
- El contenedor genera `/env.js` al arrancar (no queda cacheado por el service worker) y la app lo lee en runtime.
- `.env` (asset) sigue existiendo como fallback, pero para cloud lo ideal es **no depender** de editar `.env.example`.

Variables a definir en EasyPanel (Runtime Env):
- `API_BASE_URL` (ej: `https://tu-api.tudominio.com`)
- `API_TIMEOUT_MS` (opcional)
- `SUPPORT_EMAIL` (opcional, usado por `/support`, `/privacy`, `/account-deletion` y `/contact`)
- `SUPPORT_PHONE` (opcional)
- `SUPPORT_WHATSAPP` (opcional, en formato internacional sin `+`, ej. `18295319442`)
- `SUPPORT_HOURS` (opcional)

### Recomendado (PWA): Proxy same-origin (evita CORS/XHR)

En algunos hosting/proxies el navegador puede reportar errores tipo `XMLHttpRequest onError` aunque el backend responda.
La forma más estable de evitarlo es servir la API como **misma** origin que la PWA usando un proxy en Nginx.

Configura en EasyPanel (PWA container):
- `API_BASE_URL=/api`
- `API_UPSTREAM_URL=https://tu-api.tudominio.com`

Esto hace que la app llame a `https://TU_PWA_DOMINIO/api/...` y Nginx lo redirija al backend.

El proxy web tambien debe aceptar archivos grandes y reenviar `/uploads/*` al backend para que las evidencias subidas desde la PWA se vean correctamente con URLs same-origin.

Nota:
- `API_BASE_URL=/api` es solo para **Web/PWA** detrás del Nginx del contenedor. En Android/iOS debe ser una URL absoluta (ej: `https://tu-api.tudominio.com`).

### Uploads (evidencias) en Web: CORS del bucket
Cuando la app usa el flujo de evidencias con presigned URLs (`/storage/presign` → PUT directo a R2 → `/storage/confirm`), el PUT lo hace el navegador contra el dominio del bucket.

Si ves errores tipo `DioException [connection error] ... XMLHttpRequest onError`, además de revisar `API_BASE_URL` y HTTPS, verifica el CORS del bucket (permitir el origen de la PWA, método `PUT` y header `Content-Type`).

## Arquitectura

- `lib/core/`: api, auth storage, routing, theme, widgets, errors
- `lib/features/`: auth, splash, home, user, ponche, operaciones, ventas, contabilidad

## Backend contract

Endpoints centralizados en `lib/core/api/api_routes.dart` para ajustar rápido si tu backend difiere.

