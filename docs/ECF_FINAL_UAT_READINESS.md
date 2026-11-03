# e-CF — Readiness final para UAT

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica **intactas**.

> Convención de este documento: **HECHO** = verificado en esta sesión con código o
> ejecución real; **HIPÓTESIS** = plausible pero no verificado; **RECOMENDACIÓN** =
> propuesta, no implementada.

---

## 1. Estado E31 (crédito fiscal)

**HECHO — implementado y probado.**
- Preparación desde una venta real (`EcfPreparationService.prepareFromSale`) vía
  `POST /ecf/documents/prepare`, permiso `prepareEcfDocuments`.
- Consume un e-NCF del rango de la empresa (asignación por el servidor).
- Identidad anclada en la VENTA (`sourceType=SALE`, `sourceId`): un reintento
  reutiliza el mismo documento y el mismo número.
- Exige receptor (RNC + razón social) y metadatos del contrato (`idDoc.*`).
- No emite: ningún endpoint cablea `dispatchOnce`.

## 2. Estado E32 (consumo)

**HECHO — flujo independiente, ampliado en esta sesión.**
- Ya existía un flujo de **cupo único de sandbox** operado desde CLI con
  autorización humana explícita (`runOnce`, `maxPosts: 1`), más reconciliación y
  compatibilidad DOM. **Ese flujo no se ha tocado.**
- **Nuevo:** preparación local desde una venta (`prepareConsumoFromSale`) vía
  `POST /ecf/documents/prepare-consumo`.
  - El tipo se elige **explícitamente**: el adaptador solo exige receptor para
    E31 (`assertBuyerForDocumentType`); E32 es consumo final.
  - **NO consume numeración** de la empresa y **NO toca el cupo de sandbox**:
    devuelve `encf: null` y `numberingState: PENDING_SANDBOX_SLOT`.
  - Idempotente por venta; persiste; aparece en la bandeja sin e-NCF.
- **Regla añadida y simétrica:** una venta no puede producir dos comprobantes de
  tipos distintos (`ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE` en ambos caminos).
- La validación del esquema contratado de E32 **no** se ejecuta en este paso:
  exige el e-NCF, que entrega su propio cupo. No se simula un número provisional.

## 3. Estado E34 (nota de crédito)

**HECHO — implementado y probado.**
- `prepareCreditNote` + `POST /ecf/documents/prepare-credit-note`.
- Líneas, precios y clasificación salen del ORIGINAL; el cliente solo decide QUÉ
  se acredita (parcial con descuento proporcional, o total).
- Reserva crédito fiscal con tope en el saldo disponible
  (`E34_INSUFFICIENT_FISCAL_BALANCE`). No toca inventario, caja, turnos ni pagos.
- Solo admite originales `DGII_ACCEPTED` de la propia empresa.
- UI Flutter guiada (`ecf_credit_note_action.dart`).

## 4. Estado Flutter

**HECHO — compila limpio y con pruebas de interfaz.**
- `flutter analyze`: **No issues found!**
- Bandeja electrónica reconstruida: estado real por documento
  (`ecf_status_presentation.dart`, 14 estados), receptor congelado, importe y
  moneda, fecha, referencia al original, errores, búsqueda con retardo,
  filtros por grupo y tipo, paginación con total autoritativo del servidor,
  estados vacío/error/carga y "quitar filtros".
- Acción de preparación con **selección explícita E31/E32**; con un solo tipo
  habilitado no se pide elección.
- `uuid` pasa a dependencia directa (era transitiva): 1 línea de lockfile.

## 5. Estado Alanube

**HECHO (integración técnica) / Bloqueado (operación real).**
- Cliente HTTP seguro con timeouts, reintentos clasificados, transporte
  simulado por defecto y transporte real desactivable
  (`ALANUBE_ENABLE_REAL_CALLS=false`).
- Esquemas del contrato embebidos y validación de payload.
- Webhooks: contrato e interfaz implementados; la recepción operativa sigue
  cerrada.
- **No se ha realizado ninguna llamada real** al proveedor en esta sesión.

## 6. Estado de numeración

**HECHO.**
- Rangos por empresa con índice único **parcial** (`WHERE active`), identidad
  inmutable y `next_number` que nunca retrocede (trigger).
- E31 y E34 toman número del rango de la empresa; **E32 nunca** (`allocatable:
  false`), conserva su cupo único.
- Un número consumido no se reutiliza ni se devuelve al pool, ni siquiera si la
  validación posterior falla.

## 7. Estado de contratos

| Tipo | Estado declarado | Emisión permitida por el registro |
| --- | --- | --- |
| E31 | `CONFIRMED_OFFICIAL` | sí |
| E32 | `PARTIAL_OFFICIAL` | **no** |
| E34 | `CONFIRMED_OFFICIAL` | sí |

**HIPÓTESIS:** `PARTIAL_OFFICIAL` de E32 se refiere a campos no confirmados del
esquema publicado. No se ha inventado ninguna regla para compensarlo.

## 8. Estado de seguridad (aislamiento multiempresa)

**HECHO — cubierto por pruebas, no por inspección visual.**
- Toda consulta y mutación va acotada por `companyId` del token.
- Un id de otra empresa es indistinguible de uno inexistente (sin señal IDOR):
  `NotFoundException` en el detalle.
- E32/E34 no leen ventas ni originales de otra empresa (probado).
- La preparación exige empresa habilitada + `SANDBOX` + tipo permitido +
  actor identificado; todo en backend, no en la interfaz.

## 9. Estado de compatibilidad

**HECHO.**
- Toda la superficie e-CF está **apagada por defecto** (`enabled=false`): sin
  interruptor de empresa no hay ninguna ruta e-CF operativa.
