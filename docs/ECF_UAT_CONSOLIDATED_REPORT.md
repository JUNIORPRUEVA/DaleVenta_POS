# e-CF — Informe final consolidado (UAT, interfaz, concurrencia, E34, preparación DGII)

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.
Sin `commit`, sin `push`, sin `merge`, sin `deploy`. Producción intacta.

---

## 1. Diagnóstico inicial (verificado en esta ejecución)

| Comprobación | Resultado |
| --- | --- |
| Rama / worktree | `feature/ecf-alanube` en `FULLPOS-ECF-ALANUBE` |
| Cambios locales preservados | **89** entradas sin confirmar: no se descartó nada |
| Único punto capaz de construir el transporte REAL | `alanube-transport.provider.ts:10` (más sus pruebas) |
| Compuerta del transporte real | `isAlanubeHttpTransportSelected` = `ALANUBE_HTTP_TRANSPORT_ENABLED=true` **Y** `ALANUBE_ENABLE_REAL_CALLS=true` **Y** `ALANUBE_ENV=sandbox` |
| Entorno UAT visual | `APP_ENV=uat`, `UAT_LOCAL_ONLY=true`, `ALANUBE_ENABLE_REAL_CALLS=false`, `ALANUBE_HTTP_TRANSPORT_ENABLED=false`, `ECF_EMISSION_ENABLED=false` |
| Aislamiento | Sonda de solo lectura a la UAT histórica: **708|568|3462** (sin cambios) |

El simulador no puede hablar con el proveedor real: la ruta `simulate-dispatch` usa la
función **pura** `simulateAlanubeDispatchResponse`, nunca un cliente HTTP.

## 2. Funciones ya existentes (no se reimplementaron)

Módulo e-CF por empresa, interruptor en Configuración de empresa, entrada condicionada
en el Drawer, bandeja y detalle, preparación E31/E32/E34, estados fiscales, idempotencia,
numeración reservada, documento fiscal inmutable, evidencia, simulador Alanube (16
escenarios), perfil UAT protegido, endpoint `simulate-dispatch`.

## 3. Cambios implementados en esta ejecución

### Fase 2 — Interfaz Flutter (lo que estaba declarado pendiente)

- **`lib/features/ecf/ui/ecf_simulated_dispatch_action.dart`** (nuevo): acción de
  **despacho simulado** en el detalle del comprobante.
  - Aviso obligatorio, literal: **«SIMULACIÓN — NO VÁLIDO COMO ACEPTACIÓN DGII.»**
  - Selector de escenario (5 escenarios útiles) + botón, con indicador de carga y
    **protección contra doble pulsación**.
  - Panel de resultado: escenario, resultado observado, correlación, código y
    «Aceptación fiscal oficial: **no**».
  - Mensajes diferenciados de **éxito / error de red / bloqueo del backend** (409 con el
    código de la política).
  - Al ejecutar: invalida detalle, bandeja y contadores → el estado se refresca desde el
    servidor (fuente única de verdad).
  - Compuertas: perfil UAT **y** empresa con e-CF activo **y** permiso
    `prepareEcfDocuments` **y** estado despachable. Fuera de eso, no se renderiza nada.
  - La compuerta UAT se expone como provider para poder probarla sin `--dart-define`.
- Insertada en `_DetailBody` (`ecf_documents_page.dart`) y corregido el comentario de la
  página, que afirmaba que no existía ninguna acción de emisión.

### Fase 3 — Concurrencia real sobre PostgreSQL

- **`ecf-simulated-dispatch-concurrency-postgres.integration-spec.ts`** (nuevo): las
  solicitudes se lanzan **a la vez** (`Promise.allSettled`), no en secuencia.
  - 2 despachos simultáneos → **exactamente 1 gana**, 1 intento de envío, 1 recibo de
    evidencia, estado `HUMAN_REVIEW_REQUIRED`, 0 en `DGII_ACCEPTED`/`PROVIDER_ACCEPTED`.
  - 5 despachos simultáneos → sigue habiendo **1** ganador.
  - Dos empresas a la vez → ambas correctas, **aisladas**.
  - Timeout + reintento → el reintento se rechaza, **no hay segunda emisión**.

