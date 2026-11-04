# DOSA — checklist de UAT oficial

Estado: **preparación**. Este documento no autoriza despliegue, emisión real,
llamadas reales a DOSA, migraciones compartidas ni cambios de credenciales.

Regla de oro: si falta una respuesta de DOSA o una evidencia, el paso queda
**BLOQUEADO**. No se sustituye con una suposición, un valor manual ni una prueba
contra producción.

## 0. Separación de responsabilidades

| Bloque | Responsable | Puede ejecutarse ya |
| --- | --- | --- |
| A. Entorno, base UAT y evidencia | Nuestro equipo / operaciones | Sí, en entorno aislado |
| B. Credenciales y confirmaciones del proveedor | DOSA | No, esperando respuesta |
| C. Prueba funcional RNC/correo y vinculación | Nuestro equipo, con credenciales de DOSA | No, depende de B |
| D. Autorización de despliegue | Propietario / operaciones | No, depende de A+B+C |

## 0.1 Reconciliación de lo ya entregado por DOSA

Revisión hecha contra el historial de WhatsApp, el archivo del secreto y el
código. No se copiaron valores de credenciales.

| Elemento | Entregado por DOSA | Estado en FullPOS | Resultado |
| --- | --- | --- | --- |
| Script y clave pública del asistente | Sí, 01/11/2026 | No se usa en el backend; el asistente vive en DOSA | `ENTREGADO` |
| Dominio `fullposcloud.fulltechrd.com` | Sí | Falta fijarlo en `DOSA_SESSION_ALLOWED_RETURN_ORIGINS` | `PENDIENTE DE PRUEBA` |
| Secreto del webhook | Sí, archivo de 64 caracteres hex | No está en el `.env` local | `PENDIENTE DE PRUEBA` |
| Firma HMAC-SHA256 `t=...,v1=...` | Sí, fórmula `t + "." + cuerpo` | Implementada en código; estrategia por defecto `BLOCKED` | `PENDIENTE DE PRUEBA` |
| Unidad de `t` y encoding del secreto | No consta en el historial | Configurable; valores por defecto seguros | `PENDIENTE DE PRUEBA` |
| Vinculación automática por dominio | Sí, del lado Partner | El backend exige además una sesión local para resolver RNC → empresa | `PENDIENTE DE PRUEBA` |
| Webhook `empresa.conectada` con RNC, `postulacion_id` y credenciales | Sí, muestra entregada | Parser y persistencia implementados; tipo de evento se guarda como pendiente de clasificación | `PENDIENTE DE PRUEBA` |
| API Key TEST para RNC `133306001` | Sí, entregada en el historial | No configurada; no se usará hasta la prueba autorizada | `PENDIENTE DE PRUEBA` |
| Secuencias TEST `113500–115500`, vencimiento `31/12/2028` | Sí | No registradas aún en la base UAT | `PENDIENTE DE PRUEBA` |
| Endpoint de emisión `POST .../fe/api/emision/ecf/EnviarFactura` | Sí, mismo endpoint para TEST | Ruta implementada; `DOSA_BASE_URL` y API Key TEST no configurados | `PENDIENTE DE PRUEBA` |
| Sesiones `POST https://dosasystem.com/api/certificacion/sesiones` | Sí | Cliente implementado y validado | `PENDIENTE DE PRUEBA` |
| Campos de sesión `rnc_emisor`, `correo`, `return_url` | Sí | Cliente implementado | `PENDIENTE DE PRUEBA` |
| Respuesta `201` `url`, `path`, `token`, `expires_at`, `postulacion_id`, `prueba` | Sí | Cliente valida todos los campos | `PENDIENTE DE PRUEBA` |
| Clave `sk_...` de sesiones | Sí, aparece en el ejemplo enviado por DOSA en el historial | No configurada; no está identificada explícitamente como TEST o PROD | `PENDIENTE DE PRUEBA` |
| Certificado gestionado por DOSA | Sí: DOSA custodia, firma XML y transmite a DGII | No se almacena en FullPOS | `PENDIENTE DE PRUEBA` |
| Retomar una sesión | Sí, informado por DOSA | Reutilización y lease implementados | `PENDIENTE DE PRUEBA` |

