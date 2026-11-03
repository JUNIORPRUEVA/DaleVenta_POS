# Compatibilidad del POS tradicional con el módulo e-CF

> **Naturaleza de este documento.** Todo lo que aparece como **HECHO** está
> respaldado por pruebas ejecutadas en esta misión sobre HTTP real y PostgreSQL
> real. Lo que no se pudo verificar se marca como **PENDIENTE**. Este documento
> no certifica nada ante la DGII ni ante ningún proveedor.

## 1. Resumen ejecutivo

El módulo e-CF **no intercepta la venta**. Su punto de entrada es una llamada
explícita y separada (`POST /ecf/documents/prepare*`), y `apps/api/src/sales`
no importa nada de `ecf`. La única huella estructural en el POS es **una
columna nueva y nullable** en `SaleItem`.

Consecuencia práctica: una empresa con e-CF apagado —o que nunca lo active— no
puede ver alterada su facturación por este módulo. Eso se verificó, no se
supuso.

## 2. Acoplamiento estructural (HECHO)

| Comprobación | Resultado verificado |
| --- | --- |
| ¿`src/sales` importa algo de `ecf`? | **No.** Cero importaciones. |
| ¿Alguna migración e-CF añade *triggers* sobre `sales`, `SaleItem`, caja o inventario? | **No.** Todos los `CREATE TRIGGER` están sobre tablas `ecf_*`. |
| ¿Crear una venta escribe en tablas `ecf_*`? | **No.** Se comprueba con contadores a 0 tras vender. |
| ¿La preparación e-CF modifica la venta? | **No.** El total, el NCF y el estado se mantienen idénticos. |

Evidencia:
`apps/api/src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts` (**10 pruebas**
desde 2026-10-18: se añadieron escenarios de reintento en ambas rutas, turno
cerrado y el interruptor en ambos valores).

## 3. La única huella en el POS: `SaleItem.itemTypeSnapshot` (HECHO)

Migración `20261015120000_sale_item_type_snapshot`:

```sql
ALTER TABLE "SaleItem" ADD COLUMN "item_type_snapshot" "product_item_type";
```

- **Nullable y sin `DEFAULT`** → un cliente antiguo que inserte sin esa columna
  sigue funcionando; la fila queda con `NULL`.
- El esquema Prisma lo declara `ProductItemType?` (opcional), coherente con la
  base.
- El POS lee con tolerancia: `itemTypeSnapshot: item.itemTypeSnapshot ?? null`.

**Decisión fiscal correcta (HECHO):** cuando la clasificación está en `NULL`
—venta anterior a la migración o partida sin producto— la preparación e-CF **se
niega** con `ECF_LINE_CLASSIFICATION_UNCONFIRMED` en lugar de leer el producto
actual. Leer el producto actual no sería evidencia histórica de cómo se emitió
esa venta. Está en `ecf-sale-fiscal.adapter.ts` y cubierto por
`ecf-sale-fiscal.adapter-postgres.integration-spec.ts`.

## 4. Contrato financiero que el POS ya tenía (HECHO, y no es e-CF)

`apps/api/src/common/financial-legacy-compat.ts` clasifica cada operación
financiera según los campos nuevos que recibe:

| Lo que envía el cliente | Clasificación | Resultado |
| --- | --- | --- |
| `originCashSessionId` | `SAFE_NEW_PATH` | Se usa el turno indicado |
| Nada de lo nuevo | `LEGACY_COMPAT_PATH` | Se admite **solo** si `FINANCIAL_LEGACY_COMPAT` está activo |
| Solo `originTerminalId` | `INVALID_PARTIAL_REQUEST` | **Siempre** rechazado |

Códigos reales observados por HTTP:

- `LEGACY_MISSING_SESSION` (409) — «Actualiza Fullpos para completar esta
  operación.»
- `INVALID_PARTIAL_FINANCIAL_REQUEST` (409) — mismo texto, con `operation`.

Distinguir al cliente verdaderamente antiguo de una **actualización a medias**
es deliberado: la solicitud parcial es ambigua y no se adivina.