## 4. Defectos encontrados y corregidos

| # | Defecto | Estado |
| --- | --- | --- |
| 1 | `dispatchOnce` sin ruta HTTP: la cadena no era alcanzable | **Corregido** (ejecución anterior) |
| 2 | Cuerpos del simulador no correlacionables con el contrato local | **Corregido** (ejecución anterior) |
| 3 | `Env.appBaseUrl` descartaba localhost y caía a la URL pública de producción | **Corregido** (ejecución anterior) |
| 4 | Comentarios que declaraban «no existe acción de emisión» tras cablearla | **Corregido** en esta ejecución |
| 5 | `FINAL_GATE` afirmaba «ningún endpoint cablea el despacho» | **Corregido** (ejecución anterior) |

No se encontraron condiciones de carrera: los guardas existentes
(`FOR UPDATE` + `updateMany` condicional + intento único) resisten la contención real.

## 5. Archivos modificados en esta ejecución

| Archivo | Papel |
| --- | --- |
| `apps/fulltech_app/lib/features/ecf/ui/ecf_simulated_dispatch_action.dart` | **nuevo** — acción de validación |
| `apps/fulltech_app/lib/features/ecf/ui/ecf_documents_page.dart` | inserta la acción + corrige el comentario |
| `apps/fulltech_app/test/features/ecf/ecf_simulated_dispatch_action_test.dart` | **nuevo** — 9 pruebas |
| `apps/api/src/ecf/documents/ecf-simulated-dispatch-concurrency-postgres.integration-spec.ts` | **nuevo** — 4 pruebas de concurrencia |
| `docs/ECF_UAT_CONSOLIDATED_REPORT.md` | **nuevo** — este informe |

**Migraciones creadas: ninguna** (no se necesitó cambiar el esquema).

## 6. Resultados reales de pruebas

```
flutter analyze                        -> No issues found!
flutter test                           -> 1362 passed / 1 skipped
pwsh scripts/ecf-test-db/run-tests.ps1
  -> Test Suites: 1 skipped, 130 passed, 130 of 131 total
     Tests:       8 skipped, 1395 passed, 1403 total
     Historical UAT counts BEFORE/AFTER: 708,568,3462  ->  ISOLATION OK
pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "simulated-dispatch"
  -> Test Suites: 3 passed, 3 total      Tests: 19 passed, 19 total
npx tsc -p tsconfig.build.json --noEmit -> exit 0
npx prisma validate                     -> schema is valid
git diff --check                        -> exit 0
docker exec <uat-historica> psql ...    -> 708|568|3462 (sin cambios)
```

Ninguna prueba fue omitida salvo las 8 ya marcadas como `skip` por diseño (opt-in) y la
suite e2e de CI. **Omitidas por bloqueo: las visuales** (§9).

## 7. Evidencia de concurrencia

```text
2 despachos simultáneos  -> fulfilled: 1 | rejected: 1
                            SEND_TO_PROVIDER = 1 | recibos de evidencia = 1
                            estado = HUMAN_REVIEW_REQUIRED | DGII_ACCEPTED/PROVIDER_ACCEPTED = 0
5 despachos simultáneos  -> fulfilled: 1 | SEND_TO_PROVIDER = 1 | recibos = 1
2 empresas simultáneas   -> ambos fulfilled | cada empresa no ve el documento de la otra
timeout + reintento      -> reintento rechazado | SEND_TO_PROVIDER = 1 | recibos = 0
```

## 8. Evidencia de compatibilidad tradicional (e-CF apagado)

