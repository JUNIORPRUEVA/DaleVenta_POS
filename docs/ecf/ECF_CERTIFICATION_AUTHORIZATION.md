# Autorización de emisión e-CF por empresa

Documento operativo de la ruta administrativa que **autoriza a una empresa a
emitir** con DOSA.

Hasta esta entrega, el estado de certificación que exige el orquestador de
emisión (`AUTHORIZED_SANDBOX`, `PRODUCTION_READY`) **no lo escribía ninguna ruta
en ejecución**: `deriveCertificationStatus` solo produce `NOT_STARTED`,
`IN_PROGRESS`, `BLOCKED` y `READY_FOR_REVIEW`, porque mira la evidencia interna.
Promover a un cliente real obligaba a un `UPDATE` escrito a mano en la base: sin
autor, sin motivo y sin historial.

Esta ruta lo sustituye por una operación auditada.

> **La autorización normal ya NO pasa por aquí.** El cliente se autoriza solo
> completando su propia evidencia (credencial `ACTIVE` → estado derivado), sin
> intervención de nadie: ver `ECF_SELF_SERVICE_ACTIVATION.md`.
>
> Esta ruta queda para lo que sí es un acto humano: **retirar** una autorización,
> **suspender** una empresa con incidente fiscal o **corregir** un caso de soporte,
> siempre con motivo, actor y auditoría.

## 1. Qué hace y qué NO hace

**Hace:**

- Cambia `ecf_company_configurations.certification_status` aplicando una política
  de transiciones cerrada.
- Exige un motivo (8–500 caracteres) y registra actor, estado anterior, estado
  nuevo y referencia de evidencia en `ecf_audit_logs`.
- Es idempotente: repetir la misma autorización devuelve `changed: false` y no
  duplica la auditoría.

**NO hace:**

- No emite comprobantes ni llama a DOSA.
- No activa ni rota credenciales.
- No cambia `enabled`, `environment`, `productionEnabled`, `allowedTypes`.
- No toca banderas de entorno (`DOSA_EMISSION_ENABLED`,
  `DOSA_PRODUCTION_EMISSION_ENABLED`).

Autorizar deja a la empresa **en la compuerta de certificación**, no con el
interruptor de emisión. Para que un comprobante salga hacen falta además:
configuración `enabled`, proveedor `DOSA`, credenciales `ACTIVE` para el ambiente,
la compuerta fiscal del documento y la bandera global del entorno.

## 2. Rutas

Todas viven en `EcfPlatformController` (`/ecf/platform`) y pasan por
`AuthGuard("jwt")` → `PlatformStaffGuard` → `EcfSupportGrantGuard`.

| Método | Ruta | Alcance de la concesión | Efecto |
| --- | --- | --- | --- |
| `GET` | `/ecf/platform/dosa/certification/:companyId` | `VIEW_DOSSIER` | Estado, objetivos alcanzables e histórico. Solo lectura |
| `POST` | `/ecf/platform/dosa/certification/:companyId/authorize` | `REQUEST_CORRECTION` | Autoriza `AUTHORIZED_SANDBOX` o `PRODUCTION_READY` |
| `POST` | `/ecf/platform/dosa/certification/:companyId/revoke` | `REQUEST_CORRECTION` | Deja la empresa en `SUSPENDED` |

Cuerpo de `authorize`:

```json
{
  "target": "AUTHORIZED_SANDBOX",
  "reason": "Pruebas de emisión en ambiente de certificación",
  "evidenceReference": "DOSA-TEST-2026-001"
}
```

Cuerpo de `revoke`:

```json
{ "reason": "Incidente fiscal: se retira la autorización de emisión" }
```

`evidenceReference` es opcional y solo se guarda en la auditoría.

## 3. Transiciones permitidas

| Objetivo | Se concede desde |
| --- | --- |
| `AUTHORIZED_SANDBOX` | `NOT_STARTED`, `IN_PROGRESS`, `READY_FOR_REVIEW`, `SUSPENDED`, `AUTHORIZED_SANDBOX` (idempotente) |
| `PRODUCTION_READY` | `AUTHORIZED_SANDBOX`, `PRODUCTION_READY` (idempotente) |
| `SUSPENDED` (revocación) | `AUTHORIZED_SANDBOX`, `PRODUCTION_READY`, `SUSPENDED` (idempotente) |

