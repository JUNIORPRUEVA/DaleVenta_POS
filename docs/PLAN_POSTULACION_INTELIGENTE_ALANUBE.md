# PLAN DE IMPLEMENTACIÓN — POSTULACIÓN INTELIGENTE (ALANUBE + DGII)

| Campo | Valor |
| --- | --- |
| Proyecto | FullPOS Cloud · módulo e-CF |
| Worktree | `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE` |
| Rama | `feature/ecf-alanube` |
| Fecha | 2026-10-31 |
| Estado | **PROPUESTA PARA APROBACIÓN** — no autoriza todavía cambios de código |
| Alcance | Plan únicamente (Bloques A–F, fases F0–F6, migraciones, pruebas, criterios) |

> Este documento **no implementa nada**. Ninguna línea de código, migración ni
> llamada externa se ha ejecutado. Todo lo que aquí se afirma sobre el sistema
> actual está verificado en el repositorio y se cita con archivo y línea.

---

## 0. Resumen ejecutivo y decisiones de arquitectura

El módulo e-CF de FullPOS **ya tiene** lo que un plan desde cero tendría que
construir: un motor por pasos con dueño explícito de cada operación, una tabla de
intentos idempotentes, un transporte HTTP único hacia Alanube, referencias de
secreto (nunca secretos), auditoría y un gate fiscal que no permite declarar
emisión real sin autorización oficial verificable.

Por eso el plan **no crea un segundo motor ni un segundo cliente HTTP**. Añade
las seis operaciones de certificación que faltan, un validador de certificado que
no persiste nada, y una capa de coordinación que rellena el punto de extensión que
el motor ya tiene preparado.

### Decisiones (D1–D9)

**D1 — No hay máquina de estados nueva.** El orquestador se conecta en
`EcfDgiiActivationService.executeStep()` (`apps/api/src/ecf/dgii/ecf-dgii-activation.service.ts:308`),
que hoy es un stub: `AUTOMATIC_LOCAL` devuelve `LOCAL:<key>` y todo lo demás
devuelve `SIMULATED_OK` según un escenario (`ECF_ACTIVATION_SIMULATION_SCENARIO`).
Se sustituye ese stub por un despachador que, para los pasos de proveedor, llama
al orquestador y devuelve **la misma forma de resultado** que el motor ya
consume: `{ ok, simulated, summary, errorCode?, detail?, blockedReason? }`.
Los 15 pasos, las 4 clases (`AUTOMATIC_LOCAL`, `PROVIDER_WAIT`, `CLIENT_ACTION`,
`AUTHORITY_WAIT`) y los estados de `EcfOnboardingStep` **no cambian**.

**D2 — La inteligencia es un orquestador determinista, no un LLM.** Sin acceso a
secretos, sin decisiones creativas. Decide con reglas sobre datos persistidos.

**D3 — Idempotencia sobre la tabla que ya existe.** `EcfCertificationAttempt`
(`prisma/schema.prisma:1122`) ya tiene `@@unique([companyId, idempotencyKey])`,
`operation`, `status`, `externalId`, `errorCode`, `requestRef/responseRef`. No se
crea tabla de intentos nueva.

**D4 — Un único transporte.** Todas las llamadas al proveedor pasan por
`AlanubeHttpTransport.execute()` (`apps/api/src/ecf/alanube/alanube-safe-http.types.ts`).
`ecf-alanube.client.ts` (2,2 KB, solo `getRuntimeState()`) **no** se convierte en
cliente HTTP: se amplía su diagnóstico si hace falta, nada más.

**D5 — El certificado nunca se persiste en FullPOS.** Se recibe y se procesa en
memoria; se descarta. Se guarda únicamente `certificateSecretRef` (referencia) y
metadatos **no secretos** (huella SHA-256 del certificado, titular, caducidad).

**D6 — Honestidad de pasos mixtos (hallazgo crítico, ver §6.3).** Con el stub
actual, `DGII_POSTULATION` y `SERVICE_URLS` son `PROVIDER_WAIT`: cualquier
respuesta "ok" del proveedor los marca completados. Alanube **no** documenta
públicamente la presentación en el Portal DGII. Propuesta: reclasificar esos dos
pasos a `CLIENT_ACTION` (o dividirlos) para que el progreso no mienta. Se detalla
en §6.3 con dos alternativas.

**D7 — Un paso terminal nunca se automatiza.** `FINAL_AUTHORIZATION` y
`PRODUCTION_ENABLEMENT` siguen `AUTHORITY_WAIT`: `stepStatusFromTransport` los
manda siempre a `AWAITING_AUTHORITY` (`ecf-dgii-activation.policy.ts:189`). No se
toca.

**D8 — Sin llamadas reales por configuración a medias.** Se reutilizan
`isAlanubeRealTransportSelected()` y `sandboxAccessRefusal()`
(`alanube-transport.provider.ts:42,47`) y el kill switch
(`apps/api/src/ecf/ecf-kill-switch.policy.ts`).

**D9 — Todo lo que no tenga integración oficial se resuelve con un
`CLIENT_ACTION` útil**: descarga segura del documento, instrucciones breves,
verificación de evidencia. Nunca un botón que "hace magia".

---

## 1. Diagnóstico consolidado (verificado en el repositorio)

