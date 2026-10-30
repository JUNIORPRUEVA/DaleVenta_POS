# e-CF — Plan de activación gradual (no ejecutado)

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.

Este documento es un **plan**. Nada de lo que describe se ha ejecutado ni se
ejecutará sin autorización explícita: no hay despliegue, ni emisión, ni consumo de
numeración real, ni llamadas al proveedor.

---

## 1. Controles que ya existen (base del plan)

| Control | Estado | Dónde |
| --- | --- | --- |
| Interruptor por empresa | IMPLEMENTADO | `EcfCompanyConfiguration.enabled`; sin él todo e-CF responde `ECF_COMPANY_DISABLED` |
| Control de ambiente | IMPLEMENTADO | `environment` debe ser `SANDBOX`; `productionEnabled` bloquea (`ECF_PRODUCTION_BLOCKED`) |
| Tipos permitidos por empresa | IMPLEMENTADO | `allowedTypes`; un tipo no habilitado se rechaza |
| Ausencia de ruta de emisión | IMPLEMENTADO | Ningún controlador cablea `dispatchOnce`; `emissionPathAvailable: false` |
| Kill switch | IMPLEMENTADO | `ecf-kill-switch.policy` |
| Pre-guarda de emisión | IMPLEMENTADO | `ecf-pre-emission.guard` |
| Prevención de doble envío | IMPLEMENTADO | Reclamo del intento **antes** de la red (`SEND_IN_PROGRESS` + `UNKNOWN_RESULT`) |
| Idempotencia | IMPLEMENTADO | Clave por operación; un reintento reutiliza documento y e-NCF |
| Numeración que no retrocede | IMPLEMENTADO | Índice único parcial + trigger `ecf_sequence_identity_immutable` |
| Recuperación tras reinicio | IMPLEMENTADO | `recordUnknownOutcome` + `recoverClaimed` |
| Reconciliación | IMPLEMENTADO | `alanube-reconciliation.service`, `e32-reconciliation-executor` |
| Resolución de credenciales | IMPLEMENTADO | `ecf-secret-resolver` (referencias, no secretos en claro) |
| Auditoría | IMPLEMENTADO | `EcfAuditLog`, `EcfElectronicDocumentStatusLog`, `EcfElectronicDocumentAttempt` |
| Inmutabilidad fiscal | IMPLEMENTADO | Triggers `E34_FISCAL_SNAPSHOT_IMMUTABLE`, `ECF_FISCAL_DOCUMENT_IMMUTABLE` |
| Migraciones aditivas | IMPLEMENTADO | Ninguna migración reescribe filas existentes |
| Rollback de aplicación | IMPLEMENTADO | Niveles 1–4 documentados en `ECF_FLUTTER_Y_OPERACION.md` §8 |

## 2. Fases de activación

Ninguna se ejecuta automáticamente. Cada una exige autorización explícita en su
momento y un GO/NO-GO previo.

| # | Entorno | Entrada | Criterio de salida |
| --- | --- | --- | --- |
| 1 | **Local** | Ya alcanzado | Suites completas + E2E vertical en verde |
| 2 | **UAT aislado** | Base desechable + empresas sintéticas | Estado actual: **alcanzado** |
| 3 | **Sandbox autorizado** | Credenciales del proveedor + ventana autorizada | Un único cupo de E32 consumido con autorización humana y observación registrada |
| 4 | **Certificación** | Ejecución y firma humanas (DGII) | Casos de certificación aprobados por la DGII |
| 5 | **Piloto controlado** | 1 empresa real voluntaria, tipo E31 | Un ciclo completo observado sin incidentes fiscales |
| 6 | **Activación por empresa** | `enabled=true` caso por caso | Cada empresa con su rango y su responsable |
| 7 | **Expansión progresiva** | Por lotes pequeños | Sin regresiones en 2 lotes consecutivos |

## 3. Condiciones que **deben** cumplirse antes de la fase 3

1. Contrato **E32 `PARTIAL_OFFICIAL`** confirmado por el proveedor.
2. Mecanismo de **firma del webhook** documentado y verificado.
3. Credenciales de sandbox resueltas por referencia (nunca en claro).
4. `ALANUBE_ENABLE_REAL_CALLS` habilitado **solo** dentro de la ventana
   autorizada y con el operador presente.
5. Matriz de compatibilidad de cliente real **cerrada** (hoy tiene filas
   abiertas: ver `ECF_E2E_COMPATIBILITY_REPORT.md` §4).
6. Procedimiento supervisado para los documentos con `fiscal_document = NULL`
   (no se reconstruyen automáticamente desde información mutable; **nada de
   backfill especulativo**).

## 4. Interruptores de emergencia

| Nivel | Acción | Efecto | Reversión |
| --- | --- | --- | --- |
| 1 | `enabled=false` en la empresa | Deja de preparar; los comprobantes se conservan | Volver a `true` |
| 2 | Kill switch | Bloquea el despacho manteniendo la consulta de estado | Desactivar |
| 3 | Desactivar el transporte real | Ninguna llamada puede salir | Reactivar |
| 4 | Revertir la aplicación | Se vuelve a la versión previa | Reinstalar |

**Nunca se borran** comprobantes, evidencias, reservas ni secuencias: son el
registro fiscal. Un número consumido permanece consumido.

## 5. Qué queda fuera de este plan

- Emitir cualquier comprobante con efectos fiscales reales.
- Consumir el cupo único de sandbox de E32.
- Certificar ante la DGII.
- Desplegar en producción.
