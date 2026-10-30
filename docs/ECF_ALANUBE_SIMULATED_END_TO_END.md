# e-CF — Cadena simulada de extremo a extremo (POS → HTTP → PostgreSQL → Alanube simulado → estados)

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.
Sin `commit`, sin `push`, sin `deploy`. Producción, UAT histórica y volúmenes ajenos **intactos**.

---

## 1. La brecha real que se cerró

Los informes anteriores declaraban «simulador Alanube conectado de extremo a extremo:
pendiente». La auditoría encontró **dos** causas concretas, no una:

1. **Ninguna ruta HTTP cableaba `dispatchOnce`.** El orquestador de emisión existía
   completo (`documents/ecf-emission.service.ts`) pero era inalcanzable desde la API:
   el controlador lo decía explícitamente («There is NO emission endpoint here»). Por
   eso la cadena se detenía en la preparación.
2. **Los cuerpos del simulador no podían correlacionar.** `alanube-scenario.transport.ts`
   devuelve `{ id, documentStatus, mark }`, pero la observación local
   (`assessEcfProviderResponse`) exige el contrato local: `id` de 26 caracteres,
   `documentNumber` = e-NCF esperado, `companyIdentification` = RNC emisor, `status`,
   `sequenceConsumed` y `legalStatus`. Con los cuerpos anteriores **ninguna** respuesta
   simulada podía correlacionar: el estado persistido siempre habría sido «desconocido».

Sin arreglar (2), cablear (1) habría dado la falsa impresión de una cadena completa.

## 2. Arquitectura final del camino simulado

```
POS / cliente Flutter
  └─ POST /ecf/documents/:id/simulate-dispatch
        │  · Permissions("prepareEcfDocuments")
        │  · Política: solo UAT local y transporte real APAGADO
        ▼
     EcfSimulatedDispatchService
        │  · simulateAlanubeDispatchResponse(scenario, request)   ← cuerpo fiel al contrato local
        ▼
     EcfEmissionService.dispatchOnce(user, id, wire)
        │  1. reclama el intento ANTES de la "red" (FOR UPDATE + intento único)
        │  2. persiste SEND_IN_PROGRESS + registro de estado + intento
        │  3. "envía" (sin red, sin credenciales)
        │  4. assessEcfProviderResponse → correlación
        │  5. persiste el estado + recibo de evidencia (si correlaciona)
        ▼
     PostgreSQL (desechable)  →  GET /ecf/documents · /ecf/documents/:id · summary
        ▼
     Bandeja y detalle Flutter (los estados ya se agrupan: HUMAN_REVIEW_REQUIRED → REQUIRES_REVIEW)
```

**Regla de oro respetada:** `dispatchOnce` **nunca** concede aceptación de la DGII.
Una observación correlacionada de un 2xx acaba siempre en `HUMAN_REVIEW_REQUIRED`,
con su recibo de evidencia, para revisión humana. No existe camino a `DGII_ACCEPTED`
desde el simulador.

El transporte real sigue siendo inalcanzable: `createAlanubeHttpTransport` elige el
transporte real solo con `ALANUBE_HTTP_TRANSPORT_ENABLED=true` **y**
`ALANUBE_ENABLE_REAL_CALLS=true` **y** `ALANUBE_ENV=sandbox`, y esta ruta **no lo usa**:
trabaja contra la función pura del simulador.

## 3. Archivos modificados (todos nuevos salvo el controlador/módulo)

| Archivo | Papel |
| --- | --- |
| `apps/api/src/ecf/documents/ecf-simulated-dispatch.policy.ts` | **nuevo** — compuerta pura: UAT local y transporte real apagado |
| `apps/api/src/ecf/documents/ecf-simulated-dispatch.service.ts` | **nuevo** — adapta el simulador a `EcfEmissionWire` y llama a `dispatchOnce` |
| `apps/api/src/ecf/alanube/alanube-simulated-dispatch.response.ts` | **nuevo** — respuesta simulada **fiel al contrato local** (correlacionable), con `id` remoto estable |
| `apps/api/src/ecf/ecf-documents.controller.ts` | ruta `POST documents/:id/simulate-dispatch` |
| `apps/api/src/ecf/dto/ecf-documents.dto.ts` | `SimulateEcfDispatchDto` (escenario validado con `@IsIn`) |
| `apps/api/src/ecf/ecf.module.ts` | registra `EcfEmissionService` y el servicio nuevo |
| `apps/api/src/ecf/alanube/alanube-transport.provider.ts` | `isAlanubeRealTransportSelected` como **única** definición, usada por la fábrica y por la política |
| `apps/api/src/ecf/documents/ecf-simulated-dispatch.policy.spec.ts` | **nuevo** — 6 pruebas de la compuerta |
| `apps/api/src/ecf/documents/ecf-simulated-dispatch-postgres.integration-spec.ts` | **nuevo** — 9 pruebas E2E contra PostgreSQL |
| `apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart` | `simulateDispatch(...)` |
| `apps/fulltech_app/lib/features/ecf/ecf_models.dart` | `EcfSimulatedDispatchOutcome` |
| `apps/fulltech_app/lib/core/api/api_routes.dart` | ruta del despacho simulado |
| `apps/fulltech_app/test/features/ecf/ecf_simulated_dispatch_test.dart` | **nuevo** — 2 pruebas del contrato Flutter |