| # | Hecho | Evidencia |
| --- | --- | --- |
| 1 | El cliente HTTP real no está en `ecf-alanube.client.ts`; ese archivo es un *readiness probe* (`getRuntimeState()`, `externalCallsBlocked: true`, `productionBlocked: true`) | `apps/api/src/ecf/ecf-alanube.client.ts:21-33` |
| 2 | El transporte único es `AlanubeHttpTransport` con transporte real/simulado/scenario y un *refusal* fail-closed | `alanube/alanube-safe-http.types.ts`, `alanube/alanube-transport.provider.ts:19-52` |
| 3 | Los 5 servicios de certificación faltantes ya están declarados como datos | `dgii/ecf-dgii-certification-reference.ts:132-156` (`ECF_CERTIFICATION_GAPS`) |
| 4 | El proceso oficial está modelado en 5 etapas / 15 pasos y el contrato del set de pruebas ya está fijado | `ecf-dgii-certification-reference.ts:20-120`, `ECF_SET_TESTS_CONTRACT` |
| 5 | Cada paso tiene dueño explícito por clase | `dgii/ecf-dgii-activation.policy.ts:51-71` |
| 6 | El motor no permite saltarse pasos: se detiene en el primero no resuelto que no es suyo | `ecf-dgii-activation.policy.ts:153-165` (`nextExecutableStep`) |
| 7 | Un resultado del transporte jamás completa un paso de la autoridad | `ecf-dgii-activation.policy.ts:183-197` (`stepStatusFromTransport`) |
| 8 | `executeStep()` es hoy un stub simulado: es el punto de extensión exacto | `ecf-dgii-activation.service.ts:308-352` |
| 9 | Ya existe compare-and-set por paso (solo una ejecución lo toma) y auditoría por transición | `ecf-dgii-activation.service.ts:233-297` |
| 10 | `EcfCertificationAttempt` existe con idempotencia, operación, externalId y errores | `prisma/schema.prisma:1122-1146` |
| 11 | `EcfCompanyConfiguration` ya guarda `alanubeCompanyId`, `environment`, `credentialsSecretRef`, `certificateSecretRef`, `webhookSecretRef` | `prisma/schema.prisma:1069-1093` |
| 12 | El certificado solo existe como **referencia** validada por formato (`secret://`, `vault://`, `env://`, `uat://`) | `apps/api/src/ecf/ecf-secret-reference.service.ts:34` |
| 13 | El motor ya bloquea arrancar sin datos fiscales o sin expediente enviado | `ecf-dgii-activation.policy.ts:129-139` (`activationBlockers`) |
| 14 | Existen endpoints de arranque, consulta y reintento por paso | `ecf.controller.ts:96,107,114` |
| 15 | La app sube archivos con `FormData` + `MultipartFile` y el API usa `FileInterceptor` | `ecf_repository.dart:177-196`, `ecf.controller.ts:309` |
| 16 | **Node 24 no soporta PKCS#12 de forma nativa** (`createPrivateKey({type:'pkcs12'})` → `The property 'options.type' is invalid`) y no hay `openssl` en PATH | verificado por ejecución local |
| 17 | No hay dependencia criptográfica de terceros en el API (solo `pdfkit`, `sharp`, `@types/multer`) | `apps/api/package.json` |
| 18 | Flutter no tiene `uploadCertificate`, `startIntelligentCertification`, `getProgress` ni `resume` | `ecf_repository.dart` (superficie completa) |

### 1.1 Corrección a la auditoría previa (para no arrastrar un error)

La auditoría anterior citaba `ecf-alanube.client.ts` como "cliente existente
probado para flujo e-CF". **Es impreciso**: ese archivo son 70 líneas de
diagnóstico. El HTTP vive en `apps/api/src/ecf/alanube/`. El plan se apoya en el
transporte real, no en un cliente que no existe.

---

## 2. Arquitectura objetivo

```text
Flutter (pantallas e-CF existentes)
   │  POST /ecf/dgii/certificate/validate   (multipart: PFX + contraseña, en memoria)
   │  POST /ecf/dgii/activation/start       (YA EXISTE)
   │  GET  /ecf/dgii/activation             (YA EXISTE)
   ▼
EcfController
   ▼
EcfCertificateController (nuevo, rutas del certificado)
   ▼
EcfCertificateInspector  ──────────────►  descarta el PFX (no persiste, no loguea)
   │  devuelve informe + huella SHA-256
   ▼
EcfDgiiActivationService  (EXISTENTE, se conserva)
   └── executeStep()  ──►  EcfCertificationOrchestrator (nuevo)
                              ├── EcfAlanubeCertificationClient (nuevo, 6 operaciones)
                              │      └── AlanubeHttpTransport (EXISTENTE)
                              ├── EcfCertificationAttempt (EXISTENTE, idempotencia)
                              ├── EcfOnboardingStep (EXISTENTE, estado por paso)
                              ├── EcfEvidence (EXISTENTE, artefactos)
                              └── EcfAuditLog (EXISTENTE)
```

Regla: **una sola fuente de estado por paso** (`EcfOnboardingStep`) y **una sola
fuente de intento** (`EcfCertificationAttempt`). El orquestador no guarda estado
propio en memoria entre peticiones.

---

## 3. BLOQUE A — Servicios Alanube

### 3.1 Qué ya existe (no se toca)

- `apps/api/src/ecf/alanube/alanube-safe-http.types.ts` — contrato `AlanubeSafeRequest/Response/Result`.
- `apps/api/src/ecf/alanube/alanube-transport.provider.ts` — selección fail-closed del transporte.
- `apps/api/src/ecf/alanube/alanube-real-http.transport.ts` — transporte HTTP real (sandbox).
- `apps/api/src/ecf/alanube/alanube-error-classifier.ts` — clasificación de errores del proveedor.
- `apps/api/src/ecf/alanube/alanube-response-interpreter.ts` — interpretación de respuestas.
- `apps/api/src/ecf/alanube/alanube-schema-validator.ts` — validación de esquema.
- `apps/api/src/ecf/alanube/alanube-retry.policy.ts` — política de reintento.
- `apps/api/src/ecf/alanube/alanube-contract-matrix.ts` — matriz de contratos por tipo.

### 3.2 Archivos nuevos

