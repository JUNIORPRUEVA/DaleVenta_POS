# DOSA — vigilancia de incidencias y recuperación segura

Cómo se detecta un problema del flujo e-CF sin que nadie mire la base a mano, y
qué se repara solo y qué **nunca** se repara solo.

## 1. El problema que resuelve

Hasta esta fase, un evento que quedaba en `PENDING_CREDENTIALS` (llegó
autenticado pero no se pudieron guardar las credenciales) o en
`CONFLICT_PENDING_REVIEW` (llegaron credenciales distintas a las vigentes) solo se
descubría consultando `ecf_dosa_webhook_events`. No había ningún proceso que los
leyera: la recuperación dependía de que alguien se acordara.

## 2. Qué se vigila

Cinco condiciones, todas por empresa:

| Tipo | Condición | Severidad | ¿Se reintenta solo? |
| --- | --- | --- | --- |
| `EVENT_CREDENTIALS_NOT_STORED` | Evento en `PENDING_CREDENTIALS` con más de 15 min | ALTA | **No** |
| `CREDENTIAL_CONFLICT_REVIEW` | Evento en `CONFLICT_PENDING_REVIEW` | ALTA | **No** |
| `CREDENTIAL_AWAITING_CONFIRMATION` | Credencial en `PENDING_CONFIRMATION` con más de 15 min | MEDIA | **No** |
| `POSTULATION_NOT_BOUND` | Evento completo con `postulacion_id` que la sesión activa no vinculó, y el vínculo **es posible** | BAJA | **Sí** |
| `EVENT_TYPE_UNKNOWN` | Eventos sin tipo confirmado (DOSA no envía el campo). **Una sola incidencia por empresa**, con el recuento | BAJA | **No** |

Por qué casi nada se reintenta solo:

- `EVENT_CREDENTIALS_NOT_STORED` no se puede reparar desde aquí porque **no
  guardamos los secretos**: solo la huella del cuerpo. La recuperación real es
  que DOSA reenvíe el evento, y eso ya funciona (la deduplicación reanuda un
  evento incompleto en vez de descartarlo).
- `CREDENTIAL_CONFLICT_REVIEW` puede significar que alguien intenta rotar
  credenciales sin autorización. Reintentarlo solo sería automatizar justo lo
  que hay que revisar.
- `CREDENTIAL_AWAITING_CONFIRMATION` y `EVENT_TYPE_UNKNOWN` son estados de
  revisión humana por diseño.

La única operación reintentable (`POSTULATION_NOT_BOUND`) reejecuta
`bindProviderPostulation`, cuya sentencia exige intento **activo**, no sobrescribe
un identificador ya asignado y rechaza uno que pertenezca a otra empresa. Es
idempotente por construcción.

## 3. Deduplicación: sin alertas repetidas

La tabla `ecf_dosa_incidents` tiene un índice único `(company_id, incident_key)`.
La clave se calcula con `incidentKeyOf({ kind, subjectRef })`:

- `EVENT_CREDENTIALS_NOT_STORED:post-123`
- `CREDENTIAL_CONFLICT_REVIEW:post-123`
- `CREDENTIAL_AWAITING_CONFIRMATION:test`
- `POSTULATION_NOT_BOUND:post-123`
- `EVENT_TYPE_UNKNOWN` (sin sujeto: agregada)

El barrido hace **UPSERT** sobre esa clave, así que correr cada 10 minutos no crea
filas nuevas: solo actualiza `last_seen_at`. Un incidente distinto (otra
postulación, otro evento) sí es una fila nueva y merece su propia alerta.

## 4. Reintentos con límite y backoff

- Intentos máximos: **6**.
- Espera entre intentos: 5 min, 10, 20, 40, 80, 160 min (techo 6 h).
- Superado el límite → `ESCALATED`: deja de reintentarse y espera a una persona.
- Si el reintento funciona → `RESOLVED` con `attempts` y `resolved_at`.
- Un reintento que falla guarda `last_error_code` (`BINDING_NOT_APPLICABLE`,
  `BINDING_FAILED`, `RETRY_RUNNER_NOT_CONFIGURED`, `RETRY_SUBJECT_INCOMPLETE`).

