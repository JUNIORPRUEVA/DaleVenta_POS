# DOSA — entorno UAT local aislado

Estado: **preparado el 2026-11-04**. No se hicieron llamadas a DOSA, no se creó
ninguna postulación, no se emitió ningún comprobante y no se tocó producción ni
el Intento 1.

Este documento no contiene valores de credenciales. Los secretos viven solo en
archivos locales ignorados por Git, con ACL restringida al usuario de Windows.

## 1. Base de datos independiente

| Dato | Valor |
| --- | --- |
| Contenedor | `fullpos_ecf_dosa_uat_pg` |
| Volumen | `fullpos_ecf_dosa_uat_data` |
| Imagen | `postgres:17-alpine` |
| Host/puerto | `127.0.0.1:56560` |
| Base | `daleventa_uat_local` |
| Usuario | `fullpos_uat_user` |
| Migraciones aplicadas | **72** |
| Datos de empresas | **0** |
| Sesiones DOSA | **0** |
| Filas con RNC `133306001` | **0** |
| Filas con RNC `133080206` | **0** |

El contenedor está separado de `finanza-postgres` (55432),
`daleventas_uat_postgres` (55433), `fullpos_alanube_uat_postgres` (56550) y
cualquier base de producción.

### Migraciones relevantes

Además de las 72 migraciones existentes, este entorno incluye:

- `20261102120000_ecf_dosa_certification_sessions`
- `20261102180000_ecf_dosa_webhook_events`
- `20261103090000_ecf_dosa_company_credentials`
- `20261103150000_ecf_provider_dosa`
- `20261103200000_ecf_dosa_webhook_processing_state`
- `20261103210000_ecf_certification_portal`
- `20261104120000_ecf_intent_provider_reconciliation`
- `20261104120100_ecf_intent_provider_reconciliation_unique`
- `20261104180000_ecf_dosa_session_emission`
- `20261104200000_ecf_dosa_historical_transition_authorization`

Verificación:

```powershell
docker exec fullpos_ecf_dosa_uat_pg pg_isready -U fullpos_uat_user -d daleventa_uat_local
cd apps/api
npx prisma migrate status
```

Resultado esperado: `Database schema is up to date!` y 72 migraciones.

## 2. Archivos locales de entorno

| Archivo | Contenido | Estado |
| --- | --- | --- |
| `apps/api/.env.uat.local` | Configuración UAT, webhook, API Key TEST, key ring y claves de cifrado | Ignorado por Git, oculto, ACL solo del usuario |
| `apps/api/.env.dosa.session-key.local` | **Cuarentena** de la `sk_` de sesiones | Ignorado, oculto, ACL solo del usuario, **no cargado** |
| `apps/fulltech_app/.env.dosa.local` | `publishable-key` pública para el modo directo del SDK | Ignorado, oculto, ACL solo del usuario |

El `.env.uat.local` se escribió en UTF-8 sin BOM.

### Variables activas

- `APP_ENV=uat`
- `UAT_LOCAL_ONLY=true`
- `DATABASE_URL` apunta exclusivamente a `127.0.0.1:56560/daleventa_uat_local`
- `DOSA_CERTIFICATION_SESSIONS_ENABLED=false`
- `DOSA_SECRET_KEY` **vacía**; la `sk_` está en cuarentena
- `DOSA_WEBHOOK_ENABLED=false`
- `DOSA_WEBHOOK_SIGNATURE_STRATEGY=HMAC_SHA256_TIMESTAMPED`
- `DOSA_WEBHOOK_SECRET` cargado
- `DOSA_TEST_API_KEY` cargada, pero emisión apagada
- `DOSA_SESSION_URL_KEYS` contiene **2 versiones**; versión activa **2**
- `DOSA_CREDENTIALS_MASTER_KEY` generada
- `ECF_PORTAL_PILOT_COMPANY_IDS` **vacía** hasta crear la empresa piloto
- `DOSA_EMISSION_ENABLED=false`
- `DOSA_PRODUCTION_EMISSION_ENABLED=false`
- `ECF_EMISSION_ENABLED=false`
- `ALANUBE_ENABLE_REAL_CALLS=false`

La clave `sk_` **no se carga**. Para activarla hará falta:

1. confirmación de DOSA de que está activa y es de pruebas;
2. copiarla explícitamente al proceso UAT;
3. cambiar `DOSA_CERTIFICATION_SESSIONS_ENABLED=true`;
4. ejecutar una sola sesión controlada.

No hacerlo todavía.

## 3. Cómo iniciar el backend UAT

Cargar el archivo en el proceso **sin imprimir valores**:

```powershell
Get-Content apps/api/.env.uat.local | ForEach-Object {
  $line = $_.Trim()
  if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return }
  $i = $line.IndexOf('=')
  if ($i -le 0) { return }
  [Environment]::SetEnvironmentVariable(
    $line.Substring(0, $i).Trim(),
    $line.Substring($i + 1).Trim(),
    'Process'
  )
}
```

Iniciar:

```powershell
cd apps/api
npm run start:dev
```

Comprobar que responde el backend local:

```powershell
Invoke-RestMethod http://127.0.0.1:45660/health
```

No usar `npm start` contra este entorno sin revisar `prestart`; el flujo
controlado es `start:dev` con las variables ya cargadas.

## 4. Webhook local

- Ruta NestJS: `POST /webhook/dosa`.
- Ruta pública correcta detrás de nginx: `/api/webhook/dosa`.
- `DOSA_WEBHOOK_ENABLED=false` por defecto.
- La estrategia HMAC está implementada y probada localmente.
- Pendiente en el panel de DOSA: usar `/api/webhook/dosa`, no `/webhook/dosa`
  (esa ruta la sirve el PWA).
- Pendiente de verificación real: unidad de `t` y encoding del secreto.

Pruebas locales ejecutadas (sin red):

```text
dosa-webhook.spec.ts
dosa-webhook-hmac-pipeline.spec.ts
dosa-certification-session.service.spec.ts
dosa-emission-key-selection.spec.ts
dosa-session-url-cipher.spec.ts
82 passed
```

## 5. Certificado y proveedor efectivo

La UI ahora usa `provider` del expediente, no solo el permiso del usuario:

- `provider=DOSA`: no muestra carga de PFX/contraseña; el certificado se pide
  dentro de DOSA.
- `provider=ALANUBE`: conserva la carga local del certificado.
- `provider=null` en una respuesta antigua: conserva la carga local por
  seguridad.

Esto evita ocultar el formulario local a una empresa Alanube. Prueba añadida:
`empresa Alanube conserva la carga local del certificado`.

## 6. Qué falta para la primera conexión real

1. Confirmar que la `sk_` en cuarentena está activa y es de pruebas.
2. Crear empresa piloto UAT (RNC `133306001`) y administrador; llenar
   `ECF_PORTAL_PILOT_COMPANY_IDS`.
3. Cambiar `DOSA_CERTIFICATION_SESSIONS_ENABLED=true` solo para la ventana.
4. Confirmar/ajustar la URL pública del webhook en DOSA.
5. Recibir un evento firmado y fijar unidad/encoding.
6. Autorizar explícitamente la primera sesión controlada.

No hay que solicitar de nuevo dominio, script, publishable-key, secreto webhook,
fórmula HMAC, API Key TEST, secuencias, endpoint de sesiones ni payload.
