# Runbook de despliegue — release e-CF/DOSA del 2026-11-07

Documento operativo para que **el propietario** pulse «Implementar» en EasyPanel.
Lo escribe el agente; **el agente no despliega, no hace push y no toca producción**.

Etiquetas: **HECHO** = verificado en este árbol o en documentos del repo ·
**HIPÓTESIS** = plausible, sin verificar · **RECOMENDACIÓN** = propuesta.

---

## 1. Qué se va a desplegar

**HECHO** (`git log origin/production-main..HEAD`):

| Dato | Valor |
| --- | --- |
| Rama con el trabajo | `agent/dosa-credentials-split-20261107` |
| HEAD | `dc606206` |
| Rama de despliegue | `origin/production-main` = `aad1e7b9` |
| Commits pendientes | **24** |
| Archivos | **146** (+19 555 / −403) |
| Backend (`apps/api`) | 106 archivos |
| App/PWA (`apps/fulltech_app`) | 18 archivos |
| `production-main` es ancestro de HEAD | **Sí** → la fusión es *fast-forward*, sin conflictos |

**Se deben redesplegar los DOS servicios**: `daleventapos_backend` y
`daleventapos_pwa`. Publicar solo el backend dejaría la UI antigua sin las
pantallas nuevas.

---

## 2. Migraciones de base de datos — riesgo de pérdida de datos

**HECHO**: solo hay **dos** migraciones nuevas, y las dos son **puramente
aditivas**. No hay `DROP`, `TRUNCATE`, `DELETE`, `UPDATE` de datos existentes ni
`ALTER` sobre tablas ya existentes.

| Migración | Contenido |
| --- | --- |
| `20261107120000_ecf_dosa_incidents` | `CREATE TABLE ecf_dosa_incidents` + 3 índices + FK a `companies` |
| `20261107180000_ecf_portal_enrollments` | `CREATE TABLE ecf_portal_enrollments` + 2 índices + FK a `companies` |

**HECHO**: `prisma/schema.prisma` en este release suma **+76 líneas y 0
eliminaciones**.

**Conclusión: estas migraciones no pueden borrar datos.** Crean dos tablas
vacías. El único riesgo real es **no aplicarlas** (§4, riesgo A).

---

## 3. Variables de entorno

### 3.1 Críticas que deben SOBREVIVIR al despliegue

**HIPÓTESIS documentada** (memoria del proyecto, 2026-10-27): al pulsar
«Implementar», EasyPanel recrea el spec del servicio desde su copia persistida.
Si esa copia no tiene todas las variables, **las borra**.

| Variable | Por qué es crítica |
| --- | --- |
| `DOSA_CREDENTIALS_MASTER_KEY` | Descifra las credenciales DOSA ya guardadas. **Si se pierde, las credenciales existentes quedan ilegibles** y la API **sigue arrancando** (no falla rápido), así que el daño sería silencioso: el webhook empezaría a responder 500 y no se podría emitir |
| `DOSA_WEBHOOK_ENABLED=true` | Sin ella el webhook responde 503 y no entran credenciales |
| `DOSA_WEBHOOK_SIGNATURE_STRATEGY=HMAC_SHA256_TIMESTAMPED` | Sin ella la estrategia cae en `BLOCKED` |
| `DOSA_WEBHOOK_SECRET` | Verifica la firma del proveedor |
| `DATABASE_URL` (o partes `POSTGRES_*`) | Sin ella el arranque **aborta** |
| `JWT_SECRET` | Sin ella se usa `change-me` y las sesiones se rompen |
| `FINANCIAL_LEGACY_COMPAT=true` | Si falta, se rechazan ventas con contrato legacy |
| `FULLPOS_UPDATE_PILOT_CLIENT_KEYS` / `..._RELEASE_JSON` | Si faltan, se apaga el piloto de auto-actualización Windows |

### 3.2 Nuevas en este release