| Archivo | Contenido |
| --- | --- |
| `apps/api/src/ecf/alanube/certification/ecf-alanube-certification.contracts.ts` | Tipos y contratos puros: `AlanubeProviderInfo`, `AlanubeCompanyEnrollRequest` (`type: "associated"` + objeto `certificate`), `AlanubeCompanyInfo` (`companyUrls`), `AlanubeHabilitationSignRequest/Response`, `AlanubeSetTestsRequest/Response`, `AlanubeSetTestsStatus`, y el mapa `path → operación` de los 6 endpoints. |
| `apps/api/src/ecf/alanube/certification/ecf-alanube-certification.gaps.ts` | Mapa `ECF_CERTIFICATION_GAP_STATUS` que declara el estado de cada hueco de `ecf-dgii-certification-reference.ts` (`PENDING` → `IMPLEMENTED`). Se mantiene **fuera** del archivo de referencia para que ese siga siendo un fiel del PDF. |
| `apps/api/src/ecf/alanube/certification/ecf-alanube-certification.schemas.ts` | Validadores de respuesta por operación (usan `alanube-schema-validator.ts`), con rechazo explícito si falta un campo obligatorio. |
| `apps/api/src/ecf/alanube/certification/ecf-alanube-certification.client.ts` | Servicio `EcfAlanubeCertificationClient` con 6 métodos sobre el transporte inyectado. Sin HTTP propio. |
| `apps/api/src/ecf/alanube/certification/ecf-alanube-certification.client.spec.ts` | Pruebas unitarias con transporte falso. |

Métodos del cliente (firma propuesta):

```ts
getProviderInfo(ctx): Promise<ProviderInfoOutcome>
enrollCompany(ctx, { legalName, rnc, certificate: { p12Base64, password } }): Promise<CompanyEnrollOutcome>
getCompanyInfo(ctx, idCompany): Promise<CompanyInfoOutcome>
signHabilitation(ctx, { xml, idCompany, requestId }): Promise<SignOutcome>
createSetTests(ctx, { idCompany, retryNumber, billingIndicator, itemName, goodServiceIndicator, itemDescription, unitPriceItem }): Promise<SetTestsOutcome>
checkSetTests(ctx, idCompany): Promise<SetTestsStatusOutcome>
```

Cada método:

1. Construye `AlanubeSafeRequest` con `requestId` = clave de idempotencia (nunca aleatorio).
2. Aplica `timeoutMs` y la política de reintento existente (reintento **por operación**, no por proceso).
3. Interpreta `AlanubeTransportResult` con los módulos existentes.
4. Devuelve una unión discriminada **sin lanzar** excepciones de red: el motor decide.

### 3.3 Archivos modificados

| Archivo | Cambio exacto |
| --- | --- |
| `apps/api/src/ecf/alanube/alanube-contract-matrix.ts` | Registrar las 6 rutas de certificación con su tipo de contrato, para que la matriz siga siendo la fuente única. |
| `apps/api/src/ecf/alanube/alanube-simulated.transport.ts` | Respuestas deterministas y sintéticas para las 6 rutas (provider-info, company, company/{id}, sign-document, set-tests, check-set-tests). Nada de aleatoriedad. |
| `apps/api/src/ecf/alanube/alanube-scenario.transport.ts` | Escenarios `ok`, `reject`, `timeout`, `uncertain`, `already-enrolled` para las pruebas del motor. |
| `apps/api/src/ecf/alanube/alanube-contract-matrix.spec.ts` | Ampliar la matriz esperada a 6 contratos nuevos. |
| `apps/api/src/ecf/ecf.module.ts` | Proveer `EcfAlanubeCertificationClient` y el orquestador. |
| `apps/api/src/ecf/ecf-alanube.client.ts` | **Solo** ampliar `getRuntimeState()` con `certificationContracts: 6` y `companyAssociationReady`. Sin HTTP. |

### 3.4 Reglas de diseño del Bloque A

- **`idCompany` es del proveedor, `companyId`/`tenantId` es nuestro.** Toda consulta
  se ancla al `companyId` de la sesión (el token no lleva `idCompany` ajeno). El
  `idCompany` se lee de `EcfCompanyConfiguration.alanubeCompanyId`, nunca del
  cliente HTTP.
- **Protección de duplicados**: `enrollCompany` usa `idempotencyKey = enroll:<companyId>`;
  si ya existe `alanubeCompanyId`, no se re-enrola: se consulta (`getCompanyInfo`).
- **Estado incierto**: una respuesta ambigua **no se reintenta a ciegas**. Se marca
  el intento como incierto y se exige reconciliación (§7, M1).
- **Credenciales**: se resuelven con `EcfSecretResolverService` a partir de
  `credentialsSecretRef`; nunca se registran en logs ni en `requestRef`.
- **Errores del proveedor**: se mapean a códigos propios estables
  (`ECF_PROVIDER_REJECTED`, `ECF_PROVIDER_TIMEOUT`, `ECF_PROVIDER_CONTRACT_MISMATCH`,
  `ECF_PROVIDER_RESULT_UNKNOWN`) reutilizando `alanube-error-classifier.ts`.
- **Evidencias**: lo que el proveedor devuelva como artefacto (XML firmado, ZIP del
  set) se registra en `EcfEvidence` con `source = PROVIDER_ARTIFACT` y
  `storageRef`; nunca se guarda en el JSON de auditoría.

---

## 4. BLOQUE B — Certificado digital

### 4.1 Hallazgo que condiciona el diseño

Verificado por ejecución: **Node 24 no abre PKCS#12** y no hay `openssl` en el
equipo. Sin una dependencia, el backend no puede validar un PFX/P12.

### 4.2 Decisión propuesta (requiere tu aprobación)

Añadir **una** dependencia al API: `node-forge` (+ `@types/node-forge` en dev).
Motivos: es JavaScript puro (sin compilación nativa, funciona en el CI Node 20),
mantenida, y permite leer el contenedor PKCS#12, verificar que la clave privada
corresponde al certificado y recorrer la cadena, **todo en memoria**.

