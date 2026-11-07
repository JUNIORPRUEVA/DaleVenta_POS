# Validación definitiva multiempresa — asistente e-CF + facturación electrónica DOSA

Fecha: 2026-11-07
Rama: `agent/dosa-credentials-split-20261107`
HEAD: `2052ca77` (punto de partida real verificado con `git rev-parse`; 12 commits
desde `aad1e7b9`).

Este documento separa **lo que se ejecutó** de **lo que sólo se leyó** y de **lo
que no existe**. Todas las cifras de pruebas son salidas reales de comandos
ejecutados en esta sesión, contra PostgreSQL desechable. Ningún dato proviene de
producción.

---

## FASE 1 — Contrato: qué sabemos y con qué evidencia

### 1.1 Confirmado por DOSA (evidencia documental del proveedor)

| Hecho | Evidencia guardada |
| --- | --- |
| Cabecera `X-Dosa-Signature`, formato `t=<hora>,v1=<firma>` | `docs/ecf/research/DOSA_WEBHOOK_AND_TEST_EMISSION_STATUS.md` §2 |
| Fórmula `HMAC-SHA256(secreto, t + "." + cuerpoCrudo)` | Ídem + prueba de que un cuerpo re-serializado **no** valida |
| Estructura de `empresa.credenciales`: `{ api_key_produccion, api_key_test, api_secret }` | Muestra real sanitizada `03_WEBHOOK_EJEMPLO_SANITIZADO.json` |
| Endpoint de sesiones de certificación (`https://dosasystem.com`) | Confirmado |
| Endpoint de emisión (`EnviarFactura`) | `dosa-emission.client.ts` (`emissionPathFor`) |

### 1.2 Demostrado con FULLTECH real

- Intento 1 de FULLTECH y la reconciliación de proveedor: registrados y
  auditados; `effectiveIntentProvider = DOSA` (reportado en `a24c070b`).
- **No se volvió a tocar** ningún dato de FULLTECH en esta sesión.

### 1.3 Sólo demostrado con simulaciones UAT

- Asignación de e-NCF por rango de empresa.
- Construcción del documento fiscal (DOSA y Alanube).
- Despacho contra adaptador falso / simulador local.
- Webhooks firmados con secretos **ficticios**.
- Credenciales cifradas con clave maestra **sintética**.

### 1.4 Sin evidencia (declarado, no supuesto)

P1 unidad de `t` · P2 encoding del secreto · P3 identificador de entrega ·
P4 campo de tipo de evento · P5 catálogo completo de eventos · **P6 `api_secret`
por empresa o por ambiente** · P7 política de reintento · P8 reenvío manual ·
P9 rotación/revocación · P10 host TEST/PROD compartido · P11 condiciones
exactas de activación de credencial.

Detalle completo: `docs/ecf/DOSA_CONTRACT_STATUS.md` §1–§2.
Preguntas abiertas y su triaje: `docs/ecf/DOSA_CONTRACT_QUESTIONS_ALEJANDRO.md`.

**Advertencia explícita:** un webhook ficticio firmado con un secreto de prueba
demuestra que **nuestro receptor** verifica firmas; **no** demuestra que DOSA
haya generado credenciales reales para una empresa.

---

## FASE 2 — Asistente multiempresa

### 2.1 Dependencias analizadas

| Mecanismo | ¿De quién es la restricción? | Estado |
| --- | --- | --- |
| `ECF_PORTAL_PILOT_COMPANY_IDS` | **Interna de FullPOS** (era una lista de allowlist propia) | **Eliminada como requisito de alta**; queda sólo como compatibilidad de lectura |
| `DOSA_CERTIFICATION_SESSIONS_ENABLED` | **Mixta**: la bandera es nuestra, pero la apertura de sesión contra el proveedor exige que DOSA la habilite | Representada correctamente: `ECF_DOSA_SESSION_DISABLED` → fallback al portal público con boleto |
| Elegibilidad de la empresa | **Interna** | Persistente y auditable en `ecf_portal_enrollments` |

### 2.2 ¿El alta es automática?

**No, y es deliberado.** El nuevo mecanismo exige **una autorización
administrativa por empresa** (`POST …/portal-enrollments/:id/grant`), con motivo
obligatorio y, si aplica, referencia contractual y caducidad.

