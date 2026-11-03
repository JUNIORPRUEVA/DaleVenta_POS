# e-CF — Módulo de habilitación DGII por empresa

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.

Complementa a [`ECF_DGII_COMPANY_ONBOARDING.md`](ECF_DGII_COMPANY_ONBOARDING.md).
Aquel documento cubre el **onboarding por pasos** (`EcfOnboardingStep`) y su
consumo en Flutter. Este cubre el **registro de habilitación por empresa** y la
**puerta de emisión**.

---

## 1. El problema de producto que resuelve

Tener el módulo e-CF activado (`enabled`) **no** significa estar autorizado a
emitir. Antes de este módulo, esa distinción existía en el código pero no tenía
un lugar donde vivir:

| Plano | Antes | Ahora |
| --- | --- | --- |
| A. `enabled` (módulo activo) | `ecf_company_configurations.enabled` | igual |
| B. Estado de habilitación DGII de la empresa | **no existía** como registro propio | `ecf_dgii_habilitations` |
| C. Autorización oficial verificada | no modelada | `authorization_source` + evidencia + `authorized_at` |
| D. Emisión real autorizada | `canEmit: false` fijo | puerta evaluada, **siempre `false`** (ver §5) |

## 2. Modelo de datos (migración aditiva)

`apps/api/prisma/migrations/20261016120000_ecf_dgii_company_habilitation/migration.sql`

Nuevos objetos:

- `EcfDgiiHabilitation` → tabla `ecf_dgii_habilitations`, **única por empresa**
  (`company_id` UNIQUE). Campos: `state`, `review_state`, `requirements`, `external_id`,
  `observations`, `responsible_user_id`, `started_at`, `authorized_at`,
  `authorization_source`, `authorization_evidence_id`, `created_by_user_id`,
  `updated_by_user_id`, marcas de tiempo.
- `EcfDgiiHabilitationState` (9 estados), `EcfDgiiVerificationSource` (4 fuentes),
  `EcfEvidenceSource` (3 procedencias).
- `EcfEvidence.source` (columna nueva, `NOT NULL DEFAULT 'MANUAL_DECLARATION'`).
- 4 valores nuevos en `EcfAuditAction` para la auditoría de este módulo.

La migración se generó con `prisma migrate diff` y se **recortó** al alcance del
módulo: el diff incluía además **deriva preexistente** no relacionada (renombrado
de índices de `ecf_electronic_document_*`, `DROP DEFAULT` de columnas UUID e índice
único de `telemetry_outbox.dedupe_key`). Esa deriva **no** se corrigió aquí; queda
documentada como pendiente y ajena a esta tarea.

## 3. Controladores y permisos

Todos bajo `AuthGuard("jwt")` + `RolesGuard`, y siempre acotados a la empresa del
contexto (`requireTenant`):

| Método | Ruta | Permiso |
| --- | --- | --- |
| GET | `/ecf/dgii/habilitation` | `viewEcfOnboarding` |
| PATCH | `/ecf/dgii/habilitation` | `manageEcfOnboarding` |
| GET | `/ecf/dgii/history` | `viewEcfOnboarding` |
| GET | `/ecf/dgii/evidence` | `viewEcfOnboarding` |
| POST | `/ecf/dgii/evidence` | `manageEcfOnboarding` |
| POST | `/ecf/dgii/authorization` | `manageEcfOnboarding` |
| POST | `/ecf/dgii/authorization/revoke` | `manageEcfOnboarding` |

Se **reutilizan** los permisos de onboarding ya existentes en lugar de introducir
un catálogo nuevo: evita divergencia entre backend y la app (que ya los conoce) y
mantiene el menor cambio posible.

## 4. Reglas duras (fail-closed)

1. **Una acción administrativa no aprueba.** `state = APPROVED` solo es admisible
   si ya existe una autorización oficial registrada; si no,
   `409 ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD`.
2. **Solo una fuente oficial autoriza.** `hasOfficialAuthorization` exige las cinco
   condiciones a la vez: `APPROVED` + `DGII_OFFICIAL_RECORD` + evidencia + fecha +
   identificador externo. Una `MANUAL_OPERATOR_DECLARATION` o
   `PROVIDER_CONFIRMATION` se guarda como metadato y **no** produce `authorized_at`.
3. **Transiciones cerradas.** Solo se aceptan las transiciones declaradas en
   `ECF_DGII_ALLOWED_TRANSITIONS`; lo demás es `409 ECF_DGII_TRANSITION_NOT_ALLOWED`.
4. **Concurrencia optimista.** Toda escritura compara `updatedAt`; si otro proceso
   escribió antes, `409` en vez de sobrescribir en silencio.
5. **Evidencia ajena, imposible.** Al vincular evidencia se verifica que pertenezca
   a la misma empresa; si no, `404`.
