# FullPOS Tax Profit/Margin Decision

Fecha: 2026-08-18

## Inventario Técnico Encontrado

- Catálogo Flutter: `inventory_module_pages.dart` calcula `product.precio - product.costo` y margen sobre costo.
- Cotizaciones Flutter: `cotizaciones_screen.dart` calcula utilidad de línea como `qty * (price - cost)`.
- Cotizaciones backend: `cotizaciones.service.ts` persiste `totalProfit` y `CotizacionItem.profit`.
- Ventas backend: `sales.service.ts` persiste `Sale.totalProfit` y `SaleItem.profit`.
- Reportes backend: `reports.service.ts` suma `SaleItem.profit` y `Sale.totalProfit`.
- Caja backend/Flutter: `cash.service.ts`, `cash_*` muestran utilidad persistida.
- Nómina/comisiones: `payroll.service.ts` consume `Sale.totalProfit` y `commissionAmount`.
- PDFs/impresión: reportes de ventas y comprobantes muestran `totalProfit`/`commissionAmount`.

## Fórmula Antigua y Actual

FullPOS calcula ganancia como:

```text
ganancia = precio cobrado / subtotal vendido - costo
```

En catálogo:

```text
ganancia unidad = product.precio - product.costo
margen = ganancia unidad / product.costo
```

En ventas backend:

```text
totalProfit = totalSold - totalCost
saleItem.profit = lineTotal - subtotalCost
```

Reportes, caja y agregados usan el `profit` persistido en ventas.

## Problema con ITBIS Incluido

Si una empresa usa precios con ITBIS incluido, el precio público contiene un monto que no es ingreso económico libre:

```text
Precio público RD$2,500.00
ITBIS 18% incluido
Base RD$2,118.64
ITBIS RD$381.36
Costo RD$1,300.00
```

La fórmula bruta muestra:

```text
RD$2,500.00 - RD$1,300.00 = RD$1,200.00
```

La utilidad fiscalmente informativa antes de otros costos sería:

```text
RD$2,118.64 - RD$1,300.00 = RD$818.64
```

## Decisión de Esta Fase

No se cambia todavía la fórmula persistida de ganancia/margen ni comisiones.

Razón: cambiar solo catálogo rompería la consistencia con ventas históricas, reportes, caja, nómina/comisiones y cierres que ya consumen `Sale.totalProfit` y `SaleItem.profit`. La semántica actual queda definida como:

```text
Ganancia operativa bruta visible = total cobrado - costo
```

Esto mantiene compatibilidad completa para empresas con `taxEnabled=false` y evita recalcular histórico.

## Fórmulas Definidas

Empresa sin impuestos:

```text
ganancia bruta = totalCobrado - costo
margen legado = ganancia bruta / costo
```

ITBIS incluido:

```text
base = precioFinal / (1 + tasa)
itbis = precioFinal - base
ganancia sin impuestos = base + exento - costo
```

Precio + impuesto:

```text
base = precioConfigurado
itbis = base * tasa
totalCobrado = base + itbis
ganancia sin impuestos = base + exento - costo
```

Exento:

```text
ganancia sin impuestos = precioExento - costo
```

Margen fiscal propuesto:

```text
margen sin impuestos = ganancia sin impuestos / costo
```

Se conserva el margen sobre costo porque es la semántica histórica de FullPOS. No se migra a `profit / taxableRevenue` sin una decisión de negocio separada.

## Recomendación Fiscal Siguiente

Agregar un campo/métrica separada, no reemplazo silencioso:

```text
gananciaNetaImpuesto = baseImponible + exento - costo
```

Esa métrica debe aplicarse de forma centralizada en:

- catálogo;
- POS;
- venta histórica;
- reportes;
- caja;
- cierres;
- comisiones si negocio decide que aplica.

## Históricos, Reportes y Comisiones

- Ventas antiguas no se recalculan.
- `Sale.totalProfit`, `SaleItem.profit`, reportes, caja, nómina y comisiones mantienen la métrica bruta histórica.
- La métrica fiscal neta debe agregarse como campo separado antes de mostrarse como "Ganancia sin impuestos".
- No llamar `Ganancia` a dos métricas distintas: usar `Ganancia bruta` y `Ganancia sin impuestos`.

## Efecto Actual

- Catálogo conserva ganancia/margen legado.
- Reportes conservan `profit` persistido.
- Empresas sin impuestos no cambian comportamiento.
- Para empresas con ITBIS incluido, la ganancia mostrada puede incluir impuesto cobrado; queda documentado como limitación funcional pendiente, no como blindaje final.