Por qué no se automatiza por RNC: autorizar el asistente no es un permiso
técnico, es un **acto comercial**. Un criterio automático del tipo «cualquier RNC
registrado entra» convertiría un alta de cliente en un efecto secundario de
rellenar un formulario, y dejaría el acceso al asistente sin responsable. La
regla automática **existe** pero está apagada por defecto
(`ECF_PORTAL_AUTO_ENROLL_ENABLED=false`) y, aun encendida, exige tres condiciones
verificables (e-CF habilitado + RNC registrado + postulación iniciada).

Lo que sí se eliminó es la **dependencia de infraestructura**: ya no hay que
editar variables del servidor ni reiniciar el servicio por cada cliente nuevo.
Es un cambio de *quién* decide (negocio, con registro) y no de *cuánto* cuesta
operarlo (cero intervención técnica).

### 2.3 Estado

`IMPLEMENTADA Y PROBADA` — ver §4 y las pruebas citadas en la matriz.

---

## FASE 3 — Facturación electrónica: auditoría del recorrido real

### 3.1 Recorrido implementado (verificado leyendo el código y ejecutándolo)

```text
POST /sales                              → venta del POS (aislada por companyId)
POST /ecf/documents/prepare               → EcfPreparationService.prepareFromSale
   ├─ assertCompanyCanPrepare             → e-CF habilitado, sandbox, tipo permitido
   ├─ EcfSaleFiscalAdapter.build          → sale.findFirst({ id, companyId })   ← aislamiento
   ├─ mapSaleSnapshotToEcfDocument        → documento fiscal interno
   ├─ EcfEmissionService.prepare
   │    ├─ resolveEncf → EcfSequenceService.allocate(user, tipo, {operationKey})
   │    └─ mapEcfToAlanubeDom + validación de contrato
   └─ persiste: ecf_electronic_documents (payloadSummary.emission.{encf,senderTaxId,payload})
POST /ecf/documents/:id/simulate-dispatch → EcfSimulatedDispatchService
   └─ EcfEmissionService.dispatchOnce → cable SIMULADO (Alanube), sólo UAT local
```

### 3.2 Los 14 puntos exigidos

| # | Comprobación | Resultado | Evidencia |
| --- | --- | --- | --- |
| 1 | RNC emisor sólo de la empresa autenticada | **CUMPLE** | `EcfSaleFiscalAdapter.build` filtra `{ id, companyId }`; barrera DOSA compara `emisor.RNCEmisor` con el RNC de la empresa y rechaza el resto |
| 2 | Credenciales por `companyId` + ambiente | **CUMPLE** | `DosaCredentialService.inspect/openForEmission({companyId, rnc, environment})` |
| 3 | Ninguna empresa usa la API Key de otra | **CUMPLE** | Prueba «las claves de una empresa no se usan para otra» (X/Y) |
| 4 | TEST nunca usa PRODUCCIÓN ni al revés | **CUMPLE** | Sin fallback: `ECF_DOSA_CREDENTIALS_MISSING_FOR_ENVIRONMENT`; cliente cacheado por `empresa\|rnc\|ambiente\|huella` |
| 5 | Secuencias e-NCF de la empresa y del tipo | **CUMPLE** | `EcfSequenceService.allocate`; prueba de independencia H/I |
| 6 | Aislamiento de ventas, clientes, sucursales, config fiscal | **CUMPLE** | Esquema y consultas por `companyId`; e2e de aislamiento |
| 7 | Una factura de A jamás con RNC/numeración/clave de B | **CUMPLE** | Cuerpo inspeccionado en el adaptador falso |
| 8 | Recibir credenciales no habilita emisión | **CUMPLE** | `PENDING_CONFIRMATION` bloquea (`ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE`), caso E |
| 9 | Certificación/autorización/banderas antes del despacho | **CUMPLE** | `assessDosaEmissionGate` se evalúa **antes** de abrir la bóveda |
| 10 | Reintentos sin duplicar facturas ni e-NCF | **CUMPLE** | `operationKey` reutiliza el número; `idempotencyKey` corta el segundo envío; `dispatchOnce` reclama con `FOR UPDATE` y una sola tentativa `SEND_TO_PROVIDER` |
| 11 | Respuestas/errores/referencias por empresa | **PARCIAL** | Se persisten en `dispatchOnce` (evidencia + intentos). `DosaEmissionService.emit` **devuelve** el resultado pero **no lo persiste** |
| 12 | Anulaciones y notas de crédito con la misma separación | **CUMPLE** | E34 con reserva de crédito obligatoria por empresa (`E34_DISPATCH_REQUIRES_RESERVATION`) |
| 13 | Venta normal funciona con e-CF deshabilitado | **CUMPLE** | Caso B: la venta se crea y la preparación se rechaza con `ECF_COMPANY_DISABLED` |
| 14 | Sin dependencias del RNC de FULLTECH ni valores fijos | **CUMPLE** | `expectedTestRnc = input.rnc`; sin RNC en código ni en entorno |

