# Integración de emisión — sesiones de certificación DOSA

Estado: **implementado en rama `agent/ecf-dosa-emission`** (no desplegado, migración no aplicada).

## Qué resuelve

FullPOS envía automáticamente el **RNC** y el **correo de facturación electrónica**
de la empresa al abrir la sesión de certificación DOSA, sin volver a pedírselos al
cliente ni pedir certificados o contraseñas en la app.

## Fuentes de datos (una sola captura)

| Dato | Origen | Nunca desde el navegador |
| --- | --- | --- |
| RNC | `EcfCanonicalIdentityService.resolve(companyId)` (expediente fiscal / `app_config.rnc`) | sí |
| Correo | `app_config.ecf_contact_email` (Configuración de empresa) | sí |
| Empresa | `requireTenant(user)` del JWT | sí |

El correo se captura **una vez** en Configuración de empresa → campo compacto
«Correo de facturación electrónica». Se valida en el backend (formato y longitud
≤ 254). Guardar otros campos no lo borra (`undefined` = Prisma no toca la columna).

## Backend

- Cliente reutilizado: `dosa-certification-session.client.ts` (contrato
  `POST /api/certificacion/sesiones`, cabecera `X-Dosa-Secret-Key`). Falla
  cerrado sin bandera/clave y valida URL, token, `expires_at` y `postulacion_id`.
- Lanzador: `dosa-certification-session.service.ts`
  - reutiliza una sesión **vigente** (sin llamar al proveedor);
  - cierra la **caducada** (`EXPIRED`) y emite una nueva;
  - **candado por empresa** con un `UPDATE` condicional (lease) en la base, más
    `inFlight` en el controlador: doble clic o dos instancias no duplican;
  - timeout / 5xx / excepción → intento `ATTENTION` y **no se reintenta solo**;
  - 4xx → error definitivo, se libera el candado para reintento **manual**.
- Endpoint autenticado y aislado por empresa:
  `POST /ecf/dosa/certification-session` — permiso `manageEcfOnboarding`.
  Devuelve `{ companyId, sessionUrl, expiresAt, attemptNo, providerPostulationId, reused }`.
  `companyId` permite al cliente comprobar que el enlace es de SU empresa.
- Nunca se registran la clave de servidor, el token ni la URL de sesión.

## Flutter

- Campo «Correo de facturación electrónica» en Configuración de empresa.
- Botón **«Iniciar postulación electrónica»**: primero abre la URL de sesión
  devuelta por DOSA. Antes de abrir verifica que `companyId` coincide con el del
  usuario autenticado y que tiene `manageEcfOnboarding`.
- **Fallback seguro**: si la API de sesiones no está habilitada
  (`ECF_DOSA_SESSION_DISABLED`, 404/501), se usa el asistente/portal actual.
  Un resultado **incierto no cae al fallback** (evita duplicar postulaciones).

## Migración

`apps/api/prisma/migrations/20261104180000_ecf_dosa_session_emission/migration.sql`
— aditiva y retrocompatible, sin backfill:

- `app_config.ecf_contact_email VARCHAR(254) NOT NULL DEFAULT ''`
- `ecf_dosa_certification_sessions.session_expires_at TIMESTAMPTZ NULL`
- `ecf_dosa_certification_sessions.session_issued_at TIMESTAMPTZ NULL`
- `ecf_dosa_certification_sessions.session_lease_until TIMESTAMPTZ NULL`

## Configuración pendiente (ops)

Definir en el entorno del backend (nunca en el repositorio):

| Variable | Uso |
| --- | --- |
| `DOSA_CERTIFICATION_SESSIONS_ENABLED=true` | Habilita la apertura automática |
| `DOSA_SECRET_KEY=sk_...` | Clave **de servidor** de DOSA (no la real en pruebas) |
| `DOSA_SESSION_BASE_URL` | Base del API (por defecto `https://dosasystem.com`) |
| `DOSA_SESSION_TIMEOUT_MS` | Timeout (por defecto 15000) |
| `DOSA_SESSION_ALLOWED_RETURN_ORIGINS` | Orígenes permitidos para `return_url` |
| `DOSA_SESSION_URL_KEYS` | Key ring `version:base64,...` para cifrar URLs en reposo |
| `DOSA_SESSION_URL_ACTIVE_KEY_VERSION` | Versión de escritura del key ring |
| `ECF_DOSA_HISTORICAL_TRANSITION_ENABLED` | Autoriza la transición auditada de un histórico (apagada por defecto) |