Resultado de la revisión: **no hay que volver a pedir la mayoría de los datos**.
Lo que falta es configurarlos en el entorno UAT y ejecutar las pruebas
controladas. Ninguna credencial DOSA está configurada hoy en este worktree: los
`.env` locales solo contienen plantillas vacías.

## 1. Tareas nuestras

### A1. Congelar alcance y ambiente

- [ ] Confirmar rama `agent/ecf-dosa-integration-20261104` y commit base.
- [ ] Confirmar que no hay cambios ajenos en el worktree.
- [ ] Confirmar que `APP_ENV=uat` y que la base no es producción.
- [ ] Confirmar que la ventana de prueba y el responsable de aceptación están
      escritos.
- [ ] Confirmar que la emisión seguirá apagada durante toda la certificación.

Comandos de control:

```powershell
git branch --show-current
git rev-parse --short HEAD
git status --short
```

Resultado esperado: rama correcta, worktree limpio y commit identificado.

### A2. Inventario de variables de entorno

No copiar valores reales en este documento, en el repositorio, en tickets, en
capturas ni en mensajes.

| Variable | Valor UAT esperado | Dónde se configura |
| --- | --- | --- |
| `APP_ENV` | `uat` | Runtime del backend UAT |
| `UAT_LOCAL_ONLY` | `true` si el backend y la base son locales | Runtime local UAT |
| `DATABASE_URL` | PostgreSQL UAT, nunca producción | Gestor de secretos UAT |
| `JWT_SECRET` | Secreto exclusivo de UAT | Gestor de secretos UAT |
| `ECF_PORTAL_PILOT_COMPANY_IDS` | UUID de la empresa piloto, separados por coma | Runtime del backend UAT |
| `DOSA_CERTIFICATION_SESSIONS_ENABLED` | `true` solo al iniciar la prueba de sesión | Runtime del backend UAT |
| `DOSA_SECRET_KEY` | Clave sandbox `sk_...` entregada por DOSA | Gestor de secretos UAT |
| `DOSA_SESSION_BASE_URL` | URL base sandbox de sesiones | Runtime del backend UAT |
| `DOSA_SESSION_TIMEOUT_MS` | `15000` o el valor acordado | Runtime del backend UAT |
| `DOSA_SESSION_ALLOWED_RETURN_ORIGINS` | Origen exacto de la app UAT | Runtime del backend UAT |
| `DOSA_SESSION_URL_KEYS` | Key ring `version:base64,...` generado para UAT | Gestor de secretos UAT |
| `DOSA_SESSION_URL_ACTIVE_KEY_VERSION` | Versión de escritura del key ring | Runtime del backend UAT |
| `ECF_DOSA_HISTORICAL_TRANSITION_ENABLED` | `false`; `true` solo en la ventana autorizada del Intento 1 | Runtime del backend UAT |
| `ECF_DOSA_INTENT_RECONCILIATION_ENABLED` | `false` salvo procedimiento autorizado | Runtime del backend UAT |
| `ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED` | `false` salvo procedimiento autorizado | Runtime del backend UAT |
| `DOSA_EMISSION_ENABLED` | `false` hasta concluir la UAT oficial | Runtime del backend UAT |
| `DOSA_PRODUCTION_EMISSION_ENABLED` | `false` siempre durante la UAT | Runtime del backend UAT |
| `DOSA_EMISSION_ENVIRONMENT` | `TEST` si se autoriza una prueba de emisión | Runtime del backend UAT |
| `DOSA_TEST_API_KEY` | Vacía hasta la prueba oficial de emisión | Gestor de secretos UAT |
| `DOSA_PRODUCTION_API_KEY` | Vacía durante toda la UAT | Gestor de secretos UAT |
| `DOSA_BASE_URL` | URL base sandbox de emisión | Runtime del backend UAT |
| `DOSA_TEST_RNC` | RNC de prueba indicado por DOSA | Runtime del backend UAT |
| `ECF_EMISSION_ENABLED` | `false` | Runtime del backend UAT |
| `ALANUBE_ENABLE_REAL_CALLS` | `false` | Runtime del backend UAT |
| `ALANUBE_HTTP_TRANSPORT_ENABLED` | `false` | Runtime del backend UAT |
| `ECF_ALANUBE_AUTH_TESTS_ENABLED` | `false` | Runtime del backend UAT |
| `DOSA_WEBHOOK_ENABLED` | `false` hasta que DOSA confirme firma | Runtime del backend UAT |
| `DOSA_WEBHOOK_SIGNATURE_STRATEGY` | `BLOCKED` hasta confirmación escrita | Runtime del backend UAT |
| `DOSA_WEBHOOK_SECRET` | Vacía hasta confirmación de DOSA | Gestor de secretos UAT |
| `DOSA_CREDENTIALS_MASTER_KEY` | Clave de bóveda UAT, si se usa la bóveda | Gestor de secretos UAT |

