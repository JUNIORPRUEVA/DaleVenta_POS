# DOSA — checklist de UAT oficial

Estado: **preparación**. Este documento no autoriza despliegue, emisión real,
llamadas reales a DOSA, migraciones compartidas ni cambios de credenciales.

Regla de oro: si falta una respuesta de DOSA o una evidencia, el paso queda
**BLOQUEADO**. No se sustituye con una suposición, un valor manual ni una prueba
contra producción.

Entorno UAT local preparado: `docs/ecf/DOSA_UAT_ENVIRONMENT.md`.

Primera postulación real de FULLTECH SRL:
`docs/ecf/DOSA_FIRST_FULLTECH_POSTULATION_CHECKLIST.md`.

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

| Elemento | RECIBIDO | CONFIGURADO | PROBADO REALMENTE | PENDIENTE |
| --- | --- | --- | --- | --- |
| Script oficial y `publishable-key` | Sí: script y clave `pk_` en el historial privado | Sí: archivo local `apps/fulltech_app/.env.dosa.local` | No | Inyectarla en el build web autorizado |
| Dominio `fullposcloud.fulltechrd.com` | Sí | Sí: `DOSA_SESSION_ALLOWED_RETURN_ORIGINS` local | No | Probar el origen real |
| Secreto del webhook | Sí: 64 caracteres hex | Sí: cargado en `.env.uat.local` local | No | Probar un evento real |
| Firma HMAC-SHA256 `t + "." + cuerpo` | Sí: fórmula confirmada | Sí: `CONFIGURADO` en código; por defecto `BLOCKED` | Solo pruebas locales | Validar un evento real y fijar unidad/encoding |
| URL pública del webhook | Sí, pero la sugerida apunta al PWA | Sí: ruta NestJS `/webhook/dosa`; pública correcta `/api/webhook/dosa` | No | Corregir la URL en DOSA/panel |
| Payload `empresa.conectada` | Sí: ejemplo sanitizado | Sí: parser y persistencia redactada | Solo pruebas locales | Un evento real |
| Correlación empresa/RNC/`postulacion_id` | Sí: confirmación verbal | Sí: resolver por sesión y binding SQL protegido | Solo pruebas locales | Un evento real y una sesión UAT |
| Protección de credenciales del webhook | Sí: payload con claves | Sí: se cifran, se redactan y no se registran | Solo pruebas locales | Un evento real |
| Selección de API Key por empresa/RNC/entorno | Sí: una clave por RNC | Sí: `openForEmission` por empresa/RNC/entorno, sin fallback cruzado | Solo pruebas locales | Prueba de emisión autorizada |
| API Key TEST de RNC `133306001` | Sí: clave de 40 caracteres en el historial; DOSA la asoció explícitamente a ese RNC | Sí: `.env.uat.local` local, emisión apagada | No | Su vínculo con el RNC solo se confirma con una llamada real |
| Clave `sk_` de sesiones | Sí: aparece en el ejemplo privado de DOSA | No: en cuarentena, no cargada | No | Confirmar vigencia y activarla explícitamente |
| Endpoint y campos de sesión | Sí | Sí: cliente implementado y validado | Solo pruebas locales | Una sesión real con `sk_` |
| RNC TEST `133306001` vs FULLTECH SRL `133080206` | Sí, son distintos | Sí: no hay RNC TEST hardcodeado en producción | No | Usar empresa sintética UAT para `133306001`; no tocar FULLTECH SRL |
| Secuencias TEST `113500–115500` | Sí, vencen `31/12/2028` | No | No | Registrarlas en la base UAT |
| Endpoint `EnviarFactura` TEST | Sí | Sí: ruta, `DOSA_BASE_URL` y API Key TEST en `.env.uat.local`; emisión apagada | No | Solo después de la certificación |
| Certificado solicitado solo en DOSA | Sí: DOSA lo custodia, firma y transmite | Sí: rama DOSA no muestra carga de PFX/contraseña | Solo pruebas de widget | Confirmación visual en UAT |
| Modo directo del SDK (`publishable-key`) | Sí | Sí: fallback implementado si no hay `session-url` | Solo pruebas locales | Build web autorizado con la clave pública |
| Modo de sesiones privadas reutiliza RNC/correo | Sí: contrato de sesiones | Sí: backend lee RNC canónico y correo de empresa | Solo pruebas locales | Una sesión real; verificar que no pide datos dos veces |
| Key ring de cifrado de URLs | No es un dato de DOSA | Sí: 2 versiones, escritura activa en la 2 | No | Probar rotación con una sesión real |
| Empresa piloto y administrador UAT | No es un dato de DOSA | Sí: empresa sintética RNC `133306001` y admin local | No | Usarla solo en simulación; no es FULLTECH SRL |

