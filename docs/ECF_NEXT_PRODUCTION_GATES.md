# e-CF — Próximas compuertas hacia producción

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.

Documento de compuertas: qué falta, quién lo desbloquea y qué **no** se puede
saltar. Extiende a [`ECF_INTEGRATION_FINAL_GATE.md`](ECF_INTEGRATION_FINAL_GATE.md).

---

## Estado actual por capacidad

| # | Capacidad | Estado | Evidencia |
| --- | --- | --- | --- |
| 1 | Preparación local E31/E32/E34 | **GO** | 696 pruebas de `src/ecf`, incluye E2E HTTP |
| 2 | Despacho contra Alanube **simulado** | **GO** | HTTP E2E del circuito completo + 7 casos de servicio |
| 3 | Persistencia y consulta (bandeja/detalle) | **GO** | E2E HTTP: preparar → despachar → persistir → consultar |
| 4 | Habilitación DGII por empresa (seguimiento) | **GO** (backend) | 30 pruebas nuevas |
| 5 | Interfaz Flutter de habilitación DGII | **GO** (corregido 2026-10-18) | `lib/features/ecf/ui/ecf_dgii_habilitation_page.dart` (59.5 KB), integrada en el módulo e-CF |
| 6 | Emisión real a Alanube | **NO-GO** | `PRODUCTION_EMISSION_IMPLEMENTED = false` |
| 7 | Certificación DGII | **NO-GO** | Sin autorización oficial verificada |
| 8 | Despliegue a producción | **NO-GO** | Producción es de solo lectura por defecto |

## Compuertas que bloquean producción

### G1 — Autorización oficial de la DGII (externa, no técnica)

Ninguna acción administrativa en FullPOS puede aprobar a una empresa. `APPROVED`
exige: fuente `DGII_OFFICIAL_RECORD` + evidencia documental + fecha + identificador
externo. Sin eso, la empresa permanece en revisión y la puerta de emisión lo dice.

**Quién lo desbloquea:** el contribuyente y la DGII.
**Qué NO se puede hacer:** marcar la empresa como aprobada «para probar».

### G2 — Emisión real implementada

`PRODUCTION_EMISSION_IMPLEMENTED = false` es la única fuente de verdad y no depende
de configuración. Mientras sea `false`, `realEmissionAuthorized` es `false` siempre.

**Quién lo desbloquea:** una tarea explícita que implemente el transporte real, con
autorización previa y protocolo de alto riesgo (auth, numeración fiscal, secuencia).

### G3 — Discrepancia de esquema GET de Alanube

Ver [`ECF_ALANUBE_SCHEMA_DISCREPANCY_REPORT.md`](ECF_ALANUBE_SCHEMA_DISCREPANCY_REPORT.md).
Tres campos (`stampDate`, `signatureDate`, `trackId`) no coinciden con el contrato
oficial publicado.

**Quién lo desbloquea:** Alanube.
**Qué NO se puede hacer:** normalizar firma y trazabilidad sin confirmación.

### G4 — Contrato comercial / Reseller

La propuesta firmada de Alanube **no está en el repositorio**. Es un documento de
negocio, no técnico.

### G5 — Deriva de esquema preexistente

`prisma migrate diff` revela diferencias entre `schema.prisma` y las migraciones
aplicadas, ajenas a este trabajo (renombrado de índices, `DROP DEFAULT`, índice
único de `telemetry_outbox`). Requiere una tarea propia de reconciliación.

## Secuencia de numeración fiscal (restricción permanente)

La secuencia `E320009805001` **ya está consumida** en sandbox y no se reutiliza.
Cualquier prueba real futura debe partir de un número nuevo dentro del rango
autorizado (`9805001–9806000`, expira `2028-12-31`).

## Protocolo antes de cualquier llamada real

1. Autorización explícita en la tarea **actual** (no heredada de una tarea previa).
2. Preflight con switches de transporte real en `false` y verificación de destino.
3. Un solo envío, sin reintento automático.
4. Cualquier resultado no correlacionado ⇒ `HUMAN_REVIEW_REQUIRED`, nunca aceptado.
5. Ningún HTTP 2xx se interpreta como aceptación de la DGII.