Ubicación:

- Local: `apps/api/.env.uat.local`, archivo **ignorado** por Git. Nunca
  commitearlo.
- UAT compartida: gestor de variables/secretos del entorno UAT. No usar el
  `.env` raíz ni el de producción.
- Flutter: su `.env` solo contiene URL de API y ambiente; **no** debe contener
  claves de DOSA.

Verificación sin mostrar valores:

```powershell
# En el runtime UAT, imprimir solo nombres y si están definidas.
Get-ChildItem Env: | Where-Object { $_.Name -match '^(DOSA|ECF)_' } |
  Select-Object Name, @{n='Definida';e={-not [string]::IsNullOrWhiteSpace($_.Value)}}
```

No ejecutar `Get-ChildItem Env:` completo en una sesión con secretos.

### A3. Preparar base UAT y migración

Requisitos:

- [ ] Base local `daleventa_uat_local` o base UAT aprobada; nunca producción.
- [ ] Snapshot/backup o base desechable verificada.
- [ ] `DATABASE_URL` apunta a `127.0.0.1` o al host UAT aprobado.
- [ ] `APP_ENV=uat`.
- [ ] No hay `RUN_SEED=true`, `prisma migrate reset`, `prisma db push` ni seed.

Comandos, con el valor real tomado del gestor de secretos y sin imprimirlo:

```powershell
$env:APP_ENV = 'uat'
$env:UAT_LOCAL_ONLY = 'true'
$env:DATABASE_URL = '<url-uat-local-o-aprobada>'

cd apps/api
npx prisma validate
npx prisma migrate status
npx prisma migrate deploy
npx prisma migrate status
```

Comprobaciones:

```sql
SELECT current_database(), inet_server_addr(), inet_server_port();
SELECT count(*) FROM "_prisma_migrations";
SELECT unnest(enum_range(NULL::ecf_audit_action));
```

Resultado esperado:

- La base es la UAT esperada, no producción.
- Las migraciones pendientes quedan aplicadas.
- `INTENT_HISTORICAL_TRANSITION_AUTHORIZED` existe en el enum.
- La migración es aditiva: no borra ni reescribe filas existentes.

Si la base es compartida: exigir autorización escrita, ventana, backup y
responsable. Si no hay backup, **NO-GO**.

### A4. Verificar el Intento 1 antes de cualquier prueba

Solo sobre una copia/base UAT autorizada. No ejecutar sobre producción.

```sql
SELECT id, attempt_no, status, created_at, closed_at,
       session_url IS NOT NULL AS tiene_url,
       provider_postulation_id
  FROM ecf_dosa_certification_sessions
 WHERE company_id = '<uuid-empresa-piloto>'
 ORDER BY attempt_no DESC, created_at DESC;

SELECT action, created_at, actor_user_id
  FROM ecf_audit_logs
 WHERE company_id = '<uuid-empresa-piloto>'
   AND action::text IN ('INTENT_PROVIDER_RECONCILED',
                        'INTENT_HISTORICAL_TRANSITION_AUTHORIZED')
 ORDER BY created_at;
```

Guardar el resultado como evidencia. La fila del Intento 1 debe conservar
`attempt_no=1`, su estado, fechas, URL ausente y referencias originales.

### A5. Probar RNC y correo automáticos sin duplicar postulaciones

Precondiciones:

- Empresa piloto con RNC canónico y correo de facturación electrónica guardado.
- `DOSA_CERTIFICATION_SESSIONS_ENABLED=true`.
- `DOSA_SECRET_KEY` sandbox y `DOSA_SESSION_BASE_URL` configurados.
- Ninguna sesión activa previa sin explicar.
- Emisión apagada.

Secuencia:

1. Registrar el estado inicial:
   - número de filas en `ecf_dosa_certification_sessions` para la empresa;
   - `attempt_no` máximo;
   - si existe `provider_postulation_id`;
   - si existe `session_url`.
