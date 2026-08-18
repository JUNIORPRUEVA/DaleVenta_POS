# FULLPOS Tax And Fiscal Audit

Fecha de auditoria: 2026-08-18

Alcance revisado: backend Nest/Prisma en `apps/api`, app Flutter en `apps/fulltech_app`, ventas, cotizaciones, productos, clientes, configuracion de empresa, contabilidad fiscal, PDF/tickets, reportes, caja y flujos offline visibles en el repositorio.

## Nota Fase 6

El historial Prisma legacy fue archivado y reemplazado por el baseline activo
`20260818190000_phase6_baseline`. La validacion contra `fullpos_migration_test`
demostro `npx prisma migrate deploy = PASS` desde DB vacia. Produccion no fue
migrada; requiere backup y `migrate resolve --applied` en un despliegue
controlado.

## Nota UI fiscal de productos

La integracion de UI fiscal de productos quedo documentada en
`FULLPOS_PRODUCT_TAX_UX_IMPLEMENTATION.md`. El flujo activo de
Inventario/Catalogo ya expone tratamiento fiscal por producto solo cuando
`taxEnabled=true`, calcula preview con helper central, persiste
`taxTreatment`/`taxRate`/`taxPriceMode` y el backend valida que la tasa gravada
exista activa para el `companyId` autenticado. El modelo actual de producto no
tiene `taxId`; el blindaje se hace por `taxRate` contra `taxes.companyId`.

## 1. Estado actual

FullPOS Cloud actualmente opera principalmente como POS sin impuestos fiscales integrados en ventas. Las ventas (`Sale`/`SaleItem`) guardan `totalSold`, costo, ganancia, pago, cliente y snapshots basicos de producto, pero no guardan base imponible, ITBIS, exento, tasa, modo incluido/agregado ni NCF.

La configuracion de empresa (`Company`/`AppConfig`) guarda datos comerciales y RNC, pero no existe una configuracion fiscal formal por `companyId` como `taxEnabled`, `pricesIncludeTax`, `defaultTaxRate` o `ncfEnabled`.

Los productos (`Product`) guardan precio, costo, categoria, stock e imagen. No tienen tratamiento fiscal por producto, tasa, exencion ni modo de precio.

Cotizaciones si tienen campos `includeItbis`, `itbisRate`, `itbisAmount` y `globalDiscountAmount`, pero su calculo actual trata `includeItbis` como "sumar ITBIS al subtotal". Eso contradice el nombre y el requisito critico de ITBIS incluido, donde se debe extraer base e impuesto desde el precio final.

El modulo `FiscalInvoice` de contabilidad registra imagen, fecha y tipo interno (`SALE`, `SALE_CARD`, `PURCHASE`). No modela NCF, secuencias, tipo B01/B02/B14/B15, RNC receptor, base imponible, ITBIS ni vinculo fuerte a una venta emitida.

PDF/tickets pueden mostrar RNC e ITBIS en algunos contextos, pero dependen de datos agregados o calculados fuera de una fuente fiscal unica. No hay garantia de que A4, ticket, cotizacion y backend calculen igual.

## 2. Problemas encontrados

CRITICAL

- No existe snapshot fiscal por linea de venta: `SaleItem` no persiste `taxableBase`, `taxRate`, `taxAmount`, `taxIncluded`, `taxExempt` ni `lineDiscount`.
- No existe configuracion fiscal por empresa. Empresas existentes no tienen una bandera persistente que garantice "impuestos OFF" de forma explicita.
- El nombre `includeItbis` en cotizaciones es semanticamente peligroso: hoy suma ITBIS al subtotal, no extrae ITBIS incluido.
- El backend no valida reglas fiscales al crear ventas: totales, bases, impuestos, cliente fiscal y NCF no son fuente de verdad en servidor.
- No existe emision/transaccion de NCF ni restriccion `unique(companyId, ncf)` para facturas emitidas.

HIGH

- Hay tasas hardcodeadas `0.18` en cotizaciones backend, Flutter y almacenamiento local.
- Flutter usa `double` en calculos monetarios importantes.
- Ventas offline pueden encolar ventas, pero no hay estrategia fiscal/NCF idempotente para emision fiscal.
- Devoluciones solo marcan la venta como devuelta y restauran stock; no reversan componentes fiscales porque no existen.
- Reportes agregan ventas por total, costo y ganancia; no diferencian base gravada, ITBIS, exento ni descuentos fiscales.

MEDIUM

- PDF/ticket muestran ITBIS cuando reciben un valor, pero no hay contrato de datos fiscales obligatorio.
- Clientes tienen datos generales, pero no se fuerza cliente fiscal para B01 u otros tipos que lo requieran.
- Permisos incluyen una capacidad amplia de factura fiscal e ITBIS, pero faltan permisos granulares como editar configuracion fiscal, gestionar NCF u override de impuestos.
- La tabla `FiscalInvoice` sirve mas como archivo/registro contable de comprobantes que como documento fiscal emitido.