Sin `DOSA_CERTIFICATION_SESSIONS_ENABLED=true`, sin `DOSA_SECRET_KEY` o sin
claves de cifrado válidas, el endpoint falla cerrado (`503
ECF_DOSA_SESSION_DISABLED` o `ECF_DOSA_SESSION_ENCRYPTION_NOT_CONFIGURED`) y la
app usa el asistente actual.

## Pruebas

- `dosa-certification-session.client.spec.ts` (contrato del proveedor, 45 casos).
- `dosa-certification-session.service.spec.ts` (empresa con/sin correo, correo
  inválido, dos empresas, sesión vigente/caducada, doble clic, 4xx, incierto sin
  reintento, clave ausente, empresa sin RNC, empresa sin e-CF).
- `dosa-certification-session.controller.spec.ts` (permiso, empresa del token,
  doble clic, mapeo de errores).
- `settings.service.spec.ts` (validación y persistencia del correo).
- Flutter: `test/features/ecf/dosa_certification_session_api_test.dart`.

## Protección del Intento 1

La apertura automática no puede mutar un expediente histórico reconciliado. El
servicio consulta `ecf_audit_logs` por `INTENT_PROVIDER_RECONCILED` antes de
reclamar o llamar al proveedor y responde
`ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED` sin crear un segundo intento ni
actualizar estados, fechas, URLs o identificadores. Cualquier transición futura
exige una operación explícita, autorizada y auditada.

## URL de sesión: acceso, expiración y cifrado

- La URL es una **capacidad de acceso**. Solo se devuelve desde
  `POST /ecf/dosa/certification-session` a un usuario con
  `manageEcfOnboarding`. `GET /ecf/dosa/certification-intent` nunca devuelve la
  URL ni el criptograma: solo informa de su presencia.
- Se persiste cifrada en `ecf_dosa_certification_sessions.session_url` con
  AES-256-GCM y derivación HKDF por empresa + RNC + intento. El token separado
  del proveedor no se persiste ni se devuelve.
- Envoltorio versionado `fpv1:<keyVersion>:<iv>:<tag>:<ciphertext>`. Un valor sin
  prefijo se acepta como texto plano histórico y se cifra en la siguiente
  escritura.
- Rotación: `DOSA_SESSION_URL_KEYS` admite un key ring
  `version:base64,version:base64`; `DOSA_SESSION_URL_ACTIVE_KEY_VERSION` elige la
  versión de escritura. Los criptogramas antiguos siguen abriéndose con su
  versión. Si no hay claves válidas, la apertura automática falla cerrada con
  `ECF_DOSA_SESSION_ENCRYPTION_NOT_CONFIGURED` y nunca guarda texto claro.
- La reutilización exige URL **y** fecha de vencimiento verificable. Una fila
  histórica con URL y sin vencimiento no se reutiliza ni se sobrescribe:
  responde `ECF_DOSA_SESSION_EXPIRY_UNKNOWN`.
- Una URL cifrada que no se puede descifrar responde
  `ECF_DOSA_SESSION_URL_UNREADABLE` y no se reutiliza ni se sobrescribe.
- El lease por defecto es de 180 s, superior al timeout máximo del cliente
  (120 s), para que no expire mientras la petición ganadora espera al proveedor.
- No se registran claves, tokens ni URLs en logs. `redactSessionUrl()` existe
  para diagnóstico y elimina query y fragmento.

## Fuera de alcance respetado

No se toca el Intento 1 existente, Guardian, ventas tradicionales, caja,
inventario ni emisión fiscal. No se crean sesiones reales de DOSA durante las
pruebas.