| Variable | Valor sugerido | Efecto |
| --- | --- | --- |
| `ECF_PORTAL_AUTO_ENROLL_ENABLED` | **decidir (§5)** | Por defecto `true` (opt-out). Con `true`, **toda empresa que entre al asistente queda habilitada automáticamente** para el portal e-CF |
| `ECF_PORTAL_PILOT_COMPANY_IDS` | vacío | Lista legacy por variable de entorno; la elegibilidad ahora vive en la tabla `ecf_portal_enrollments` |
| `DOSA_EMISSION_TRANSPORT` | `FETCH` o sin definir | Sin definir equivale a `FETCH`. `FAKE` fuera de UAT local **impide arrancar** |

### 3.3 Deben seguir apagadas

`DOSA_EMISSION_ENABLED=false`, `DOSA_PRODUCTION_EMISSION_ENABLED=false`.
**HECHO**: con la emisión apagada, la validación de arranque no exige nada y la
API arranca aunque falten `DOSA_BASE_URL` o las claves.

### 3.4 Comprobación contra el servicio real (nombres, sin valores)

**HECHO (2026-11-07)**: se listaron los **nombres** de las variables del
servicio `daleventapos_backend` en producción y se compararon con las que lee
el código de este release. Solo se extrajo la parte izquierda de cada
`NOMBRE=valor`; **ningún valor se leyó ni se imprimió**.

**Están presentes** todas las críticas de §3.1: `DOSA_CREDENTIALS_MASTER_KEY`,
`DOSA_WEBHOOK_ENABLED`, `DOSA_WEBHOOK_SIGNATURE_STRATEGY`, `DOSA_WEBHOOK_SECRET`,
`DOSA_WEBHOOK_SECRET_ENCODING`, `DOSA_WEBHOOK_TIMESTAMP_UNIT`,
`DOSA_CERTIFICATION_SESSIONS_ENABLED`, `DOSA_SESSION_BASE_URL`,
`DOSA_SESSION_URL_KEYS`, `DOSA_SESSION_URL_ACTIVE_KEY_VERSION`,
`ECF_DOSA_HISTORICAL_TRANSITION_ENABLED`, `ECF_PORTAL_PILOT_COMPANY_IDS`,
`DATABASE_URL`, `JWT_SECRET`, `FINANCIAL_LEGACY_COMPAT`,
`FULLPOS_UPDATE_PILOT_CLIENT_KEYS`, `FULLPOS_UPDATE_PILOT_RELEASE_JSON`,
`RUN_MIGRATIONS`, `MIGRATION_STRICT`.

**Ausentes y con consecuencia real:**

| Variable ausente | Valor efectivo al no estar | ¿Hay que hacer algo? |
| --- | --- | --- |
| `ECF_PORTAL_AUTO_ENROLL_ENABLED` | **`true`** (`?? "true"` en `ecf-portal-enrollment.service.ts`) | **Sí, es la decisión de §5.** Al desplegar, toda empresa que abra el asistente queda inscrita sola. Para estrenarlo de forma controlada hay que definirla en `false` **antes** de pulsar |
| `DOSA_INCIDENT_MONITOR_ENABLED` | `false` | No es un fallo: la vigilancia de incidencias nueva **no arranca**. Si se quiere activa, definirla en `true` de forma explícita |

**Ausentes y sin efecto hoy** (leen con valor por defecto seguro):
`DOSA_EMISSION_TRANSPORT` (ausente = `FETCH`, nunca el transporte falso),
`DOSA_EMISSION_ENVIRONMENT` (`TEST`), `DOSA_API_QUERIES_ENABLED`,
`DOSA_BASE_URL`, `DOSA_TEST_API_KEY`, `DOSA_PRODUCTION_API_KEY`,
`ECF_DOSA_INTENT_RECONCILIATION_ENABLED`,
`ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED`, `DOSA_QUERY_TIMEOUT_MS`,
`DOSA_SESSION_TIMEOUT_MS`, `DOSA_EMISSION_TIMEOUT_MS`, `ECF_EMISSION_ENABLED`,
`ECF_DOCKER_SECRETS_DIR` (`/run/secrets`), `ECF_DGII_STORAGE_DIR`.