También verificado: **sin turno de caja abierto no hay venta** por ninguna de
las dos rutas («Debes abrir caja antes de facturar»).

> **Dependencia operativa a confirmar (PENDIENTE):** este repositorio no
> demuestra con qué valor se despliega `FINANCIAL_LEGACY_COMPAT` en producción.
> Si estuviera apagado, los clientes instalados que no envían
> `originCashSessionId` **no podrían vender**. Debe confirmarse en el entorno
> real antes de cualquier release.

## 5. Precondiciones de la facturación tradicional (HECHO)

Se comprobó por HTTP que una venta con NCF requiere, en este orden:

1. Turno de caja abierto.
2. `ncfEnabled = true` en `/company/fiscal-settings`; si no:
   *«Los comprobantes fiscales no están activados para esta empresa.»*
3. Un cliente con RNC/cédula y nombre cuando el comprobante lo exige
   (B01): *«Para emitir un comprobante B01 debes seleccionar un cliente con
   RNC/Cédula y nombre.»*
4. Una serie NCF registrada (`POST /ncf/sequences`).

Nada de esto es e-CF y nada de esto cambió. Se documenta porque **cualquier
prueba de compatibilidad que lo omita falla por el motivo equivocado**.

## 6. Matriz de compatibilidad

| Escenario | App antigua | App nueva | Backend nuevo | Resultado verificado |
| --- | --- | --- | --- | --- |
| Vender sin campos nuevos, `FINANCIAL_LEGACY_COMPAT=true` | ✔ | ✔ | ✔ | **Venta creada**; 0 filas `ecf_*` |
| Vender sin campos nuevos, interruptor apagado | ✔ | — | ✔ | **409** `LEGACY_MISSING_SESSION`; **no** se crea la venta |
| Vender con `originTerminalId` y sin `originCashSessionId` | — | ✘ | ✔ | **409** `INVALID_PARTIAL_FINANCIAL_REQUEST` |
| Vender con `originCashSessionId` (ruta nueva) | — | ✔ | ✔ | **Venta creada** |
| Venta fiscal tradicional con NCF | ✔ | ✔ | ✔ | **Venta creada** con su NCF; 0 filas `ecf_*` |
| Vender con e-CF encendido | ✔ | ✔ | ✔ | **Venta creada**; la clasificación se congela; **no** se prepara nada |
| Partida sin producto | ✔ | ✔ | ✔ | Venta **creada**; clasificación `NULL`; preparación **rechazada** con `ok:false` |
| Preparar con e-CF apagado | — | ✔ | ✔ | Rechazo en el cuerpo, **nunca** un documento a medias |

## 7. Riesgos y pendientes

| # | Riesgo | Estado |
| --- | --- | --- |
| R1 | Valor de `FINANCIAL_LEGACY_COMPAT` en producción sin confirmar | **PENDIENTE** |
| R2 | Una partida fuera de inventario **nunca** puede facturarse electrónicamente, y el mensaje promete una «revisión supervisada» que no existe como función | **RESUELTO por F1** (2026-10-18): clasificación supervisada append-only, endpoint y diálogo. Ver `ECF_F1_CLASSIFICATION_REVIEW.md` |
| R3 | Los endpoints `prepare*` informan el resultado en el cuerpo (`ok`), no en el estado HTTP: un **201 no significa preparado** | **HECHO**, documentado; exige que todo cliente lea `ok` |
| R4 | Compatibilidad con APKs antiguos en Flutter (no solo el contrato HTTP) | **PENDIENTE** — no probado en esta misión |
| R5 | Clientes en versiones anteriores que no envíen `originTerminalId` | Cubierto por la clasificación, pero sin prueba en dispositivo real |

**R2 merece decisión de producto.** Opciones: (a) dejar la restricción y
retirar del mensaje la promesa de una revisión supervisada inexistente;
(b) añadir `itemType` opcional al DTO de venta para partidas sin producto y
congelarlo como se hace con las que sí lo tienen. La opción (b) cambia una
regla de clasificación fiscal, así que **no se implementó**: requiere
autorización explícita.