## 4. Defectos corregidos

1. **Emisión inalcanzable por HTTP** — `dispatchOnce` sin ruta. Resuelto con una ruta
   *exclusivamente simulada* (no se abrió ningún camino al proveedor real).
2. **Simulador no correlacionable** — cuerpos fuera del contrato local; con ellos la
   cadena no podía llegar a un estado observado. Resuelto con una capa adicional que
   respeta el contrato local y toma la identidad del propio payload (`idDoc.encf`,
   `sender.rnc`). El simulador original y sus 33 pruebas **no se tocaron**.
3. **Condición del transporte real duplicada** — vivía dentro de la fábrica. Ahora hay
   una única definición (`isAlanubeRealTransportSelected`) compartida por la fábrica y
   la política, para que no puedan divergir.

## 5. Evidencia de persistencia (de la ejecución real)

Del escenario `PROVIDER_ACCEPTED` en la suite de integración:

```
correlated: true            officialFiscalAcceptance: false     simulated: true
checks: HTTP_201 ✅ · OFFICIAL_SCHEMA ✅ · REMOTE_ID ✅ · DOCUMENT_NUMBER ✅
        COMPLETE ✅ · NUMBER_MATCH ✅ · COMPANY_MATCH ✅
        REMOTE_NOT_CONFLICTING ✅ · SEQUENCE_CONSISTENT ✅ · RESPONSE_CONSISTENT ✅
observation.providerOutcome: "ACCEPTED"      safeCode: "ECF_OBSERVED_ACCEPTED"
documents.status  = HUMAN_REVIEW_REQUIRED     externalDocumentNumber = e-NCF
recibos de evidencia = 1                      documentos en DGII_ACCEPTED / PROVIDER_ACCEPTED = 0
```

Persistencia real en PostgreSQL: estado del documento, registro de estado, intento
único y recibo de evidencia.

## 6. Pruebas ejecutadas (exactas)

```
pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "simulated-dispatch"
  -> Test Suites: 2 passed, 2 total
     Tests:       15 passed, 15 total

flutter analyze                     -> No issues found!
flutter test                        -> 1351 passed / 1 skipped
pwsh scripts/ecf-test-db/run-tests.ps1
  -> Test Suites: 1 skipped, 129 passed, 129 of 130 total
     Tests:       8 skipped, 1391 passed, 1399 total
     Historical UAT counts BEFORE/AFTER (companies,trials,documents): 708,568,3462
     ISOLATION OK: historical UAT unchanged by the automated suite.
npx tsc -p tsconfig.build.json --noEmit  -> exit 0
npx prisma validate                      -> schema is valid
git diff --check                         -> exit 0
```

Casos cubiertos por la suite nueva (15): permitido en UAT local; `UAT_LOCAL_ONLY`
solo; negativa con transporte real; negativa en producción/staging/vacío; aceptación
simulada correlacionada → revisión humana + evidencia; rechazo simulado; pendiente;
timeout (desconocido, sin evidencia); cuerpo malformado (falla cerrado); segundo
despacho rechazado; negativa sin tocar el documento (0 intentos de envío);
aislamiento entre empresas.

## 7. Matriz E31/E32/E34

| Tipo | Preparación | Despacho simulado | Estado resultante | Observaciones |
| --- | --- | --- | --- | --- |
| **E31** | `POST /ecf/documents/prepare` (consume numeración) | **Sí**, cubierto por la suite (fixture `validE31WithItbis`) | `HUMAN_REVIEW_REQUIRED` + evidencia | Único tipo con e-NCF asignado |
| **E32** | `POST /ecf/documents/prepare-consumo` (no consume cupo) | **Sí** (ruta genérica; el simulador es agnóstico del tipo) | `HUMAN_REVIEW_REQUIRED` | Su flujo de cupo único de sandbox sigue siendo un paso aparte |
| **E34** | `POST /ecf/documents/prepare-credit-note` | **Sí**, con las precondiciones de `dispatchOnce` | `HUMAN_REVIEW_REQUIRED` | Exige reserva de crédito ACTIVA y referencia al original; sin ellas la ruta rechaza |