6. **Evidencia ≠ aprobación.** Registrar evidencia no mueve el estado.
7. **Datos internos fuera de la vista.** `storageRef` no se devuelve al cliente: es
   una referencia interna.

## 5. Puerta de emisión

`evaluateEcfEmissionGate()` es pura y fail-closed. Devuelve **siempre** la lista de
bloqueos (para que la interfaz explique qué falta) y estos tres campos:

```ts
{ realEmissionAuthorized: false,
  simulatedDispatchAuthorized: boolean,
  productionEmissionImplemented: false }
```

- `productionEmissionImplemented` está fijado por la constante
  `PRODUCTION_EMISSION_IMPLEMENTED = false`, que es la **única** fuente de verdad
  de que la emisión real no está implementada. Ninguna combinación de estados,
  permisos ni configuración puede poner `realEmissionAuthorized` en `true`.
- `simulatedDispatchAuthorized` es `true` solo con módulo activo **y** entorno UAT
  local: el simulador no contacta al proveedor ni consume numeración.

Códigos de bloqueo emitidos: `ECF_MODULE_DISABLED`,
`ECF_FISCAL_CONFIGURATION_INVALID` (RNC ausente en `appConfig.rnc`),
`ECF_LICENSE_NOT_ALLOWED`, `ECF_DGII_REQUIREMENTS_PENDING`,
`ECF_DGII_OFFICIAL_AUTHORIZATION_MISSING`, `ECF_PRODUCTION_NOT_ENABLED`,
`ECF_CERTIFICATION_NOT_PRODUCTION_READY`, `ECF_REAL_EMISSION_NOT_IMPLEMENTED`,
`ECF_ENVIRONMENT_NOT_LOCAL_UAT`.

## 6. Requisitos

`ECF_DGII_REQUIREMENT_CATALOG` deriva 14 requisitos de las etapas canónicas ya
existentes (`EcfOnboardingStepKey`). Cada uno marca `mandatory` y `automatable`.
`automatable: false` señala los trámites externos que **no** se pueden automatizar
sin evidencia oficial. El catálogo es una vista informativa del proceso: **no**
sustituye ninguna resolución oficial, y así se declara en la respuesta
(`isInternalTrackingOnly: true`).

## 7. Pruebas

```
pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "ecf-dgii-habilitation"
  → 2 suites, 30 pruebas, 30 PASS

  Policy (18): autorización oficial (5 condiciones), declaración manual no autoriza,
    transiciones permitidas/prohibidas/desconocidas, terminales, anti-falsificación,
    registro de autorización, progreso de requisitos, puerta de emisión.

  Integración PostgreSQL (12): creación sin autorización, aislamiento entre dos
    empresas (estado, evidencias e historial), anti-falsificación, declaración
    manual, fuente oficial incompleta, evidencia ajena, aprobación oficial con
    emisión real aún bloqueada, revocación, procedencia de evidencia, progreso real,
    historial + persistencia tras reconectar, transición inválida y carrera.
```

## 8. Lo que este módulo NO hace

- **No** contacta a la DGII ni a Alanube.
- **No** habilita emisión real: la puerta devuelve `false` por diseño.
- **No** almacena certificados, claves privadas ni credenciales: solo referencias.
- **No** convierte el seguimiento interno en un estado oficial.
- **No aprueba nada automáticamente**: ni la interfaz ni la API pueden declarar una
  empresa aprobada sin un registro oficial verificado.

## 9. Interfaz Flutter

Pantalla **Facturación electrónica → Habilitación DGII**
(`lib/features/ecf/ui/ecf_dgii_habilitation_page.dart`), alcanzable desde dos sitios:

- `Facturación electrónica` (`/ecf`) → icono *Habilitación DGII* en la barra superior.
- `Configuración e-CF` (`/ecf/config`) → *Abrir habilitación DGII*.

Ruta propia: `/ecf/dgii`. El Drawer general **no** se modificó y no se duplicó ninguna opción.

| Sección | Contenido |
| --- | --- |
| Aviso de distinción | Autorización oficial presente o ausente, con los motivos concretos |
| Seguimiento interno | Estado, revisión, fechas, observaciones y bloqueos |
| Autorización para emitir | Emisión real (bloqueada), despacho simulado y si está implementada |
| Requisitos y progreso | Barra, porcentaje y los 14 requisitos con obligatorio/externo |
| Datos fiscales registrados | Razón social, RNC, dirección, representante, integración, certificación |
| Evidencias y fuente | Evidencias con su procedencia y las acciones de registro |
| Historial | Cambios registrados |

Decisiones de la interfaz:

1. **Nunca ofrece aprobar.** `allowedNextStates` excluye `APPROVED` en todos los estados; el
   diálogo de avance solo lista lo que el backend admite.
2. **Permisos**: las acciones de escritura exigen `manageEcfConfig`. Sin él la pantalla es de
   solo lectura, y hay una prueba que lo verifica.
