# APPYRA Guardian AI — Rotación de secretos

Procedimiento operativo para rotar las credenciales de Guardian **sin exponerlas** en
logs, reportes, commits ni canales de chat. Aplica a UAT y, con autorización explícita,
a producción.

## 1. Inventario de secretos

| Secreto | Dónde vive | Quién lo usa | Rotable sin downtime |
| --- | --- | --- | --- |
| `GUARDIAN_PLATFORM_TOKEN` | Entorno del API + entorno del backend de Appyra | Canal de plataforma (proxy) | Sí, con doble token de transición¹ |
| `GUARDIAN_READER_DATABASE_URL` | Entorno del API (herramientas IA) | Consultas de solo lectura | Sí |
| `OPENAI_API_KEY` | Entorno del API | Proveedor IA | Sí |
| `GUARDIAN_WA_CLOUD_TOKEN` | Entorno de los workers | WhatsApp Cloud API | Sí, el token anterior sigue válido hasta revocarlo |
| `GUARDIAN_WA_APP_SECRET` | Entorno del API | Firma del webhook | Sí, pero invalida webhooks firmados con el anterior |
| `GUARDIAN_WA_VERIFY_TOKEN` | Entorno del API + consola de Meta | Verificación del webhook | Sí |
| `GUARDIAN_WATCHDOG_WEBHOOK_TOKEN` | Entorno del watchdog y del receptor | Avisos del watchdog | Sí |
| `JWT_SECRET` | Entorno del API | Sesiones de clientes | **No** — rota en ventana de mantenimiento |
| `ADMIN_PASSWORD` (Appyra) | Entorno del backend de Appyra | Login del panel | Sí |

¹ Doble token: el guard compara contra un único valor, por lo que la rotación corta
el panel durante el tiempo entre el cambio en el API y el cambio en Appyra. Ejecutar
ambos reinicios seguidos y verificar con el comando de §4.

## 2. Comprobaciones previas (obligatorias)

```powershell
# 1. Ningun secreto real debe estar rastreado por git (solo se listan rutas).
git ls-files | Select-String -Pattern '(^|/)\.env($|\.)'      # solo *.example
git grep -l -I -E "(GUARDIAN_PLATFORM_TOKEN|OPENAI_API_KEY|WA_CLOUD_TOKEN)=[^'`"$<{ ]"

# 2. El .gitignore cubre .env reales.
Select-String -Path .gitignore -Pattern '\.env'
```

Si el paso 1 devuelve un archivo que no sea `*.example`, **detener**: el secreto está
comprometido y debe rotarse antes de continuar (el historial de git conserva el valor).

## 3. Procedimiento de rotación (UAT)

1. Generar el nuevo valor fuera del repositorio:

   ```powershell
   # 32 bytes en base64url, sin caracteres problematicos
   [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
   ```

2. Guardarlo en el gestor de secretos del entorno (nunca en un archivo del repositorio).
3. Actualizar la variable en el proceso consumidor.
4. Reiniciar solo el proceso afectado:
   - `GUARDIAN_PLATFORM_TOKEN` → reiniciar API **y** backend de Appyra.
   - `GUARDIAN_READER_DATABASE_URL` → reiniciar API (los workers lo leen al arrancar).
   - Credenciales de WhatsApp / IA → reiniciar `guardian:workers` y el API.
   - `GUARDIAN_WATCHDOG_WEBHOOK_TOKEN` → reiniciar el watchdog y su receptor.
5. Revocar el valor anterior en el proveedor cuando el nuevo esté verificado.

### Rotación del rol PostgreSQL de lectura

```sql
-- El rol no puede escribir: la rotacion no afecta datos.
ALTER ROLE guardian_reader WITH PASSWORD '<nueva-clave>';
```

Después de rotar, verificar de nuevo que sigue siendo de solo lectura (§4).

## 4. Verificación posterior

```powershell
# Canal de plataforma operativo con el token nuevo
$h = @{ 'x-guardian-platform-token' = $env:GUARDIAN_PLATFORM_TOKEN }
(Invoke-WebRequest -Uri 'http://127.0.0.1:4010/guardian/platform/health' -Headers $h).StatusCode   # 200

# Token viejo rechazado
$hOld = @{ 'x-guardian-platform-token' = '<token-anterior>' }
# Debe devolver 401

# El rol de lectura sigue sin permisos de escritura (debe fallar con 42501)
# INSERT/UPDATE/DELETE sobre guardian_incidents con guardian_reader → error 42501

# El watchdog sigue avisando por su canal
npm --workspace apps/api run guardian:watchdog
```

## 5. Registro de rotación

Mantener un registro con: fecha, secreto rotado (por nombre), responsable, ventana de
cambio y resultado de la verificación. **Nunca** registrar el valor.

## 6. Riesgos conocidos

- `GUARDIAN_READER_DATABASE_URL` y `GUARDIAN_PLATFORM_TOKEN` viajan en variables de
  entorno: cualquier proceso con acceso al entorno del host puede leerlas. Mitigación:
  usuario de sistema dedicado por servicio y permisos mínimos sobre el archivo de entorno.
- No hay rotación automática programada: depende de este procedimiento manual.
- `guardian_reader` es un rol compartido por todas las empresas: su compromiso expone
  datos de lectura de todo el inquilino. Mitigación propuesta: un rol por entorno.