Cada intento, su resultado y el cierre quedan escritos en la propia incidencia.

## 5. Cierre automático y cierre humano

- **Automático** (`RESOLVED`): la condición desapareció. Por ejemplo, DOSA reenvió
  el evento y ahora está `COMPLETE`, o el vínculo se resolvió.
- **Humano** (`CLOSED`): una persona elige un motivo del catálogo cerrado
  (`PROVIDER_RESENT_EVENT`, `CREDENTIALS_CONFIRMED_BY_ADMIN`,
  `ROTATION_AUTHORIZED`, `FALSE_POSITIVE`, `COMPANY_DISABLED`).
- Una incidencia `ESCALATED` **no** se cierra sola: alguien tiene que mirarla. Una
  incidencia `CLOSED` es terminal: el barrido no la reabre aunque la condición
  siga viva en la base.

Cerrar una incidencia **no** activa credenciales, **no** rota material y **no**
cambia el estado de certificación. Solo deja constancia de la revisión.

## 6. Aislamiento entre empresas

- La tabla es `company_id` + FK a `companies` con `ON DELETE CASCADE`.
- Cada consulta de detección agrupa y filtra por `company_id`.
- Cada escritura lleva `WHERE id = … AND company_id = …`, así que un
  identificador ajeno no puede modificarse.
- Un fallo en una empresa se captura y se cuenta (`errors`) sin interrumpir a las
  demás.

## 7. Cómo lo usa el administrador

Rutas de plataforma (mismo `PlatformStaffGuard` + `EcfSupportGrantGuard` que la
bandeja DGII, y por tanto **solo empresas que autorizaron asistencia**):

```
GET  /ecf/platform/dosa/incidents                    Bandeja multiempresa
GET  /ecf/platform/dosa/incidents/:companyId         Incidencias de una empresa
POST /ecf/platform/dosa/incidents/sweep              Barrido bajo demanda
POST /ecf/platform/dosa/incidents/:companyId/:incidentId/close
                                                     Cerrar con motivo
```

La respuesta no incluye credenciales: la incidencia guarda empresa, RNC,
referencia del sujeto (postulación o ambiente), contadores y estados.

## 8. Activación

```text
DOSA_INCIDENT_MONITOR_ENABLED=true   # apagado por defecto (fail-closed)
```

Sin la bandera, el planificador no ejecuta ni una consulta. El barrido manual
(`POST …/sweep`) sí funciona, porque es una acción autorizada de una persona.

Cadencia: cada 10 minutos (`CronExpression.EVERY_10_MINUTES`). No se baja a 1
minuto porque la antigüedad mínima para considerar incidencia es de 15 minutos:
barrer más a menudo no adelantaría ninguna detección y multiplicaría las consultas
sobre las tablas del flujo fiscal.

## 9. Qué NO hace

- No reenvía eventos a DOSA ni salta la verificación HMAC.
- No lee ni escribe credenciales.
- No activa credenciales ni cambia estados de certificación.
- No integra ningún proveedor de mensajería nuevo: la alerta se publica en la API
  administrativa y queda en la incidencia. No se añadió ninguna plantilla de
  WhatsApp porque eso exige aprobación de Meta y no estaba autorizado.

## 10. Evidencia

```text
# Unidad (sin base de datos)
npx jest src/ecf/provider/dosa/dosa-incident
  dosa-incident.policy.spec.ts       catálogo, deduplicación, backoff
  dosa-incident.reconcile.spec.ts    plan de acciones
  dosa-incident.service.spec.ts      barrido, aislamiento, cierre

# Integración (PostgreSQL desechable)
ECF_POSTGRES_UAT=true npx jest src/ecf/provider/dosa/dosa-incident-postgres
  detección de las cinco condiciones
  no repite alertas en barridos sucesivos
  aislamiento entre empresas
  reintento que vincula y resuelve
  no reintenta lo que no es seguro
  resolución automática cuando la condición cesa
  cierre humano terminal
```