`PROBADO REALMENTE` significa contra DOSA o contra su sandbox real, con una
sesión o un webhook auténticos. Las pruebas unitarias, de contrato y E2E con
dobles **no** cuentan como prueba real.

Resultado: **casi todo está RECIBIDO, la configuración local está preparada y
nada está PROBADO REALMENTE contra DOSA**. El `.env.uat.local` está cargado con
las credenciales disponibles, el key ring y la base aislada; la `sk_` sigue en
cuarentena y las banderas de sesión/webhook/emisión están apagadas. El paquete
original de noviembre confirma que la `publishable-key` es pública, la API Key
TEST es secreta y la clave de sesiones no estaba acreditada en ese paquete; la
clave `sk_` aparece después, en el ejemplo privado del 4 de noviembre, y aún debe
confirmarse como vigente.

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
| `DOSA_ASSISTANT_ENABLED` | `true` solo para el build web/portal autorizado | Build de Flutter Web |
| `DOSA_ASSISTANT_PUBLISHABLE_KEY` | Clave pública `pk_...`, solo para modo directo | `-PublishableKey`, variable de build o `apps/fulltech_app/.env.dosa.local` |
| `DOSA_ASSISTANT_BASE_URL` | `https://dosasystem.com` | Build de Flutter Web |
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

- Empresa **sintética** de UAT con RNC `133306001` y correo de facturación
  electrónico guardado.
- **No** usar para esta prueba la empresa real FULLTECH SRL (`133080206`).
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
8. Fallback directo permitido solo si el backend responde de forma definitiva
   que la sesión privada no está disponible (`ECF_DOSA_SESSION_DISABLED`, 404 o
   501). En ese caso se puede usar el modo directo del SDK con
   `publishable-key`, siempre que el build tenga la clave pública y el dominio
   esté autorizado. **Nunca** usar el fallback ante timeout, 5xx o resultado
   incierto.
9. Evidencia: request-id, `companyId`, `attemptNo`, `providerPostulationId`,
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

- [ ] Usar la confirmación ya entregada, sin volver a pedirla:
  - cada RNC se certifica a nombre de la empresa;
  - cada empresa tiene su API Key propia y única por RNC;
  - el RNC del payload debe coincidir con el de la API Key;
  - DOSA custodia el certificado, firma el XML y transmite a DGII.
- [ ] Verificar en el panel de DOSA que el certificado está cargado y que el
      RNC mostrado es `133306001`, no `133080206`.
- [ ] Verificar que la API Key de emisión es de **TEST** y que su etiqueta
      corresponde a `133306001`. Guardar solo la etiqueta o fingerprint,
      nunca el valor.
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

Si la prueba controlada no demuestra que el certificado, el RNC y la API Key
son la misma identidad: **NO-GO** para emisión. No se vuelve a pedir la
confirmación general: ya fue entregada.

> Nota de regresión: el widget local de PFX/contraseña sigue existiendo para
> proveedores no-DOSA. En el recorrido DOSA no se muestra. `dosaOwnsCertificate`
> se activa por permiso `manageEcfOnboarding`, no por proveedor; si Alanube
> sigue activo, validar que ese recorrido no pierda su carga local. No bloquea
> la UAT DOSA.

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
5. Verificar la empresa sintética y el administrador UAT ya creados; confirmar
   `ECF_PORTAL_PILOT_COMPANY_IDS=11111111-1111-4111-8111-111111111111`. No usar
   FULLTECH SRL para la simulación local.
6. Ejecutar A5 una sola vez con una empresa sintética UAT de RNC `133306001`.
   No usar FULLTECH SRL (`133080206`) para esta prueba. No repetir a ciegas si
   hay timeout.
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
- Base UAT local: **creada y migrada** (72 migraciones), vacía y aislada.
- Credenciales DOSA: **configuradas localmente**, excepto `sk_`, que sigue en
  cuarentena y no se carga.
- Key ring UAT: **configurado** con dos versiones; escritura en la versión 2.
- Webhook local: **configurado pero apagado**; falta un evento real.
- UAT oficial: **pendiente de crear empresa/admin, confirmar `sk_`, corregir la
  URL pública en DOSA y recibir un evento firmado**. Ya no se deben volver a
  solicitar el dominio, la fórmula HMAC, la API Key TEST, las secuencias, el
  endpoint de sesiones ni el payload del webhook.
