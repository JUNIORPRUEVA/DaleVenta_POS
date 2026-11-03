# e-CF — Progress file (bitácora de misión)

Actualizado: **2026-10-15**. Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica intactas.

## Fase actual

**Fases A–E completadas.** En curso: F (envío) y G (Flutter) — parciales por diseño.
Completadas en esta iteración: **E34 desde la app**, **blindaje histórico** y
**proyección de importes en la bandeja**. Sigue **sin endpoint de despacho**.

Última iteración: **bandeja profesional** (14 estados reales), **E32 consumo
local** y **persistencia íntegra del comprobante preparado**. Readiness completo
en `ECF_FINAL_UAT_READINESS.md`.

## Tareas terminadas

| Fase | Entregable | Pruebas |
| --- | --- | --- |
| A | Auditoría de `Sale`, `SaleItem`, `Product`, impuestos, numeración, estados, idempotencia | — |
| B | Contrato fiscal derivado del esquema embebido (no inventado) | `ecf-sale-fiscal.policy.spec.ts` |
| C | **Adaptador venta → snapshot e-CF** (`EcfSaleFiscalAdapter`) | 31 puras + 18 PG |
| D | **Preparación E31 desde venta** (`EcfPreparationService` + `POST /ecf/documents/prepare`) | 10 PG |
| E | E34 ya existía (reservas + guarda de despacho) | 13 PG |
| F | Despacho: **sin endpoint**, verificado por diseño | — |
| I | Pruebas integrales backend | 61 PG e-CF + suite completa |
| L | Documentación | este archivo + `ECF_FLUTTER_Y_OPERACION.md` |
| M | **Nota de crédito E34 (política pura)** — `ecf-credit-note.policy.ts` | 15 puras |
| N | **E34 desde venta/nota** — `prepareCreditNote` + `POST /ecf/documents/prepare-credit-note` | 10 PG |
| O | **Blindaje histórico** — `SaleItem.item_type_snapshot` + migración aditiva | suite completa |
| P | **Bandeja con importe/moneda/original** — proyección de `payloadSummary` | 7 PG |
| Q | **Acción E34 en Flutter** — `ecf_credit_note_action.dart` | 6 widget + 5 repositorio |
| R | **Bandeja profesional** — 14 estados reales, receptor, búsqueda y paginación | 12 puras + 14 widget |
| S | **E32 consumo local** — `prepareConsumoFromSale`, sin numeración ni cupo | 12 PG + 6 widget |
| T | **Persistencia íntegra** — `fiscal_document` inmutable y reconstruible | 7 PG |
| U | **E2E vertical HTTP + PostgreSQL** — login real, E31/E32/E34 de punta a punta | 3 e2e |
| V | **Defectos corregidos por el E2E** — e-NCF visible en bandeja; numeración ya no se gasta en una nota rechazada | suite completa |
| W | **Simulador Alanube por escenarios** — los 16 escenarios + invariantes | 33 puras |
| X | **Matriz de la máquina de estados** — 196 pares, con y sin evidencia | 18 puras |
| Y | **E2E visual Flutter** — recorridos E31/E32/E34 de la interfaz | **implementado, NO ejecutado** (bloqueado por infraestructura) |
| Z | **Drawer e-CF por empresa** — compuerta `ecfEnabled` + opción al final del menú | 11 puras + 11 funcionales (pantalla y Drawer reales) |
| Z2 | **Interruptor en Configuración de empresa** — sección e-CF + `ecfEnabled` publicado por `/settings` | funcionales 1-11 PASS + spec backend `ecfEnabled` scoped PASS |
| Z3 | **Defectos corregidos por la verificación** — `copyWith` perdía el flag; `toPublicSettings` no lo publicaba; el Drawer lo titulaba «Más módulos» | corregidos y cubiertos por prueba |
| Z4 | **Blindaje `API_BASE_URL` del perfil UAT** — sin valor por defecto, solo host local, fallo visible | 9 pruebas (`uat_api_config_test.dart`) |
| Z5 | **Perfil UAT visual aislado** — API en 4004 + base **desechable** 56551, histórica intocable | `scripts/visual-uat/visual-uat.ps1` (asserts + seed idempotente) |
| Z6 | **UAT visual autenticada en Windows** — build UAT abierto atado a `127.0.0.1:4004`, empresa sintética creada por API | **NO-GO/BLOCKED**: sin acceso al árbol de accesibilidad y la inyección de teclas rompe `HardwareKeyboard` (ver `docs/ECF_WINDOWS_AUTHENTICATED_UAT.md` §6) |
| Z7 | **Cadena simulada de extremo a extremo** — `POST /ecf/documents/:id/simulate-dispatch` + respuesta simulada fiel al contrato local + persistencia + evidencia | **GO local**: 15 pruebas nuevas (6 política + 9 E2E PostgreSQL); `officialFiscalAcceptance=false`, 0 en `DGII_ACCEPTED` |
| Z8 | **Disparador en la interfaz Flutter** — acción de despacho simulado en el detalle, con aviso obligatorio y doble pulsación bloqueada | **GO**: 9 pruebas de widget; visual BLOCKED |
| Z9 | **Concurrencia real sobre PostgreSQL** — 2 y 5 despachos simultáneos, dos empresas a la vez, timeout + reintento | **GO**: 4 pruebas; siempre 1 ganador, 1 intento, 1 recibo |