LOW

- Existen documentos previos de auditoria multiempresa y seguridad que ayudan, pero la arquitectura fiscal aun no esta alineada con ellos.
- Algunas referencias a ITBIS son solo textos/UI o pruebas de impresion, no calculos.

## 3. Riesgos de produccion

- Cobrar RD$1,180 + 18% cuando el precio ya incluye ITBIS.
- Emitir documentos con ITBIS calculado distinto en Flutter, backend y PDF.
- Recalcular una factura historica con la tasa actual del producto.
- Duplicar NCF bajo concurrencia o reintentos.
- Mezclar configuracion fiscal entre empresas por falta de modelos aislados.
- Ensuciar empresas simples con impuestos activados implicitamente.

## 4. Arquitectura actual

- POS: Flutter arma items y total; backend normaliza precio/costo, valida stock y pago.
- Persistencia: Prisma usa `Decimal(12,2)` para dinero y `Decimal(12,3)` para cantidades en ventas.
- Cotizaciones: calculo fiscal disperso entre modelo Flutter, pantalla, repositorio local SQLite y backend.
- Fiscal: modulo de contabilidad guarda imagen/fecha/tipo, no secuencia NCF ni documento emitido.
- Impresion/PDF: consume modelos de venta/cotizacion/ticket sin snapshot fiscal completo.

## 5. Arquitectura propuesta

Crear un motor fiscal unico en backend, por ejemplo `TaxCalculationService`, que calcule:

- impuestos OFF;
- impuesto agregado;
- impuesto incluido;
- productos exentos;
- descuentos por linea y descuento global;
- totales por linea y por factura;
- asignacion deterministica de centavos.

Flutter puede tener un espejo de presentacion, pero el backend debe ser la fuente de verdad para guardar ventas fiscales.

Modelo conceptual:

- `Company.taxEnabled`
- `Company.defaultTaxRate`
- `Company.pricesIncludeTax`
- `Company.ncfEnabled`
- `Product.taxTreatment`: `INHERIT`, `TAXABLE`, `EXEMPT`
- `Sale` snapshots fiscales agregados
- `SaleItem` snapshots fiscales por linea
- `NcfSequence` por empresa/tipo
- `FiscalDocument` o extension de `Sale` para NCF emitido

## 6. Cambios de base de datos

Cambios seguros recomendados:

- agregar columnas fiscales con defaults conservadores (`tax_enabled = false`);
- agregar campos nullable/default cero a ventas e items;
- crear enum de tratamiento fiscal de producto;
- crear secuencias NCF por `companyId` y tipo;
- crear restriccion unica para NCF emitidos por empresa.

No migrar productos existentes a ITBIS 18%. No modificar totales historicos.

## 7. Cambios backend

Realizado en esta iteracion:

- Se agrego un motor fiscal puro backend (`TaxCalculationService`) con reglas para impuestos apagados, agregado, incluido, exentos, descuentos y redondeo.
- Se agregaron pruebas unitarias para los casos obligatorios base, incluida la factura FULLTECH/CANATECH.

Pendiente:

- Conectar el motor a `SalesService.create` solo cuando `taxEnabled = true`.
- Validar en backend que ventas fiscales coincidan con el calculo del motor.
- Implementar emision NCF transaccional e idempotente.

## 8. Cambios Flutter

Pendiente:

- Mostrar controles fiscales solo cuando `taxEnabled` este activo.
- Renombrar/corregir semantica de `includeItbis` en cotizaciones.
- Evitar que cajeros editen tratamiento fiscal en venta normal.
- Enviar payload fiscal solo como intencion; backend recalcula.

## 9. Cambios impresion/PDF

Pendiente:

- Extender `TicketData`, PDFs de venta y cotizacion para recibir base gravada, ITBIS, exento, descuentos, NCF, RNC emisor/receptor y razon social.
- Mostrar "ITBIS incluido" cuando aplique.
- No afirmar autorizacion DGII si solo se valida formato.

## 10. Cambios reportes

Pendiente:

- Agregar columnas/metricas fiscales condicionadas a `taxEnabled`.
- Mantener reportes simples cuando impuestos esten OFF.

## 11. Migracion de empresas existentes

Estrategia conservadora:

- Empresas existentes quedan con `taxEnabled = false`.
- Productos existentes quedan `taxTreatment = INHERIT`.
- Ventas historicas conservan totales actuales y campos fiscales en cero/null.
- Activar impuestos debe ser una accion explicita de administrador.

## 12. Compatibilidad hacia atras