Alternativas evaluadas y descartadas para esta fase:

- Subir el PFX sin validar: inaceptable (el usuario no sabría si su certificado sirve).
- Validar en Flutter: la clave privada viajaría al cliente y el resultado no sería
  confiable; además la validación debe ser autoridad del servidor.
- `openssl` por `child_process`: depende de binarios externos y hace pasar secretos
  por línea de comandos. Descartado.

### 4.3 Archivos nuevos

| Archivo | Contenido |
| --- | --- |
| `apps/api/src/ecf/dgii/certificate/ecf-certificate.errors.ts` | Códigos estables: `ECF_CERTIFICATE_INVALID_FORMAT`, `ECF_CERTIFICATE_WRONG_PASSWORD`, `ECF_CERTIFICATE_EXPIRED`, `ECF_CERTIFICATE_NOT_YET_VALID`, `ECF_CERTIFICATE_NO_PRIVATE_KEY`, `ECF_CERTIFICATE_KEY_MISMATCH`, `ECF_CERTIFICATE_REPRESENTATIVE_MISMATCH`, `ECF_CERTIFICATE_TOO_LARGE`, `ECF_CERTIFICATE_UNSUPPORTED_ENCRYPTION`. |
| `apps/api/src/ecf/dgii/certificate/ecf-certificate-inspector.ts` | `inspectPkcs12(bytes, password)` → informe **sin secretos**: titular, emisor, número de serie, `notBefore/notAfter`, huella SHA-256 del DER del certificado, `hasPrivateKey`, `keyMatchesCertificate`, `chainLength`, `daysRemaining`. Cero `console.log`. Buffers de entrada puestos a cero al terminar. |
| `apps/api/src/ecf/dgii/certificate/ecf-certificate.policy.ts` | Reglas puras y testeables: vigencia (margen configurable), coincidencia con el representante (RNC/cédula del expediente), tamaño máximo (2 MB), extensiones admitidas (`.pfx`, `.p12`), antigüedad mínima del certificado. |
| `apps/api/src/ecf/dgii/certificate/ecf-certificate.service.ts` | Orquesta: recibe el archivo, aplica el *inspector*, aplica la *policy*, compara con `EcfDgiiApplicationSnapshot` (representante), escribe metadatos no secretos y audita sin material. |
| `apps/api/src/ecf/dgii/certificate/ecf-certificate-inspector.spec.ts` | Certificado válido, contraseña equivocada, caducado, sin clave privada, clave no coincidente, archivo corrupto, archivo gigante, extensión no admitida. |
| `apps/api/src/ecf/dto/ecf-certificate.dto.ts` | DTO del multipart (`password` con `@IsString()`, longitud acotada; nunca serializado en auditoría). |

### 4.4 Archivos modificados

| Archivo | Cambio exacto |
| --- | --- |
| `apps/api/src/ecf/ecf.controller.ts` | Ruta `POST /ecf/dgii/certificate/validate` con `@UseInterceptors(FileInterceptor("file"))` (patrón ya usado en la línea 309) y permiso `manageEcfDgiiRequirements`. |
| `apps/api/src/ecf/dgii/ecf-dgii-habilitation.service.ts` | Devolver en la vista un bloque `certificate` **sin secretos** (titular, caducidad, días restantes, huella corta) para que la UI muestre estado real. |
| `apps/api/src/ecf/ecf.module.ts` | Proveer el servicio y el inspector. |
| `apps/api/package.json` | `node-forge` + `@types/node-forge` (pendiente de aprobación). |

### 4.5 Cómo se procesa el certificado sin persistirlo

```text
1. Flutter envía multipart: file (bytes) + password (campo de texto).
2. El API limita tamaño ANTES de leer completo (límite del interceptor = 2 MB).
3. Se decodifica el PKCS#12 en memoria.
4. Se extraen metadatos NO secretos (huella, titular, vigencia).
5. Se compara con el representante del expediente.
6. Se devuelve el informe al cliente y se descarta el buffer.
7. Se persisten SOLO: huella SHA-256, titular, notAfter, fecha de validación.
8. La contraseña no aparece en: logs, `EcfAuditLog.after`, `requestRef`,
   `responseRef`, telemetría, ni en la respuesta HTTP.
```

Prohibiciones explícitas que el código debe cumplir y las pruebas verificar:

- No existe ninguna columna ni tabla para PFX, PEM ni contraseña.
- El DTO no se registra en logs (no se usa `@Log()` ni `console.log`).
- Las pruebas comprueban que ni el cuerpo de la petición ni la contraseña aparecen
  en `ecf_audit_logs` ni en `ecf_certification_attempts`.

### 4.6 Custodia (depende de Alanube)

| Opción | Descripción | Veredicto |
| --- | --- | --- |
| **B1 — preferida** | Upload directo del cliente a un endpoint/token de *enrollment* de Alanube: FullPOS nunca ve la clave privada. | Se planifica **si** Alanube lo confirma (§12, P11). |
| **B2 — aceptable con contrato** | FullPOS transmite el PFX y la contraseña **una vez**, por TLS, y no los persiste; Alanube queda como custodio. | Se planifica como respaldo. |
| **B3 — no se implementa** | Custodia propia (vault/HSM, rotación, operadores). | Excluida de este plan. |

En esta fase solo se implementa **la validación** (B1/B2 no se conectan todavía):
no hay envío de certificados a Alanube hasta que exista confirmación escrita.

---

## 5. BLOQUE C — Experiencia del cliente (solo pantallas e-CF existentes)

Se conserva el asistente único y las tres etapas **Solicitud · Pruebas ·
Certificación**. No se crea otro asistente ni se duplican formularios fiscales.

### 5.1 Archivos nuevos (Flutter)