**Anomalía menor detectada**: el spec del servicio tiene `PORT` **duplicado** y
una entrada vacía. No rompe el arranque, pero conviene limpiarlo la próxima vez
que se editen las variables del panel.

### 3.5 Panel de EasyPanel — verificado el 2026-11-07

**HECHO**: el propietario mostró la lista de variables del panel. Comparada con
el spec del servicio en ejecución:

| Variable | Panel | Servicio | Veredicto |
| --- | --- | --- | --- |
| `DOSA_SESSION_BASE_URL` | `https://dosasystem.com` | igual | Correcto (HTTPS, sin barra final) |
| `DOSA_SESSION_URL_KEYS` | `1:…` (truncado en la captura) | contiene **versiones 1 y 2** | Correcto: la activa es `2` y existe |
| `DOSA_SESSION_URL_ACTIVE_KEY_VERSION` | `2` | `2` | Correcto |
| `DOSA_WEBHOOK_SIGNATURE_STRATEGY` | `HMAC_SHA2…` | `HMAC_SHA256_TIMESTAMPED` | Correcto, valor exacto |
| `DOSA_CREDENTIALS_MASTER_KEY` | presente | 44 caracteres | Correcto |
| `ECF_PORTAL_AUTO_ENROLL_ENABLED` | `true` | **ausente** | Normal: el panel va por delante; «Implementar» la aplicará (ver §5) |
| `DOSA_SECRET_KEY` | `sk_SU_LLAVE_SECRETA` | 19 caracteres | **Marcador de ejemplo, no es una clave real** |
| `DOSA_INCIDENT_MONITOR_ENABLED` | ausente | ausente | Vigilancia de incidencias apagada |

**`DOSA_SECRET_KEY` es un marcador.** Solo lo usan `dosa-api.client.ts` (con
`DOSA_API_QUERIES_ENABLED=true`) y `dosa-certification-session.client.ts` (con
`DOSA_CERTIFICATION_SESSIONS_ENABLED=true`). Las dos banderas están apagadas o
ausentes, así que **hoy no tiene efecto**. Ojo: la validación de arranque solo
comprueba el prefijo `sk_`, que el marcador **sí** cumple, así que no falla
rápido: al encender cualquiera de las dos banderas el rechazo llegará del
proveedor. **Sustituirla por la clave real de DOSA antes de eso.**

---

## 4. Los dos riesgos reales

### Riesgo A — `RUN_MIGRATIONS=false` (el más importante)

**HECHO**: `apps/api/Dockerfile` define `ENV RUN_MIGRATIONS=true`, pero la
variable del **servicio** la sobrescribe. **HIPÓTESIS documentada** (memoria
2026-10-27): el servicio tiene `RUN_MIGRATIONS=false`.

Consecuencia: `scripts/start-prod.sh` imprime
`RUN_MIGRATIONS disabled -> skipping prisma schema sync`, **no crea las dos
tablas**, y como `MIGRATION_STRICT=false`, la API **arranca igual** con el
esquema viejo. Resultado: el sitio funciona, pero las funciones nuevas
(inscripciones del portal e incidencias DOSA) fallan con error de tabla
inexistente.

**RECOMENDACIÓN (una de las dos, no ambas):**

- **A1, preferida**: poner `RUN_MIGRATIONS=true` en el servicio **antes** de
  desplegar. `start-prod.sh` aplica las migraciones y solo después ejecuta
  `node dist/main.js`, así que la API no atiende tráfico con el esquema
  incompleto. Es seguro porque las migraciones son aditivas.
- **A2**: dejar `RUN_MIGRATIONS=false` y, en cuanto el contenedor nuevo esté
  arriba, ejecutar a mano:
  `docker exec <contenedor-backend-nuevo> npx prisma migrate deploy`

### Estado real: migración YA aplicada (2026-11-08 02:52 UTC)

Se eligió una tercera vía, más segura que A1 y A2: **aplicar las migraciones
antes de desplegar**, dejando `RUN_MIGRATIONS=false` como está.

Verificado en producción antes de escribir:

| Comprobación | Resultado |
| --- | --- |
| `prisma migrate status` en el contenedor vivo | `Database schema is up to date!` (73 migraciones) → sin `P3009` pendiente |
| Migraciones pendientes tras copiar las 2 nuevas | **exactamente 2**: `20261107120000_ecf_dosa_incidents` y `20261107180000_ecf_portal_enrollments` |
| Respaldo previo | `/root/daleventas-backups/pre-ecf-202611080252.dump` (7.5 MB, 163 entradas `TABLE DATA`, verificadas con `pg_restore --list`) |

Ejecutado: `docker cp` de las dos carpetas al contenedor vivo y
`npx prisma migrate deploy` → `All migrations have been successfully applied.`

Verificado después:

| Comprobación | Resultado |
| --- | --- |
| `prisma migrate status` | `Database schema is up to date!` (75 migraciones) |
| Tablas nuevas | `ecf_dosa_incidents` y `ecf_portal_enrollments` existen |
| `_prisma_migrations` | las dos filas con `finished_at` no nulo, `applied_steps_count = 1` |
| Datos previos | `companies` 2 · `users` 4 · `ecf_dosa_webhook_events` 2 · `ecf_dosa_company_credentials` 1 — intactos |
| Salud pública | `GET /api/health` → **200** `{"status":"ok"}` |

**Consecuencia para el despliegue:** el contenedor nuevo encontrará el esquema
ya actualizado. `RUN_MIGRATIONS` puede quedarse en `false`; si se pone en `true`,
`migrate deploy` será un no-op.

Nota: la "migración fallida" que resuelve `start-prod.sh`
(`20260502043000_add_status_history_user_name_and_created_at`) **no existe en el
repo** y **no está bloqueando** la base: el estado real era «up to date». El
resolver no se ejecutó.

### Riesgo B — pérdida de variables al recrear el spec

Ver §3.1. **RECOMENDACIÓN**: antes de pulsar «Implementar», abrir la pestaña de
variables del servicio y comprobar que están las críticas. Después del
despliegue, comprobar dentro del contenedor nuevo que siguen presentes
(`docker exec <c> printenv DOSA_CREDENTIALS_MASTER_KEY` debe devolver algo, sin
imprimir el valor en logs compartidos).

---

## 5. Decisión de producto: `ECF_PORTAL_AUTO_ENROLL_ENABLED`

**HECHO (2026-11-07)**: el panel ya la define en **`true`** y el servicio en
ejecución todavía no la tiene, así que «Implementar» la aplicará. La decisión
está tomada; queda escrito aquí qué significa.

`ECF_PORTAL_AUTO_ENROLL_ENABLED` por defecto `true` significa que **cualquier
empresa que abra el asistente queda autorizada sola** para el portal de
certificación e-CF. Eso es el objetivo del producto (el cliente hace todo solo),
pero tiene coste: cada postulación que el cliente abra la factura el proveedor.

- Si quieres el comportamiento nuevo ya: no definas la variable (o pon `true`).
- Si prefieres estrenarlo de forma controlada: define
  `ECF_PORTAL_AUTO_ENROLL_ENABLED=false`; las empresas se autorizan una a una
  desde la pantalla de administración, y luego lo enciendes.

Una revocación individual siempre gana sobre esta regla.

---

## 6. Procedimiento

### Paso 0 — Respaldo (obligatorio, antes de tocar nada)

```bash
ssh -i ~/.ssh/daleventas_codex root@31.97.99.70
mkdir -p /root/daleventas-backups
docker exec <contenedor-db> pg_dump -U <user> -d daleventa -Fc \
  > /root/daleventas-backups/pre-ecf-$(date +%Y%m%d%H%M).dump
docker exec -i <contenedor-db> pg_restore --list < archivo.dump | head
```

Verificar que el listado sale: un dump vacío no sirve.

### Paso 1 — Anotar el estado actual (para poder volver)

```bash
docker service inspect daleventapos_backend --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
docker service inspect daleventapos_pwa    --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
docker image tag <imagen-backend-actual> fullpos/daleventapos-backend:pre-ecf-20261107
docker image tag <imagen-pwa-actual>     fullpos/daleventapos-pwa:pre-ecf-20261107
```

