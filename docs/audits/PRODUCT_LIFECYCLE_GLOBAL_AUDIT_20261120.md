# Auditoría forense integral — Eliminación, archivado y ciclo de vida de productos en FullPOS Cloud

- **Fecha:** 2026-11-20
- **Alcance:** Producción FullPOS Cloud (`daleventapos_backend`, `daleventapos_pwa`, `daleventapos_database`) + código fuente del repositorio + app Flutter.
- **Modo:** **SOLO LECTURA**. No se ejecutó ningún `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `ALTER`, migración, reinicio ni despliegue.
- **Estado final:** **AUDITORÍA COMPLETADA** (con limitaciones de evidencia documentadas en la sección de limitaciones).
- **Incidente de origen:** SIJO TELA (`sijo-tela-y-tapiceria`) reporta que no puede eliminar productos.

---

## A. Resumen ejecutivo

El sistema **no permite borrar definitivamente un producto que tenga cualquier historial protegido**. La regla está en el backend (`ProductsService.remove`) y devuelve `409 Conflict` con `code: PRODUCT_HAS_HISTORY` y `canArchive: true`.

El historial protegido incluye **los movimientos de inventario**, y crear un producto con existencia inicial genera automáticamente un movimiento `INITIAL_STOCK`. Por tanto, **un producto creado con stock > 0 queda protegido desde el segundo en que se crea**, aunque nunca se haya vendido ni tocado.

Resultados verificados:

| Indicador | Valor |
|---|---|
| Empresas/tenants totales | 38 (15 con productos) |
| Productos totales | 548 |
| Productos activos / archivados | 500 / 48 |
| Productos **no eliminables** por la regla actual | **459 (83,8 %)** |
| Productos eliminables hoy | 89 (16,2 %) |
| Productos bloqueados **solo** por su carga inicial | **86** |
| Empresas con al menos un producto bloqueado | **9 de 38** (9 de 15 con catálogo) |
| Empresas con el 100 % de su catálogo bloqueado | **5** |
| Empresas con intento fallido **confirmado por logs** | **1** (SIJO TELA) |
| Eventos `PRODUCT_DELETED` históricos en toda la plataforma | 5 (FULLTECH 4, Antonio Celulares 1) |
| Eventos `PRODUCT_REACTIVATED` históricos | **0** |

**Respuesta a la pregunta central:** el problema **no es exclusivo de SIJO TELA**. La regla es global y compartida por todas las empresas; lo que varía es el dato. SIJO TELA es el caso extremo (126/126 bloqueados), pero otras 8 empresas también tienen productos bloqueados y 4 de ellas superan el 60 % de su catálogo afectado.

Además del bloqueo, la auditoría detectó **problemas adicionales verificados**, entre ellos:

1. La **eliminación masiva** de la app no maneja el conflicto: aborta en el primer producto con historial y no explica nada al usuario.
2. **No existe interfaz para ver ni restaurar productos archivados** (el backend sí lo soporta).
3. El endpoint de **depuración `DELETE /products/debug/purge`** está expuesto en producción y accesible para cualquier ADMIN de empresa desde la app de escritorio/web, **sin telemetría ni auditoría**.
4. Hoy se pueden borrar **83 productos que aún tienen existencia** (514 unidades) sin ningún movimiento de inventario que registre la pérdida.
5. **Archivar no libera ni oculta el stock**: hay **42 productos archivados con 3.026,1 unidades** que ya no aparecen en el catálogo.
6. El **código/SKU de un producto archivado sigue reservado** (7 productos archivados con código).
7. La **deduplicación de productos puede reutilizar un producto archivado** y devolverlo sin desarchivarlo. Verificado en producción (LANOTABAR, 2 eventos).

---

## B. Respuesta global: ¿afecta solo a SIJO TELA?

**No.** La regla de negocio es única y global (`products.service.ts`), sin variación por plan, plataforma, versión ni configuración. No depende de `product_source` (las 38 empresas están en modo LOCAL), ni del plan (`STANDARD` en todas las que tienen catálogo), ni del número de almacenes.

Lo que determina que una empresa sufra el problema es **su dato**: si todos sus productos tienen movimientos de inventario (o ventas/cotizaciones/compras/transferencias), todos quedan bloqueados.

### Empresas afectadas (con al menos un producto bloqueado)

| Empresa | Productos | Bloqueados | % bloqueado | Solo carga inicial | Eliminables |
|---|---:|---:|---:|---:|---:|
| SIJO TELA | 126 | 126 | 100,0 % | 52 | 0 |
| Asadero Pacheco | 31 | 31 | 100,0 % | 1 | 0 |
| LANOTABAR | 27 | 27 | 100,0 % | 14 | 0 |
| jc distribuidores | 2 | 2 | 100,0 % | 0 | 0 |
| Solimac | 1 | 1 | 100,0 % | 0 | 0 |
| Puerta y Ventana. Aquino | 25 | 24 | 96,0 % | 6 | 1 |
| Siarah Beer & Café | 100 | 93 | 93,0 % | 2 | 7 |
| FULLTECH, SRL | 110 | 80 | 72,7 % | 1 | 30 |
| Antonio Celulares | 120 | 75 | 62,5 % | 10 | 45 |
| **Total** | **542*** | **459** | — | **86** | **83** |

\* Suma de las 9 empresas afectadas.

### Empresas con productos y sin bloqueo

| Empresa | Productos | Eliminables |
|---|---:|---:|
| EyC Embutidos Y Surtidora | 1 | 1 |
| pureva7 | 1 | 1 |
| Smoke Tenant A 1786069854106 | 1 | 1 |
| Smoke Tenant A 1786070004410 | 1 | 1 |
| Smoke Tenant A 1786070213775 | 1 | 1 |
| Codex Produccion 1786071396-3ced6c A | 1 | 1 |

Las 23 empresas restantes **no tienen ningún producto** (tenants de smoke test, demos y empresas creadas sin catálogo).

### Diferencia entre “afectada” e “incidente confirmado”

| Nivel | Criterio | Empresas |
|---|---|---|
| **Incidente confirmado** | Log de un `DELETE /products/:id` devolviendo `409 PRODUCT_HAS_HISTORY` y/o telemetría que demuestra el bloqueo | **SIJO TELA** |
| **Afectada potencial** | Datos que garantizan que el borrado devolverá `409` si se intenta | Asadero Pacheco, LANOTABAR, jc distribuidores, Solimac, Puerta y Ventana. Aquino, Siarah Beer & Café, FULLTECH, SRL, Antonio Celulares |
| **No afectada** | No tiene productos o todos son eliminables | 29 tenants |

**No se afirma** que las 8 empresas “potenciales” hayan intentado eliminar y fallado: no existe evidencia de sus intentos (ver limitaciones de logs).

---

## C. Estadísticas de producción (verificadas)

### C.1 Totales globales

| Métrica | Valor |
|---|---:|
| Tenants (`companies`) | 38 |
| Tenants con productos | 15 |
| Productos (`Product`) | 548 |
| Activos (`archived_at IS NULL`) | 500 |
| Archivados | 48 |
| Movimientos de inventario | 10.437 |
| Movimientos `INITIAL_STOCK` | 241 |
| Productos con movimiento inicial | 241 |
| Líneas de venta (`SaleItem`) | 21.452 |
| Productos con ventas | 332 |
| Productos con movimientos | 410 |
| Productos **sin** movimientos | 138 |
| Productos sin movimientos pero con stock ≠ 0 | **114** |
| Productos con código (`codigo`) | 205 |
| Productos archivados con código | **7** |

### C.2 Bloqueo según la regla real

La regla de `remove()` bloquea si existe **cualquiera** de estas referencias:

1. `inventory_movements`
2. `warehouse_transfer_items`
3. `SaleItem`
4. `CotizacionItem`
5. `purchase_order_items`
6. `purchase_receipt_items`

| Métrica | Valor |
|---|---:|
| Bloqueados | **459** |
| Eliminables | **89** |
| Bloqueados **solo** por `INITIAL_STOCK` (sin ventas, cotizaciones, compras, recepciones ni transferencias) | **86** |
| De esos 86: activos | 64 |
| De esos 86: ya archivados | 22 |
| Unidades implicadas en esos 86 | **6.076,07** |

Los **86 candidatos seguros a anulación de alta** se distribuyen así:

| Empresa | Candidatos | Activos | Archivados | Unidades |
|---|---:|---:|---:|---:|
| SIJO TELA | 52 | 35 | 17 | 5.741,07 |
| LANOTABAR | 14 | 10 | 4 | 229,00 |
| Antonio Celulares | 10 | 10 | 0 | 45,00 |
| Puerta y Ventana. Aquino | 6 | 6 | 0 | 32,00 |
| Siarah Beer & Café | 2 | 2 | 0 | 24,00 |
| FULLTECH, SRL | 1 | 0 | 1 | 1,00 |
| Asadero Pacheco | 1 | 1 | 0 | 4,00 |
| **Total** | **86** | **64** | **22** | **6.076,07** |

En los 86 se verificó que:
- Su `stock` coincide **exactamente** con el `resulting_quantity` del movimiento inicial (0 discrepancias).
- No tienen ventas, cotizaciones, compras, recepciones ni transferencias.
- Tienen **un único** movimiento de inventario, de tipo `INITIAL_STOCK`, y es el primero del producto.

### C.3 Caso SIJO TELA (detalle)

| Métrica | Valor |
|---|---:|
| Productos | 126 |
| Activos / archivados | 97 / 29 |
| Con ventas | 70 |
| Sin ventas | 56 |
| Con movimientos | 126 |
| Movimientos totales | 566 |
| — `SALE` | 372 |
| — `INITIAL_STOCK` | 125 |
| — `RETURN` | 43 |
| — `ADJUSTMENT_IN/OUT` | 26 |
| Líneas de venta | 445 |
| Bloqueados solo por carga inicial | 52 |
| Archivados con stock | 29 (2.803,5 unidades) |
| Archivados con código | 1 |
| `PRODUCT_DELETED` históricos | **0** |
| `PRODUCT_ARCHIVED` históricos | 22 (29 en tabla; 7 anteriores a la telemetría) |
| Plan | `STANDARD`, `max_products = 100`, 97 activos → **3 cupos libres** |

### C.4 Integridad de datos (sin hallazgos)

| Comprobación | Resultado |
|---|---|
| `Product.stock` vs suma de `warehouse_stocks` | 0 discrepancias |
| Cadena de movimientos (`previous + delta = resulting`) | 0 inconsistencias |
| Movimientos con `company_id` distinto al del producto | 0 |
| Líneas de venta/cotización/compra cruzadas entre empresas | 0 |
| `operation_id` duplicados en movimientos | 0 |
| `website_product_overrides` huérfanos | 0 (tabla vacía) |
| `warranty_product_configs` huérfanos | 0 (tabla vacía) |
| Productos con más de un `INITIAL_STOCK` | 0 |
| `INITIAL_STOCK` que no sea el primer movimiento | 0 |
| `INITIAL_STOCK` con delta ≤ 0 o resultado 0 | 0 |

**Conclusión de integridad:** los datos actuales son consistentes. El problema es de **reglas de negocio y de experiencia**, no de corrupción.

### C.5 Detalle por empresa (métricas solicitadas)

Solo se listan las 9 empresas con productos bloqueados. “Mov. solo iniciales” = todos sus movimientos son `INITIAL_STOCK` (puede incluir productos que además tienen ventas).

| Empresa | Total | Act. | Arch. | Con ventas | Con mov. | Mov. solo iniciales | Sin mov. | Compras | Transf. | Devol. | Cotiz. | Otras refs | Eliminables | Bloqueados | Arch. con código | Stock > 0 | Stock = 0 | Stock < 0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| SIJO TELA | 126 | 97 | 29 | 70 | 126 | 52 | 0 | 0 | 0 | 21 | 0 | 0 | 0 | 126 | 1 | 126 | 0 | 0 |
| Antonio Celulares | 120 | 119 | 1 | 63 | 72 | 10 | 48 | 3 | 0 | 4 | 0 | 0 | 45 | 75 | 0 | 109 | 11 | 0 |
| FULLTECH, SRL | 110 | 103 | 7 | 57 | 40 | 1 | 70 | 6 | 1 | 5 | 43 | 1 | 30 | 80 | 2 | 92 | 18 | 0 |
| Siarah Beer & Café | 100 | 96 | 4 | 80 | 88 | 3 | 12 | 0 | 0 | 5 | 0 | 0 | 7 | 93 | 4 | 73 | 27 | 0 |
| Asadero Pacheco | 31 | 30 | 1 | 29 | 31 | 1 | 0 | 0 | 0 | 5 | 0 | 0 | 0 | 31 | 0 | 31 | 0 | 0 |
| LANOTABAR | 27 | 21 | 6 | 12 | 26 | 14 | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 27 | 0 | 25 | 2 | 0 |
| Puerta y Ventana. Aquino | 25 | 25 | 0 | 17 | 24 | 6 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 24 | 0 | 19 | 6 | 0 |
| jc distribuidores | 2 | 2 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 2 | 0 | 0 |
| Solimac | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 0 |

Notas verificadas:

- **Almacenes:** solo FULLTECH, SRL tiene más de uno (2). El resto tiene 1.
- **Servicios (`item_type = SERVICE`):** 0 en toda la plataforma; todos los productos son físicos con inventario.
- **Stock negativo:** 0 productos en todas las empresas.
- **Otras referencias:** 1 regla de lista de precios (FULLTECH) y 0 overrides web en toda la plataforma.
- **Empresas sin bloqueo:** EyC Embutidos Y Surtidora, pureva7, Smoke Tenant A (×3) y Codex Produccion (1 producto cada una, todos eliminables).
- **Empresas sin productos:** 23 (smoke tests, demos y tenants vacíos).

---

## D. Causa raíz

### D.1 Regla exacta

Archivo: `apps/api/src/products/products.service.ts` (rama `production-main`, HEAD `6b3e38e`, 2026-10-12; verificado además en el artefacto desplegado `/app/dist/products/products.service.js`).

```ts
// products.service.ts:1829
async remove(user: TenantUser, id: string) {
  const companyId = requireTenant(user);
  await this.assertWritable(companyId);              // bloquea empresas FULLPOS (no aplica hoy)
  const existing = await this.prisma.product.findFirst({ where: { id, companyId } });
  if (!existing) return { ok: true };                // idempotente
  if (existing.archivedAt) return { ok: true, archived: true }; // NO borra un archivado

  await this.prisma.$transaction(async (tx) => {
    const references = await this.protectedProductReferenceCounts(tx, companyId, id);
    if (this.hasProtectedProductHistory(references)) {
      throw this.productHasHistoryConflict(references);   // 409
    }
    await tx.product.deleteMany({ where: { id, companyId } });
    // telemetría PRODUCT_DELETED
  });
}
```

`protectedProductReferenceCounts` (líneas 664-705) consulta las 6 tablas indicadas. `hasProtectedProductHistory` devuelve `true` si **cualquiera** es > 0.

Respuesta:

```json
{
  "code": "PRODUCT_HAS_HISTORY",
  "message": "Este producto tiene historial y no puede eliminarse definitivamente.",
  "canArchive": true,
  "details": { "inventoryMovements": 2, "warehouseTransferItems": 0, "saleItems": 1,
               "cotizacionItems": 0, "purchaseOrderItems": 0, "purchaseReceiptItems": 0 }
}
```

HTTP: **409**. Permisos: `AuthGuard("jwt")` + `RolesGuard`, roles `ADMIN|ASISTENTE`, permiso `editProducts`.

### D.2 Por qué “ni siquiera los productos nuevos”

Al crear con stock inicial > 0:

```ts
// products.service.ts:1024-1048 (y 1080-1104 en el camino de fallback)
if (initialStock.gt(0)) {
  await this.inventoryMutationService().increaseStockInTransaction(tx, {
    companyId, productId, warehouseId,
    quantity: initialStock,
    type: InventoryMovementType.INITIAL_STOCK,
    sourceType: "PRODUCT_CREATE",
    reason: "PRODUCT_INITIAL_STOCK",
    createdByUserId: user.id,
  });
}
```

El movimiento se crea **en la misma transacción del alta**. A partir de ese instante el producto tiene `inventoryMovements > 0` y `remove()` lo rechaza para siempre, aunque nunca se venda.

### D.3 Segunda barrera: PostgreSQL

Aunque el código permitiese el borrado, la base lo impediría:

| Tabla | FK | `ON DELETE` |
|---|---|---|
| `inventory_movements` | `(company_id, product_id)` | **RESTRICT** |
| `warehouse_transfer_items` | `(company_id, product_id)` | **RESTRICT** |
| `SaleItem` | `productId` | SET NULL |
| `CotizacionItem` | `productId` | SET NULL |
| `purchase_order_items` | `product_id` | SET NULL |
| `warehouse_stocks` | `(company_id, product_id)` | CASCADE |
| `price_list_product_rules` | `product_id` | CASCADE |

No existen **triggers** en `Product` ni en sus tablas hijas.

### D.4 Respuestas verificadas sobre `INITIAL_STOCK`

| # | Pregunta | Respuesta verificada |
|---|---|---|
| 1 | ¿Cuándo se genera? | En la **misma transacción del alta**, cuando la empresa tiene inventario activo, el artículo es físico (`trackInventory`) y `stock inicial > 0`. |
| 2 | ¿Se genera con stock cero? | **No.** Solo si `initialStock.gt(0)`. |
| 3 | ¿Se genera al importar productos? | No existe endpoint de importación masiva. La importación de la app crea producto a producto con `operationId` (`import-create-N`), por lo que **sí** genera `INITIAL_STOCK` si la fila trae stock. |
| 4 | ¿Desde Windows? | Sí: mismo endpoint `POST /products`. La app es una sola base de código Flutter. |
| 5 | ¿Desde Android? | Sí, mismo endpoint. |
| 6 | ¿Desde Web/PWA? | Sí, mismo endpoint. |
| 7 | ¿Desde iPhone? | Sí, mismo endpoint (no ejecutado en dispositivo; ver limitaciones). |
| 8 | ¿Puede duplicarse en sincronización? | El alta exige `operationId`; el backend deriva un UUID determinista `sha256(companyId:operationId)` y hace `upsert`, por lo que el reintento devuelve el mismo producto. Datos: **0** productos con más de un `INITIAL_STOCK` y **0** `operation_id` duplicados. |
| 9 | ¿Cómo se relaciona con el Kardex? | Es el **primer** movimiento: `previous_quantity = 0`, `quantity_delta = stock inicial`, `resulting_quantity = stock inicial`. Verificado en los 241 movimientos. |
| 10 | ¿Cómo se relaciona con los almacenes? | Se aplica al almacén resuelto (`dto.warehouseId` o el almacén activo/por defecto). Se crea la fila de `warehouse_stocks` en 0 y luego se incrementa. |
| 11 | ¿Qué ocurre al archivar? | Nada: no se toca el movimiento ni el stock. |
| 12 | ¿Qué ocurre al restaurar? | Nada: el stock se conserva tal cual. |
| 13 | ¿Se conserva la trazabilidad? | Sí, el movimiento es inmutable y permanece. |
| 14 | ¿Se distingue de una operación comercial? | Sí: `type = INITIAL_STOCK`, `source_type = PRODUCT_CREATE`, `reason = PRODUCT_INITIAL_STOCK`. |
| 15 | ¿Consecuencias de revertir? | **Borrar** el movimiento destruye el rastro y descuadra el Kardex. **Compensar** con un movimiento inverso conserva la trazabilidad y deja el stock en 0. Se recomienda la compensación (sección J). |

### D.5 Verificación en el artefacto desplegado

- Contenedor `daleventapos_backend` (imagen `ghcr.io/juniorprueva/fullpos-cloud-api@sha256:0054cdaa…`, arrancado `2026-11-20T15:50:01Z`).
- `/app/dist/products/products.service.js` contiene la misma regla, el mismo mensaje y la poda de duplicados.
- El frontend desplegado (`main.dart.js`) contiene `PRODUCT_HAS_HISTORY` y el diálogo “Archivar producto”.

---

## E. Evidencias

### E.1 Evidencia del incidente (SIJO TELA)

```
2026-11-20T19:52:02.175Z [req] fcc22500-… DELETE /products/665cc617-0308-4f69-811f-21138e6309ac -> 409 (47 ms)
```

Cuerpo registrado por el servidor:

```
{"code":"PRODUCT_HAS_HISTORY","message":"Este producto tiene historial y no puede eliminarse definitivamente.",
 "canArchive":true,"details":{"inventoryMovements":2,"warehouseTransferItems":0,"saleItems":1,
 "cotizacionItems":0,"purchaseOrderItems":0,"purchaseReceiptItems":0}}
