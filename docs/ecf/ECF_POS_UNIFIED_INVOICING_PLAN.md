# Facturación unificada del POS sobre e-CF — decisión y plan

Fecha: 2026-11-08 · Estado: **decisión tomada, implementación pendiente**
Rama de trabajo: `agent/ecf-pos-unified-invoicing` (a crear desde `production-main`)

## 1. Decisión del propietario (HECHO)

Se sustituye el selector fiscal antiguo **B01/B02** por el sistema **E31/E32** dentro del
proceso de venta. Un solo flujo de facturación visible. B01/B02 se retiran de la
interfaz de venta **solo** para empresas que ya operan con e-CF; las empresas que aún
deban operar con NCF tradicionales conservan su flujo y **no se interrumpe** nada.

Dos modos por empresa:

| `allowSalesWithoutEcf` | Comportamiento del POS |
| --- | --- |
| `false` (por defecto) | El tipo se selecciona **automáticamente** (E31 o E32). Se muestra antes de cobrar y solo se corrige entre tipos permitidos. **«Normal» no existe** como opción |
| `true` | Aparecen **Normal**, E31 y E32. **Normal** viene preseleccionado en cada venta nueva. Exige **motivo** y registra la excepción |

Regla automática acordada: **cliente con RNC → E31**; **sin RNC → E32**; si el cliente
pide consumo teniendo RNC, se permite E32 entre los tipos habilitados. Si falta un dato
o no hay rango disponible, **se bloquea**; nunca se degrada a Normal en silencio.

## 2. Estado del código (HECHO, verificado)

- El POS ya tiene un selector fiscal: `modules/ventas/fiscal_voucher_options.dart`,
  con **B01** y **B02**, visible si `taxEnabled && ncfEnabled`, alimentado por
  `/ncf/sequences`.
- La e-CF vive **fuera** del POS: `EcfPrepareAction` en Mis Ventas.
- La preparación de **consumo (E32)** devuelve `encf: null`
  (`ecf-preparation.service.ts`): el e-NCF lo aporta solo el flujo de certificación.
- `EcfSequenceService` solo admite `E31` y `E34`; el patrón de e-NCF es `E(31|34)`.
- `DosaEmissionDispatchService` rechaza cualquier tipo distinto de E31/E34.

Conclusión: **no es un interruptor**, es integrar dos sistemas que hoy no se hablan.

## 3. Fases (cada una con sus pruebas y su commit)

### Fase 1 — Cerrar la numeración de E32 (condición previa)
- `E32` pasa a ser tipo asignable: `EcfSequenceService`, patrón `E(31|32|34)`, DTOs.
- La preparación de consumo **asigna el e-NCF del rango autorizado** y lo persiste, en
  lugar de dejar `null`.
- El despacho DOSA acepta E32 (la compuerta ya lo soporta).
- Pruebas: rango autorizado, agotamiento, idempotencia y **no duplicar** al reintentar.
- **No se habilita nada visible** hasta que esta fase esté verde.

### Fase 2 — Configuración por empresa
- `allowSalesWithoutEcf` en `ecf_company_configurations` (default `false`) con auditoría
  del cambio (`CONFIG_UPDATED` ya guarda antes/después).
- Validación **en backend**: una venta marcada «Normal» con la bandera apagada se
  rechaza con código propio. Sin degradación automática.
- Registro de excepciones: empresa, venta, usuario, fecha, motivo y tipo esperado.
- Ajustes → e-CF: interruptor **«Permitir ventas normales sin e-CF»** con el aviso rojo
  aprobado y confirmación explícita.

### Fase 3 — POS
- Selector compacto con el tipo preseleccionado; «Normal» solo si la bandera está activa.
- Integración de la preparación/emisión dentro del cierre de venta, reutilizando el motor
  DOSA, la numeración, la caja, los pagos y el inventario existentes.
- B01/B02 ocultos únicamente para empresas con e-CF activo.
- Pruebas: ambos modos, cambio de configuración en caliente, ventas consecutivas, dos
  empresas aisladas, y que un fallo de emisión **no** convierta la venta en Normal.

## 4. Reglas que no se relajan

- Nunca cambiar a Normal por un error de emisión: se bloquea o queda pendiente.
- E34 no se ofrece como factura de venta.
- Sin emisión duplicada: se reutiliza la idempotencia existente.
- Permisos, rangos e-NCF, estado de certificación y aislamiento multiempresa intactos.

## 5. Qué falta para arrancar

Nada de producto. Falta ejecutar la Fase 1 en una rama nueva, con sus pruebas, y no
tocar la interfaz hasta que la numeración E32 esté cerrada.