**No ejecutar `docker image prune -a`**: borraría estas imágenes de vuelta atrás.

### Paso 2 — Llevar el código a `production-main`

**HECHO (2026-11-07)**: la rama **ya está publicada**.
`origin/agent/dosa-credentials-split-20261107` apunta al mismo commit que el
árbol local y el PR está abierto contra `production-main`. **No hay que volver
a empujar nada**; el paso que queda es fusionar.

La fusión es *fast-forward*, sin conflictos: `git merge-base --is-ancestor
origin/production-main HEAD` devuelve 0, así que `aad1e7b9` es ancestro.

### Paso 3 — Revisar variables en el panel

§3.1 y §5. Marcar `RUN_MIGRATIONS=true` si eliges A1.

### Paso 4 — Pulsar «Implementar»

**Primero el backend.** Esperar a que el contenedor esté sano
(`HEALTHCHECK` a `/health`, 120 s de margen inicial, 10 reintentos).

**Después el PWA.** **HECHO**: el build de Flutter en este host tarda
~25–30 min en 1 vCPU y consume ~5 GB de disco. Antes de lanzarlo:

```bash
df -h /                       # debe quedar holgura
docker builder prune -f       # reclama espacio de build (seguro)
```

### Paso 5 — Verificar (backend)

```bash
# 1) Migraciones aplicadas
docker exec <c> npx prisma migrate status
docker exec <db> psql -U <user> -d daleventa -tAc \
  "SELECT table_name FROM information_schema.tables
    WHERE table_name IN ('ecf_dosa_incidents','ecf_portal_enrollments');"
# esperado: dos filas

# 2) Variables críticas presentes (sin imprimir valores)
docker exec <c> sh -c 'for v in DOSA_CREDENTIALS_MASTER_KEY DOSA_WEBHOOK_SECRET JWT_SECRET DATABASE_URL; do
  [ -n "$(printenv $v)" ] && echo "$v OK" || echo "$v MISSING"; done'

# 3) Salud pública
curl -s -o /dev/null -w '%{http_code}\n' https://fullposcloud.fulltechrd.com/api/health   # 200
curl -s -o /dev/null -w '%{http_code}\n' https://fullposcloud.fulltechrd.com/api/webhook/dosa  # 404 JSON = NestJS vivo
```

**HECHO**: `/api/webhook/dosa` devuelve 404 a un GET porque no es su método; eso
es correcto, no un fallo.

### Paso 6 — Verificar (PWA)

Abrir `https://fullposcloud.fulltechrd.com` en incógnito, entrar al recorrido
e-CF y comprobar que aparecen las pantallas nuevas (estado de activación y
rango de numeración).

### Paso 7 — Webhook real (cuando DOSA reenvíe)

Tras el despliegue, el reenvío de `empresa.credenciales` **sí** guardará la
llave TEST que se perdió el 07/11 (`duplicate: true`), porque este release
incluye la deduplicación por contenido (`497636c9`). La credencial entra como
`PENDING_CONFIRMATION`; se activa sin intervención de Fulltech cuando el cliente
abre su pantalla de estado o registra su autorización DGII.

---

## 7. Rollback

| Capa | Acción |
| --- | --- |
| Servicio | `docker service update --image <tag-pre-ecf> --force daleventapos_backend` (y lo mismo con `_pwa`) |
| O bien | `docker service rollback daleventapos_backend` — **HIPÓTESIS**: solo funciona si la imagen anterior sigue en el host; verificar con `docker image ls` antes de confiar en ello |
| Base de datos | **No hace falta deshacer nada**: las dos tablas nuevas son aditivas y el código anterior las ignora. Dejarlas creadas es más seguro que borrarlas |
| Datos | El respaldo del paso 0 es la red de seguridad; solo se restauraría si algo corrupto hubiera entrado en datos existentes, y este release no modifica datos existentes |

**Nunca** ejecutar `prisma migrate reset` contra producción.