2. Abrir el portal e-CF y pulsar **una sola vez** «Iniciar postulación
   electrónica».
3. Verificar en la respuesta:
   - `companyId` coincide con la empresa del usuario;
   - `attemptNo` es el esperado;
   - `reused=false` en la primera apertura;
   - `providerPostulationId` presente.
4. Verificar en la base que se creó **una** sesión y que el RNC guardado es el
   canónico de la empresa.
5. Verificar con DOSA que recibió el RNC y el correo correctos y que **no** pidió
   certificado ni contraseña a FullPOS.
6. Sin cerrar la sesión, repetir la apertura o recargar y pulsar de nuevo:
   - debe devolver `reused=true`;
   - no debe crear otra fila;
   - no debe crear otra postulación en DOSA.
7. Si la respuesta es incierta, timeout o 5xx:
   - **no reintentar a ciegas**;
   - no borrar la sesión;
   - registrar el caso y reconciliar con DOSA por `postulacion_id`.
8. Evidencia: request-id, `companyId`, `attemptNo`, `providerPostulationId`,
   conteo antes/después y captura sin URL ni token.

Criterio de aceptación:

- Una sola postulación por empresa/RNC.
- RNC y correo correctos.
- Segunda apertura reutiliza la misma sesión.
- Ningún secreto ni URL de sesión en logs o capturas.

### A6. Comprobar certificado ↔ RNC ↔ API Key de emisión

FullPOS **no** almacena certificados ni contraseñas. El certificado se carga en
DOSA y la API Key llega por el canal del proveedor; no se introduce a mano.

Pasos:

- [ ] Pedir a DOSA confirmación escrita de:
  - titular del certificado y RNC al que queda vinculado;
  - alcance de la API Key de emisión: empresa, partner o entorno;
  - si la API Key puede emitir para cualquier RNC o solo para el RNC vinculado;
  - qué ocurre si el certificado pertenece a otro RNC.
- [ ] Verificar en el panel de DOSA que el certificado está cargado y que el
      RNC mostrado es el de la empresa piloto.
- [ ] Verificar que la API Key de emisión es de **TEST** y que su etiqueta
      corresponde a la empresa/RNC de la prueba. Guardar solo la etiqueta o
      fingerprint, nunca el valor.
- [ ] Verificar en FullPOS, sin abrir valores, que la credencial existe:
  - entorno `TEST`;
  - estado `PENDING_CONFIRMATION` o superior;
  - `present.apiKeyTest=true`;
  - mismo RNC de la empresa.
- [ ] Verificar que el evento autenticado de DOSA trae el mismo
      `postulacion_id` del intento vigente y `estado_certificacion=finalizado`.
- [ ] Solo con autorización expresa, ejecutar **una** emisión de prueba con la
      clave TEST y confirmar que la respuesta del proveedor acepta el documento
      firmado con el certificado cargado.
- [ ] Ejecutar la evaluación de activación y revisar bloqueos. No promover a
      `ACTIVE` ni marcar certificación completada sin registro oficial DGII y
      autorización administrativa auditada.

Criterio de aceptación:

- DOSA confirma por escrito la vinculación certificado/RNC/API Key.
- La credencial de emisión es TEST y pertenece al mismo RNC.
- La prueba de emisión autorizada usa el certificado cargado y no otra clave.
- La evidencia queda ligada al `postulacion_id` y al intento vigente.

Si DOSA no confirma la vinculación: **NO-GO** para emisión.

### A7. Mantener la emisión desactivada

Antes de cada sesión de UAT:

```powershell
Get-ChildItem Env: | Where-Object {
  $_.Name -in @(
    'DOSA_EMISSION_ENABLED',
    'DOSA_PRODUCTION_EMISSION_ENABLED',
    'ECF_EMISSION_ENABLED',
    'ALANUBE_ENABLE_REAL_CALLS',
    'ALANUBE_HTTP_TRANSPORT_ENABLED',
    'ECF_ALANUBE_AUTH_TESTS_ENABLED'
  )
} | Select-Object Name, Value
```

Debe mostrar `false` en todas. Reglas:

- [ ] `DOSA_EMISSION_ENABLED=false`.
- [ ] `DOSA_PRODUCTION_EMISSION_ENABLED=false`.
- [ ] `ECF_EMISSION_ENABLED=false`.
- [ ] `ALANUBE_ENABLE_REAL_CALLS=false`.
- [ ] `DOSA_PRODUCTION_API_KEY` ausente o vacía.
- [ ] `DOSA_TEST_API_KEY` vacía hasta la prueba oficial de emisión.
- [ ] No se escribe `DGII_ACCEPTED` ni «certificación completada» sin evidencia
      oficial.
- [ ] Si se enciende temporalmente una bandera para una prueba autorizada, se
      apaga inmediatamente después y se registra quién lo hizo.

Prueba de seguridad, usando la suite existente que cubre la compuerta:

```powershell
cd apps/api
npx jest --runInBand src/ecf/provider/dosa/dosa-integration-journey.spec.ts
```

La compuerta debe rechazar con `ECF_DOSA_GATE_EMISSION_DISABLED` mientras la
bandera esté apagada. No ejecutar una emisión real para comprobarlo.

### A8. Evidencia para autorizar despliegue

Conservar en una carpeta segura, sin secretos:

- [ ] Rama y commit exactos.
- [ ] `git diff` revisado y worktree limpio.
- [ ] Salida de `npm run api:build`.
- [ ] Salida de `npx prisma validate`.
- [ ] Salida de `npx prisma migrate status` antes y después.
- [ ] Identidad de la base UAT (`current_database()`, host local o UAT aprobado).
- [ ] Inventario de variables **solo con nombres y estado definida/no definida**.
- [ ] Estado del Intento 1 antes y después.
- [ ] Auditoría `INTENT_PROVIDER_RECONCILED` y, si aplica,
      `INTENT_HISTORICAL_TRANSITION_AUTHORIZED`.
- [ ] Evidencia de una sola postulación y de `reused=true` en la segunda apertura.
- [ ] Respuesta escrita de DOSA sobre certificado/RNC/API Key.
- [ ] Evidencia de la prueba de emisión autorizada, si se hizo.
- [ ] Captura de las banderas de emisión en `false`.
- [ ] Aprobación del propietario y ventana de UAT.

No conservar: `DOSA_SECRET_KEY`, API Keys, `DATABASE_URL`, `JWT_SECRET`,
`DOSA_SESSION_URL_KEYS`, URLs de sesión, tokens ni cookies.

## 2. Preguntas abiertas para DOSA

Solo quedan dudas que **no** están respondidas en el historial. No repetir las
que ya constan en la tabla 0.1.

| # | Duda abierta | ¿Bloquea? | Cómo se resuelve |
| --- | --- | --- | --- |
| R1 | ¿La `t` de `X-Dosa-Signature` viene en segundos o milisegundos? | Sí, para aceptar webhooks reales | Confirmación escrita o primer evento firmado con `DOSA_WEBHOOK_TIMESTAMP_UNIT` |
| R2 | ¿El secreto de 64 hex se usa como texto UTF-8 o como 32 bytes decodificados? | Sí, para aceptar webhooks reales | Confirmación escrita o prueba controlada con `DOSA_WEBHOOK_SECRET_ENCODING` |
| R3 | La URL que DOSA sugirió (`/webhook/dosa`) la sirve el PWA, no el API | Sí, para recibir el evento | Usar `https://fullposcloud.fulltechrd.com/api/webhook/dosa` y corregirla en DOSA/panel |
| R4 | ¿La clave `sk_...` del ejemplo es la clave TEST vigente de FULLTECH? | Sí, para abrir sesiones | Confirmar etiqueta/vigencia; no usarla si es solo un ejemplo |
| R5 | ¿Hay límite de sesiones activas o TTL de `session_url`? | No, el cliente ya reutiliza y falla cerrado | Observar en la primera prueba; no bloquear el inicio |
| R6 | ¿El `postulacion_id` es único por empresa o global? | No, el vínculo local ya impide compartirlo entre empresas | Observar en la prueba; no bloquear el inicio |

No hace falta volver a pedir: dominio, script/clave pública, secreto del webhook,
fórmula HMAC, payload de `empresa.conectada`, API Key TEST para RNC
`133306001`, secuencias `113500–115500` con vencimiento `31/12/2028`, endpoint de
sesiones, campos de respuesta, endpoint `EnviarFactura`, manejo del certificado
por DOSA ni el comportamiento de retomar sesión.