### 3.3 Diferencias de estado que NO se confunden

| Estado | Significado |
| --- | --- |
| `LOCAL_VALIDATED` | El documento existe, es coherente y tiene e-NCF. **No ha salido nada.** |
| `SEND_IN_PROGRESS` | Se reclamó la tentativa; el envío puede estar ocurriendo |
| `HUMAN_REVIEW_REQUIRED` | Hubo respuesta correlacionada del proveedor; **no** es aceptación fiscal |
| Aceptación del proveedor | Sólo con respuesta real de DOSA. No demostrado |
| Aceptación fiscal DGII | **Nunca** se concede automáticamente. No demostrado |

### 3.4 PIEZA FALTANTE (defecto real de arquitectura)

> **ACTUALIZACIÓN 2026-11-07 (commit `53db1157`).** Esta pieza **ya está
> implementada y probada con transporte falso**:
> `DosaEmissionDispatchService` + `POST /ecf/documents/:id/dispatch-dosa`. Lo que
> sigue se conserva como registro del hallazgo original; el estado vigente está
> en `docs/ecf/ECF_DOSA_EMISSION_ORCHESTRATION.md`. La emisión **real** sigue
> bloqueada por P1/P2/P6 y por el propio encargo.

**No existe orquestación de emisión DOSA desde una venta.** Hechos verificados:

1. `DosaEmissionService.emit` (compuerta + credenciales + cliente) **no tiene
   ningún llamador** en el código de producción.
2. `DosaEmissionWire` (el cable que conectaría DOSA con `dispatchOnce`) **nunca se
   instancia**, ni en producción ni en pruebas.
3. La única ruta de despacho es `POST /ecf/documents/:id/simulate-dispatch`, que
   usa el **simulador de Alanube**, no DOSA.
4. La propia API declara `emissionPathAvailable: false` y
   `simulatedDispatchPathAvailable: true` en `GET /ecf/capabilities`.

Consecuencia: hoy FullPOS puede **preparar** un comprobante por empresa con su
RNC, su numeración y su configuración fiscal, y puede **despacharlo a un
simulador**, pero **no puede emitirlo por DOSA**.

Además, hay un desajuste latente que un orquestador ingenuo heredaría:
`payloadSummary.emission.payload` guarda el **DOM de Alanube**, mientras DOSA
exige su propio contrato (`encabezado` + `detallesItems`). Enviar el primero al
cliente de DOSA produciría un comprobante mal formado. Por eso las pruebas de
esta sesión construyen el cuerpo con `mapEcfToDosaDraft` a partir del documento
fiscal persistido, que es exactamente lo que deberá hacer el orquestador.

**No se implementó el orquestador en esta sesión** porque el encargo prohíbe
cambiar el diseño del producto y porque un camino de emisión real exige además
resolver P1/P2/P6 (firma y secreto). Se identifica, se demuestra qué falta y se
declara.

---

## FASE 4 — Prueba integral con cinco empresas (ejecutada)

Archivo: `apps/api/src/ecf/integration/multi-company-e2e.integration-spec.ts`
(12 casos, **12 PASS**). PostgreSQL desechable creado y destruido por la propia
prueba; adaptador DOSA falso que **no abre ningún socket**.

Escenarios: A (flujo completo), B (sin e-CF), C (TEST/PROD separadas),
C2 (PRODUCCIÓN no autorizada), D (RNC ambiguo), E (credencial no activa),
F (RNC ajeno en el cuerpo), G (reinicio del backend), H+I (concurrencia),
X/Y (claves cruzadas), J (reintento sin duplicado), aislamiento B↔A.

### Matriz de resultados

Leyenda: **IP** Implementada y probada · **ISV** Implementada sin validación
funcional · **PEND** Pendiente · **BLQ** Bloqueada por requisito externo.

