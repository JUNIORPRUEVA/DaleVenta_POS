# Acceso al asistente e-CF por empresa (`ecf_portal_enrollments`)

Documento operativo del control de acceso al **asistente e-CF** (portal de
certificación). Sustituye, para el alta de clientes, a la lista de entorno
`ECF_PORTAL_PILOT_COMPANY_IDS`.

## 1. Problema que resuelve

Antes, la elegibilidad se decidía con una variable del despliegue:

```text
ECF_PORTAL_PILOT_COMPANY_IDS=<uuid-1>,<uuid-2>,...
```

Consecuencias:

- Cada cliente nuevo exigía **editar el entorno y reiniciar el servicio**: una
  tarea de infraestructura, no una decisión comercial.
- El valor no tenía autor, motivo ni fecha: no era auditable.
- Un error de formato (coma, espacio, UUID truncado) dejaba al cliente fuera sin
  explicación visible.

## 2. Cómo funciona ahora

La autorización es un **dato por empresa** en la tabla `ecf_portal_enrollments`:

| Columna | Uso |
| --- | --- |
| `company_id` | Empresa autorizada. FK a `companies` con `ON DELETE CASCADE`. |
| `source` | `ADMIN_AUTHORIZATION`, `CONTRACT_REFERENCE` o `AUTO_ELIGIBLE`. |
| `status` | `ACTIVE` o `REVOKED`. |
| `reason` | Motivo obligatorio. Sin motivo no hay autorización. |
| `contract_reference` | Referencia contractual, cuando existe. |
| `authorized_by_user_id` | Quién la concedió. |
| `expires_at` | Caducidad opcional. Pasada la fecha, deja de servir sola. |
| `revoked_at`, `revoked_by_user_id`, `revocation_reason` | Revocación auditada. |

Un **índice único parcial** garantiza una sola fila `ACTIVE` por empresa:

```sql
CREATE UNIQUE INDEX "ecf_portal_enrollments_active_company_key"
  ON "ecf_portal_enrollments"("company_id") WHERE "status" = 'ACTIVE';
```

Revocar **no borra**: marca `status='REVOKED'` y conserva el histórico, de modo
que siempre se puede reconstruir quién autorizó qué y cuándo.

## 3. Regla única de decisión

`apps/api/src/ecf/portal/ecf-portal-enrollment.policy.ts` contiene la regla, y es
la única copia. Orden de evaluación:

1. Fila `REVOKED` (o `status` distinto de `ACTIVE`) → **no elegible**
   (`AUTHORIZATION_REVOKED`).
2. Fila con `expires_at <= ahora` → **no elegible** (`AUTHORIZATION_EXPIRED`).
3. Fila `ACTIVE` vigente → **elegible** (`ENROLLED`).
4. Sin fila, pero la empresa figura en `ECF_PORTAL_PILOT_COMPANY_IDS` →
   **elegible** (`ENROLLED_LEGACY_ENV`, solo compatibilidad).
5. Nada de lo anterior → **no elegible** (`NO_AUTHORIZATION`).

Nótese que revocar y caducar **ganan** sobre la lista heredada: si un despliegue
conserva la variable antigua, una revocación sigue teniendo efecto.

## 4. Dónde se aplica

La misma decisión se usa en los cuatro puntos de entrada:

| Punto | Archivo |
| --- | --- |
| Portal (ticket y canje) | `portal/ecf-certification-portal.service.ts` |
| Sesión viva del portal | `portal/ecf-certification-portal.service.ts` (`readContext`) |
| Configuración de empresa (`ecfPilotEligible`) | `settings/settings.service.ts` |
| Rutas admin de transición/reconciliación | `provider/dosa/dosa-certification-intent.controller.ts` |
| Webhook DOSA (`portalEligible`) | `provider/dosa/dosa-company-resolver.service.ts` |

El resolutor del webhook calcula `portalEligible` en la **misma** consulta que
resuelve la empresa por RNC, sin una segunda ida a la base.