No se asignó numeración fiscal real, no se transformaron ventas históricas y no se
declaró aceptación de la DGII en ninguno de los tres.

## 8. Aislamiento y seguridad

- `run-tests.ps1` deja la UAT histórica **exactamente** igual (708/568/3462 antes y
  después) y lo afirma con `ISOLATION OK`.
- La ruta es *tenant-scoped* (`requireTenant`) y el despacho de un documento ajeno
  responde `ECF_EMISSION_DOCUMENT_NOT_FOUND` (probado).
- Permiso requerido: `prepareEcfDocuments` (no se amplía el RBAC).
- Idempotencia: el segundo despacho se rechaza (`ECF_EMISSION_ALREADY_ATTEMPTED`).
- La negativa de política ocurre **antes** de tocar la base (0 intentos de envío).
- Marcado explícito: la respuesta lleva `simulated: true` y
  `officialFiscalAcceptance: false`, para que ni la interfaz ni la auditoría puedan
  confundirla con una aceptación oficial.

## 9. Riesgos y bloqueos

1. **Proveedor real y DGII: NO-GO.** Sin credenciales, contrato oficial validado ni
   autorización. `ALANUBE_ENABLE_REAL_CALLS=false` y el transporte real no se usa.
2. **Disparador desde la interfaz Flutter: pendiente.** La capa de datos está
   completa y probada (`simulateDispatch`, `EcfSimulatedDispatchOutcome`), pero **no
   se añadió el botón** en el detalle del comprobante. No se hizo a medias para no
   dejarlo sin verificar.
3. **Recorrido visual Windows: sigue BLOCKED** (Flutter no expone el árbol de
   accesibilidad y la inyección de teclas rompe `HardwareKeyboard`). Ver
   `docs/ECF_WINDOWS_AUTHENTICATED_UAT.md` §6.
4. **Concurrencia dura (dos despachos simultáneos)**: la suite prueba el segundo
   despacho *secuencial*; el `FOR UPDATE` + `updateMany` condicional lo cubren por
   diseño, pero **no hay aún una prueba con dos transacciones en paralelo**.
5. **`PROVIDER_ACCEPTED` y `DGII_ACCEPTED_SIMULATED` producen el mismo estado
   persistido** (`HUMAN_REVIEW_REQUIRED`). Es intencional —el simulador no decide
   fiscalidad—; conviene no leerlo como una distinción perdida.

## 10. GO / NO-GO

| Área | Estado |
| --- | --- |
| Cadena simulada POS → HTTP → PostgreSQL → simulador → estados | **GO** (15 pruebas) |
| Contrato Flutter del despacho | **GO** (capa de datos + 2 pruebas) |
| Aislamiento y seguridad | **GO** |
| Regresiones (Flutter 1351 / backend 1391, aislamiento OK) | **GO** |
| Disparador en la interfaz Flutter | **NO-GO** (pendiente, declarado) |
| Proveedor real / DGII / certificación | **NO-GO** |
| Recorrido visual Windows | **BLOCKED** |

**Global: GO WITH BLOCKERS** para la validación local simulada;
**NO-GO** para emisión real, certificación y producción.

## 11. Próximos pasos exactos

1. **Botón de validación en el detalle Flutter** (`_DetailBody` en
   `lib/features/ecf/ui/ecf_documents_page.dart`): selector de escenario + llamada a
   `simulateDispatch`, mostrando el resultado como **validación simulada**, nunca como
   aceptación. Cubrir con prueba de widget.
2. **Concurrencia real**: dos `dispatch` en paralelo sobre el mismo documento → uno
   debe ganar y el otro recibir `ECF_EMISSION_CONCURRENT_CLAIM`.
3. **E34 con reserva**: prueba E2E del despacho simulado de una nota de crédito con
   reserva ACTIVA y con reserva ausente (rechazo).
4. **Matriz de escenarios completa** (429, 500, conexión perdida, duplicado, fuera de
   orden, reintento idempotente) expuesta como suite E2E de la ruta.
5. **Certificación**: contratos oficiales (auth, envío, consulta, webhooks, firmas),
   credenciales de sandbox, numeración e-NCF y habilitación productiva — todo sigue
   pendiente de información oficial y autorización.