- Migraciones **aditivas**: columnas opcionales, triggers nuevos, sin reescritura
  de filas.
- Un documento sin `fiscal_document` (preparado con una versión anterior)
  mantiene bandeja y detalle funcionando (probado).
- Nada de e-CF se exige a empresas que no lo usan.

**RECOMENDACIÓN:** ejecutar una pasada de regresión con un cliente Windows
antiguo real antes de cualquier despliegue; esta sesión no la ha hecho.

## 10. Estado de migraciones

**HECHO.** 39 migraciones en `apps/api/prisma/migrations`, aplicadas en la base
efímera de pruebas. Nueva en esta sesión:

- `20261015160000_ecf_fiscal_document_snapshot` — añade `fiscal_document JSONB`
  y el trigger `ecf_protect_fiscal_document` (`ECF_FISCAL_DOCUMENT_IMMUTABLE`).
  **Aditiva**: no modifica ninguna fila existente.

**Persistencia fiscal (auditoría pedida):** hasta ahora el documento preparado
solo dejaba un resumen (`payload_summary`) y una huella. **No era reconstruible.**
Ahora se guarda el documento completo, la huella se reproduce desde él y una vez
escrito no puede cambiar. El resto de la fila (estado, resumen de emisión) sí
evoluciona. `fiscal_document` nunca se devuelve por las rutas de lectura.

## 11. Resultados de pruebas (ejecutadas en esta sesión)

```
flutter analyze                                         → No issues found!
flutter test                                            → 1325 passed, 1 skipped
flutter test test/features/ecf                          → 61 passed
npx tsc -p tsconfig.build.json --noEmit                 → TSC_EXIT=0
npx prisma validate                                     → schema is valid
pwsh scripts/ecf-test-db/run-tests.ps1                  → 125 suites passed (1 skipped),
                                                          1327 passed, 8 skipped
                                                          ISOLATION OK (708/568/3462)
pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern ...   → e32-consumo+preparation 22/22
                                                          fiscal-document-persistence 7/7
                                                          document-query 10/10
git diff --check                                        → DIFFCHECK_EXIT=0
```

Pruebas nuevas de esta sesión: **12** de E32 consumo (PG), **7** de persistencia
íntegra (PG), **3** de proyección del receptor (PG), **38** de Flutter
(presentación de estados, bandeja, preparación E31/E32, repositorio).

## 12. Riesgos

> **Actualización (segunda sesión del 2026-10-15).** Se añadió el **E2E vertical
> HTTP + PostgreSQL** (`docs/ECF_E2E_COMPATIBILITY_REPORT.md`), que encontró y
> corrigió dos defectos reales (el e-NCF reservado no aparecía en la bandeja; una
> nota rechazada por saldo gastaba numeración), y el **plan de activación**
> (`docs/ECF_ALANUBE_ACTIVATION_PLAN.md`). El veredicto de UAT se mantiene en
> **GO**; pruebas externas, producción y emisión real siguen **NO-GO**. La
> compatibilidad con clientes instalados queda **abierta** (A–D y G sin probar).

| Riesgo | Severidad | Estado |
| --- | --- | --- |
| E32: contrato `PARTIAL_OFFICIAL` sin confirmar | Alta | Bloquea emisión, no la preparación local |
| Webhook sin firma confirmada | Alta | Recepción cerrada por diseño |
| `fiscal_document` en `NULL` para documentos anteriores | Baja | Probado: la bandeja funciona; no se reconstruyen |
| E32 preparado localmente sin e-NCF | Media | Es un borrador honesto; no debe presentarse como emitido |
| Sobrecarga de la bandeja en móvil | Baja | Tarjeta compacta con menos metadatos en pantallas estrechas |
| Regresión con clientes Windows antiguos | Media | **No probada** en esta sesión |
| Certificación DGII | Alta | No iniciada (requiere ejecución humana) |

## 13. Bloqueantes externos

1. Confirmación del contrato E32 `PARTIAL_OFFICIAL` (proveedor).
2. Mecanismo de firma del webhook (proveedor).
3. Credenciales de sandbox y ventana autorizada para el cupo único.
4. Certificación DGII: requiere ejecución y autorización humanas.
5. Autorización para emitir documentos fiscales reales.

## 14. GO/NO-GO — UAT

**GO.** Implementación local completa para E31, E32 (preparación) y E34, suites
en verde, aislamiento histórico intacto y migración aditiva aplicada. Nada de
esto toca producción ni datos reales.

## 15. GO/NO-GO — pruebas externas

**NO-GO.** Dependen de los bloqueantes 1–3: sin contrato E32 confirmado, sin
firma de webhook y sin credenciales, cualquier prueba externa sería una
simulación presentada como real.

## 16. GO/NO-GO — producción

**NO-GO.** No hay certificación DGII, no hay confirmación del contrato E32, el
webhook sigue cerrado y la regresión con clientes antiguos no se ha ejecutado.

## 17. GO/NO-GO — emisión fiscal real

**NO-GO por construcción.** Ningún endpoint cablea `dispatchOnce`; la emisión
desde la aplicación es inalcanzable. Se mantiene así de forma deliberada.

## 18. Próximos pasos exactos

1. Solicitar al proveedor la confirmación del contrato E32 y el mecanismo de
   firma del webhook.
2. Ejecutar el cupo único de sandbox de E32 con autorización humana explícita y
   registrar la observación.
3. Regresión con un cliente Windows antiguo real contra el backend nuevo.
4. Renovar la lista de estados conocidos (`kEcfKnownStatuses`) si el esquema
   añade alguno: la prueba de completitud falla a propósito si no se actualiza.
5. Solo después de (1)–(2): proponer la fase de certificación.