Readiness: `ECF_FINAL_UAT_READINESS.md`. E2E y compatibilidad:
`ECF_E2E_COMPATIBILITY_REPORT.md`. Activación: `ECF_ALANUBE_ACTIVATION_PLAN.md`.
Validación avanzada (simulador + estados + auditoría de compatibilidad):
`ECF_ADVANCED_FINAL_VALIDATION.md`. Compuerta de integración y estado del E2E
visual: `ECF_INTEGRATION_FINAL_GATE.md`.

## Decisiones técnicas (y por qué)

1. **El precio unitario fiscal es SIN impuesto.** El validador exige
   `cantidad × unitPrice − descuento = baseNeta` y `itbis = baseNeta × taxRate`.
   El adaptador DERIVA `unitPrice = (baseNeta + descuento) / cantidad` a partir de
   lo persistido (`taxableBase`, `exemptAmount`, `lineDiscountAmount`), no del
   precio de venta (que suele incluir ITBIS). Si la división no reproduce el
   importe al céntimo → `ECF_LINE_AMOUNT_NOT_REPRESENTABLE` (se bloquea).
2. **Bien/servicio sale de `SaleItem.item_type_snapshot`**, la clasificación
   CONGELADA al registrar la venta (capturada de `Product.itemType` en ese
   momento). Sin clasificación confirmada → `ECF_LINE_CLASSIFICATION_UNCONFIRMED`.
   Nunca se deduce del nombre, del precio, del inventario ni del producto actual.
3. **`paymentType` es entrada explícita.** No existe en el repositorio un mapeo
   oficial `Sale.paymentMethod → paymentType`; inventarlo produciría un
   comprobante inválido.
4. **La identidad fiscal se ancla en la VENTA.** El módulo rechaza
   `sourceId` + `clientRequestId` a la vez. Anclar en la venta impide por
   construcción que una venta genere dos comprobantes.
5. **La numeración se reutiliza por operación**, no por petición: la clave de
   operación es `clientRequestId ?? SOURCE:<tipo>:<id>`. Un reintento de la misma
   venta reutiliza el e-NCF ya consumido; si los datos cambiaron → divergencia
   (`ECF_EMISSION_PAYLOAD_DIVERGENCE`), nunca un segundo comprobante.
6. **E32 no pasa por el orquestador genérico** (`ECF_EMISSION_TYPE_UNSUPPORTED`):
   consume un cupo de un solo uso y tiene su flujo propio de sandbox. Mezclarlos
   permitiría emitir consumidor final con numeración de crédito fiscal.
7. **Comparación de dinero en céntimos enteros.** En coma flotante
   `70.81 - 70.80` da `0.010000000000005116` y rompía la tolerancia justo en el
   límite. Tolerancia = 1 céntimo; dos céntimos ya son incoherencia.
8. **Sin endpoint de emisión.** Verificado: ningún controlador invoca
   `dispatchOnce`. `capabilities.emissionPathAvailable = false`.

## Pruebas ejecutadas (reales)

