# DOSA — checklist de la primera postulación real de FULLTECH SRL

Estado: **PREPARADO, NO EJECUTADO**. Este documento no autoriza por sí solo la
postulación, el despliegue, la emisión ni la modificación de producción.

## Identidad que se va a certificar

| Dato | Valor |
| --- | --- |
| Empresa | FULLTECH, SRL |
| `companyId` | `165e3fca-6225-479b-8805-d2205f10536c` |
| RNC real | `133080206` |
| RNC TEST de DOSA | `133306001` |
| Intento existente | Intento 1 reconciliado |
| Proveedor objetivo | DOSA |

**Regla:** `133306001` es una identidad de prueba y **no** se usará para
FULLTECH SRL. La primera conexión real de FULLTECH usa `133080206`.

## Antes de pedir autorización

- [ ] Confirmar que el entorno elegido es el oficial autorizado, no la base UAT
      local ni una base desechable.
- [ ] Confirmar que `ECF_PORTAL_PILOT_COMPANY_IDS` incluye exactamente
      `165e3fca-6225-479b-8805-d2205f10536c`.
- [ ] Confirmar que el deploy tiene la URL pública del webhook
      `/api/webhook/dosa` y que DOSA/el panel apuntan a esa URL.
- [ ] Confirmar que `DOSA_WEBHOOK_ENABLED`, `DOSA_WEBHOOK_SIGNATURE_STRATEGY` y
      el secreto están configurados según el contrato del 4 de noviembre.
- [ ] Confirmar la unidad de `t` y el encoding del secreto con un evento de
      prueba; si no, no activar el webhook.
- [ ] Confirmar que `sk_` es la clave de sesiones vigente de FULLTECH y está
      cargada solo en el backend del entorno oficial.
- [ ] Confirmar que la API Key TEST `133306001` no se usará para FULLTECH.
- [ ] Confirmar que la API Key de producción solo se configurará después de la
      certificación oficial.
- [ ] Confirmar que el certificado digital y el representante legal están
      preparados para cargarse **dentro de DOSA**.
- [ ] Confirmar que la emisión permanece apagada:
      `DOSA_EMISSION_ENABLED=false`, `DOSA_PRODUCTION_EMISSION_ENABLED=false`,
      `ECF_EMISSION_ENABLED=false`.
- [ ] Obtener autorización escrita del propietario, con ventana, responsable y
      referencia de aprobación.

## Protección del Intento 1

Antes de abrir cualquier sesión oficial, ejecutar solo lecturas:

```sql
SELECT id, attempt_no, status, created_at, closed_at,
       session_url IS NOT NULL AS tiene_url,
       provider_postulation_id
  FROM ecf_dosa_certification_sessions
 WHERE company_id = '165e3fca-6225-479b-8805-d2205f10536c'
 ORDER BY attempt_no DESC, created_at DESC;

SELECT action, created_at, actor_user_id
  FROM ecf_audit_logs
 WHERE company_id = '165e3fca-6225-479b-8805-d2205f10536c'
   AND action::text IN ('INTENT_PROVIDER_RECONCILED',
                        'INTENT_HISTORICAL_TRANSITION_AUTHORIZED')
 ORDER BY created_at;
```

Condiciones:

- [ ] El Intento 1 conserva `attempt_no=1`, su estado y sus fechas.
- [ ] No se borra ni reescribe la auditoría de reconciliación.
- [ ] No se crea un segundo intento por conveniencia.
- [ ] Si el expediente sigue bloqueado, no se fuerza la apertura: se usa el
      procedimiento auditado de transición histórica y una autorización de 24 h.
- [ ] La autorización, si se usa, solo crea auditoría; no muta la fila ni activa
      emisión.

## Secuencia de la primera postulación

1. Confirmar identidad y leer el estado de la empresa y del Intento 1.
2. Abrir **una sola vez** `POST /ecf/dosa/certification-session` con la sesión
   autenticada de FULLTECH.
3. Verificar en la respuesta:
   - `companyId` es `165e3fca-6225-479b-8805-d2205f10536c`;
   - `attemptNo=1`;
   - `providerPostulationId` presente;
   - la URL de sesión no se registra en logs ni capturas.
4. Abrir la URL de sesión en el navegador oficial.
5. El cliente carga certificado y contraseña **solo dentro de DOSA**. FullPOS no
   los pide, no los guarda y no los muestra.
6. Verificar en DOSA que el RNC mostrado es `133080206`, no `133306001`.
7. Confirmar que se reutiliza el Intento 1 y que no aparece una segunda
   postulación.
8. No reintentar ante timeout, 5xx o resultado incierto. Reconciliar por
   `provider_postulation_id` con DOSA.
9. Recibir el webhook autenticado de finalización; comprobar firma,
   `postulacion_id` y que las credenciales queden `PENDING_CONFIRMATION`.
10. Verificar que el certificado, el RNC y la API Key de emisión serán la misma
    identidad antes de activar cualquier emisión.
11. Esperar la habilitación oficial de DGII y la autorización administrativa
    auditada. Un `cert:complete` o un webhook **no** equivalen a certificación.
12. Mantener emisión apagada hasta completar la evidencia y la autorización
    separada.

## Evidencia que se debe guardar

- [ ] `companyId`, RNC `133080206` y nombre de empresa.
- [ ] Estado del Intento 1 antes y después.
- [ ] Auditoría `INTENT_PROVIDER_RECONCILED` y, si aplica, la autorización.
- [ ] `attemptNo`, `providerPostulationId` y fechas de la sesión.
- [ ] Comprobante de que no se creó un segundo intento.
- [ ] Confirmación de que FullPOS no solicitó PFX ni contraseña.
- [ ] Evento de webhook autenticado y resultado de la correlación.
- [ ] Estado de la credencial: `PENDING_CONFIRMATION`, nunca `ACTIVE` por el
      webhook.
- [ ] Registro oficial DGII y autorización administrativa antes de activar.
- [ ] Captura de las banderas de emisión en `false`.

No guardar: `sk_`, API Keys, `DATABASE_URL`, `JWT_SECRET`, URLs de sesión,
tokens, cookies ni contenido del certificado.

## Bloqueos reales para autorizar esta postulación

1. Confirmar que `sk_` está activa y es de sesiones de FULLTECH.
2. Corregir/confirmar la URL pública del webhook en DOSA: `/api/webhook/dosa`.
3. Fijar unidad de `t` y encoding del secreto con un evento firmado.
4. Confirmar que el entorno oficial tiene la migración y el enum `EcfProvider`
   con `DOSA`.
5. Tener el certificado y el representante legal listos para DOSA.
6. Obtener autorización escrita y ventana para el Intento 1.
7. Completar la habilitación oficial DGII y la autorización administrativa.
8. No activar emisión hasta la fase posterior y con la API Key de producción.

## Criterio de éxito

- FULLTECH SRL queda vinculada a su RNC `133080206`.
- El Intento 1 conserva su historial y no se duplica.
- El certificado se carga solo en DOSA.
- El webhook se autentica y correlaciona con el mismo `postulacion_id`.
- La certificación oficial queda registrada con evidencia.
- La emisión no se activa en esta fase.
