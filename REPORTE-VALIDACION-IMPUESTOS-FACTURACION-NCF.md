# REPORTE — VALIDACIÓN FINAL: IMPUESTOS / FACTURACIÓN / NCF

**Proyecto:** DaleVentas POS / FullPOS Cloud
**Fecha:** 2026-08-22
**HEAD:** `359ef560` (origin/main)
**Modo:** SOLO VALIDACIÓN — sin cambios, sin commit, sin push, sin deploy.

---

## RESUMEN

```
IMPUESTOS OFF:           PASS
IMPUESTOS ON + NCF ON:   PASS
DRAFT FISCAL ANTIGUO:    PASS
MULTIEMPRESA:            PASS
PAYLOAD CON IMPUESTOS OFF:  fiscalVoucherType = null
¿PUEDE CONSUMIR NCF CON IMPUESTOS OFF?:  NO
BACKEND SOURCE OF TRUTH NCF:  SÍ
FLUTTER ANALYZE:         PASS
TESTS:                   160/160 Flutter fiscales + 41/41 backend fiscales
FALLOS PREEXISTENTES:    1 (quote_pdf_viewer_share_action_test.dart — ajeno, documentado)
RIESGO:                  BAJO
LISTO PARA COMMIT:       La corrección fiscal YA está commiteada (HEAD).
                         Los cambios sin commit son de OTRO workstream (reportes) — NO se tocan.
```

---

## LA CORRECCIÓN (código actual, HEAD)

### Vínculo: Configuración empresa → Utilizar impuestos → Facturación → Fiscal → NCF

| Archivo | Lógica |
|---|---|
| `fiscal_voucher_options.dart` | `shouldShowFiscalVoucherControl = taxEnabled && ncfEnabled`; `fiscalVoucherOptionsFromConfiguredTypes` → `[]` si el flujo está OFF; `shouldResetFiscalVoucherSelection` limpia selección obsoleta |
| `registrar_venta_screen.dart` (POS) | Control fiscal solo si `taxEnabled && ncfEnabled`; NCF sequences solo si se muestra el control; selección obsoleta se resetea; payload `fiscalVoucherType: _selectedFiscalVoucherType` |
| `cotizaciones_screen.dart` | `_fiscalFlowEnabled` (desde `companySettingsProvider`, scoped por empresa); `_effectiveFiscalVoucherType` → `''` si el flujo está OFF; al restaurar draft limpia B01 obsoleto; payload `fiscalVoucherType: voucherType.isEmpty ? null : voucherType` |
| Backend `sales.service.ts` | `requestedVoucherType = fiscalVoucherType?.trim() ? normalize : null`; bloquea si `requestedVoucherType && !ncfEnabled`; **reserva NCF solo si `requestedVoucherType` es truthy**; `fiscalVoucherType: requestedVoucherType` |

---

## ESCENARIOS

### ESCENARIO 1 — IMPUESTOS OFF ✅ PASS
- `taxEnabled = false` → `shouldShowFiscalVoucherControl` = false → NO control fiscal, NO B01/B02, NO NCF.
- `fiscalVoucherOptions` = `[]`; cualquier selección previa se resetea (`shouldResetFiscalVoucherSelection`).
- Payload de cobro: `fiscalVoucherType: null`.
- Backend: `requestedVoucherType = null` → **no reserva NCF** (`reservedNcf = null`). Venta tratada como Normal.
- Defensa extra backend: si un cliente forzara un `fiscalVoucherType` con `ncfEnabled=false` → `BadRequestException("Los comprobantes fiscales no están activados...")`.

### ESCENARIO 2 — IMPUESTOS ON + NCF ON ✅ PASS
- Control fiscal visible con los tipos configurados y activos (`sequence.active && remaining > 0`).
- B01 exige RNC/Cédula + nombre (validación Flutter y backend).
- NCF asignado server-side (incremento atómico transaccional). Sin regresión: tests de `ventas_fiscal_payload`, `fiscal_voucher_options`, PDF fiscal, tickets → PASS.

### ESCENARIO 3 — DRAFT ANTIGUO (B01) + IMPUESTOS OFF ✅ PASS
- `_fiscalVoucherType = _fiscalFlowEnabled ? draft.fiscalVoucherType.toUpperCase() : ''`
- → draft B01 obsoleto se **limpia** → ticket queda Normal.
- Al cobrar: `fiscalVoucherType = null` → **0 NCF consumidos** (backend no reserva).

