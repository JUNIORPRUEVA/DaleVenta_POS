# FullPOS Fiscal E2E Manual Checklist

Fecha: 2026-08-18

No ejecutar deploy antes de completar esta lista en staging.

## PC

1. Tax OFF: crear producto RD$2,500 costo RD$1,300, venderlo y confirmar total RD$2,500, ganancia histórica RD$1,200 y sin ITBIS.
2. ITBIS incluido: empresa con precios incluidos, producto RD$1,180, confirmar preview/base RD$1,000, ITBIS RD$180 y total/cobro RD$1,180.
3. Precio + impuesto: producto base RD$1,000, confirmar preview/base RD$1,000, ITBIS RD$180 y total/cobro RD$1,180.
4. Exento: producto RD$500, confirmar ITBIS RD$0, exento RD$500 y total/cobro RD$500.
5. Mixto: vender incluido RD$1,180 + exento RD$500, confirmar base RD$1,000, ITBIS RD$180, exento RD$500 y total RD$1,680.
6. Cotización FULLTECH: FOTOCELDA 1200, MOTOR WIFI 13000, SERVICIO EXTRA 4000, SERVICIO REEMPLAZO 6000, LAMPARA 1500, confirmar total RD$25,700, base RD$21,779.66 e ITBIS RD$3,920.34.
7. Cotización no consume NCF: crear cotización y confirmar que secuencia NCF no cambia.
8. Cotización a B01: convertir/emmitir desde venta fiscal y confirmar total RD$25,700 y un solo NCF consumido.
9. Snapshot histórico: emitir factura, editar empresa/cliente/producto/impuesto, regenerar documento y confirmar datos originales.
10. Cambio empresa: abrir Nuevo Producto con Empresa A, cambiar a Empresa B y confirmar formulario cerrado/reseteado sin impuestos/categorías/productos de A.
11. Carrito y cambio empresa: llenar carrito en A, cambiar a B y confirmar carrito limpio.

## Móvil

Repetir los mismos 11 casos anteriores en viewport móvil/PWA, incluyendo scroll del formulario de producto, panel de cotización y cobro en POS.

## Resultado Esperado

Producto, catálogo, POS, cotización, factura y reportes no deben mostrar totales fiscales distintos para el mismo snapshot. Empresa A nunca debe reutilizar productos, clientes, impuestos, cotizaciones, carrito ni secuencias de Empresa B.

## Fiscal Regression Results

Ejecutado localmente el 2026-08-18.

```text
Included 1180 = PASS
Base 1000 / ITBIS 180 / Total 1180

Added 1000 = PASS
Base 1000 / ITBIS 180 / Total 1180

Exempt 500 = PASS
ITBIS 0 / Exento 500 / Total 500

Mixed 1680 = PASS
Base 1000 / ITBIS 180 / Exento 500 / Total 1680

Tax Off backward compatibility = PASS
Empresa sin impuestos conserva total comercial y no genera ITBIS.

Company A/B/C isolation = PASS
A sin impuestos, B incluido y C agregado producen sus resultados desde settings separados.

Cross-tenant backend = PASS
ProductId, ClientId, QuoteId y NCF sequence se consultan con companyId autenticado.
```
