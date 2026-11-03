# e-CF E31 — Matriz de estado técnico (factura con valor fiscal)

> **Este documento no certifica nada.** No existe homologación de la DGII ni de
> Alanube en este repositorio. «Validado en local» es una prueba ejecutada por el
> equipo; «simulado» es el circuito interno sin proveedor; «sandbox» es una
> llamada real al entorno de pruebas del proveedor. Ninguna de las tres es
> certificación.

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Última revisión de
este documento: **2026-10-18**.

## Leyenda

| Marca | Significado |
| --- | --- |
| **TEST** | Cubierto por prueba automatizada ejecutada |
| **SIM** | Cubierto con transporte simulado (sin proveedor) |
| **CONTRATO** | Contraste con el contrato publicado del proveedor |
| **SANDBOX** | Ejecutado contra el entorno de pruebas real del proveedor |
| **PROVEEDOR** | Pendiente de respuesta escrita del proveedor |
| **DGII** | Pendiente de la DGII / del contribuyente |
| **NO IMPL.** | No implementado (por diseño o por bloqueo) |

## Requisitos del comprobante

| # | Requisito | Evidencia | Estado |
| --- | --- | --- | --- |
| 1 | Identidad del emisor (nombre, RNC, dirección, contacto) | Snapshot `issuer_*` en `Sale`; `ecf-sale-fiscal.adapter.ts` | **TEST** |
| 2 | Datos del receptor (nombre y RNC/cédula) | `fiscalCustomerName`, `fiscalCustomerTaxId`; validación de cliente en venta B01 | **TEST** |
| 3 | Validación de RNC/cédula | `ecf-validator` | **TEST** |
| 4 | e-NCF y numeración | `ecf_sequences` + auditoría; **nunca** numeración real | **TEST** (local), **SIM** |
| 5 | Líneas de producto y servicio | `SaleItem.itemTypeSnapshot` + clasificación supervisada F1 | **TEST** |
| 6 | ITBIS | `ecf-money.ts`, `ROUND_HALF_UP` a 2 decimales | **TEST** |
| 7 | Montos exentos | `exempt_amount` en `Sale`/`SaleItem` | **TEST** |
| 8 | Descuentos por línea y globales | `line_discount_amount`, `discount_amount` | **TEST** |
| 9 | Totales y conciliación | Tolerancia documentada de 1 céntimo (enteros de céntimos) | **TEST** |
| 10 | Snapshot fiscal inmutable | `fiscalSnapshot` solo con evidencia; permanece `null` en simulación | **TEST** / **NO IMPL.** (real) |
| 11 | Máquina de estados | `ecf-document-state-machine.matrix.spec.ts` (20/20) | **TEST** |
| 12 | Idempotencia | `requestFingerprint` + detección de reintento divergente | **TEST** |
| 13 | Reintentos | Un reintento divergente **no** reutiliza el comprobante anterior | **TEST** |
| 14 | Inmutabilidad | Triggers `ecf_*` (append-only) + pruebas PostgreSQL | **TEST** |
| 15 | Multiempresa | `companyId` del contexto autenticado; FKs compuestas | **TEST** |
| 16 | RBAC | Permisos por cadena; 401/403 por HTTP | **TEST** |

## Suites que lo respaldan

| Suite | Alcance |
| --- | --- |
| `ecf-e31-emission-postgres.integration-spec.ts` | Emisión E31 completa: válido → `HUMAN_REVIEW_REQUIRED`, rechazo → revisión humana, sin liberar secuencia |
| `ecf-documents-http.e2e-spec.ts` | Preparación por HTTP real |
| `ecf-fiscal-core.spec.ts`, `ecf-money.spec.ts` | Aritmética fiscal |
| `ecf-document-state-machine.matrix.spec.ts` | Transiciones válidas e inválidas |
| `ecf-line-classification-*.spec.ts` (30) | Clasificación supervisada que desbloquea partidas sin producto |

## Contraste con el contrato del proveedor

| Aspecto | Estado |
| --- | --- |
| Estructura del `POST /invoices` | **CONTRATO** — cubierta por el simulador y las pruebas de contrato local |
| Lectura `GET /invoices/{id}` | **PROVEEDOR** — discrepancia en `stampDate`, `signatureDate`, `trackId` (ver `ECF_ALANUBE_SCHEMA_DISCREPANCY_REPORT.md`) |
| Significado de `ACCEPTED` | **PROVEEDOR** — no se interpreta como aceptación de la DGII |

## Sandbox y certificación

| Hito | Estado | Motivo |
| --- | --- | --- |
| Envío E31 real a sandbox | **NO EJECUTADO** | Requiere autorización explícita y una tarea de alto riesgo |
| Aceptación de la DGII | **DGII** | Sin registro oficial verificado |
| Certificación | **DGII** | No obtenida |

## Conclusión

**E31 está preparado técnicamente en local y simulación.** No hay ninguna
evidencia de aceptación fiscal real. Cualquier afirmación de «E31 certificado»
sería falsa con la evidencia actual.