| Archivo | Contenido |
| --- | --- |
| `apps/fulltech_app/lib/features/ecf/ui/ecf_habilitacion_video_card.dart` | Espacio 16:9 (`AspectRatio`) con `InkWell` de reproducción. Si no hay URL configurada, **no** se dibuja un reproductor falso: se muestra la guía escrita. Sin dependencia nueva: abre la URL en el navegador externo. |
| `apps/fulltech_app/lib/features/ecf/ui/ecf_certificate_card.dart` | Selector de PFX/P12 (`FilePicker` con `allowedExtensions: ['pfx','p12']`), campo de contraseña (`obscureText`), botón *Validar certificado*, resultado legible (✅/⚠️ con motivo y caducidad), y estado "registrado" cuando ya hay huella guardada. |
| `apps/fulltech_app/lib/features/ecf/ecf_certificate_models.dart` | `EcfCertificateReport` (validez, titular, caducidad, días, huella corta, motivos). |
| `apps/fulltech_app/lib/features/ecf/data/ecf_certificate_repository.dart` | `validate({bytes, fileName, password})` con `FormData` (patrón de `uploadDgiiDocument`). |
| `apps/fulltech_app/lib/features/ecf/data/ecf_certification_repository.dart` | `start()`, `progress()`, `retryStep(key)` sobre los endpoints **existentes**; no inventa rutas. |
| `apps/fulltech_app/test/features/ecf/ecf_certificate_card_test.dart` | Selección, contraseña vacía, resultado válido/inválido, sin desbordes a 360/768/1366. |
| `apps/fulltech_app/test/features/ecf/ecf_habilitacion_video_card_test.dart` | Sin URL → guía escrita; con URL → 16:9 y acción de abrir. |

### 5.2 Archivos modificados (Flutter)

| Archivo | Cambio exacto |
| --- | --- |
| `apps/fulltech_app/lib/core/api/api_routes.dart` | `ecfDgiiCertificateValidate`, `ecfDgiiActivation`, `ecfDgiiActivationStart`, `ecfDgiiActivationStepRetry(key)`. |
| `apps/fulltech_app/lib/features/ecf/ui/ecf_dgii_habilitation_page.dart` | En la etapa *prepare*: video + guía escrita + `EcfCertificateCard`. Botón principal del asistente: **"Iniciar postulación inteligente"** → `start()`. Barra de progreso por pasos usando `GET /ecf/dgii/activation` (ya existe), con etiquetas humanas por clase (`AUTOMATIC_LOCAL` → "Automático", `PROVIDER_WAIT` → "En manos del proveedor", `CLIENT_ACTION` → "Te toca a ti", `AUTHORITY_WAIT` → "Pendiente de la DGII"). Recuperación de estado al reabrir: el `GET` ya lo resuelve. |
| `apps/fulltech_app/lib/features/ecf/ecf_models.dart` | Modelos del `activation` (pasos, clase, estado) reutilizando `EcfDgiiBlocker` donde encaje. |
| `apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart` | Mostrar (solo lectura, admin) el estado de certificado y del transporte Alanube, sin exponer secretos ni rutas internas. |

### 5.3 Configuración del vídeo (sin hardcodeo)

El vídeo **no** se inventa ni se incrusta como activo. Se sirve como configuración
del servidor:

- Nueva clave en la respuesta de `GET /ecf/config`: `habilitacionVideoUrl` (vacío = no configurado).
- Origen: variable de entorno / `AppConfig` del backend, editable sin publicar la app.
- Si está vacía, la pantalla solo muestra la guía escrita y el enlace al portal
  oficial de la DGII.

Cambios asociados: `apps/api/src/ecf/ecf.controller.ts` (respuesta de `config`) y
`apps/api/src/ecf/dto/ecf.dto.ts`.

### 5.4 Reglas de UI (heredadas del módulo)

- Compacto y legible en Windows, Android y web; sin tarjetas decorativas.
- Nada de XML, `trackId`, `idCompany` ni JSON visible al cliente.
- Avisos arriba a la derecha (sistema `AppFeedback` ya adaptado), no barras inferiores.
- Toda acción oficial pendiente se explica en una frase y con un botón claro.

---

## 6. BLOQUE D — Orquestador inteligente

### 6.1 Dónde se enchufa (sin motor paralelo)

```text
EcfDgiiActivationService.runPendingSteps()      ← EXISTENTE, no se toca
   └── executeStep(key, className)              ← se reescribe el cuerpo
          ├─ AUTOMATIC_LOCAL  → resolución local (como hoy)
          ├─ PROVIDER_WAIT    → EcfCertificationOrchestrator.runStep(key)
          ├─ CLIENT_ACTION    → AWAITING_CLIENT con instrucción concreta
          └─ AUTHORITY_WAIT   → AWAITING_AUTHORITY (sin cambios)
```

El orquestador **no** guarda estado propio: lee el paso, resuelve prerrequisitos,
ejecuta la operación del proveedor, escribe `EcfCertificationAttempt` y devuelve
el resultado al motor, que es quien persiste `EcfOnboardingStep` y audita.

### 6.2 Archivo nuevo

`apps/api/src/ecf/dgii/ecf-certification-orchestrator.service.ts`

Responsabilidades:

1. Comprobar prerrequisitos por paso (empresa enrolada, certificado validado, expediente enviado).
2. Resolver o crear el intento idempotente en `EcfCertificationAttempt`.
3. Llamar al cliente de certificación del Bloque A.
4. Interpretar el resultado en la forma que el motor espera.
5. Registrar artefactos en `EcfEvidence` cuando existan.
6. Devolver `blockedReason` comprensible cuando falte una acción del cliente o de la DGII.

Secuencia por paso:

| Clave del catálogo | Clase hoy | Quién ejecuta en la fase final |
| --- | --- | --- |
| `FISCAL_DATA` | AUTOMATIC_LOCAL | Local (sin cambios) |
| `REQUIREMENTS` | CLIENT_ACTION | Cliente (sin cambios) |
| `DIGITAL_CERTIFICATE` | CLIENT_ACTION | Cliente sube y valida; el motor solo comprueba que hay certificado válido registrado |
| `ALANUBE_REGISTRATION` | PROVIDER_WAIT | **Orquestador** → `enrollCompany` / `getCompanyInfo` |
| `DGII_POSTULATION` | PROVIDER_WAIT | **Ver §6.3** (propuesta: CLIENT_ACTION) |
| `XML_SIGNATURE` | PROVIDER_WAIT | **Orquestador** → `signHabilitation` |
| `SET_TESTS` | PROVIDER_WAIT | **Orquestador** → `createSetTests` |
| `SIMULATIONS` | PROVIDER_WAIT | **Orquestador** → `checkSetTests` (consulta con reintento acotado) |
| `PRINTED_REPRESENTATION` | AUTOMATIC_LOCAL | Local (genera PDF de representación) |
| `SERVICE_URLS` | PROVIDER_WAIT | **Ver §6.3** (propuesta: CLIENT_ACTION) |
| `SWORN_DECLARATION` | CLIENT_ACTION | Cliente firma/presenta; el orquestador puede preparar el XML |
| `FINAL_AUTHORIZATION` | AUTHORITY_WAIT | DGII (sin cambios) |
| `ENCF_REQUEST` | PROVIDER_WAIT | Cliente en OFV (propuesta: ver §6.3) |
| `ROLE_ASSIGNMENT` | CLIENT_ACTION | Cliente en OFV (sin cambios) |
| `PRODUCTION_ENABLEMENT` | AUTHORITY_WAIT | Personal autorizado (sin cambios) |

### 6.3 Hallazgo: tres pasos pueden marcar completado algo que no lo está

Hoy `DGII_POSTULATION`, `SERVICE_URLS` y `ENCF_REQUEST` son `PROVIDER_WAIT`.
`stepStatusFromTransport` los marca `COMPLETED` en cuanto el transporte responde
"ok". Alanube **no documenta públicamente** la presentación de la postulación, el
registro de URLs ni la solicitud de numeración en el Portal DGII. Con llamadas
reales, ese "ok" significaría "el proveedor dijo que sí" y la pantalla diría
"presentado".

Dos opciones (se propone la primera):

**Opción 1 — reclasificar (recomendada, sin migración de datos).**
`DGII_POSTULATION`, `SERVICE_URLS` y `ENCF_REQUEST` pasan a `CLIENT_ACTION`. El
trabajo del proveedor (firma XML, `companyUrls`, generación) ocurre en
`XML_SIGNATURE` / `ALANUBE_REGISTRATION`. El resultado más honesto: el motor
nunca declara presentado lo que el cliente debe presentar.
Archivos: `ecf-dgii-activation.policy.ts` (mapa de clases) y su spec.

**Opción 2 — dividir los pasos** en `*_READY` (proveedor) y `*_PRESENTED` (cliente).
Da progreso más fino, pero exige cambiar el enum `EcfOnboardingStepKey`, migración
de datos existentes y ajustes en la UI. Se recomienda **no** hacerlo en esta fase.

### 6.4 Lo que el orquestador NO hace

- No presenta nada en el Portal DGII.
- No pide ni guarda credenciales del contribuyente.
- No usa un LLM.
- No inventa pasos ni estados nuevos.
- No continúa si un paso anterior no está resuelto.

---

## 7. Migraciones previstas

Dos, ambas aditivas y reversibles. **No se ejecutan en esta fase.**

### M1 — Estado de resultado incierto (necesaria)

```sql
-- prisma/migrations/<ts>_ecf_certification_attempt_unknown_result/migration.sql
ALTER TYPE "ecf_certification_attempt_status" ADD VALUE IF NOT EXISTS 'UNKNOWN_RESULT';
```

Motivo: distinguir "no se sabe si el proveedor lo aplicó" de "falló". Sin esto,
un timeout en `signHabilitation` obligaría a reintentar a ciegas (riesgo de doble
firma) o a marcar error (riesgo de falso negativo). Con `UNKNOWN_RESULT` el
sistema se detiene y pide reconciliación explícita.

Alternativa sin migración (si prefieres cero cambios de esquema): usar
`status = IN_PROGRESS` + `errorCode = ECF_PROVIDER_RESULT_UNKNOWN` y bloquear el
reintento automático. Pierde claridad semántica en reportes.

### M2 — Metadatos no secretos del certificado (recomendada)

```sql
ALTER TABLE "ecf_company_configurations"
  ADD COLUMN "certificate_fingerprint_sha256" VARCHAR(64),
  ADD COLUMN "certificate_subject"            VARCHAR(256),
  ADD COLUMN "certificate_expires_at"         TIMESTAMP(3),
  ADD COLUMN "certificate_validated_at"       TIMESTAMP(3);
```

Motivo: mostrar "certificado registrado, caduca el …" y detectar caducidad sin
guardar el certificado. Son datos públicos del certificado, no secretos.

Sin M2 la alternativa es no mostrar estado del certificado en la UI, lo cual
empeora la experiencia del punto 4 del objetivo.

**No se prevé ninguna migración** para `EcfOnboardingStep`, `EcfEvidence`,
`EcfAuditLog` ni `EcfDgiiHabilitation`: su forma actual es suficiente.

---

## 8. Orden de implementación por fases

Cada fase es pequeña, verificable y deja el sistema en verde. Ninguna fase avanza
sin tu aprobación de la anterior.

### F0 — Contratos y simulador (≈1 día)

Archivos: `ecf-alanube-certification.contracts.ts`, `...schemas.ts`, `...gaps.ts`,
`alanube-contract-matrix.ts`, `alanube-simulated.transport.ts`,
`alanube-scenario.transport.ts`, specs de contrato.