| Función | A | B | C | D | E |
| --- | --- | --- | --- | --- | --- |
| Registro | IP | IP | IP | IP | IP |
| Asistente (elegibilidad) | IP | IP | IP | IP | IP |
| Postulación | IP | IP | IP | IP | IP |
| Webhook firmado | IP¹ | IP¹ | IP¹ | IP² | IP¹ |
| Credenciales TEST | IP | — | IP | IP² | IP |
| Credenciales PRODUCCIÓN | — | — | IP (bloqueada para emitir) | — | — |
| Autorización de emisión | IP | **no autoriza** | IP | **no autoriza** | **bloquea** |
| Venta POS | IP | IP | IP | IP | IP |
| e-NCF | IP | — | IP | — | IP |
| JSON fiscal | IP | — | IP | — | IP |
| Selección de credenciales | IP | — | IP (TEST) | — | rechaza |
| Despacho simulado (adaptador falso) | IP³ | — | IP³ | — | **0 peticiones** |
| Estado final | IP⁴ | IP | IP⁴ | IP | IP |
| Aislamiento | IP | IP | IP | IP | IP |

¹ Cubierto por `dosa-webhook-postgres.integration-spec.ts` (dos empresas con RNC
propios no se contaminan; doble entrega no duplica; ninguna credencial llega a la
fila persistida).
² Escenario de conflicto/ambigüedad: el resolutor devuelve `null` y **no elige** a
ninguna empresa; el evento queda en revisión sin afectar a las demás.
³ Contra el **adaptador falso**. Ningún despacho real a DOSA.
⁴ El estado final es de preparación/simulación, **nunca** aceptación fiscal.

---

## FASE 5 — Interfaz

**NO EJECUTADA.** `mcp_playwright_browser_navigate` respondió «currently disabled
by the user» (segundo intento, misma respuesta). No se ejecutó **ninguna**
interacción de interfaz.

Procedimiento manual reproducible con evidencia exigida:
`docs/ecf/ECF_PORTAL_UI_VALIDATION_PROCEDURE.md`.

No se declara la interfaz aprobada por compilar. Compilar no es validar.

---

## FASE 6 — Dependencias manuales, clasificadas

| # | Dependencia | Clase | Estado |
| --- | --- | --- | --- |
| 1 | Añadir el RNC de un cliente a `ECF_PORTAL_PILOT_COMPANY_IDS` y reiniciar | **A** interna | **ELIMINADA** (inscripción en base de datos) |
| 2 | Editar `.env` para la emisión de cada empresa | **A** interna | **ELIMINADA**: la credencial se lee por `companyId` + ambiente desde la fila cifrada; `expectedTestRnc` es el RNC de la empresa, no una variable |
| 3 | Crear credenciales a mano en PostgreSQL | **A** interna | **CUBIERTA**: `POST /webhook/dosa` autenticado + promoción con evidencia (`promote`) |
| 4 | Redesplegar por cada empresa | **A** interna | **ELIMINADA**: decisiones leídas en cada petición |
| 5 | Cambiar el proveedor fiscal de cada cliente a mano | **C** operativa | Existe `PATCH /ecf/config`, pero la habilitación sigue siendo un acto administrativo. Proceso: configuración guiada + auditoría |
| 6 | Asignar secuencias/permisos sin flujo administrativo | **C** operativa | `POST /ecf/sequences` por empresa con permisos; asignación es acto administrativo auditado |
| 7 | Secreto global tratado como si fuera de una empresa | **A** interna | **CORREGIDA**: credenciales cifradas por `(empresa, ambiente)` con AAD `companyId:rnc:environment`; `api_secret` único es limitación declarada (P6) |
| 8 | `DOSA_TEST_RNC` como identidad de prueba | **A** interna | **CORREGIDA**: se usa el RNC de la empresa emisora |
| 9 | Habilitar la certificación e-CF de un cliente | **B** externa (acto administrativo + requisito DGII) | Requiere autorización humana; no se automatiza |
| 10 | Activar credenciales (`PENDING_CONFIRMATION` → `ACTIVE`) | **B** externa | Exige evidencia: identidad vinculada, postulación, confirmación del proveedor, DGII, autorización administrativa |
| 11 | Conceder acceso al asistente a una empresa nueva | **C** operativa (nueva) | `POST …/portal-enrollments/:id/grant` con motivo, autor y caducidad. Una acción de negocio, no de infraestructura |

---

## FASE 7 — Informe final

### 7.1 Defectos reales encontrados

