# Rotación de credenciales UAT (post-integración)

Durante las sesiones de integración se usaron credenciales **locales de UAT** en
terminales y variables de proceso. Aunque no son productivas, deben rotarse
antes de reutilizar el entorno o de promocionar cualquier valor.

## Qué rotar (solo nombres)

| Credencial | Uso | Acción |
| --- | --- | --- |
| `JWT_SECRET` (API Fullpos UAT) | Firmar tokens de prueba del cliente | Generar uno nuevo y reiniciar la API UAT. |
| `GUARDIAN_PLATFORM_TOKEN` (UAT) | Acceso del proxy Appyra a `/guardian/platform/*` | Emitir valor nuevo, actualizar **solo** el backend de Appyra y Fullpos; nunca en Flutter. |
| `ADMIN_PASSWORD` / `ADMIN_USERNAME` (Appyra UAT) | Login administrativo del panel | Cambiar contraseña, invalidar sesiones. |
| `ADMIN_SESSION_JWT_SECRET` (Appyra UAT) | Firmar sesiones administrativas | Rotar; las sesiones antiguas quedan inválidas. |
| `PG_PASSWORD` (Postgres UAT) | Conexiones locales | Rotar si el entorno se comparte. |
| `GUARDIAN_WA_APP_SECRET` / `GUARDIAN_WA_VERIFY_TOKEN` | Firma/verificación del webhook | Rotar junto con el webhook de Meta cuando exista número real. |
| `GUARDIAN_AI_API_KEY` | Proveedor de IA | Rotar en el gestor de secretos al activarlo. |

## Procedimiento

1. Generar el valor nuevo en el gestor de secretos del entorno UAT.
2. Actualizar las variables del proceso/servicio correspondiente (no del repo).
3. Reiniciar los procesos afectados de forma escalonada.
4. Verificar: login administrativo, `GET /api/admin/guardian/health` y una
   ingesta sintética.
5. Invalidar sesiones y revocar el valor anterior.
6. Registrar fecha y responsable **sin** escribir el valor.

## Reglas

- Nunca committear valores reales; `.env` está ignorado por Git.
- Nunca imprimir tokens, secretos ni cadenas de conexión completas.
- El token de plataforma vive solo en el backend de Appyra y en Fullpos; Flutter
  no lo contiene ni lo recibe.
- `guardian_reader` debe seguir siendo un rol `SELECT` únicamente; su contraseña
  se rota con el mismo procedimiento.