Criterio de GO: los 6 contratos están modelados, validados por esquema, y el
simulador responde de forma determinista a las 6 rutas. `npm test` verde.
Sin endpoints nuevos, sin UI.

### F1 — Cliente de certificación (≈1,5 días)

Archivos: `ecf-alanube-certification.client.ts` + spec.

Criterio de GO: 6 métodos con transporte falso; casos éxito, rechazo, timeout,
respuesta incierta y contrato inválido; **ninguna** excepción de red escapa.
`idCompany` siempre desde configuración por `companyId` de sesión.

### F2 — Certificado (≈2 días)

Archivos: `ecf-certificate.errors.ts`, `ecf-certificate-inspector.ts`,
`ecf-certificate.policy.ts`, `ecf-certificate.service.ts`, DTO, ruta en
`ecf.controller.ts`, migración M2, specs.

Criterio de GO: válido, contraseña incorrecta, caducado, sin clave privada, clave
no coincidente, representante distinto, archivo corrupto y archivo demasiado
grande devuelven códigos distintos y mensajes útiles. Pruebas negativas
demuestran que no se persiste ni se registra material ni contraseña.

### F3 — Orquestador y motor (≈2 días)

Archivos: `ecf-certification-orchestrator.service.ts`, `executeStep()` en
`ecf-dgii-activation.service.ts`, migración M1, reclasificación de §6.3,
`ecf.module.ts`, specs de integración con PostgreSQL aislado.

Criterio de GO: `POST /ecf/dgii/activation/start` recorre los pasos de proveedor;
un timeout deja el intento en `UNKNOWN_RESULT` y **no** reintenta solo; reiniciar
el proceso y volver a llamar reanuda sin duplicar; ningún paso de autoridad se
completa.

### F4 — Experiencia Flutter (≈2–3 días)

Archivos: `ecf_habilitacion_video_card.dart`, `ecf_certificate_card.dart`,
`ecf_certificate_models.dart`, `ecf_certificate_repository.dart`,
`ecf_certification_repository.dart`, `api_routes.dart`,
`ecf_dgii_habilitation_page.dart`, `ecf_models.dart`, `ecf_config_page.dart`,
pruebas de widget.

Criterio de GO: el cliente puede ver la guía, validar su certificado, pulsar
"Iniciar postulación inteligente", ver progreso por pasos, cerrar la app y
recuperar el estado. Sin desbordes a 320/390/768/1366. Sin barras inferiores.

### F5 — Endurecimiento (≈1 día)

Rate limit por empresa en las rutas de certificado, kill switch aplicado a las
llamadas de certificación, verificación de que la auditoría no contiene secretos,
documentación de operación.

Criterio de GO: matriz de pruebas del Bloque E completa y verde; informe de
seguridad sin hallazgos abiertos.

### F6 — (Requiere autorización externa)

Credenciales reales de Alanube, empresa piloto, custodia del certificado y
cualquier presentación en DGII. **Fuera del alcance de este plan.**

---

## 9. BLOQUE E — Matriz de pruebas