- `ecf.service.spec.ts` → «creates an e-CF config **disabled by default** without touching
  fiscal settings».
- `ecf-pre-emission.guard.spec.ts` → «blocks global emission disabled».
- `ecf-processing-queue.policy.spec.ts` → «does not enqueue when emission is disabled».
- `ecf-sale-adapter.spec.ts` → «maps a stable sale snapshot **without touching sales
  services**»: el adaptador e-CF es de solo lectura sobre la venta y no modifica el flujo
  de ventas, caja, inventario ni NCF tradicional.
- La suite completa (1395 pruebas, 130 suites) incluye ventas, NCF, caja, inventario,
  clientes, cotizaciones y licencias: todas en verde.

**Sin datos concluyentes en contra:** no se modificó ningún endpoint tradicional.

## 9. Estado del simulador

16 escenarios disponibles; correlacionan los que representan respuesta del proveedor
(identidad tomada del payload: `idDoc.encf`, `sender.rnc`). Los de transporte
(timeout, 429, 500, conexión perdida, cuerpo ilegible) **no** correlacionan a propósito.
El simulador **nunca** concede aceptación de la DGII: la cadena termina en
`HUMAN_REVIEW_REQUIRED` con recibo de evidencia.

## 10. Estado E31 / E32 / E34

| Tipo | Preparación | Despacho simulado | Concurrencia | Observaciones |
| --- | --- | --- | --- | --- |
| **E31** | GO | GO (E2E, 9 casos) | GO | Consume numeración en la preparación |
| **E32** | GO | GO (ruta genérica) | GO | No consume cupo de empresa |
| **E34** | GO | GO por la ruta genérica | GO | Precondiciones cubiertas por `ecf-e34-emission-postgres.integration-spec.ts`: sin reserva → `E34_DISPATCH_REQUIRES_RESERVATION`; nota total/parcial; exceso rechazado; original no aceptado rechazado; original de otra empresa rechazado; idempotencia; rechazo/timeout conservan la reserva; «solo un despacho efectivo bajo concurrencia» |

Las precondiciones E34 **no** se re-probaron por la ruta nueva: usan el mismo
`dispatchOnce`, así que los guardas aplican sin cambios. Se declara tal cual.

## 11. Preparación del proceso DGII (Fase 8) — diseño, NO implementado

Máquina de estados de **incorporación**, separada de la activación operativa
(`EcfCompanyConfiguration.enabled`). Diseño propuesto:

| Estado | Depende de | ¿Automatizable por FullPOS? |
| --- | --- | --- |
| `INTERESTED` | contribuyente | Sí (marca interna) |
| `FISCAL_DATA_COLLECTED` | contribuyente | Sí (formulario) |
| `REQUIREMENTS_PENDING` | contribuyente + DGII | Sí (checklist) |
| `CREDENTIALS_PENDING` | **Alanube** | No: requiere credenciales |
| `TESTING` | FullPOS + Alanube | Parcial (sandbox) |
| `CERTIFICATION_PENDING` | **DGII** | **No** |
| `CERTIFIED_WITH_EVIDENCE` | **DGII** | No: exige evidencia oficial |
| `PROVIDER_CONFIGURED` | Alanube | No |
| `OPERATIONAL_ACTIVATION_AUTHORIZED` | FullPOS (humano) | Sí, manual y auditado |

**Regla dura:** nunca marcar `CERTIFIED_WITH_EVIDENCE` ni equivalente por completar pasos
internos. No se generan certificados ni autorizaciones simuladas como verdaderas.
Estados no confirmados por la DGII se etiquetan como internos.

**No se implementó** porque no hay documentación oficial en el repositorio que respalde
los nombres/orden de los estados oficiales, y la misión prohíbe inventarlos. Es un
componente **NO-GO** hasta tener el contrato oficial.

## 12. Dependencias externas, bloqueos y pruebas visuales

