# F1 — Clasificación fiscal supervisada

> **Estado: `F1 = GO`.** Backend, Flutter y HTTP probados. Queda **una** decisión
> de producto/legal (borrado de empresas con datos fiscales, ver §5), que no es
> parte de F1 y se documenta aparte.

## 1. El problema

Una partida **fuera de inventario** (sin `productId`) no tiene producto del que
heredar si es un bien o un servicio. Quedaba con `SaleItem.item_type_snapshot =
NULL` y la preparación del e-CF la rechazaba —correctamente, porque no se debe
adivinar— con `ECF_LINE_CLASSIFICATION_UNCONFIRMED`.

Consecuencia real: **esa venta nunca podía facturarse electrónicamente**, y el
mensaje prometía una «revisión supervisada» que no existía como función. No había
ni endpoint ni campo en el DTO para fijar la clasificación.

## 2. Diseño elegido y por qué

Se evaluaron las tres alternativas de la misión:

| Alternativa | Valoración |
| --- | --- |
| **A** Clasificar al crear la venta (campo en el DTO) | Ayuda solo a ventas **nuevas** y solo si el cliente envía el campo. El cliente actual no lo envía, así que no resuelve el caso. Además toca el contrato del POS, que es justo lo que hay que preservar. |
| **B** Modificar `SaleItem.item_type_snapshot` | **Reescribe la clasificación congelada de una venta**, que es evidencia histórica de cómo se emitió. Rechazada: la misión prohíbe la modificación silenciosa y la reescritura de hechos fiscales. |
| **C** Registro complementario, inmutable y auditado | **Elegida.** No toca la venta ni la partida, es append-only, fechado, con autor y motivo, y encaja con la arquitectura que el módulo ya usa (`ecf_evidence_receipts`, `ecf_credit_reservation_events`). |

**Alternativa C implementada.** La venta y su `SaleItem` **no se modifican
nunca**; la decisión es un hecho nuevo y fechado que el adaptador consulta
únicamente **cuando la clasificación congelada está ausente**.

Precedencia explícita y probada: **la clasificación congelada en la venta manda
siempre** (`effectiveLineClassification`).

## 3. Implementación

| Arquitectura | Archivo |
| --- | --- |
| Tabla append-only | `prisma/migrations/20261016190000_ecf_line_classification_supervised/` |
| Valor de auditoría | `prisma/migrations/20261016191000_ecf_line_classification_audit_action/` |
| Modelo | `EcfLineClassification` en `prisma/schema.prisma` |
| Política pura | `src/ecf/documents/ecf-line-classification.policy.ts` |
| Mensajes | `src/ecf/documents/ecf-line-classification.messages.ts` |
| Servicio | `src/ecf/documents/ecf-line-classification.service.ts` |
| Consumo | `src/ecf/pos/ecf-sale-fiscal.adapter.ts` |
| Rutas | `src/ecf/ecf-documents.controller.ts` |
| Permiso nuevo | `confirmEcfLineClassification` (**sin alias**) |

### Reglas que hace cumplir

- Solo `PRODUCT` o `SERVICE`; **nunca** se infiere del nombre.
- **Motivo obligatorio** (3–300 caracteres): una decisión sin justificación no es auditable.
- **Después de salir del equipo, no se clasifica.** Si algún comprobante de la venta está en un estado fiscal (`READY_TO_SEND` … `HUMAN_REVIEW_REQUIRED`), se rechaza.
- Los estados **locales** (`LOCAL_DRAFT`, `LOCAL_VALIDATION_PENDING`, `LOCAL_VALIDATED`, `CANCELLED`) sí permiten clasificar: todavía no ha salido nada.
- **Corregir es añadir**: el valor anterior queda en `previousClassification` y la fila previa no se toca.
- **Ni importes, ni impuestos, ni caja, ni inventario** se modifican (se comprueba en la prueba).
- Todo acotado al `companyId` del contexto autenticado.

### Rutas

| Ruta | Permiso | Qué hace |
| --- | --- | --- |
| `GET /ecf/documents/:saleId/pending-classifications` | `viewEcfDocuments` | Qué partidas bloquean y por qué |
| `POST /ecf/documents/line-classifications` | `confirmEcfLineClassification` | Confirma la clasificación |

Permiso propio **sin alias**, igual que las dos operaciones sensibles de la
habilitación DGII: no debe heredarse de un permiso de gestión genérico. El rol
ADMIN lo tiene por su vía de rol; **ningún rol no-admin lo recibe**.

## 4. Pruebas (HECHO — 14 en verde)

`ecf-line-classification.policy.spec.ts` (6) y
`ecf-line-classification-postgres.integration-spec.ts` (8):