Rechazos con su código HTTP:

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND` | 404 | La empresa no tiene configuración e-CF. No se crea: no ha empezado el trámite |
| `ECF_CERTIFICATION_SANDBOX_REQUIRED` | 409 | Se pide `PRODUCTION_READY` sin haber pasado por sandbox |
| `ECF_CERTIFICATION_DOWNGRADE_NOT_ALLOWED` | 409 | Se pide `AUTHORIZED_SANDBOX` a una empresa en `PRODUCTION_READY` |
| `ECF_CERTIFICATION_STATE_BLOCKED` | 409 | La empresa está en `BLOCKED`: hay evidencia vigente en contra |
| `ECF_CERTIFICATION_NOT_AUTHORIZED` | 409 | Se revoca algo que no estaba autorizado |
| `ECF_CERTIFICATION_TARGET_NOT_ALLOWED` | 400 | `target` fuera del catálogo |

### Por qué `BLOCKED` no se puede autorizar

`resolveCertificationStatus` aplica la regla «un bloqueo real aflora siempre».
Autorizar por encima de un bloqueo produciría un estado que la siguiente
actualización de una etapa revertiría a `BLOCKED`: una autorización que no dura.
Por eso se rechaza y se pide resolver el bloqueo primero.

### Por qué `SUSPENDED` no es un `NOT_STARTED`

`SUSPENDED` describe «se le retiró la autorización»; `NOT_STARTED`, «no ha
empezado». Además `SUSPENDED` es pegajoso: tocar una etapa de onboarding **no**
lo levanta. Levantarlo exige una autorización nueva por esta vía.

## 4. Auditoría

Cada cambio escribe una fila en `ecf_audit_logs`:

| Campo | Contenido |
| --- | --- |
| `action` | `CONFIG_UPDATED` |
| `targetType` | `ECF_CERTIFICATION_AUTHORIZATION` |
| `companyId` / `actorUserId` | Empresa y persona de plataforma que autorizó |
| `before` | `{ "certificationStatus": "<anterior>" }` |
| `after` | `{ "certificationStatus": "<nuevo>" }` |
| `metadata` | `operation`, `reason`, `evidenceReference`, `target` |

`operation` es `CERTIFICATION_STATUS_AUTHORIZED` o
`CERTIFICATION_STATUS_REVOKED`.

Se reutiliza `CONFIG_UPDATED` a propósito: el cambio **es** una actualización de
la configuración e-CF y distinguirlo por `targetType` y `metadata` evita una
migración de tipo en producción para añadir un valor al enum.

El histórico se consulta desde la propia ruta `GET`, que devuelve las últimas 20
operaciones (máximo 100).

## 5. Procedimiento operativo

Requisitos previos, en orden:

1. La empresa inicia el trámite e-CF: existe la fila en
   `ecf_company_configurations` (si no existe, la ruta responde 404).
2. La empresa **concede asistencia** a plataforma con alcance
   `REQUEST_CORRECTION` (`POST /ecf/dgii/support-grants`). Sin eso el staff
   recibe 403.
3. La persona que ejecuta la autorización está en el staff de plataforma
   (`PLATFORM_STAFF_ENV`).

Ejemplo (PowerShell):

```powershell
$token   = "<jwt del staff de plataforma>"
$company = "<uuid de la empresa>"

# 1) Ver el estado y qué se puede pedir
Invoke-RestMethod -Method Get `
  -Uri "https://<host>/ecf/platform/dosa/certification/$company" `
  -Headers @{ Authorization = "Bearer $token" }

# 2) Autorizar sandbox
Invoke-RestMethod -Method Post `
  -Uri "https://<host>/ecf/platform/dosa/certification/$company/authorize" `
  -Headers @{ Authorization = "Bearer $token" } `
  -ContentType "application/json" `
  -Body (@{
      target            = "AUTHORIZED_SANDBOX"
      reason            = "Pruebas de emisión en ambiente de certificación"
      evidenceReference = "DOSA-TEST-2026-001"
    } | ConvertTo-Json)
```

Después de autorizar, la empresa **sigue sin poder emitir** hasta que se cumplan
las condiciones del apartado 1. La comprobación final es una emisión: si
`DosaEmissionDispatchService` devuelve
`ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED:<estado>`, el estado no se aplicó
como se esperaba.

## 6. Verificación

Automatizada, sin proveedor real:

- `src/ecf/certification/ecf-certification-authorization.policy.spec.ts` — tabla
  completa de transiciones (24 casos).
- `src/ecf/platform/ecf-certification-auth-http.e2e-spec.ts` — 14 casos por HTTP
  real contra PostgreSQL desechable: 403 sin concesión, 403 para un administrador
  de empresa, transición aplicada y auditada, idempotencia, sandbox obligatorio,
  rebaja rechazada, `BLOCKED` rechazado, revocación y reactivación, 404 sin
  configuración, 400 de validación, aislamiento entre empresas, la autorización
  no enciende `enabled`, y una etapa de onboarding no degrada la autorización.

Comando:

```powershell
cd apps/api
$env:ECF_POSTGRES_UAT='true'
$env:ALANUBE_ENABLE_REAL_CALLS='false'
npx jest --runInBand src/ecf/platform/ecf-certification-auth-http.e2e-spec.ts
```
