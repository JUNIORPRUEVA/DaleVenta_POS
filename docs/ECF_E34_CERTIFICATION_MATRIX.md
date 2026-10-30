# e-CF E34 — Matriz de estado técnico (nota de crédito electrónica)

> **Este documento no certifica nada.** Ver la leyenda de
> `ECF_E31_CERTIFICATION_MATRIX.md`.

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Última revisión:
**2026-10-18**.

E34 es la modalidad con **mayor cobertura de pruebas** del módulo: 28 pruebas de
integración sobre PostgreSQL real, incluidas condiciones de carrera.

## Requisitos del comprobante

| # | Requisito | Evidencia | Estado |
| --- | --- | --- | --- |
| 1 | Referencia al comprobante original | Documento original + saldo consultable | **TEST** |
| 2 | Nota total | Consumo íntegro del saldo | **TEST** |
| 3 | Nota parcial | Consumo de una parte, saldo restante correcto | **TEST** |
| 4 | Monto máximo (no exceder el saldo) | `E34_BALANCE_INTEGRITY_VIOLATION` | **TEST** |
| 5 | Saldo nunca negativo | Restricción en base + aplicación | **TEST** |
| 6 | Concurrencia: dos reservas incompatibles en paralelo | **Una sola gana** | **TEST** |
| 7 | Concurrencia: 8 réplicas idénticas en paralelo | **Una** reserva y **un** evento | **TEST** |
| 8 | Concurrencia a nivel de base (inserciones directas) | Una sola pasa; el límite lo impone PostgreSQL | **TEST** |
| 9 | Doble solicitud idéntica | Idempotente, sin duplicar | **TEST** |
| 10 | Numeración independiente de la nota | Secuencia propia | **TEST** (local), **SIM** |
| 11 | Inmutabilidad | Triggers `ecf_credit_reservation_events` (append-only) | **TEST** |
| 12 | Motivo obligatorio | Validado en DTO y en política | **TEST** |
| 13 | Auditoría de cada decisión | `ecf_audit_logs` con actor y fecha | **TEST** |
| 14 | Resultado desconocido **retiene** el dinero | `UNKNOWN_RESULT` no libera ni cancela solo | **TEST** |
| 15 | Rechazo libera **solo** con evidencia coincidente | Verificado | **TEST** |
| 16 | Multiempresa | Una empresa no puede operar sobre notas de otra | **TEST** |

## Suites que lo respaldan

| Suite | Alcance |
| --- | --- |
| `ecf-e34-postgres.integration-spec.ts` | 28 casos, incluidas carreras reales e inserciones concurrentes directas |
| `ecf-documents-http.e2e-spec.ts` | Preparación de la nota por HTTP |
| Interfaz Flutter (`ecf_credit_note_action.dart`) | Selección del original, nota parcial, motivo obligatorio, bloqueo de exceso |

## Contraste con el contrato del proveedor

| Aspecto | Estado |
| --- | --- |
| Estructura de la nota (referencia al original y montos) | **CONTRATO** (simulador y pruebas locales) |
| Lectura de la nota en el proveedor | **PROVEEDOR** — misma discrepancia de esquema que E31 |

## Sandbox y certificación

| Hito | Estado | Motivo |
| --- | --- | --- |
| Envío E34 real a sandbox | **NO EJECUTADO** | Requiere autorización explícita |
| Aceptación DGII de una nota | **DGII** | Sin registro oficial verificado |

## Riesgo específico documentado

Las tablas append-only del módulo (`ecf_evidence_receipts`,
`ecf_credit_reservation_events`, `ecf_line_classifications`) tienen triggers sin
vía de `DELETE` y FK en cascada desde `companies`. Consecuencia: **el borrado de
una empresa con datos fiscales falla a nivel de base**. No se ha introducido
ningún bypass. Ver `ECF_COMPANY_DELETION_RETENTION_DESIGN.md`.

## Conclusión

**E34 es la modalidad mejor respaldada técnicamente**: integridad de saldo,
concurrencia real en base de datos e inmutabilidad están probadas. Sigue sin
haber emisión real ni certificación.