| Bloqueo | Detalle |
| --- | --- |
| Credenciales Alanube sandbox | No existen; sin ellas no hay integración real |
| Contrato oficial de envío/consulta/webhooks/firmas | Pendiente de información oficial |
| Certificación DGII | Requiere trámite y autorización humanos |
| Recorrido visual Windows | **BLOCKED**: Flutter no expone el árbol de accesibilidad a UI Automation (solo `FLUTTERVIEW`) y la inyección sintética de teclas rompe `HardwareKeyboard` (`_AssertionError`). Ver `ECF_WINDOWS_AUTHENTICATED_UAT.md` §6 |
| Prueba visual del botón nuevo | **No ejecutada.** Las 9 pruebas de widget cubren las compuertas, el aviso, el resultado, la doble pulsación y el bloqueo; **no** sustituyen a la observación de la interfaz |

Pasos manuales pendientes (para una persona, en la build UAT ya preparada): abrir la app
→ entrar con `ecf.visual.admin@fullpos.local` → Configuración → Empresa → activar e-CF →
Drawer → Facturación electrónica → abrir un comprobante en `LOCAL_VALIDATED` → ejecutar
el despacho simulado → comprobar el estado en la bandeja.

## 13. Clasificación de fases

| Fase | Estado |
| --- | --- |
| 1. Auditoría y protección | **GO** |
| 2. Interfaz Flutter | **GO** (código + 9 pruebas; visual BLOCKED) |
| 3. Concurrencia | **GO** (4 pruebas reales) |
| 4. E34 simulado | **GO WITH BLOCKERS** (precondiciones cubiertas por suite existente; ruta nueva reutiliza `dispatchOnce`) |
| 5. Regresión E31/E32/E34 | **GO** |
| 6. Compatibilidad POS tradicional | **GO** |
| 7. Preparación Alanube real | **GO** en lo verificable localmente (cliente, secretos, separación de ambientes, adaptadores, simulador); real **NO-GO** |
| 8. Proceso DGII por empresa | **NO-GO** (diseño documentado, sin contrato oficial) |
| 9. Pruebas visuales | **NO-GO / BLOCKED** |
| 10. Validaciones finales | **GO** |
| 11. Documentación | **GO** |

## 14. Los cuatro hitos, por separado

**A. Simulación funcional en UAT — GO.**
Cadena completa ejecutada: preparar → despacho simulado → correlación → estado →
evidencia → bandeja. 19 pruebas del camino simulado (incluidas 4 de concurrencia real),
1362 Flutter y 1395 backend en verde, aislamiento histórico demostrado.

**B. Integración real con Alanube — NO-GO.**
Falta: credenciales de sandbox, contrato oficial de autenticación, envío, consulta de
estados, webhooks y firmas. No se ha llamado nunca al proveedor ni se ha consumido
numeración real.

**C. Habilitación y certificación DGII — NO-GO.**
Falta el proceso oficial, la evidencia de certificación y el trámite. Ningún paso interno
puede marcar a una empresa como habilitada.

**D. Autorización para despliegue productivo — NO-GO.**
Sin B ni C, sin recorrido visual ejecutado y sin validación en un cliente tradicional. La
integración local no habilita producción.

## 15. Próxima misión recomendada

1. **Recorrido visual por una persona** con la build UAT ya preparada (los 6 pasos de §12),
   usando el botón nuevo. Es lo único que desbloquea el PASS visual.
2. **E34 por la ruta simulada** de extremo a extremo (reutilizando los fixtures del spec
   E34 existente).
3. **Contratos oficiales**: obtener de Alanube/DGII la documentación de auth, envío,
   consulta, webhooks y firmas y convertirla en adaptadores + validadores con mocks.
4. **Máquina de onboarding DGII**: implementar solo cuando exista la fuente oficial.
5. **Rotación de secretos y auditoría fiscal**: revisar `EcfSecretResolverService` con el
   contrato real.