---

## 8. Lo que este runbook NO hace

- No hace `push`, ni PR, ni fusión.
- No despliega, ni reinicia servicios, ni aplica migraciones.
- No lee ni imprime secretos.
- No modifica datos ni variables del panel.

---

## 9. Activación de la emisión TEST (sin emitir de verdad a la DGII)

**HECHO (2026-11-07)**: estado real leído de producción y de la compuerta
`assessDosaEmissionGate`. Para que una emisión TEST pase hoy faltan seis cosas;
**cinco son datos o configuración, no variables de entorno**.

| # | Requisito | Estado real hoy | Cómo se resuelve |
| --- | --- | --- | --- |
| 1 | `DOSA_BASE_URL` presente y HTTPS | **ausente** | Panel: `https://dosasystem.com`. **Obligatoria ANTES de encender la bandera**: sin ella el backend **no arranca** (`DOSA_STARTUP_BASE_URL_REQUIRED`) |
| 2 | `DOSA_EMISSION_ENABLED=true` | `false` | Panel, **en el mismo guardado** que el punto 1 |
| 3 | `DOSA_EMISSION_ENVIRONMENT=TEST` | ausente (el código ya asume `TEST`) | Panel, explícita por claridad |
| 4 | `ecf_company_configurations.provider` = `DOSA` | **`ALANUBE`** | Endpoint de configuración e-CF, que ya solo acepta `DOSA` |
| 5 | Fila de credencial `test` en `ACTIVE` | **no existe fila `test`**; el paquete completo está en la fila `production` con `PENDING_CONFIRMATION` | Reclasificar con el script + activación normal del producto |
| 6 | Secuencia e-NCF disponible | sin verificar | Pantalla de rango de numeración |

**No hay que tocar**: `DOSA_PRODUCTION_EMISSION_ENABLED=false` (queda apagado y
es lo que impide emitir de verdad) y `DOSA_TEST_API_KEY` (la emisión **no la
usa**: lee la credencial cifrada de la empresa desde la bóveda).

### Por qué no existe la fila `test`

El paquete del webhook se guardaba bajo el `ambiente` declarado por el evento
(`Produccion`), con las tres claves juntas dentro. Este release lo corrige
(`ca9dd3b0`) repartiendo por nombre de clave. Para el dato **ya guardado** existe
una herramienta manual:

```bash
# 1) Ver qué haría (no escribe nada)
npm run dosa:credentials:reclassify -- --company-id 165e3fca-6225-479b-8805-d2205f10536c --rnc 133080206

# 2) Aplicar (exige la confirmación en el entorno)
DOSA_CREDENTIALS_RECLASSIFY=CONFIRM \
  npm run dosa:credentials:reclassify -- --company-id 165e3fca-6225-479b-8805-d2205f10536c --rnc 133080206 --apply
```

- El script vive en la **imagen**: solo puede ejecutarse **después de desplegar**.
- Dry-run por defecto; `--apply` exige `DOSA_CREDENTIALS_RECLASSIFY=CONFIRM`.
- **No activa nada**: lo que escribe entra como `PENDING_CONFIRMATION`.
- **No toca** la fila de origen; es idempotente por huella.

Después, la credencial `test` se activa por la vía normal del producto (abrir la
pantalla de estado e-CF o registrar la autorización DGII), que es la que produce
la evidencia que la activación exige.

### Orden seguro

1. Fusionar el PR y desplegar backend (las variables 1–3 se pueden poner antes o
   en el mismo guardado; **nunca** la 2 sin la 1).
2. Cambiar `provider` a `DOSA` en la configuración e-CF de la empresa.
3. Dry-run de la reclasificación → `--apply` → comprobar que aparece la fila `test`.
4. Activar la credencial desde la pantalla de estado e-CF del cliente.
5. Confirmar la secuencia e-NCF y recién entonces emitir **un** comprobante TEST.
6. `DOSA_PRODUCTION_EMISSION_ENABLED` se queda en `false` hasta que el TEST esté
   validado; emitir de verdad es un acto aparte, con su propia autorización.
