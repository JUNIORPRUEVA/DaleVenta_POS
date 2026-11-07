# Backend DOSA multiempresa — cierre de la integración

Fase 2 sobre la rama `agent/dosa-credentials-split-20261107`. Sin despliegue, sin
migraciones reales, sin emisión.

## 1. RNC dinámico (se elimina la dependencia global)

**Antes:** `verifyFiscalIdentity` comparaba el emisor de una emisión TEST con
`DOSA_TEST_RNC`, una variable global. Con dos clientes, el valor solo podía servir
a uno: cualquier empresa nueva exigía editar el entorno.

**Ahora:** el RNC esperado en TEST es **el de la empresa que emite**
(`input.rnc`, ya acotado al tenant de la petición). `DOSA_TEST_RNC` deja de
intervenir en la compuerta; queda solo para la sonda de laboratorio
`dosa-test-emission.probe`.

Consecuencias:

- Alta de un cliente nuevo sin tocar variables de entorno ni código.
- Sigue impidiéndose lo que importaba: una emisión de prueba que declare un RNC
  distinto del de la empresa cuyas credenciales se están usando.
- La clave se resuelve por `(company_id, rnc, environment)`: TEST usa solo la fila
  `test` y PRODUCCIÓN solo la `production`. No hay sustitución entre ambientes.

## 2. Webhooks duplicados

**Antes:** la identidad del evento era `sha256(postulacion_id|estado|disponibles_desde)`.
Un envío legítimo con el mismo identificador pero **credenciales nuevas** se
descartaba como `duplicate` y las claves se perdían en silencio.

**Ahora:** la identidad incluye el `sha256` del **cuerpo exacto**
(`…|rawBodySha256`). Es un hash del cuerpo: no expone valores y no es reversible.

| Situación | Comportamiento |
| --- | --- |
| Reintento idéntico (mismo cuerpo) | `duplicate: true`, sin efectos |
| Mismo identificador lógico, cuerpo distinto | Evento **nuevo**, se procesa |
| Mismo identificador con credenciales distintas de una clave ACTIVA/CONFIRMADA | Se registra el evento con `processing_state = CONFLICT_PENDING_REVIEW` y **no se toca** la credencial |
| Llegada concurrente | `INSERT … ON CONFLICT DO NOTHING` + índice único: una sola fila |
| Error temporal del proveedor | Sigue respondiendo 5xx para que reintente; el evento queda en `PENDING_CREDENTIALS` y el reenvío lo reanuda |

La firma HMAC, la tolerancia temporal y el cuerpo crudo no cambian.

## 3. Rotación y protección de credenciales

- **Una credencial `CONFIRMED`/`ACTIVE` nunca se sustituye por un webhook.** La
  rotación es un acto humano: bajar la fila a `PENDING_CONFIRMATION`, aplicar y
  reactivar.
- **Nunca se degrada un estado ya alcanzado** (`CASE WHEN status IN ('CONFIRMED','ACTIVE')`).
- **No se reescribe si el `fingerprint` no cambió** (`WHERE … IS DISTINCT FROM`),
  y `created_at` no se toca.
- **Un evento incompleto no borra nada**: cada ambiente solo se escribe si trae su
  clave identificadora.
- **El `apiSecret` ya no se duplica entre ambientes**: se guarda en una sola fila
  (la que declare el evento). Compartirlo entre entornos es una decisión de
  contrato del proveedor que aún no está validada.

## 4. Validación de la empresa destinataria

`PrismaDosaCompanyResolver` resuelve por `ecf_dosa_certification_sessions` y
**rechaza la ambigüedad**: si un RNC aparece en más de una empresa devuelve `null`
→ `404 UNKNOWN_RNC`, sin escribir nada. No se elige "la primera". Verificado en
pruebas con una sesión duplicada entre dos empresas.

## 5. Compatibilidad con FULLTECH

Nada de lo anterior toca los datos de producción. La certificación y las
credenciales ya guardadas siguen donde estaban (una fila `production` con
`apiKeyProduccion` y `apiKeyTest`). La herramienta de reclasificación
(`npm run dosa:credentials:reclassify`) **no se ha ejecutado**: sigue disponible en
modo dry-run y requiere `DOSA_CREDENTIALS_RECLASSIFY=CONFIRM` para escribir.

## 6. Pruebas ejecutadas

```
npx tsc -p tsconfig.build.json --noEmit            → exit 0
npx jest src/ecf/provider/dosa                     → 30 suites · 565 passed
npm test (suite completa del API)                  → 210 suites · 2487 passed · 0 failed
```

Con PostgreSQL desechable (`postgres:17` en contenedor, base `dosa_uat`):

```
npx prisma migrate deploy                          → All migrations applied
dosa-credential-postgres + dosa-webhook-postgres   → 2 suites · 14 passed
dosa-multi-company-postgres (nuevo)                → 8 passed
```

Casos del nuevo E2E multiempresa: A recibe sus dos ambientes y B/C quedan intactas ·
reintento idéntico → `duplicate` · mismo identificador con cuerpo distinto → evento
nuevo · rotación sobre clave activa → `CONFLICT_PENDING_REVIEW` sin cambiar la
credencial · RNC sin sesión → 404 · RNC repetido entre dos empresas → 404 · ninguna
empresa ve credenciales de otra · tres entregas concurrentes → una sola fila.

## 7. Riesgos pendientes

| Riesgo | Detalle |
| --- | --- |
| Sin histórico de versiones de credenciales | La fila anterior se conserva porque **no se sobrescribe** cuando está activa, pero no hay tabla de versiones. Requiere migración y autorización. |
| La `dedupe_key` cambia de semántica | Solo afecta a eventos futuros; las filas existentes no se tocan ni hay que recalcular nada. |
| Fallos preexistentes de otras suites | `dosa-sale-to-json-postgres`, `dosa-phase-f-postgres`, `dosa-intent-http-postgres` y los `*.e2e-spec` fallan en un entorno sin datos de siembra (`E2E_REFUSES_REAL_PROVIDER_CALLS`). Reproducido en la rama base `f46c0ab1`: **no lo causa este cambio**. |
| `DOSA_TEST_RNC` sigue en el entorno de UAT local | Ya no participa en la compuerta; puede retirarse cuando se quiera. |

## 8. Despliegue (para aprobación)

1. Revisión del diff y de esta nota.
2. Desplegar **solo** `daleventapos_backend`, con las banderas intactas
   (`DOSA_EMISSION_ENABLED=false`, `DOSA_PRODUCTION_EMISSION_ENABLED=false`,
   `DOSA_WEBHOOK_ENABLED=true`).
3. Verificar con un `SELECT` que las filas de FULLTECH no cambiaron.
4. Cuando se autorice: dry-run y luego `--apply` de la reclasificación para mover
   la clave TEST a su fila.

## 9. Migración y reversión

- **No hay migración de esquema.** Se reutilizan columnas existentes; el nuevo
  estado `CONFLICT_PENDING_REVIEW` cabe en `processing_state` (varchar).
- **Reversión:** `git revert` del commit y redesplegar. Los datos siguen siendo
  válidos en ambos sentidos: no se renombró ni se borró ninguna columna, y los
  eventos con la `dedupe_key` nueva conviven con los antiguos.
- Si se ejecutó la reclasificación y hay que deshacerla: marcar la fila `test`
  como `REVOKED` (nunca borrar), para conservar la auditoría.