| Caso | Resultado |
| --- | --- |
| Sin clasificación, la partida bloquea con `ECF_LINE_CLASSIFICATION_UNCONFIRMED` | ✔ |
| Confirmar desbloquea la compuerta **sin tocar la venta ni la partida** | ✔ |
| Importes, impuestos y totales intactos tras confirmar | ✔ |
| Cada decisión deja fila con autor, fecha y motivo | ✔ |
| Corregir registra `previousClassification` y **no** reescribe la anterior | ✔ |
| Auditoría `LINE_CLASSIFICATION_CONFIRMED` escrita | ✔ |
| PostgreSQL **impide** `UPDATE` y `DELETE` (`ECF_LINE_CLASSIFICATION_IMMUTABLE`) | ✔ |
| Reclasificar una partida con clasificación congelada → rechazado | ✔ |
| Clasificar después de que el comprobante salió → rechazado | ✔ |
| Empresa B no ve ni clasifica partidas de A | ✔ |
| Identificadores reales de A no sirven desde B | ✔ |
| Reintentar la misma decisión no duplica historial | ✔ |

## 5. Hallazgo colateral (IMPORTANTE, preexistente)

Las tablas append-only del módulo tienen **`trigger` sin `DELETE` + clave foránea
en cascada** desde `companies` (o desde `ecf_electronic_documents`). Consecuencia:
**borrar una empresa con datos e-CF falla a nivel de base de datos**
(`ECF_EVIDENCE_APPEND_ONLY`, y ahora también
`ECF_LINE_CLASSIFICATION_IMMUTABLE`).

- **No lo introduje yo**: ya ocurría con `ecf_evidence_receipts` y
  `ecf_credit_reservation_events`, ambos con *trigger* incondicional y sin vía de
  escape (verificado: no existe ninguna bandera de purga; el único
  `current_setting` es `fullpos.ecf_actor`).
- Mi tabla **amplía el conjunto** de tablas que se comportan así, por lo que hay
  que verificarlo contra el borrado de cuenta (`DELETE /auth/account`).
- **RECOMENDACIÓN:** decidir explícitamente entre (a) que el borrado de cuenta
  purgue e-CF con una ruta autorizada y auditada, o (b) que el borrado de cuenta
  con datos fiscales quede bloqueado y se documente como tal. **No se cambió nada
  aquí**: tocar la ruta de borrado sin autorización sería peligroso.

## 6. Interfaz Flutter (HECHO)

El cliente consume el flujo existente; **no se creó ningún sistema paralelo**.

| Pieza | Archivo |
| --- | --- |
| Permiso | `confirmEcfLineClassification` en `lib/core/auth/app_permissions.dart` |
| Rutas | `ecfPendingClassifications(saleId)`, `ecfLineClassifications` |
| Modelos | `EcfPendingClassificationLine`, `EcfPendingClassifications` |
| Repositorio | `pendingClassifications`, `confirmLineClassification` en `data/ecf_repository.dart` |
| Provider | `ecfPendingClassificationsProvider` (família, autoDispose) |
| Diálogo | `ui/ecf_line_classification_dialog.dart` |
| Enganche | `ui/ecf_prepare_action.dart` |

### Cómo se llega

Cuando la preparación se bloquea con `ECF_LINE_CLASSIFICATION_UNCONFIRMED`, el
diálogo de resultado muestra el motivo **y ofrece «Revisar clasificación fiscal»**,
que abre el diálogo de clasificación. Después de confirmar indica que hay que
volver a pulsar «Preparar»: **no se reintenta sola ninguna operación fiscal**.

### Qué respeta

- **No decide nada por su cuenta:** `canConfirm` y `fiscallyFrozen` vienen del
  backend.
- **Sin permiso no hay botón** y se explica cómo obtenerlo.
- **No preselecciona** BIEN ni SERVICIO: la clasificación la elige la persona.
- **Motivo obligatorio** (mínimo 3 caracteres) y validado antes de enviar.
- **Perfil de "solo lectura"** funciona: consulta el bloqueo sin poder confirmar.
- **No promete lo que no pasó:** el diálogo dice que no emite nada ni sustituye
  ninguna autorización de la DGII.
- **Errores traducidos** a algo accionable (403, 409 por comprobante ya enviado,
  401 por sesión expirada) y mostrados dentro del diálogo.
- **Doble pulsación protegida** con un indicador de ocupado.

## 7. Pruebas (HECHO — 30 en verde)

| Suite | Casos |
| --- | --- |
| `ecf-line-classification.policy.spec.ts` | 6 |
| `ecf-line-classification-postgres.integration-spec.ts` | 8 |
| `ecf-line-classification-http.e2e-spec.ts` | 7 |
| `test/features/ecf/ecf_line_classification_test.dart` | 9 |

Además de los casos de §4, la prueba HTTP cubre **401 sin sesión**, **403 sin el
permiso** (con `viewEcfDocuments` se consulta pero **no** se confirma), **400** con
clasificación inventada, motivo vacío o `companyId` colado en el cuerpo, **404**
cross-empresa con el identificador real y con uno inventado, **409** al
reclasificar una venta que ya declaró su tipo, y que tras confirmar **la venta, los
impuestos y la caja quedan intactos** y la auditoría registra un asiento.

## 8. Pendiente (no es parte de F1)

| # | Pendiente | Motivo |
| --- | --- | --- |
| P1 | Política de borrado de empresas con datos fiscales | Requiere asesoría legal. Ver `ECF_COMPANY_DELETION_RETENTION_DESIGN.md`; **no se ejecutó ningún borrado** |
| P2 | UAT visual en Windows del flujo nuevo | No ejecutada (ver informe de misión) |