### ESCENARIO 4 — MULTIEMPRESA (A fiscal / B normal) ✅ PASS
- `cotizaciones_screen._handleCompanyChanged`: resetea editor (`_resetEditorState` → `_fiscalVoucherType = ''`, `_fiscalCustomerTaxId = ''`) e invalida `productTaxUiConfigProvider`, `catalogControllerProvider`, `cotizacionesRepositoryProvider`, `ventasControllerProvider`.
- Caché de drafts scoped por `company:<companyId>` → A y B nunca comparten drafts.
- `_fiscalFlowEnabled` se re-evalúa con la configuración de la empresa actual → B no hereda Fiscal/B01/NCF de A; A recupera la suya al volver.
- POS (`registrar_venta_screen._handleCompanyChanged`): resetea `_selectedFiscalVoucherType = null` e invalida providers.

---

## BACKEND — SOURCE OF TRUTH NCF ✅

`sales.service.ts` (verificado en el código):
```
requestedVoucherType = dto.fiscalVoucherType?.trim() ? normalizeType(...) : null
if (requestedVoucherType && !fiscalSettings.ncfEnabled) → BadRequestException   ← bloqueo
reservedNcf = requestedVoucherType ? await ncf.reserveNextNcf(...) : null        ← solo reserva si hay tipo
fiscalVoucherType: requestedVoucherType                                          ← null cuando no fiscal
```
Tests backend: `sales.service.tenant`, `sales.service.ncf-expiration`, `sales.service.fiscal-final`, `ncf.service.tenant`, `tax-calculation` → **41/41 PASS**.

---

## PAYLOAD CON IMPUESTOS OFF

```
fiscalVoucherType = null
ncf = null
¿PUEDE CONSUMIR NCF CON IMPUESTOS OFF?  NO
    (Flutter envía null; backend además bloquea si ncfEnabled=false)
```

---

## TESTS

```
FLUTTER ANALYZE:   PASS (No issues found)

FLUTTER (fiscal/ventas/cotizaciones/NCF/taxes/PDF/tickets):
   160/160 PASS
   - fiscal_voucher_options, ventas_fiscal_payload, ventas_recent_sales_repository
   - ncf_sequence_model, contabilidad_ncf_repository
   - catalog_tax_persistence, pdf_fiscal_templates
   - cotizacion_tax_snapshot, cotizacion_pdf_service, cotizacion_pdf_pagination_structure
   - cotizaciones_fiscal_layout, billing_product_tax_live_sync
   - product_tax_preview_calculator, product_tax_options_provider
   - ticket_data_fiscal_routes, ticket_builder_pdf, ticket_data
   - cash_close_ticket_printer_route

BACKEND (ventas/fiscal/NCF):
   41/41 PASS
```

---

## FALLOS PREEXISTENTES (documentado, NO arreglado)

```
quote_pdf_viewer_share_action_test.dart → FAIL (1)
    Espera un elemento 'Compartir con cliente' en el visor PDF de cotizaciones
    que el código actual no renderiza. NO relacionado con la corrección fiscal
    (impuestos→NCF). Es un test de otro workstream; NO se arregló en esta tarea,
    conforme a lo indicado.
```

---

## DIFF / ARCHIVOS

```
CAMBIO FISCAL ACTUAL (ya en HEAD, commiteado):
    - lib/modules/ventas/fiscal_voucher_options.dart
    - lib/modules/ventas/registrar_venta_screen.dart
    - lib/modules/cotizaciones/cotizaciones_screen.dart
    - apps/api/src/sales/sales.service.ts

CAMBIOS SIN COMMIT (NO relacionados con fiscal — workstream de REPORTES):
    - lib/features/reports/ui/reports_page.dart   (M) — debounce recarga realtime
    - lib/modules/ventas/data/ventas_repository.dart (M) — cast de tipos
    - test/modules/ventas/reports_models_test.dart (untracked)
    - AUDITORIA-MODULO-REPORTES.md (untracked)
    - REPORTE-REBUILD-REDEPLOY-BACKEND.md (untracked)

NO se mezclan: el commit de la corrección fiscal es independiente de los cambios
de reportes pendientes.
```

---

## CONCLUSIÓN

```
RIESGO: BAJO
LISTO PARA COMMIT: SÍ (la corrección fiscal ya está en HEAD y validada)
   - Los cambios pendientes de reportes pertenecen a otro workstream; decidir por separado.

Validación realizada por análisis de código + tests (160 Flutter + 41 backend).
No se ejecutó una validación en vivo multiempresa con dos sesiones reales
(requiere credenciales/dispositivo); la lógica y los tests lo cubren.
```

---

## DETENERSE

Validación completada. Sin cambios, sin commit, sin push, sin deploy.
El test ajeno `quote_pdf_viewer_share_action_test.dart` queda documentado como preexistente.
