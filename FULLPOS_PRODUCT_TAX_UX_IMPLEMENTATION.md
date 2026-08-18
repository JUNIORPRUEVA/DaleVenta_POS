# FullPOS Product Tax UX Implementation

Fecha: 2026-08-18

## Alcance Implementado

- Editor de productos de Inventario/Catálogo con sección fiscal visible solo cuando `company.taxEnabled` está activo.
- Controles fiscales:
  - Tratamiento: `Predeterminado`, `Gravado`, `Exento`.
  - Selector de impuesto basado en `/taxes` y limitado a impuestos activos de la empresa autenticada.
  - Modo de precio: configuración de empresa, ITBIS incluido o ITBIS agregado.
- Preview centralizado en `ProductTaxPreviewCalculator`:
  - `1180` incluido al 18% => base `1000`, ITBIS `180`, final `1180`.
  - `1000` + ITBIS 18% => base `1000`, ITBIS `180`, final `1180`.
  - Exento => ITBIS `0`, final igual al precio.
- Persistencia de `taxTreatment`, `taxRate` y `taxPriceMode` en create/update, incluyendo cola offline.
- Badges fiscales compactos en catálogo desktop/mobile cuando ITBIS está activo.
- POS PC/móvil muestra y cobra el total fiscal local: base, exento, ITBIS y total.
- Backend valida que productos `TAXABLE` usen una tasa activa existente en `taxes` para el `companyId` autenticado.
- Ganancia/margen queda documentado en `FULLPOS_TAX_PROFIT_MARGIN_DECISION.md`.

## Multiempresa

El frontend carga configuración fiscal desde providers dependientes de la sesión (`authStateProvider`) y del scope de empresa. El backend aplica siempre `requireTenant(user)` y consulta `tax.findFirst({ companyId, isActive: true, rate })`.

Nota técnica: el modelo `Product` no tiene `taxId`; guarda `taxRate`. Por eso el blindaje posible y aplicado es validar que la tasa exista activa en la empresa actual. Si en el futuro se agrega `Product.taxId`, debe migrarse la validación a `id + companyId`.

## Matriz

| Área | Estado |
| --- | --- |
| Form PC producto | OK |
| Form móvil producto | OK |
| Preview sin duplicar fórmula | OK |
| Catálogo badges | OK |
| Persistencia create/update/offline | OK |
| Backend multiempresa por impuesto | OK según modelo actual (`taxRate`) |
| POS totales | OK para preview/cobro local y backend |
| Ganancia/margen fiscal | PARTIAL: fórmula legado documentada, sin cambio masivo |

## Validación

- `flutter analyze`: PASS
- `flutter test`: PASS, 108 tests
- `npm test`: PASS, 30 tests
- `npm run build`: PASS