```
npx jest ecf-sale-fiscal.policy.spec.ts                    31 passed
run-focused.ps1 -Pattern "ecf-sale-fiscal.adapter-postgres" 18 passed
run-focused.ps1 -Pattern "ecf-preparation-postgres"          10 passed
run-focused.ps1 -Pattern "ecf-(e31|e34|sequence|document-query)-postgres|ecf-e34-emission"
                                                             61 passed / 4 suites
npx tsc -p tsconfig.build.json --noEmit                      TSC_EXIT=0
flutter analyze                                              No issues found
```

## Fase 1 — Blindaje fiscal histórico (COMPLETADO)

**Problema:** la clasificación fiscal (bien/servicio) se leía del producto actual.
Editar el tipo de un producto habría cambiado la clasificación de ventas ya
emitidas.

**Solución:** `SaleItem.item_type_snapshot` (`ProductItemType?`), congelado al
registrar la venta.

- Migración **aditiva** `20261015120000_sale_item_type_snapshot`
  (`ALTER TABLE "SaleItem" ADD COLUMN "item_type_snapshot" "product_item_type"`).
  Sin `DEFAULT` y sin `NOT NULL`: segura sobre datos reales y reversible con un
  `DROP COLUMN`.
- **Fuente autoritativa:** el producto leído de la BD dentro de la transacción de
  venta. Un valor enviado por el cliente **nunca** se copia al snapshot.
- **Un solo punto de escritura:** `sales.service.ts` (`saleItemRows` →
  `createMany`). Verificado por auditoría: es el único camino que crea partidas.
- El adaptador e-CF lee **solo** el snapshot y ya no une con `Product`.

### Política para ventas anteriores a la migración

Las filas existentes quedan en `NULL` = **no confirmada**, y **no** se rellenan
con el valor actual del producto: eso no es evidencia de cómo se clasificó la
venta. Al preparar un comprobante, una partida sin confirmar bloquea con
`ECF_LINE_CLASSIFICATION_UNCONFIRMED` y exige revisión supervisada.

Auditoría supervisada (solo lectura, nunca masiva):

```sql
-- Partidas sin clasificación fiscal confirmada, por empresa.
SELECT s."company_id", COUNT(*) AS partidas_sin_confirmar
FROM "SaleItem" si
JOIN "Sale" s ON s."id" = si."sale_id"
WHERE si."item_type_snapshot" IS NULL
GROUP BY s."company_id"
ORDER BY partidas_sin_confirmar DESC;
```

La corrección es una decisión de negocio supervisada por empresa, no un
`UPDATE` automático.

### Pruebas

| Escenario | Resultado |
| --- | --- |
| Clasificación congelada al cambiar el tipo del producto después | ✅ |
| Producto archivado después de la venta | ✅ |
| Partida sin clasificación (`NULL`) → bloqueo | ✅ |
| Bien vs servicio desde el snapshot | ✅ |
| La venta persiste el snapshot (y `null` si no procede) | ✅ |
| Multiempresa / regresión de ventas tradicionales | ✅ (suite completa) |

## Fase 5 (parcial) — acción Flutter "Preparar e-CF"

Añadida la acción contextual en el **detalle de venta** (`mis_ventas_screen`),
mediante el widget reutilizable `lib/features/ecf/ui/ecf_prepare_action.dart`.

**Se autooculta** salvo que se cumplan las tres condiciones: empresa con e-CF
habilitado (`capabilities.enabled`), usuario con permiso `prepareEcfDocuments` y
tipo E31 habilitado para la empresa. Si e-CF está apagado, no aparece ninguna
operación e-CF en ventas (la configuración sigue siendo accesible desde su
pantalla).

Confirmación previa con tipo documental, cliente, total, forma de pago fiscal
(selección **explícita**, códigos 1/2), tipo de ingreso y vencimiento de
secuencia. No se puede confirmar sin elegir la forma de pago. Tras preparar se
muestra el e-NCF asignado y el estado, dejando claro que es un **borrador local**
que no se ha enviado al proveedor.

### Contrato: `paymentType` corregido a [1, 2]

El esquema del proveedor declara `paymentType` con **enum [1, 2]** para E31. El
DTO y el servicio aceptaban `1 | 2 | 3`, lo que permitía enviar un código fuera
del contrato. Alineado a `@IsIn([1, 2])` y `1 | 2`. La selección sigue siendo
explícita porque **no existe un mapeo oficial verificado** entre
`Sale.paymentMethod` y el código fiscal.

### Contrato de respuesta

