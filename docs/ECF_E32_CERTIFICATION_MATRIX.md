# e-CF E32 — Matriz de estado técnico (consumo electrónico)

> **Este documento no certifica nada.** Ver la leyenda de
> `ECF_E31_CERTIFICATION_MATRIX.md`.

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Última revisión:
**2026-10-18**.

## Leyenda

**TEST** prueba ejecutada · **SIM** transporte simulado · **CONTRATO** contraste
con el contrato publicado · **SANDBOX** llamada real al entorno de pruebas ·
**PROVEEDOR** pendiente del proveedor · **DGII** pendiente de la DGII ·
**NO IMPL.** no implementado.

## Requisitos del comprobante

| # | Requisito | Evidencia | Estado |
| --- | --- | --- | --- |
| 1 | Reglas específicas de consumo | `ecf-e32-consumo-postgres.integration-spec.ts` | **TEST** |
| 2 | Identidad del consumidor cuando corresponda | Snapshot de receptor; opcional según regla de consumo | **TEST** |
| 3 | Totales e ITBIS | Motor fiscal compartido con E31 | **TEST** |
| 4 | Numeración | Secuencia local; **nunca** e-NCF real en automático | **TEST** (local), **SIM** |
| 5 | Máquina de estados | Matriz de estados (20/20) | **TEST** |
| 6 | Preparación local | `POST /ecf/documents/prepare` con `documentType: "E32"` | **TEST** |
| 7 | Separación simulación / emisión real | `PRODUCTION_EMISSION_IMPLEMENTED = false`; el despacho solo existe contra el simulador | **TEST** |
| 8 | Ensayo de secuencia (trial) | `ecf-e32-trial-postgres.integration-spec.ts` + `ecf_sandbox_e32_trials` | **TEST** |
| 9 | Evaluación de la respuesta del proveedor | `e32-response-assessment.spec.ts` | **TEST** |
| 10 | Compatibilidad DOM E32 | `alanube-dom-e32-compatibility.spec.ts` | **CONTRATO** |
| 11 | Concurrencia del despacho | 2 y 5 despachos simultáneos → 1 ganador, 1 envío, 1 recibo | **TEST** |

## Suites que lo respaldan

| Suite | Alcance |
| --- | --- |
| `ecf-e32-consumo-postgres.integration-spec.ts` | Consumo completo contra PostgreSQL real |
| `ecf-e32-trial-postgres.integration-spec.ts` | Ensayo de secuencia con aislamiento |
| `e32-sandbox.spec.ts` | Reglas de entorno de pruebas |
| `e32-response-assessment.spec.ts` | Cómo se interpreta una respuesta (nunca como aceptación fiscal) |
| `alanube-dom-e32-compatibility.spec.ts` | Correspondencia con el contrato DOM |
| `ecf-alanube-simulated-end-to-end` | Despacho simulado correlacionado de extremo a extremo |

## Evidencia histórica de sandbox (NO reproducida en esta revisión)

| Dato | Valor |
| --- | --- |
| Artefacto | `artifacts/e32-first-trial/` |
| Resultado | POST real aceptado por el proveedor |
| Secuencia | `E320009805001` **consumida** — no se reutiliza |
| Rango autorizado | `9805001–9806001`, expira `2028-12-31` |
| Lectura posterior (`GET`) | HTTP 200, pero **el esquema oficial no coincide** (`OFFICIAL_GET_SCHEMA: false`) |
| `canUpdateFiscalStatus` | `false` |
| `sufficientForProviderReview` | `false` |

**Lectura correcta:** el proveedor recibió el documento; eso **no** es aceptación
de la DGII y la respuesta no permite actualizar el estado fiscal.

## Bloqueos abiertos

| # | Bloqueo | Quién lo resuelve |
| --- | --- | --- |
| 1 | Contrato `PARTIAL_OFFICIAL` del E32 sin confirmar por escrito | **Alanube** |
| 2 | Discrepancia de esquema en la lectura (`stampDate`, `signatureDate`, `trackId`) | **Alanube** |
| 3 | Mecanismo de firma del webhook de estado | **Alanube** |
| 4 | Certificación y autorización de emisión | **DGII** |

## Conclusión

**E32 está preparado en local y simulación, con un ensayo de sandbox histórico
consumido y no reutilizable.** La emisión real sigue sin ruta: no hay camino a
`DGII_ACCEPTED`.