| # | Defecto | Severidad | Estado |
| --- | --- | --- | --- |
| 1 | **No hay orquestación de emisión DOSA**: `DosaEmissionService.emit` sin llamadores y `DosaEmissionWire` sin instanciar | **CRÍTICO** para facturación | **IDENTIFICADO, NO CORREGIDO** (exige decisión de diseño + P1/P2/P6) |
| 2 | Desajuste de payload latente: se guarda DOM de Alanube, DOSA exige su contrato | **ALTO** | IDENTIFICADO; las pruebas evitan la trampa usando `mapEcfToDosaDraft` |
| 3 | `DosaEmissionService.emit` devuelve el resultado pero **no lo persiste** | **ALTO** | Identificado |
| 4 | La prueba integral dejaba `DATABASE_URL` apuntando a la base que ella destruye, contaminando las suites siguientes | MEDIO (pruebas) | **CORREGIDO** (`setEnv`) |
| 5 | La prueba integral asumía que dos empresas con secuencias propias debían tener e-NCF distinto | BAJO (prueba) | **CORREGIDO**: dos rangos independientes empiezan igual; se verifica el rango de cada empresa |
| 6 | La prueba integral trataba un rechazo fiscal (`201` + `ok:false`) como error HTTP | BAJO (prueba) | **CORREGIDO**: se comprueba el código fiscal |
| 7 | La base desechable tenía datos de ejecuciones previas y rompía suites no idempotentes | MEDIO (entorno) | **CORREGIDO** recreando y migrando la base |

Ninguno de los defectos 1–3 se ocultó ni se disfrazó con una prueba artificial.

### 7.2 Archivos modificados en esta sesión

- `apps/api/src/ecf/integration/multi-company-e2e.integration-spec.ts` (**nuevo**, commit `2052ca77`): prueba integral de cinco empresas con adaptador DOSA falso.

Motivo: es la única pieza nueva necesaria para demostrar la facturación
multiempresa. No se modificó código de producción en esta sesión.

### 7.3 Pruebas nuevas y resultados

```text
npx jest --runInBand src/ecf/integration/multi-company-e2e
→ 1 suite · 12 tests · 12 PASS

npx jest --runInBand src/ecf                        → 146 suites · 1892 PASS
npx jest --runInBand --testPathIgnorePatterns=\.e2e-spec\.ts$ → 248 suites · 2957 PASS
npx jest --runInBand --testPathPatterns "\.e2e-spec\.ts$"     → 18 suites · 163 PASS
npx tsc -p tsconfig.build.json --noEmit             → exit 0
```

Todo contra `fullpos_ecf_ephemeral_test` (127.0.0.1:56701), recreada y migrada
antes de cada corrida; 75 migraciones.

### 7.4 Qué no se puede demostrar sin DOSA real

- Que DOSA acepte un comprobante y devuelva un `trackId` real.
- Que la DGII acepte el e-CF.
- Que la firma del webhook funcione con el secreto real (P1, P2).
- Que `api_secret` sea único por empresa (P6).
- Que las credenciales entregadas por webhook sean las que DOSA emitió de verdad.

### 7.5 Qué falta para un despliegue controlado

1. Implementar el orquestador de emisión DOSA (documento preparado → cuerpo DOSA
   → compuerta → `dispatchOnce` con `DosaEmissionWire` → persistencia).
2. Resolver P1/P2 (unidad de `t`, encoding del secreto) antes de cualquier envío
   real: con la suposición equivocada se rechaza todo.
3. Validar la interfaz con el procedimiento de Fase 5.
4. Corregir el desajuste de payload (DOSA vs Alanube) en la misma pieza.

### 7.6 GO / NO-GO

| Ámbito | Veredicto | Motivo |
| --- | --- | --- |
| **Asistente multiempresa** | **GO** | Elegibilidad persistente por empresa, sin variables por cliente; aislamiento probado en unitario, PostgreSQL real y HTTP; 12 casos integrales + 8 HTTP + 30 del portal |
| **Facturación electrónica multiempresa** | **GO para emisión simulada** | Orquestador implementado y probado por HTTP con transporte falso; **emisión real NO-GO** hasta resolver P1/P2/P6 |
| **Despliegue en UAT** | **GO WITH ISSUES** | Desplegable: migraciones aditivas, banderas apagadas, transporte real inaccesible. La interfaz queda sin validar |
| **Producción** | **NO-GO** | P1/P2/P6 sin resolver + interfaz no validada + emisión real nunca ejecutada |

No se confunde ninguna capa: **pruebas de backend** (verdes) ≠ **pruebas de
interfaz** (no ejecutadas) ≠ **pruebas con DOSA real** (ninguna).