`POST /ecf/documents/prepare` devuelve el resultado en el **cuerpo**: `ok: true`
con `{documentId, encf, status}` o `ok: false` con `{code, safeMessage}`. Así la
interfaz puede explicar exactamente por qué una venta no es elegible en lugar de
tratarlo como un fallo de red.

## Pendiente

| Tarea | Bloqueo / nota |
| --- | --- |
| ~~E34 desde venta/nota~~ | **Hecho.** `prepareCreditNote` construye la nota desde las líneas autoritativas del original; la clasificación y el precio nunca los elige el cliente. |
| ~~UI Flutter de preparación~~ | **Hecho.** E31 desde la venta (`ecf_prepare_action.dart`) y E34 desde el original elegible (`ecf_credit_note_action.dart`). |
| Bandeja: borrador vs enviado | La proyección ya trae importe, moneda y e-NCF del original; falta separar visualmente borrador local, pendiente, enviado, aceptado y rechazado. |
| E32 desde la app | Debe ir por el flujo de cupo único de sandbox, no por el genérico. |
| Endpoint de despacho | **Intencionalmente ausente.** Implementarlo exige decisión explícita. |
| Contrato E32 `PARTIAL_OFFICIAL` | Confirmación del proveedor. |
| Firma de webhook | Confirmación del proveedor. |
| Certificación DGII/Alanube | Requiere autorización y ejecución humana. |
| Ventas anteriores a la migración | Quedan sin clasificación confirmada y se bloquea su preparación (`ECF_LINE_CLASSIFICATION_UNCONFIRMED`); requieren revisión supervisada por empresa. |

## Siguiente acción

1. ~~Flujo E34 desde la app sobre los originales elegibles ya listados.~~ **Hecho**: reserva crédito fiscal sin tocar inventario, caja, turnos, pagos ni la venta.
2. ~~Flujo E32 independiente por su **propio camino**.~~ **Hecho** (preparación local): `EcfEmissionService` sigue rechazando E32 por diseño y el cupo `FIRST_E32_SANDBOX` no se consume.
3. ~~Distinguir visualmente borradores de documentos enviados/aceptados en la bandeja.~~ **Hecho**: cada documento muestra su estado persistido real, su fase operativa y su resultado fiscal, sin promover ninguno.
4. Confirmación del contrato E32 `PARTIAL_OFFICIAL` y de la firma del webhook (proveedor).
5. Regresión con un cliente Windows antiguo real contra el backend nuevo.

---

## Actualización 2026-10-16 — cierre de la habilitación DGII en Flutter

**Entregado en esta sesión**

| Pieza | Estado |
| --- | --- |
| Pantalla **Facturación electrónica → Habilitación DGII** | Implementada y probada |
| Capa de datos Flutter (rutas, modelos, repositorio, providers) | Implementada |
| Endpoints `/ecf/dgii/*` consumidos por la app | Conectados |
| Circuito de despacho simulado por HTTP | Cubierto por E2E |
| Utilidad centralizada de redacción de secretos | Implementada (backend) |
| Blindaje UAT de actualizador, descargas y analítica | Implementado |
| Deriva Prisma de índices | Reducida y verificada |

**Cómo se entra**: `Facturación electrónica` (`/ecf`) → icono *Habilitación DGII* en la barra
superior, o desde `Configuración e-CF` → *Abrir habilitación DGII*. El Drawer general **no** se
tocó y no se duplicó ninguna opción.

**Invariante de producto respetada**: la pantalla muestra el seguimiento interno y la
autorización oficial **por separado**, y **nunca** ofrece aprobar la empresa. El diálogo de
avance solo lista las transiciones que el backend admite; `APPROVED` no aparece.

**Validaciones ejecutadas**: `flutter analyze` sin incidencias; `flutter test` completo
1386 pruebas en verde (1 omitida por requerir `--dart-define`); backend e-CF 60 suites / 696
pruebas.

**Pendiente**

1. Recorrido visual autenticado en Windows (ver `ECF_WINDOWS_AUTHENTICATED_UAT.md`).
2. `DROP DEFAULT` de columnas UUID y el índice único parcial de `telemetry_outbox`:
   deriva restante, benigna y documentada; no se corrige sin decisión expresa.
3. Todo lo relativo a proveedor real, certificación DGII y producción.