| Escenario | Dónde | Qué debe demostrar |
| --- | --- | --- |
| Certificado incorrecto (no PKCS#12) | F2 unitario | `ECF_CERTIFICATE_INVALID_FORMAT`, sin excepción no controlada |
| Contraseña PFX equivocada | F2 unitario | `ECF_CERTIFICATE_WRONG_PASSWORD`, sin filtrar material |
| Certificado caducado | F2 unitario | `ECF_CERTIFICATE_EXPIRED` con fecha legible |
| Representante distinto | F2 unitario | `ECF_CERTIFICATE_REPRESENTATIVE_MISMATCH` |
| Empresa ya asociada | F1 + F3 | No se re-enrola; se consulta `getCompanyInfo` |
| Error de Alanube | F1 | Código propio, mensaje seguro, sin stack del proveedor |
| Timeout | F1 + F3 | Intento en `UNKNOWN_RESULT`; el motor no reintenta solo |
| Reintentos | F1 | Política por operación; no repite una operación con clave ya usada |
| Operación incierta | F3 | Reconciliación explícita antes de continuar |
| Caída y reinicio | F3 integración | `start` reanuda desde el paso persistido |
| Acciones manuales | F3 + F4 | Pasos `CLIENT_ACTION` muestran instrucción y esperan evidencia |
| Reanudación tras evidencia | F3 | Registrar evidencia permite avanzar |
| Aislamiento multiempresa | F3 integración | Token de empresa A no ve ni opera sobre datos de B |
| e-CF desactivado | F3 | Motor bloqueado por `activationBlockers` |
| Sin regresiones POS tradicional | Suite completa | `flutter test` y `npm test` del API en verde |

Infraestructura: transportes simulados + PostgreSQL aislado (contenedor de
pruebas ya descrito en el entorno de UAT), sin llamadas externas reales.

---

## 10. BLOQUE F — Seguridad

| Activo | Control en este plan |
| --- | --- |
| Empresa / tenant | Toda consulta anclada al `companyId` de la sesión; `idCompany` solo leído de configuración; pruebas de aislamiento obligatorias |
| Certificado (PFX) | Solo en memoria; límite 2 MB; buffers a cero; sin logs |
| Contraseña del certificado | Solo en memoria; nunca en DTO serializado, auditoría, intentos, telemetría ni respuesta |
| Clave privada | Nunca se extrae a disco; nunca se registra |
| Referencias de secreto | Validación de formato existente (`secret://`, `vault://`, `env://`, `uat://`) |
| Consentimiento | Sin cambios: el de la postulación interna ya está versionado |
| Auditoría | Se audita la **operación** y el resultado, jamás el material |
| Estados legales | `AUTHORITY_WAIT` sigue intocable; sin autorización oficial no hay emisión real |
| E31/E32/E34 | No se toca ningún servicio de emisión; el E32 histórico no se modifica |
| Facturación electrónica | No se activa por defecto; `productionEnabled` sigue en `false` sin acción explícita |
| Credenciales del Portal DGII | No se solicitan, no se guardan, no se usan |

---

## 11. Criterios de aceptación globales

1. El cliente puede validar su certificado y ver un resultado comprensible.
2. "Iniciar postulación inteligente" ejecuta los pasos que el proveedor permite y
   **se detiene** explicando qué falta cuando no hay integración.
3. Ningún paso de DGII se marca completado por una respuesta del proveedor.
4. No existe en la base de datos ningún byte de PFX ni contraseña, y las pruebas
   lo demuestran.
5. Reiniciar el API y volver a entrar recupera el progreso sin duplicar operaciones.
6. `flutter analyze` sin hallazgos, `flutter test` verde, `npm test` del API verde,
   `tsc` del API sin errores.
7. POS tradicional, caja, inventario y emisión e-CF existente sin regresiones.
8. Ninguna llamada real a Alanube/DGII durante el desarrollo de F0–F5.

---

## 12. Bloqueos que requieren respuesta de Alanube o DGII

Sin estas respuestas, F6 no puede empezar y algunas piezas de F0–F5 quedan
declaradas como simulación.

### Alanube

1. ¿Una cuenta integradora puede certificar compañías `associated` completas por API?
2. ¿Existe endpoint para crear/recuperar la **postulación DGII**?
3. ¿Existe servicio para **presentar** el XML de postulación firmado?
4. ¿Existe API para subir los XML/PDF de las representaciones del set?
5. ¿Existe API para consultar la aprobación de representaciones?
6. ¿Existe API para registrar las **URLs productivas** en DGII?
7. ¿Existe API para obtener y presentar la **declaración jurada**?
8. ¿Ofrecen "managed certification" para partners?
9. ¿Qué credenciales del cliente necesita Alanube, si alguna?
10. ¿Alanube es custodio legal del PFX de compañías asociadas?
11. **¿Se puede subir el certificado sin almacenarlo en FullPOS (opción B1)?**
12. ¿Retención, cifrado, HSM/KMS, rotación y revocación del certificado?
13. ¿SLA y rate-limit de `set-tests`, `check-set-tests` y firma?
14. ¿Notificación de cambios de estado por webhook, polling o ambos?
15. ¿Base URL y alcance exacto del token para certificación **real** de asociadas?

### DGII

1. ¿Puede un integrador que opera sobre un proveedor certificado automatizar el Portal de Certificación en nombre del contribuyente?
2. ¿Existe API oficial, privada para proveedores certificados o canal B2B para postulación, RI, URLs y declaración?
3. ¿Qué mecanismo de delegación debe quedar registrado?
4. ¿Está permitida la automatización del Portal si el contribuyente consiente?
5. ¿Puede FullPOS transportar un PFX hacia Alanube sin ser custodio?
6. ¿Qué auditoría debe conservar el integrador?
7. ¿Qué operaciones exigen presencia explícita del representante?
8. ¿Roles y NCF deben permanecer manuales?

---

## 13. Qué queda funcional en simulación y qué sigue pendiente

**Funcional en simulación (F0–F5, sin respuestas externas):**

- Validación real de certificado PFX/P12 (no es simulación: es criptografía local).
- Enrolamiento de empresa, firma de habilitación, set de pruebas y consulta de
  estado **contra el transporte simulado**, con contratos validados.
- Orquestación completa, idempotencia, estados inciertos, reanudación y auditoría.
- Experiencia de cliente: guía, certificado, botón de arranque, progreso, acciones
  pendientes.

**Pendiente de autorización externa:**

- Certificación real de una empresa con Alanube en producción.
- Presentación de la postulación, representaciones impresas, URLs y declaración en
  el Portal DGII.
- Custodia del certificado por parte de Alanube (B1/B2).
- Asignación de roles y solicitud de NCF en OFV (seguirá siendo del cliente).
- Activación de emisión real (requiere autorización oficial verificable).

---

## 14. Estimación y dependencias

| Fase | Estimación | Depende de |
| --- | --- | --- |
| F0 Contratos + simulador | 1 día | — |
| F1 Cliente de certificación | 1,5 días | F0 |
| F2 Certificado | 2 días | Aprobación de `node-forge` y de M2 |
| F3 Orquestador + motor | 2 días | F1, F2, M1, decisión de §6.3 |
| F4 Experiencia Flutter | 2–3 días | F3 (endpoints estables) |
| F5 Endurecimiento | 1 día | F4 |
| **Total F0–F5** | **9,5–10,5 días-hombre** | — |
| F6 Piloto real | Fuera de alcance | Respuestas de §12 |

Son estimaciones de ingeniería, no compromisos de plazo. La variación principal
depende de las respuestas de Alanube y de DGII.

---

## 15. Decisiones que necesito de ti antes de implementar

1. **`node-forge`** como dependencia del API para validar PKCS#12. (Sí / No)
2. **Migración M2** (4 columnas de metadatos no secretos del certificado). (Sí / No / solo si hay alternativa)
3. **Migración M1** (`UNKNOWN_RESULT`) o la alternativa sin migración de §7. (Elegir)
4. **§6.3 Opción 1** (reclasificar `DGII_POSTULATION`, `SERVICE_URLS`, `ENCF_REQUEST`
   a `CLIENT_ACTION`) frente a la Opción 2 (dividir pasos). (Elegir)
5. **Orden de las fases**: ¿empezamos por **F0 + F1** (contratos Alanube) como
   pediste, o por **F2** (certificado) por ser el que ya aporta valor visible al
   cliente sin depender de respuestas externas? (Elegir)

Con esas cinco respuestas, F0 puede comenzar de inmediato y detenerse al final de
cada fase para tu revisión.

---

**FIN DEL PLAN — no se ha modificado ninguna línea de código.**