3. **Sin selector de empresa**: el ámbito lo impone el backend desde la sesión; la aplicación
   nunca envía `companyId` y la pantalla no proyecta el identificador.
4. **Responsive**: en pantallas estrechas la etiqueta pasa encima del valor en lugar de
   reservar una columna fija de 180 px.
5. **Fallo visible**: si la consulta falla se muestra una tarjeta de error con *Reintentar*,
   que además no deja el fallo asíncrono sin manejar.

Pruebas: `test/features/ecf/ecf_dgii_habilitation_repository_test.dart` (13 casos) y
`test/features/ecf/ecf_dgii_habilitation_page_test.dart` (18) — 31 en total.

---

## Revisión de evidencias y seguimiento por requisito

### Revisión interna (dimensión separada del origen)

El **origen** de una evidencia («quién la entregó») y su **revisión** («si alguien la miró»)
son dos hechos distintos y se almacenan en campos distintos:

| Origen (`ecf_evidence_source`) | Revisión (`ecf_evidence_review_status`) | Nivel presentado |
| --- | --- | --- |
| `MANUAL_DECLARATION` | `PENDING` | `DECLARED_BY_COMPANY` |
| `MANUAL_DECLARATION` | `REVIEWED` | `INTERNALLY_REVIEWED` |
| `PROVIDER_ARTIFACT` | cualquiera | `PROVIDER_ISSUED` |
| `OFFICIAL_DOCUMENT` | `PENDING` | `OFFICIAL_DOCUMENT_PENDING_REVIEW` |
| `OFFICIAL_DOCUMENT` | `REVIEWED` | `OFFICIAL_DOCUMENT_REVIEWED` |

Regla verificada: **ninguna evidencia concede autorización** por sí sola
(`evidenceGrantsOfficialAuthorization()` siempre devuelve `false`), y solo un documento
oficial **ya revisado** puede sustentarla (`evidenceSupportsOfficialAuthorization`).

Refuerzo del registro oficial: al registrar `source: DGII_OFFICIAL_RECORD` el backend exige
que la evidencia vinculada sea `OFFICIAL_DOCUMENT` **y** esté `REVIEWED`. Si no, responde
`ECF_DGII_AUTHORIZATION_REQUIRES_OFFICIAL_EVIDENCE` o
`ECF_DGII_AUTHORIZATION_REQUIRES_REVIEWED_EVIDENCE`. Es un **endurecimiento respecto del
contrato anterior** (antes bastaba con referenciar cualquier evidencia propia); se aplicó
porque el módulo no está en producción y ninguna empresa externa depende del comportamiento
previo.

### Seguimiento por requisito

`PATCH /ecf/dgii/requirements/:key` guarda `status`, `note`, `responsibleUserId` y `dueDate`
dentro de `EcfDgiiHabilitation.requirements`. Es una **libreta de trabajo**: no modifica el
progreso real, que sigue derivándose de `EcfOnboardingStep`. El catálogo es cerrado y una
clave desconocida responde `404`.

### Permisos granulares

| Ruta | Permiso exigido |
| --- | --- |
| `GET /ecf/dgii/habilitation`, `/history`, `/evidence` | `viewEcfOnboarding` **o** `viewEcfDgiiHabilitation` |
| `PATCH /ecf/dgii/habilitation`, `/requirements/:key` | `manageEcfOnboarding` **o** `manageEcfDgiiRequirements` |
| `POST /ecf/dgii/evidence` | `manageEcfOnboarding` **o** `registerEcfDgiiEvidence` |
| `PATCH /ecf/dgii/evidence/:id/review` | `reviewEcfDgiiEvidence` (**sin alias**) |
| `POST /ecf/dgii/authorization`, `/revoke` | `recordEcfDgiiOfficialVerification` (**sin alias**) |

Los alias mantienen el acceso ya concedido; las dos operaciones sensibles exigen su propio
permiso. Los nombres del cliente Flutter **coinciden** con estas cadenas, de modo que la
bandera guardada en la base y lo que la interfaz muestra no pueden discrepar. Una prueba E2E
HTTP (`src/ecf/dgii/ecf-dgii-http.e2e-spec.ts`) verifica `401`, `403` por rol y por permiso,
el aislamiento entre empresas y que la referencia interna de almacenamiento no se expone.

### Defecto corregido durante la implementación

`listHistory` filtraba por una lista explícita de acciones y no incluía
`DGII_EVIDENCE_REVIEWED`: la revisión quedaba auditada en la base pero **invisible** para la
empresa. Lo detectó una prueba propia y se corrigió.

### Migración

`20261016180000_ecf_dgii_evidence_review` (aditiva): enum
`ecf_evidence_review_status`, valor `DGII_EVIDENCE_REVIEWED` en `ecf_audit_action`, cuatro
columnas en `ecf_evidences` y su índice. El archivo contiene **solo** los objetos de este
cambio; la deriva preexistente de otras columnas se dejó fuera deliberadamente.