```

Producto: **“Vinil Blanco”**, SIJO TELA, stock 26, 2 movimientos, 1 venta. Quedó **archivado** a las `19:52:04Z` (2 s después): la app ofreció archivar y el usuario aceptó.

En los logs retenidos del backend: **1** único `DELETE /products/…` (el anterior), **0** respuestas 500 en rutas de productos y **0** podas de duplicados.

### E.2 Evidencia de telemetría (`telemetry_outbox`)

| Evento | Total | Empresas |
|---|---:|---|
| `PRODUCT_CREATED` | 216 | — |
| `PRODUCT_UPDATED` | 256 | — |
| `PRODUCT_ARCHIVED` | 34 | SIJO TELA 22, LANOTABAR 7, FULLTECH 3, Antonio 1, Asadero 1 |
| `PRODUCT_DELETED` | **5** | FULLTECH 4 (2026-09-11), Antonio Celulares 1 (2026-09-16) |
| `PRODUCT_REACTIVATED` | **0** | — |

SIJO TELA: **0** `PRODUCT_DELETED` desde que existe la telemetría.

### E.3 Evidencia del defecto de deduplicación con archivados

Producto `e8ca60ce-36ad-4c83-868e-e66ef4785774` — **“presidente pq dura”**, LANOTABAR, categoría `cerveza`, precio 130, costo 95,80, stock 24:

- Archivado: `2026-10-01 05:18:12`.
- `PRODUCT_UPDATED` con `metadata.reason = "reuse_equivalent_product"`: `2026-10-01 05:23:20` y `2026-10-01 05:29:17`.
- El producto seguía archivado después de ambos eventos y sigue archivado hoy.

Es decir: **el alta reutilizó un producto archivado y lo devolvió sin desarchivarlo**, por lo que el usuario no lo ve en el catálogo.

### E.4 Consultas de solo lectura ejecutadas (resumen)

- Conteos por empresa de productos, activos, archivados, ventas, movimientos, compras, transferencias, devoluciones, cotizaciones y otras referencias.
- Agregado global de bloqueados/eliminables/“solo inicial”.
- Conteo de candidatos a anulación verificando stock = resultado del movimiento inicial.
- Validación de integridad: stock vs almacenes, cadena de movimientos, aislamiento multiempresa, huérfanos, `operation_id`.
- Inventario de columnas con referencias a producto y de claves foráneas con su acción `ON DELETE`.
- Telemetría por tipo de evento y por empresa.

No se extrajeron correos, contraseñas, tokens ni datos personales.

### E.5 Limitaciones de la evidencia (importante)

1. **Logs**: el servicio usa `json-file` con `max-file=3`, `max-size=10m`, y la tarea actual se recreó hoy a las `15:50Z`. La ventana útil es de ~4,5 horas. **Los intentos de borrado anteriores a hoy no son verificables.** La ausencia de logs **no** demuestra ausencia de incidentes.
2. **Fuente vs despliegue**: el repositorio local está en `production-main` (HEAD 2026-10-12) con cambios sin commitear; la imagen desplegada se construyó hoy y no está mapeada a un commit. Por eso la regla se verificó **en el artefacto desplegado** (`/app/dist`), no solo en la fuente.
3. **App Flutter**: no se ejecutaron builds de Windows, Android ni iOS. Las conclusiones de UI provienen del código compartido (`apps/fulltech_app`) y del bundle web desplegado. La versión local (`1.0.6+141`) no coincide con la release publicada (`1.0.7-151`, 2026-11-02).
4. **Sin pruebas destructivas**: no se intentó borrar ningún producto real ni se ejecutaron escenarios adversariales en producción.
5. No existe un evento de auditoría de **intentos fallidos** de borrado, por lo que la frecuencia histórica es desconocida.

---

## F. Problemas adicionales encontrados

### F.1 Eliminación masiva sin manejo del conflicto (UX)

`apps/fulltech_app/lib/features/products/ui/inventory_module_pages.dart:1370`

```dart
for (final product in products) {
  await controller.remove(product.id);   // puede lanzar ProductDeleteRequiresArchiveException
  _productSearch.removeLocal(product.id);
}
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('${products.length} productos eliminados')),
);
```

- No captura `ProductDeleteRequiresArchiveException`.
- Aborta en el primer producto con historial.
- No informa qué productos se borraron, cuáles no ni por qué.
- La barra “N productos eliminados” solo se muestra si **ninguno** falla (aunque el mensaje, de mostrarse, sería engañoso si hubiera fallos parciales).
- En SIJO TELA, cualquier selección que incluya un producto con historial termina en error no controlado.

La eliminación **individual** sí está bien resuelta (`catalogo_screen.dart:1101-1150`): diálogo “Archivar producto” tras el 409.

### F.2 No existe forma de ver ni restaurar archivados en la app

- El backend soporta `GET /products?includeArchived=true` y `PATCH /products/:id/reactivate` (con control de cupo).
- La app **nunca** envía `includeArchived=true` (búsqueda exhaustiva: ninguna pantalla lo activa) y **no llama** a `/reactivate`.
- Resultado: para el cliente, **archivar es una acción irreversible**. No hay “papelera”, ni listado de archivados, ni botón de restaurar.
- Telemetría: **0** `PRODUCT_REACTIVATED` en toda la historia.

### F.3 Endpoint de depuración destructivo expuesto en producción

- Ruta: `DELETE /products/debug/purge` (`products.controller.ts:571`), rol `ADMIN`, permiso `editProducts`.
- Implementación: `purgeAllForDebug` → `product.deleteMany({ where: { companyId } })`, **sin comprobar historial** y **sin telemetría** (`products.service.ts:1957`).
- UI: botón “Limpiar tabla (debug)” visible para **cualquier ADMIN de empresa** en la app de escritorio/web (`catalogo_screen.dart:574`, `core/debug/debug_admin_action.dart:6`).
- Comportamiento real: si algún producto de la empresa tiene movimientos o transferencias, la sentencia falla completa por `RESTRICT` (no borra nada, devuelve 500). Si **ningún** producto tiene esas referencias, borra **todo el catálogo**, incluidas existencias (`warehouse_stocks` CASCADE) y deja las líneas de venta/cotización con `productId = NULL` (histórico conservado por snapshots).
- No queda registro de auditoría de la purga.

### F.4 Se pueden borrar productos con existencia real (pérdida silenciosa)

La regla **no comprueba `stock`**. Hay **114 productos con stock ≠ 0 y sin ningún movimiento**; de ellos, **83 son eliminables hoy** (79 de empresas reales + 4 de smoke tests) y suman **514 unidades** (502 en empresas reales):

| Empresa | Eliminables hoy | Con stock | Unidades |
|---|---:|---:|---:|
| Antonio Celulares | 45 | 45 | 152 |
| FULLTECH, SRL | 30 | 28 | 340 |
| Siarah Beer & Café | 7 | 6 | 10 |
| Smoke Tenant A (×3) + Codex | 4 | 4 | 12 |

Al borrarlos, `warehouse_stocks` se elimina por CASCADE y **no queda ningún movimiento que explique la desaparición del inventario**.

### F.5 Archivar no descarga el stock

- Archivar solo escribe `archived_at`; no ajusta `stock` ni `warehouse_stocks`.
- Los productos archivados desaparecen de listados, inventario y buscador, pero **conservan sus unidades**.
- Hay **42 productos archivados con 3.026,1 unidades** (SIJO TELA 2.803,5; LANOTABAR 156; FULLTECH 39,6; Asadero 21; Antonio 6).
- Sin pantalla de archivados (F.2), ese inventario es **invisible** para el negocio.

### F.6 Códigos reservados por archivados

- Índice único real: `UNIQUE (company_id, lower(btrim(codigo))) WHERE codigo IS NOT NULL AND btrim(codigo) <> ''`. **No excluye archivados.**
- `findByNormalizedCode` tampoco excluye archivados (`products.service.ts:585-600`).
- Consecuencia: al crear un producto con el código de uno archivado se recibe `409 “Ya existe un producto con ese código en esta empresa”`.
- Afecta a **7 productos archivados con código** (1 en SIJO TELA).

### F.7 `codigo`, `code`, `sku` y `barcode` son el mismo campo

`normalizeProductCode` usa `dto.codigo ?? dto.code ?? dto.sku ?? dto.barcode` y lo guarda en una sola columna `codigo`. No es posible tener SKU y código de barras distintos; el escáner y el SKU compiten por el mismo identificador.

### F.8 La poda de duplicados usa una lista de referencias incompleta

`pruneSafeDuplicateProducts` (`products.service.ts:737`) comprueba solo `saleItems + cotizacionItems + purchaseOrderItems + websiteOverrides` (`productReferenceCount`, línea 640). **No comprueba `inventory_movements`, `warehouse_transfer_items` ni `purchase_receipt_items`.**

Riesgos:
- Intenta borrar un duplicado con movimientos → PostgreSQL lo bloquea (`RESTRICT`) → `P2003` no capturado → **toda la transacción de alta/edición falla con 500**.
- Puede borrar duplicados **archivados** (la búsqueda de equivalencias no filtra `archivedAt`).
- Se ejecuta **después de cada alta y cada edición**, de forma silenciosa.

### F.9 La deduplicación puede reutilizar un producto archivado

`productIdentityWhere` (`products.service.ts:615`) compara `nombre + categoria + precio + costo + stock + unidad` y **no filtra `archivedAt`**. Si coincide con un producto archivado, `create()` lo actualiza y lo devuelve **sin desarchivarlo** (`productResponse` tampoco filtra archivados).

Evidencia real: LANOTABAR, producto “presidente pq dura”, 2 eventos `reuse_equivalent_product` posteriores a su archivado.

### F.10 Cotizaciones no excluyen archivados

`sales.service.ts:1516/2136`, `purchases.service.ts:836/1175` y `warehouses.service.ts:423` filtran `archivedAt: null`. **`cotizaciones.service.ts:1568` no lo hace.** Un cliente con caché obsoleta o una llamada directa puede cotizar un producto archivado.

### F.11 La imagen del producto no se elimina al borrar

`remove()` no toca R2 ni el almacén de imágenes. Cada borrado definitivo deja el objeto huérfano en el bucket.

### F.12 Sin notificación en tiempo real de cambios de catálogo

El relay Socket.IO existe para caja (`catalog-realtime-relay`), pero **no** para alta/edición/archivado/borrado de productos. Otros dispositivos mantienen el catálogo antiguo hasta refrescar; el servidor sí revalida en la venta (`archivedAt: null`).

### F.13 Asimetría offline

- **Borrar** sí se encola si falla la red o hay 5xx (`catalog_repository.dart:119`, `_shouldQueueSync`).
- **Archivar / restaurar** no se encolan: requieren conexión.
- Un borrado encolado que al reconectarse devuelve 409 se marca como fallo permanente y la UI ofrece “Archivar producto” (`sync_queue_service.dart:510`, `sync_status_menu_button.dart:598`). Diseño correcto.

### F.14 Respuestas ambiguas del API

- `DELETE` de un producto archivado devuelve `200 { ok: true, archived: true }` **sin borrar nada**. Un cliente que interprete 200 como “eliminado” mostrará un éxito falso.
- `DELETE` de un producto inexistente devuelve `200 { ok: true }`.

### F.15 No hay auditoría de intentos fallidos

Solo se registra la telemetría de operaciones exitosas. No existe evento para `PRODUCT_DELETE_REJECTED`, por lo que no se puede medir cuántos clientes lo intentan ni cuándo.

---

## G. Riesgos

| ID | Riesgo | Severidad | Probabilidad | Evidencia |
|---|---|---|---|---|
| R-01 | Pérdida silenciosa de inventario al borrar productos con stock sin movimientos | **Alta** | Media | 83 productos eliminables con 514 unidades |
| R-02 | Purga de depuración accesible a ADMIN de empresa, sin auditoría | **Alta** | Baja-Media | Endpoint y botón en producción |
| R-03 | Alta de producto devuelve un registro archivado (producto “no aparece”) | **Alta** | Media | 2 eventos reales en LANOTABAR |
| R-04 | Eliminación masiva falla sin explicación y sin ofrecer archivar | Media | Alta | Código + SIJO TELA bloqueado al 100 % |
| R-05 | Imposibilidad de restaurar archivados desde la app | Media | Alta | 0 `PRODUCT_REACTIVATED`; sin UI |
| R-06 | Inventario invisible en archivados (3.026 unidades) | Media | Alta | 42 archivados con stock |
| R-07 | Código reservado por archivados impide reutilizarlo | Media | Media | 7 archivados con código; índice único |
| R-08 | Poda de duplicados provoca 500 en alta/edición | Media | Baja | `productReferenceCount` incompleto |
| R-09 | Cotizar productos archivados | Baja | Baja | Falta filtro en cotizaciones |
| R-10 | Imágenes huérfanas en R2 | Baja | Alta | Sin borrado de objetos |
| R-11 | Catálogo desincronizado entre dispositivos | Baja | Media | Sin eventos realtime de producto |

---

## H. Matriz de decisiones funcionales

Leyenda: **Sí** = permitido; **No** = prohibido; **Cond.** = permitido con condiciones; **Hoy** = comportamiento actual.

| Escenario | Eliminar (hoy) | Eliminar (propuesto) | Archivar | Restaurar | Anular alta | Riesgo principal |
|---|---|---|---|---|---|---|
| Producto recién creado sin stock | **Sí** | Sí | Sí | Sí | No aplica | Ninguno |
| Producto con `INITIAL_STOCK` únicamente | **No** | **No** (borrado físico) | Sí | Sí | **Sí** | Revertir stock sin rastro → exige movimiento de reversión |
| Producto con ventas | **No** | No | Sí | Sí | No | Pérdida de trazabilidad comercial |
| Producto con devolución | **No** | No | Sí | Sí | No | Igual que ventas |
| Producto con cotización | **No** | Cond. (si la cotización es la única referencia y está anulada) | Sí | Sí | No | Documento histórico apunta a producto |
| Producto con compra/recepción | **No** | No | Sí | Sí | No | Coste y trazabilidad de compra |
| Producto con transferencia | **No** | No | Sí | Sí | No | Movimiento entre almacenes |
| Producto con ajuste manual | **No** | No | Sí | Sí | No | Auditoría de inventario |
| Producto archivado | **No** (200 sin borrar) | Cond. (solo si “anulado” y sin refs) | Idempotente | Sí (con cupo) | Cond. | Ambigüedad de respuesta |
| Producto con sincronización pendiente | **No** | No | Cond. (tras sincronizar) | Cond. | No | Carreras multi-dispositivo |
| Producto con stock y sin movimientos | **Sí** | **No** (exigir stock 0 o anulación previa) | Sí | Sí | Cond. | Pérdida silenciosa de inventario |

**Definiciones propuestas**
- **Eliminación física:** borra la fila. Solo si no hay ninguna referencia y `stock = 0`.
- **Eliminación lógica / archivado:** `archived_at`, fuera de operación, conserva todo.
- **Anulación de alta:** revierte la carga inicial con un movimiento compensatorio y deja el producto en estado `ANNULLED` (sin operar, sin ocupar código, conservado para auditoría).

---

## I. Alternativas de arquitectura

### Alternativa A — Mantener la protección y mejorar solo el archivado

| Aspecto | Evaluación |
|---|---|
| Ventajas | Riesgo de datos mínimo; cambios pequeños; sin migraciones |
| Desventajas | No resuelve los 86 casos de alta por error; el cliente sigue sin poder “quitar” un producto mal creado |
| Complejidad | Baja |
| Impacto DB/Backend/Flutter | Nulo / bajo / medio (UI de archivados y restaurar) |
| Sincronización | Sin cambios |
| Pruebas | Medias |

### Alternativa B — Permitir “anular alta” de productos solo con `INITIAL_STOCK`

| Aspecto | Evaluación |
|---|---|
| Ventajas | Resuelve exactamente los 86 casos seguros; conserva trazabilidad si se hace con movimiento de reversión |
| Desventajas | Requiere regla nueva, endpoint, transacción y UI; no cubre productos con otras referencias |
| Complejidad | Media |
| Impacto DB | Nuevo estado/campos de anulación + posible política de código |
| Impacto Backend | Endpoint `POST /products/:id/annul` con validación estricta |
| Impacto Flutter | Botón “Anular alta” en el diálogo de conflicto |
| Sincronización | Debe replicarse como operación idempotente |
| Riesgo | Medio si la reversión no es atómica |

### Alternativa C — Eliminación lógica como comportamiento principal

| Aspecto | Evaluación |
|---|---|
| Ventajas | Uniforme, reversible, sin riesgo de pérdida |
| Desventajas | No libera códigos salvo política adicional; el cliente percibe que “no borra”; requiere reescribir DELETE y la UI |
| Complejidad | Media-Alta |
| Impacto | Alto en backend y UI; migración de semántica |
| Riesgo | Bajo en datos, alto en expectativas del usuario |

### Alternativa D — Ciclo de vida explícito del producto (recomendada)

Estados: `DRAFT` → `ACTIVE` → `ARCHIVED` ↔ `ACTIVE`; `ACTIVE|ARCHIVED` → `ANNULLED` (solo si nunca tuvo operación comercial); `ANNULLED` → eliminación física opcional (solo si no hay referencias).

| Aspecto | Evaluación |
|---|---|
| Ventajas | Reglas claras y testeables; resuelve alta por error, archivo y restauración; permite política de códigos coherente |
| Desventajas | Mayor esfuerzo inicial y migración de datos/estado derivado |
| Complejidad | Alta |
| Impacto DB | Campos de estado/anulación + índices parciales |
| Impacto Backend | Reescritura de reglas en un módulo `product-lifecycle` |
| Impacto Flutter | Menús y mensajes por estado |
| Sincronización | Operaciones con `operationId` e idempotencia |
| Riesgo | Medio, mitigable por fases y flags |

### Comparación resumida

| Criterio | A | B | C | D |
|---|---|---|---|---|
| Resuelve SIJO TELA (52 casos) | No | **Sí** | Parcial | **Sí** |
| Riesgo de datos | Muy bajo | Bajo | Bajo | Bajo-Medio |
| Esfuerzo | Bajo | Medio | Medio-Alto | Alto |
| Claridad para el cliente | Media | Alta | Media | **Alta** |
| Compatibilidad con datos actuales | Total | Total | Alta | Alta (migración) |

### Solución recomendada

**D como objetivo, implementando B primero.** Es decir:

1. **Corto plazo (B):** endpoint de **anulación de alta** para productos cuyo único historial sea `INITIAL_STOCK` y sin referencias comerciales. Revierte el stock con un movimiento compensatorio y deja el producto `ANNULLED`.
2. **Mediano plazo (D):** formalizar el ciclo de vida con estados y reglas de transición, política de códigos y eliminación física restringida a productos sin referencias y con stock 0.
3. **Transversal:** corregir UX (masiva, archivados, restaurar), retirar/proteger la purga de depuración, cerrar los huecos de integridad (F.4, F.8, F.9, F.10).

---

## J. Solución recomendada (diseño funcional y técnico)

### J.1 Estados

| Estado | Descripción | Visible catálogo | Ocupa cupo | Reserva código | Vendible |
|---|---|---|---|---|---|
| `ACTIVE` | Operativo | Sí | Sí | Sí | Sí |
| `ARCHIVED` | Fuera de operación, reversible | No | No | **Sí** (propuesta) | No |
| `ANNULLED` | Alta revertida, sin operación histórica | No | No | **No** (propuesta) | No |

### J.2 Reglas

1. **Eliminar (físico)** solo si: `stock = 0`, sin movimientos, sin ventas, sin cotizaciones, sin compras/recepciones, sin transferencias, sin reglas de precio, sin overrides web, sin imágenes referenciadas en documentos. Si no, `409 PRODUCT_HAS_HISTORY`.
2. **Archivar**: siempre permitido (excepto ya archivado → idempotente). No toca stock.
3. **Restaurar**: solo `ARCHIVED → ACTIVE`, con control de cupo (`PLAN_LIMIT_REACHED`).
4. **Anular alta**: solo si el **único** movimiento es `INITIAL_STOCK`, `stock` coincide con su `resulting_quantity`, y no hay ninguna referencia comercial. Transacción:
   - Bloquear producto (`SELECT … FOR UPDATE`).
   - Insertar movimiento compensatorio `ADJUSTMENT_OUT` (o nuevo tipo `INITIAL_STOCK_REVERSAL`) con `sourceType = PRODUCT_ANNULMENT`, cantidad `-initial`, `resulting_quantity = 0`, `operation_id` idempotente.
   - Dejar `stock = 0` y `warehouse_stocks = 0`.
   - Marcar `annulled_at`, `annulled_by`, `annulment_reason`, `annulled_from_initial_stock_id`.
   - Telemetría `PRODUCT_ANNULLED`.
   - **No** borrar los movimientos: se conserva el rastro.
5. **Códigos**: `ARCHIVED` reserva; `ANNULLED` libera. Índice único parcial `WHERE annulled_at IS NULL`. `findByNormalizedCode` debe usar el mismo criterio.
6. **Purga debug**: eliminar la ruta en producción o exigir `ENABLE_DEBUG_PURGE=true` + superadmin + telemetría.
7. **Deduplicación**: excluir archivados/anulados y usar la lista completa de referencias protegidas; o desactivar la poda automática.
8. **Cotizaciones**: filtrar `archivedAt: null`.
9. **Imágenes**: al borrar físicamente, encolar eliminación del objeto en R2.
10. **Realtime** (opcional): emitir `product.changed` a la room de la empresa.

### J.3 API propuesta

| Método | Ruta | Descripción | Respuestas |
|---|---|---|---|
| `DELETE` | `/products/:id` | Borrado físico estricto | 200, 404, 409 `PRODUCT_HAS_HISTORY`, 409 `PRODUCT_HAS_STOCK` |
| `PATCH` | `/products/:id/archive` | Archivar (idempotente) | 200 |
| `PATCH` | `/products/:id/reactivate` | Restaurar (cupo) | 200, 409 `PLAN_LIMIT_REACHED` |
| `POST` | `/products/:id/annul` | Anular alta (`operationId`) | 200, 409 `PRODUCT_ANNUL_NOT_ALLOWED` |
| `GET` | `/products?includeArchived=true` | Listado con archivados | 200 |

### J.4 Mensajes de UI

- “Este producto ya tiene movimientos de inventario o ventas. Puedes **archivarlo** para que deje de aparecer y liberar cupo.”
- “Este producto solo tiene la carga inicial de existencias y nunca se usó. Puedes **anular el alta** (se revertirá el stock y quedará registrado).”
- “Se eliminó definitivamente.” / “Se archivó. Puedes restaurarlo desde Productos → Archivados.”
- En la eliminación masiva: “3 eliminados, 2 archivados, 1 con historial no se pudo quitar” con detalle por producto.

---

## K. Plan de implementación por fases

> **No ejecutar sin autorización expresa.** Cada fase termina con criterios de aceptación y condición de parada.

### Fase 1 — Protección y preparación

- **Trabajo:** respaldo verificado de PostgreSQL; entorno de staging aislado; feature flag `PRODUCT_LIFECYCLE_V2`; inventario de datos (86 candidatos) congelado como referencia.
- **Archivos/módulos:** infraestructura, `apps/api/.env`, scripts de respaldo.
- **Pruebas:** restaurar el respaldo en staging y comparar conteos.
- **Criterios de aceptación:** staging con copia anonimizada; flag apagado en producción.
- **Parada:** si el respaldo no se puede restaurar o hay drift entre esquema real y migraciones.

### Fase 2 — Reglas de negocio

- **Trabajo:** aprobar matriz H; definir estados y política de códigos; documentar quién puede anular.
- **Criterios:** documento firmado por el propietario; sin código aún.

### Fase 3 — Backend

- **Trabajo:** `ProductLifecycleService`; `DELETE` estricto (stock 0 y lista completa de referencias); `annul` transaccional; `archive/reactivate` idempotentes; corregir `pruneSafeDuplicateProducts`; excluir archivados de `productIdentityWhere`; filtro en cotizaciones; telemetría de anulación y de rechazo.
- **Archivos:** `products.service.ts`, `products.controller.ts`, `license.service.ts`, `cotizaciones.service.ts`, `warehouses.service.ts` (revisión), DTOs.
- **Dependencias:** Fase 2.
- **Riesgos:** carreras; usar `SELECT … FOR UPDATE` y advisory locks de cupo.
- **Pruebas:** unitarias y de integración con PostgreSQL real en staging.
- **Parada:** cualquier cambio que requiera borrar movimientos históricos.

### Fase 4 — PostgreSQL

- **Trabajo:** migración **aditiva** (columnas `annulled_at`, `annulled_by`, `annulment_reason`, `annulled_from_initial_stock_id`), índice parcial de código `WHERE annulled_at IS NULL`, índice `(company_id, annulled_at)`.
- **Prohibido:** cambiar `ON DELETE RESTRICT` de movimientos/transferencias; borrar columnas.
- **Criterios:** migración idempotente, reversible y probada en clon; `db:migrate` con revisión de SQL.
- **Parada:** si Prisma genera `DROP INDEX` de índices manuales.

### Fase 5 — Flutter

- **Trabajo:** pantalla “Archivados” con restaurar; diálogo de conflicto con opción “Anular alta” cuando aplique; eliminar-selectivo con resumen por producto; mensajes claros; soporte de `includeArchived`.
- **Archivos:** `catalogo_screen.dart`, `inventory_module_pages.dart`, `catalog_controller.dart`, `catalog_repository.dart`, `api_routes.dart`.
- **Criterios:** mismos textos y flujos en Windows/Web/Android/iOS; sin cambios de identidad visual.

### Fase 6 — Sincronización

- **Trabajo:** cola offline para `annul` y `archive`; idempotencia con `operationId`; resolución de conflictos (producto ya anulado, ya archivado, con venta nueva); reintentos acotados.
- **Pruebas:** escenarios 12–19 de la sección L.

### Fase 7 — Pruebas automatizadas

- **Trabajo:** batería L en unitarias, integración y e2e; contract tests de códigos HTTP.
- **Criterios:** 100 % de los 20 escenarios con evidencia; sin regresiones en ventas/compras/inventario.

### Fase 8 — Pruebas reales por plataforma

- **Trabajo:** Windows, Web/PWA, Android e iOS (si hay entorno); tamaños teléfono/tableta/escritorio; offline real.
- **Criterios:** captura + interacción registrada por plataforma.

### Fase 9 — Despliegue controlado

- **Trabajo:** backup, migración, backend, app; flag ON por empresa piloto (SIJO TELA); monitoreo de `PRODUCT_HAS_HISTORY`, `PRODUCT_ANNULLED`, 409/500, colas; rollback (flag OFF + migración aditiva no destructiva).
- **Parada:** cualquier 500 nuevo, pérdida de stock o discrepancia en kardex.

---

## L. Plan de pruebas

| # | Escenario | Resultado esperado | Estado |
|---|---|---|---|
| 1 | Crear y eliminar producto sin stock ni referencias | 200 y fila eliminada | Existe prueba unitaria; **falta e2e** |
| 2 | Crear con stock inicial y anular alta | Movimiento de reversión, stock 0, estado `ANNULLED`, código liberado | **No existe** (nueva funcionalidad) |
| 3 | Eliminar producto vendido | 409 `PRODUCT_HAS_HISTORY`, `canArchive: true` | Existe unitaria |
| 4 | Eliminar producto con devolución | 409 | Falta explícita (cubierto por movimientos) |
| 5 | Eliminar producto comprado | 409 | **Falta** |
| 6 | Eliminar producto transferido | 409 | **Falta** |
| 7 | Archivar producto con historial | 200; desaparece del listado; stock intacto | Existe unitaria; falta e2e |
| 8 | Restaurar archivado | 200; vuelve al listado | Existe unitaria; **sin UI** |
| 9 | Restaurar con plan lleno | 409 `PLAN_LIMIT_REACHED` | Existe unitaria |
| 10 | Reutilizar código de anulado | 200 | **No existe** |
| 11 | Reutilizar código de activo/archivado | 409 | **Falta** |
| 12 | Operaciones simultáneas (delete vs archive) | Un único resultado consistente; sin 500 | **Falta** (riesgo de carrera) |
| 13 | Respuesta perdida y reintento | Idempotente; sin duplicados | Parcial (create por `operationId`) |
| 14 | Acceso desde otra empresa | 404/403; sin fuga | Existe unitaria |
| 15 | Intento sin permisos | 403 | Existe a nivel guard; falta e2e |
| 16 | Sincronización con datos obsoletos | Venta rechazada por `archivedAt: null` | Existe validación; falta e2e |
| 17 | Inventario en varios almacenes | Transferencia y anulación correctas | **Falta** para anulación |
| 18 | Producto con historial fiscal | Venta conserva snapshots tras cualquier cambio | Cubierto por `SET NULL` + snapshots; falta e2e fiscal |
| 19 | Producto con operaciones pendientes offline | No se anula/borra hasta sincronizar | **Falta** |
| 20 | Kardex y reportes tras cada operación | Cuadran con `warehouse_stocks` y movimientos | **Falta** verificación automatizada |

**Advertencia:** las pruebas 2, 10, 12, 17, 19 y 20 **no pueden ejecutarse todavía** porque la funcionalidad no existe o no hay entorno. Se listan como diseño, no como resultado.

---

## M. Estrategia de despliegue

1. **Previo:** backup lógico y físico; verificación de restauración; ventana sin e2e en curso; API sin procesos de cola activos.
2. **Migración:** solo aditiva; ejecutar con el script seguro del proyecto; verificar índices manuales.
3. **Backend:** despliegue con flag `PRODUCT_LIFECYCLE_V2=false`; validar arranque y `GET /products`.
4. **Piloto:** activar flag para SIJO TELA; anular los 35 candidatos activos uno a uno con evidencia; verificar kardex.
5. **Resto de empresas:** activación progresiva por lista; los 64 activos restantes solo con autorización del cliente.
6. **App:** publicar versión con Archivados/Restaurar y masiva corregida.
7. **Monitoreo:** `PRODUCT_HAS_HISTORY` (baja esperada), `PRODUCT_ANNULLED`, `PRODUCT_DELETED`, 409/500, diferencias de stock, colas offline.
8. **Rollback:** flag OFF (las columnas nuevas son ignoradas); no revertir la migración salvo incidente grave; restaurar backup solo con autorización.

---

## N. Decisiones pendientes del propietario

1. ¿Se aprueba **anular el alta** de productos con solo `INITIAL_STOCK` (86 casos, 6.076 unidades)?
2. ¿El borrado físico se restringe a `stock = 0` y sin referencias?
3. ¿Los **archivados** deben seguir reservando su código, o se libera también al archivar?
4. ¿Se habilita en la app la pantalla de **archivados + restaurar**?
5. ¿Qué hacemos con el stock de los archivados actuales (3.026 unidades)?
6. ¿Se retira `DELETE /products/debug/purge` de producción o se limita a superadmin con auditoría?
7. ¿Se registra un evento de **intento fallido** de borrado?
8. ¿Se añaden eventos en tiempo real de cambios de catálogo?
9. ¿Se eliminan las imágenes de R2 al borrar definitivamente?
10. ¿Se permite reutilizar el código de un anulado de inmediato?
11. ¿Quién puede anular: ADMIN, ASISTENTE o solo soporte?
12. ¿Se comunica a los clientes afectados que deben **archivar** mientras se implementa?

---

## O. Conclusión y dictamen

- **Gravedad:** **Alta funcional** (no hay corrupción de datos). Afecta al 83,8 % de los productos de la plataforma y al 100 % del catálogo de SIJO TELA.
- **Alcance:** **global**, no exclusivo de SIJO TELA. 9 de 38 tenants afectados; 5 con el catálogo completo bloqueado.
- **Causa:** regla de protección que incluye los movimientos de inventario, combinada con la generación automática de `INITIAL_STOCK` al crear con existencia.
- **Agravantes:** eliminación masiva sin manejo del conflicto, ausencia de restauración en la app, purga de depuración sin auditoría, borrado permitido con stock sin kardex, reutilización silenciosa de archivados.
- **Solución:** ciclo de vida explícito (Alternativa D) con **anulación de alta** (Alternativa B) como primera entrega.
- **Riesgo de no actuar:** pérdida silenciosa de inventario, pérdida de confianza del cliente y soporte recurrente por un comportamiento que el usuario no puede entender ni resolver.
- **No se implementó nada.** Se espera autorización expresa para iniciar la Fase 1.

### Tabla de hallazgos

| ID | Severidad | Empresa(s) afectada(s) | Evidencia | Causa | Solución propuesta | Riesgo | Prioridad |
|---|---|---|---|---|---|---|---|
| H-01 | Alta | SIJO TELA + 8 empresas | 459/548 bloqueados; 409 en log | `remove()` bloquea por `inventory_movements` | Anulación de alta + archivado claro | Cliente sin salida | P0 |
| H-02 | Alta | Todas | 86 productos solo con `INITIAL_STOCK` | Alta con stock genera movimiento | Endpoint `annul` con reversión | Pérdida de trazabilidad si no se compensa | P0 |
| H-03 | Alta | SIJO TELA (confirmado), resto potencial | Bulk delete sin `catch` | UI no maneja 409 | Resumen por producto + archivar | Fallo silencioso | P0 |
| H-04 | Alta | Todas | Purga accesible a ADMIN, sin telemetría | Endpoint debug en producción | Retirar o restringir + auditar | Borrado masivo | P0 |
| H-05 | Alta | Antonio, FULLTECH, Siarah | 83 eliminables con 514 unidades | Regla no valida `stock` | Exigir stock 0 | Pérdida de inventario | P0 |
| H-06 | Alta | LANOTABAR | 2 eventos `reuse_equivalent_product` tras archivar | `productIdentityWhere` incluye archivados | Excluir archivados/anulados | Producto “no aparece” | P1 |
| H-07 | Media | Todas | 0 `PRODUCT_REACTIVATED`; sin UI | No hay pantalla de archivados | Listado + restaurar | Archivado irreversible | P1 |
| H-08 | Media | Todas | 42 archivados con 3.026 unidades | Archivar no ajusta stock | Política de stock al archivar | Inventario invisible | P1 |
| H-09 | Media | Todas | 7 archivados con código | Índice único incluye archivados | Política de códigos | No se puede reutilizar | P1 |
| H-10 | Media | Todas | `productReferenceCount` incompleto | Poda de duplicados | Lista completa o desactivar | 500 en alta/edición | P1 |
| H-11 | Baja | Todas | `cotizaciones.service.ts:1568` | Falta filtro `archivedAt` | Añadir filtro | Cotizar archivados | P2 |
| H-12 | Baja | Todas | Sin borrado de R2 | `remove()` no limpia objetos | Job de limpieza | Coste/almacenamiento | P2 |
| H-13 | Baja | Todas | 200 en borrado de archivado | Respuesta ambigua | 409 o `deleted:false` explícito | Éxito falso | P2 |
| H-14 | Baja | Todas | Sin eventos realtime de producto | Relay solo de caja | Emitir `product.changed` | Catálogo obsoleto | P3 |

---

## P. Respuestas directas a las 15 preguntas

1. **¿Afecta a todas las empresas?** La regla sí es global; el impacto no. 9 de 38 tenants tienen productos bloqueados (9 de 15 con catálogo).
2. **¿Cuántas empresas están afectadas?** 9 potencialmente; **1 confirmada** por logs (SIJO TELA). 5 tienen el 100 % bloqueado.
3. **¿Cuántos productos no pueden eliminarse?** **459 de 548** (83,8 %).
4. **¿Cuántos podrían anularse de forma segura?** **86** (64 activos, 22 archivados), 6.076,07 unidades, con stock exactamente igual a la carga inicial y sin otras referencias.
5. **¿Por qué se bloquean?** Porque `remove()` exige cero referencias en 6 tablas y todo producto con existencia inicial nace con un movimiento `INITIAL_STOCK`.
6. **¿Qué comportamiento debería tener FullPOS?** Ciclo de vida explícito: eliminar solo lo nunca usado y sin stock; archivar siempre; restaurar; anular el alta cuando solo haya carga inicial.
7. **¿Consecuencias de cambiar la regla?** Si se hace sin compensación, pérdida de trazabilidad y de inventario; con reversión y auditoría, ninguna pérdida y sí más claridad.
8. **¿Qué otros módulos se ven afectados?** Inventario/Kardex, ventas, compras, cotizaciones, transferencias, cupos de plan, portal web y sincronización offline.
9. **¿Cambios indispensables?** Anulación de alta, borrado estricto (stock 0 + referencias), UX de conflictos, archivados/restaurar, purga debug, política de códigos.
10. **¿Cambios opcionales?** Realtime de productos, limpieza de imágenes, evento de intentos fallidos.
11. **¿Solución recomendada?** Alternativa D con entrega inicial B.
12. **¿Plan exacto?** Sección K (9 fases).
13. **¿Cómo se garantiza la integridad?** Transacciones con bloqueo, movimiento compensatorio, telemetría, restricciones FK intactas, pruebas de kardex.
14. **¿Cómo se prueba en todas las plataformas?** Batería L en staging + pruebas reales Windows/Web/Android/iOS con capturas e interacción.
15. **¿Qué decisiones aprobar?** Las 12 preguntas de la sección N.

---

**FIN DEL INFORME — AUDITORÍA COMPLETADA. NO SE HA IMPLEMENTADO NINGÚN CAMBIO.**
