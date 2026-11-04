# Reconciliación excepcional DOSA con revisión interna

Documento de la excepción administrativa que permite corregir la atribución de un
intento DOSA **sin exigir una confirmación externa inexistente** y sin fabricar
evidencia.

Estado: **implementado y probado, desactivado por defecto**. No autoriza
desplegar, reconciliar, emitir e-CF ni presentar nada ante la DGII.

## 1. Problema que resuelve

El intento de FULLTECH SRL (`attempt_no = 1`, `NOT_STARTED`) quedó registrado por
el servicio local DOSA pero con la etiqueta histórica `ALANUBE`, heredada de
`ecf_company_configurations.provider`. La compuerta del portal exige que el
proveedor efectivo sea `DOSA`.

El mecanismo anterior exigía `externalReviewReference`, una cadena que el sistema
**no puede verificar**: cualquier texto servía. Es decir, el control no impedía
fabricar una confirmación externa, solo la dejaba implícita.

La excepción invierte esa situación: obliga a **declarar** que la revisión fue
interna y a firmar la evidencia que la sustenta.

## 2. Dos clases de revisión, mutuamente excluyentes

| | `EXTERNAL` (por defecto) | `INTERNAL` (excepción) |
| --- | --- | --- |
| Referencia | `externalReviewReference`: acto del proveedor | `internalReviewReference`: artefacto interno |
| Verificable por el software | No | **Sí**, mediante `internalEvidenceDigest` |
| Bandera maestra | `ECF_DOSA_INTENT_RECONCILIATION_ENABLED=true` | la anterior **y** `ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED=true` |
| Consecuencia | Atribución apoyada en el proveedor | Atribución corregida administrativamente, declarada como tal |

Enviar las dos referencias a la vez se rechaza con
`DOSA_INTENT_REVIEW_REFERENCES_CONFLICT`: no se puede disfrazar una revisión
interna de confirmación externa. La aprobación del propietario
(`ownerApprovalReference`) es obligatoria en ambas.

## 3. Evidencia interna que se firma

El `evidenceSnapshot` se construye **en el servidor, dentro de la transacción
Serializable**, y el cliente no puede aportarlo ni aportar el digest:

- identidad del intento: `id`, `companyId`, `rnc`, `attemptNo`, `status`, `createdAt`, `createdByUserId`;
- ausencia de referencias de proveedor (`provider_postulation_id`, `session_url`, `last_event_type`, `provider_confirmed_at`, `closed_at`);
- auditoría original: total, id, actor, proveedor, `created`, RNC y `attemptNo`;
- actividad externa: intentos heredados del proveedor, webhooks, tickets y sesiones de portal.

`internalEvidenceDigest = SHA-256(stableStringify(snapshot))`, con serialización de
claves ordenadas para que el mismo snapshot dé siempre el mismo digest.

**Qué demuestra:** integridad y reproducibilidad. Cualquier alteración del
snapshot o del digest se detecta.
**Qué NO demuestra:** ausencia absoluta de actividad en el sistema del proveedor.

`effectiveIntentProvider` **no** acepta un hash por su formato: vuelve a verificar
toda la consistencia del snapshot antes de conceder `DOSA`.

## 4. Condiciones que deben cumplirse

1. Rol `ADMIN`/`ADMINISTRADOR` con permiso `manageEcfOnboarding`.
2. Empresa en la lista del piloto (`ECF_PORTAL_PILOT_COMPANY_IDS`).
3. Intento **exacto**: el último de la empresa, `attempt_no = 1`, `NOT_STARTED`, sin
   referencias de proveedor y sin cierre.
4. Auditoría: **una sola** fila `ONBOARDING_STARTED` con `created = true`, RNC y
   `attemptNo` coincidentes, y actor igual al creador del intento.
5. Cero actividad externa: sin intentos heredados del proveedor, sin webhooks, sin
   tickets ni sesiones de portal posteriores a la creación.
6. `ownerApprovalReference` (≥8) y `reason` (≥20) no vacíos.
7. Índice único parcial: **una sola** reconciliación por intención, para siempre.

Todo se evalúa en una transacción `Serializable`, de modo que una escritura
concurrente (por ejemplo, un webhook) provoca el aborto de una de las dos partes:
la comprobación falla cerrada.

## 5. Qué se conserva intacto

- La auditoría original `ONBOARDING_STARTED` con `provider: "ALANUBE"` **no se modifica**.
  La reconciliación es una fila nueva con `before: {provider: "ALANUBE"}` y
  `after: {provider: "DOSA"}`.
- `historicalIntentProvider` sigue devolviendo `ALANUBE`.
- La emisión fiscal permanece cerrada: la respuesta siempre incluye
  `fiscalAuthorizationGranted: false` y esta ruta nunca toca
  `ecf_company_configurations`, credenciales ni secuencias.
- El aislamiento multiempresa: la empresa sale del token y el intento se busca por
  `companyId`; un identificador de otra empresa no existe para esta consulta.

## 6. Diagnóstico

`GET /ecf/dosa/certification-diagnostic` incorpora:

- `reconciliationKind`: `EXTERNAL`, `INTERNAL`, `UNVERIFIED` o `null`.
- `attributionConflict`: `true` si existe una reconciliación **y** además hay datos
  del proveedor en el intento. Es una señal para revisión humana: el sistema
  **no** cambia la atribución automáticamente ante un evento tardío.

La interfaz debe mostrar «atribución corregida por revisión interna» y no
insinuar una confirmación del proveedor.

## 7. Activación y desactivación

Activación (requiere autorización separada del propietario, nunca incluida en un
despliegue):

```
ECF_DOSA_INTENT_RECONCILIATION_ENABLED=true
ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED=true
```

Desactivación: poner cualquiera de las dos en `false` (o eliminarlas) y reiniciar
el servicio. Efecto inmediato:

- con la bandera interna apagada, la variante `INTERNAL` responde
  `DOSA_INTENT_RECONCILIATION_INTERNAL_DISABLED` y la `EXTERNAL` sigue disponible;
- con la maestra apagada, ninguna reconciliación es posible;
- las reconciliaciones **ya escritas** no se borran ni se revierten: son auditoría.
  Si se necesitara revertir una atribución, es una decisión administrativa nueva,
  no un cambio de fila.

Procedimiento seguro recomendado: desactivar ambas banderas, verificar el
diagnóstico y decidir con el registro de auditoría delante. No se edita ninguna
fila de `ecf_audit_logs`.

## 8. Riesgos residuales

1. **Confianza en el atestado.** El digest prueba reproducibilidad, no sinceridad.
   La responsabilidad queda en quien firma la aprobación y en la inmutabilidad de
   la auditoría.
2. **Evento tardío del proveedor.** Tras la reconciliación, un evento real puede
   aparecer; el sistema lo señalará con `attributionConflict` y no cambiará nada
   por sí solo.
3. **Uso único.** El índice parcial impide una segunda reconciliación del mismo
   intento, incluida una posterior con evidencia externa.
4. **Superficie nueva** en una ruta sensible: exige revisión de código y CI antes
   de cualquier activación.
5. **Límite epistémico**: describe el estado local verificable, no el del proveedor.

## 9. Pruebas

- `apps/api/src/ecf/provider/dosa/dosa-internal-reconciliation.spec.ts` — camino
  favorable, banderas, rechazos, idempotencia, aislamiento, auditoría intacta,
  emisión cerrada y señal de conflicto.
- `apps/api/src/ecf/provider/dosa/dosa-internal-review-evidence.spec.ts` —
  serialización determinista, digest reproducible y cada invariante del snapshot.
