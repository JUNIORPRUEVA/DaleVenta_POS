# DGII Traditional Invoice Fields Checklist

Fecha de revisión: 2026-08-18

Fuentes oficiales consultadas:

- DGII, Tipos de Comprobantes Fiscales: https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscales/Paginas/tiposComprobantes.aspx
- DGII, Formatos de Factura: https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscales/Paginas/formatosFactura.aspx
- DGII, Comprobantes Fiscales: https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscales/Paginas/default.aspx

## Alcance

Esta checklist cubre comprobantes fiscales tradicionales usados por FullPOS Cloud:

- B01 / Tipo 01: Factura de Crédito Fiscal.
- B02: Factura de Consumo / consumidor final.

No cubre e-CF, XML, firma digital, E31/E32 ni envío electrónico DGII.

## Criterios Aplicados En FullPOS

- El NCF se muestra solo si viene del backend/snapshot de venta.
- La cotización nunca muestra NCF ni se etiqueta como factura fiscal.
- B01 se etiqueta como `FACTURA FISCAL` y `B01 - CRÉDITO FISCAL`.
- B02 se etiqueta como `FACTURA FISCAL` y `B02 - CONSUMIDOR FINAL`.
- Para B02, el bloque de cliente no obliga RNC/Cédula; se muestra solo si existe.
- El emisor muestra nombre comercial/razón social, RNC, teléfono y dirección cuando están disponibles.
- El detalle fiscal usa importes almacenados por línea: `Base`, `ITBIS`, `Total`.
- Las facturas de consumo no prometen crédito fiscal al receptor.

## Campos Visuales

| Campo | Cotización | Factura interna | B01 | B02 |
| --- | --- | --- | --- | --- |
| Nombre emisor | READY | READY | READY | READY |
| RNC emisor | READY si disponible | READY si disponible | READY si disponible | READY si disponible |
| Dirección/teléfono emisor | READY si disponible | READY si disponible | READY si disponible | READY si disponible |
| Tipo de documento | COTIZACIÓN | FACTURA | FACTURA FISCAL | FACTURA FISCAL |
| Tipo NCF | No aplica | No aplica | B01 - CRÉDITO FISCAL | B02 - CONSUMIDOR FINAL |
| NCF | No mostrar | No mostrar | READY desde snapshot | READY desde snapshot |
| Cliente | READY | READY | READY | READY opcional |
| RNC/Cédula cliente | Opcional | Opcional | READY si snapshot | Opcional |
| Fecha | READY | READY | READY | READY |
| Detalle Base/ITBIS/Total | READY cuando tax ON | READY cuando tax ON | READY | READY |
| Total general | READY | READY | READY | READY |

## Notas De Cumplimiento

DGII describe el Tipo 01 como comprobante para sustentar costos/gastos o crédito de ITBIS. DGII también indica que en Facturas de Consumo se omiten datos del cliente por estar dirigidas a consumidores finales. FullPOS refleja esa diferencia visualmente en B01/B02.