## 3. Orden exacto para iniciar la UAT controlada

1. Completar A1 y A2. Confirmar que la clave `sk_` es la de UAT y no una de
   producción.
2. Cargar el secreto del webhook y las claves en el gestor de secretos UAT. No
   pegarlas en documentos, tickets ni capturas.
3. Configurar `DOSA_SESSION_BASE_URL=https://dosasystem.com`,
   `DOSA_SESSION_ALLOWED_RETURN_ORIGINS=https://fullposcloud.fulltechrd.com`,
   `DOSA_CERTIFICATION_SESSIONS_ENABLED=true` y las banderas de emisión en
   `false`.
4. Completar A3 y A4 en base UAT aislada y verificar que el Intento 1 no cambió.
5. Crear la empresa piloto y el administrador UAT. Registrar `ECF_PORTAL_PILOT_COMPANY_IDS`.
6. Ejecutar A5 una sola vez con RNC `133306001` y el correo de la empresa. No
   repetir a ciegas si hay timeout.
7. Configurar el webhook con la URL pública confirmada y la estrategia
   `HMAC_SHA256_TIMESTAMPED`. Recibir **un** evento firmado y validar R1/R2.
8. Verificar que el evento guarda el `postulacion_id` del mismo intento y que la
   credencial TEST queda cifrada y pendiente, sin activar emisión.
9. Ejecutar A6 solo con autorización expresa; no antes.
10. Recolectar evidencia A8 y revisar GO/NO-GO.
11. Solo después: autorizar despliegue y una prueba de emisión oficial separada.

## 4. Criterios GO / NO-GO de la UAT

GO para iniciar pruebas oficiales solo si:

- R1, R2, R3 y R4 están resueltos o verificados en una prueba controlada;
- la base UAT está migrada y verificada;
- el Intento 1 está intacto;
- la emisión está apagada;
- existe ventana, backup y responsable;
- no hay secretos en el repositorio ni en la evidencia.

NO-GO si:

- falta la clave de sesiones o no se sabe si es TEST;
- no se puede verificar la firma del webhook;
- la URL de base no se puede demostrar como UAT;
- el Intento 1 cambió;
- se intenta probar con una clave de producción;
- se activa emisión antes de la autorización;
- se marca certificación completada sin registro oficial.

## 5. Aislamiento de dependencias y pruebas

El 2026-11-04 se detectó que este worktree tenía `node_modules` enlazado a
`C:\src\fullpos-ecf-dosa-simplify`, por lo que `prisma generate` escribía en el
otro proyecto. Se corrigió así:

- [x] Se eliminaron los enlaces `node_modules` y `apps/api/node_modules` de este
      worktree.
- [x] Se ejecutó `npm ci` local: 706 paquetes instalados.
- [x] `node_modules` quedó como directorio real dentro de este worktree.
- [x] `npm run api:build` y la suite completa del backend pasan con las
      dependencias locales.
- [x] La suite no cambió el `package.json` del cliente Prisma del otro worktree
      (`LastWriteTimeUtc` idéntico antes y después).

Verificación antes de cada tanda de pruebas:

```powershell
cd C:\src\fullpos-ecf-dosa-integration
(Get-Item .\node_modules).LinkType
(Get-Item .\node_modules\@prisma\client).FullName
git status --short
```

Resultado esperado:

- `LinkType` vacío.
- Ruta del cliente Prisma bajo `C:\src\fullpos-ecf-dosa-integration`.
- Sin cambios en el worktree.

Si aparece un enlace a otro worktree, **detener**: reinstalar localmente antes de
ejecutar builds o pruebas.

## 6. Estado actual

- Procedimiento del Intento 1: implementado, **no ejecutado**.
- Cifrado de URLs de sesión: implementado y probado.
- E2E locales: ejecutados con base desechable y DOSA simulado.
- Emisión: **desactivada**.
- Certificación: **no completada**.
- Credenciales DOSA: **entregadas**, pero **no configuradas** en este worktree.
- UAT oficial: **pendiente de configuración UAT y de R1–R4**. Ya no se deben
  volver a solicitar el dominio, la fórmula HMAC, la API Key TEST, las
  secuencias, el endpoint de sesiones ni el payload del webhook.