La introduccion de campos con defaults no debe cambiar ventas actuales. El POS debe seguir calculando:

`Producto RD$1,000 -> Total RD$1,000`

mientras `taxEnabled = false`.

## 13. Estrategia de redondeo

Regla implementada en el motor:

- trabajar con `Prisma.Decimal`;
- redondear moneda a 2 decimales con half-up;
- calcular objetivos de factura por grupo de tasa;
- redondear lineas;
- asignar diferencias de centavos de forma deterministica a lineas gravadas usando mayor residuo y orden original;
- no crear productos/ajustes visibles ficticios.

Para FULLTECH/CANATECH con RD$25,700 ITBIS incluido al 18%:

- Base imponible: RD$21,779.66
- ITBIS: RD$3,920.34
- Total: RD$25,700.00

## 14. Estrategia NCF

Pendiente de implementacion completa:

- `NcfSequence(companyId, type, prefix, nextNumber, endNumber, validUntil, active)`;
- reserva dentro de transaccion backend;
- `unique(companyId, ncf)`;
- validacion de prefijo contra tipo seleccionado;
- idempotencia por `clientRequestId` o llave fiscal de emision;
- cancelaciones/anulaciones con auditoria.

Advertencia: `B0100000014` en pruebas es solo formato/valor de regresion. Debe pertenecer a una secuencia B01 vigente y autorizada para FULLTECH, SRL. Sin integracion DGII solo puede mostrarse "formato valido", no "autorizado por DGII".

## 15. Seguridad multiempresa

La mayoria de queries revisadas en ventas, productos, clientes, fiscal invoices y reportes usan `companyId`. Para NCF se requiere reforzar:

- todas las secuencias filtradas por `companyId`;
- indices unicos compuestos por empresa;
- emision y consulta nunca globales.

## 16. Tests anadidos

Backend:

- Sin impuestos.
- ITBIS agregado.
- ITBIS incluido.
- Exento.
- Factura mixta.
- Cantidad mayor que 1.
- Descuento.
- Descuento + incluido.
- Descuento + agregado.
- Redondeo RD$99.99.
- Multiples productos con centavos.
- B01 sin RNC falla.
- NCF duplicado por empresa falla en helper.
- Mismo NCF en empresas diferentes permitido por helper.
- Emision concurrente conceptual cubierta por estrategia pendiente.
- FULLTECH/CANATECH: total RD$25,700, base RD$21,779.66, ITBIS RD$3,920.34.

## 17. Pendientes

- Conectar motor fiscal a ventas reales.
- Migrar cotizaciones a semantica correcta de precio incluido/agregado.
- UI de configuracion fiscal por empresa.
- UI de tratamiento fiscal por producto.
- Motor equivalente en Flutter solo para previsualizacion.
- NCF transaccional real.
- PDF/tickets fiscales completos.
- Reportes fiscales.
- Devoluciones fiscales proporcionales.

## 18. Riesgos legales/fiscales que requieren revision externa

- Determinar si productos/servicios especificos estan gravados, exentos o sujetos a otra tasa.
- Validar reglas DGII aplicables a B01/B02/B14/B15 y e-CF.
- Confirmar requisitos de representacion impresa/PDF para comprobantes fiscales.
- Confirmar vigencia y autorizacion real de secuencias NCF.

## PHASE 2 IMPLEMENTATION STATUS

Fecha: 2026-08-18

Implementado:

- Configuracion fiscal por empresa integrada en backend y Flutter settings.
- Catalogo `Tax` por empresa con endpoints `/taxes` y configuracion fiscal `/company/fiscal-settings`.
- Inicializacion idempotente de ITBIS 18% solo al activar impuestos o consultar catalogo fiscal.
- Productos con `taxTreatment`, `taxRate` y `taxPriceMode` opcionales, manteniendo `INHERIT` por defecto.
- Ventas conectadas al motor fiscal backend cuando `taxEnabled = true`.
- Snapshots fiscales agregados en `Sale` y por linea en `SaleItem`.
- `POST /sales/calculate` para previsualizacion fiscal desde el mismo motor backend.
- Cliente fiscal opcional (`taxId`, `businessName`, `taxIdType`).
- PDF carta, PDF de venta y tickets muestran base/ITBIS/exento/descuento/NCF cuando existen.
- Reportes backend agregan `taxableBase`, `taxAmount`, `exemptAmount` y `discountAmount`.

Pendiente:

- UI completa de tratamiento fiscal en formularios de producto.
- UI POS con desglose fiscal previo en pantalla.
- Generacion/reserva NCF automatica y transaccional.
- Devoluciones fiscales proporcionales con documento/snapshot propio.
- Cotizaciones migradas totalmente a semantica incluido/agregado.
- Pruebas Flutter especificas de UI fiscal.