## 5. Alta de un cliente nuevo (procedimiento)

1. Crear la empresa y su configuración fiscal (RNC registrado) por el flujo
   normal de alta.
2. Registrar la postulación DOSA desde el backend (`POST /ecf/dosa/certification-intent`).
3. Autorizar el asistente:

```http
POST /ecf/platform/dosa/portal-enrollments/{companyId}/grant
Content-Type: application/json
Authorization: Bearer <token de personal de plataforma>

{
  "source": "ADMIN_AUTHORIZATION",
  "reason": "Alta comercial autorizada por dirección",
  "contractReference": "CTR-2026-001",
  "expiresAt": null
}
```

Requiere `PlatformStaffGuard` **y** una concesión de soporte vigente de esa
empresa (`EcfSupportGrantGuard`): ser personal de plataforma no basta.

4. Verificar:

```http
GET /ecf/platform/dosa/portal-enrollments/{companyId}
```

Devuelve `{ eligibility: { eligible: true, reason: "ENROLLED", ... }, history }`.

**No hace falta reiniciar nada**: la decisión se lee en cada llamada.

## 6. Revocar el acceso

```http
POST /ecf/platform/dosa/portal-enrollments/{companyId}/revoke
{ "reason": "Baja solicitada por el cliente" }
```

Efectos inmediatos: el portal deja de emitir boletos, las sesiones vivas dejan de
servir y el webhook deja de procesar eventos de esa empresa salvo que tenga el
e-CF emitiendo. El histórico permanece.

## 7. Inscripción automática (opcional, apagada por defecto)

```text
ECF_PORTAL_AUTO_ENROLL_ENABLED=false   # valor seguro por defecto
```

Con `true`, una empresa que cumpla **las tres** condiciones se autoriza sola con
`source='AUTO_ELIGIBLE'`:

1. `ecf_company_configurations.enabled = TRUE`;
2. `app_config.rnc` no vacío;
3. existe al menos una fila en `ecf_dosa_certification_sessions`.

La regla se evalúa al consultar la elegibilidad del portal y es *best-effort*: si
falla, no rompe la petición y el resultado sigue siendo cerrado.

## 8. Qué NO hace este mecanismo

- No emite comprobantes ni habilita la transmisión.
- No activa credenciales DOSA ni toca material cifrado.
- No cambia el estado de certificación.
- No contacta con DOSA.

## 9. Compatibilidad y retirada de la variable

`ECF_PORTAL_PILOT_COMPANY_IDS` sigue leyéndose **solo** como respaldo cuando la
empresa no tiene fila. Está declarada obsoleta: no se escribe desde la
aplicación y su contenido no otorga ningún permiso que una revocación no pueda
anular. Plan de retirada: cuando todas las empresas activas tengan fila, vaciar
la variable y eliminarla del despliegue.

## 10. Pruebas

| Archivo | Qué demuestra |
| --- | --- |
| `portal/ecf-portal-enrollment.policy.spec.ts` | Matriz completa de la decisión (vigente, caducada, revocada, heredada, ausente). |
| `portal/ecf-portal-enrollment.service.spec.ts` | Idempotencia, motivo obligatorio, historial, aislamiento, auto-inscripción apagada. |
| `portal/ecf-portal-enrollment-postgres.integration-spec.ts` | PostgreSQL real: índice único parcial, caducidad con reloj de la base, revocación con historial, dos empresas independientes, concurrencia. |
| `portal/ecf-certification-portal.service.spec.ts` | El portal emite boleto con la fila de la base y lo corta al revocar. |

Ejecución (base desechable autorizada `fullpos_ecf_ephemeral_test` en el puerto
56701):

```powershell
$env:ECF_POSTGRES_UAT = "true"
$env:DATABASE_URL = "postgresql://...@127.0.0.1:56701/fullpos_ecf_ephemeral_test"
$env:ALANUBE_ENABLE_REAL_CALLS = "false"
$env:ECF_EMISSION_ENABLED = "false"
npx jest --runInBand src/ecf
```
