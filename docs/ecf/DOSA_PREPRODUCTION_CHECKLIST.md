# DOSA — checklist de preproducción

Lista de verificación para autorizar un despliegue **controlado**. Se ejecuta en
orden y cada paso tiene criterio de éxito. Los comandos de producción **no** se
han ejecutado: este documento es el permiso de trabajo, no el trabajo.

Complementa a `docs/ecf/DOSA_DEPLOYMENT_RUNBOOK.md` (procedimiento detallado y
reversión). Aquí está lo que hay que comprobar, no cómo hacerlo.

## 0. Antes de empezar

- [ ] Rama `agent/dosa-credentials-split-20261107`, HEAD `8173febf` (o posterior), árbol limpio.
- [ ] Confirmadas las respuestas de DOSA que bloquean decisiones: `api_secret`
      único o por ambiente, unidad de `t`, encoding del secreto.
      Ver `docs/ecf/DOSA_CONTRACT_QUESTIONS_ALEJANDRO.md`.
- [ ] Autorización explícita, por escrito, para: migración, despliegue y
      reclasificación de FULLTECH. Sin ella, el proceso se detiene aquí.

## 1. Verificación del artefacto

- [ ] `npm ci && npm run api:build` → exit 0.
- [ ] `npx prisma validate` (desde `apps/api`) → schema válido.
- [ ] `npm test` → 0 fallos.
- [ ] `npx jest --testPathPatterns "\.e2e-spec\.ts$"` con `ALANUBE_ENABLE_REAL_CALLS=false`
      y `ECF_POSTGRES_UAT=true` → 0 fallos.
- [ ] **`flutter build web` / `flutter build windows` llevan los `--dart-define`**:
      ```powershell
      flutter build web --release --dart-define=APP_ENV=uat `
        --dart-define=API_BASE_URL=https://<backend> --dart-define=APP_BASE_URL=https://<backend>
      ```
      **Sin `API_BASE_URL`, el bundle apunta a PRODUCCIÓN por defecto**
      (`Env._defaultApiBaseUrl = ProductConfig.productionApiBaseUrl`).
- [ ] **Comprobación automática del bundle** (no basta con revisar el comando):
      ```powershell
      npm run verify:bundle:env -- --bundle apps/fulltech_app/build/web/main.dart.js `
        --expect-api 127.0.0.1:4004
      ```
      Criterio de éxito: `VERIFICACIÓN CORRECTA` y exit 0. Un artefacto
      compilado sin `--dart-define=API_BASE_URL` **falla** con
      «falta la URL declarada».

      Nota de precisión: los hosts productivos (`daleventapos-backend...`,
      `31.97.99.70`, …) son constantes de `ProductConfig` y aparecen en
      **cualquier** build, incluido el correcto; por eso el criterio es la
      **presencia de la URL declarada**, no la ausencia del host productivo.
- [ ] Para un artefacto comercial, la comprobación inversa:
      ```powershell
      npm run verify:bundle:env -- --bundle <bundle> `
        --expect-api <host-de-produccion> --forbid-api 127.0.0.1:4004
      ```
- [ ] Prueba de regresión del perfil UAT (debe pasar en ambos modos):
      ```powershell
      cd apps/fulltech_app
      flutter test test/core/api/env_uat_profile_fail_closed_test.dart
      flutter test test/core/api/env_uat_profile_fail_closed_test.dart --dart-define=APP_ENV=uat
      ```
- [ ] Variables de bandera en el entorno destino: `DOSA_EMISSION_ENABLED=false`,
      `DOSA_PRODUCTION_EMISSION_ENABLED=false`, `DOSA_WEBHOOK_ENABLED=true`,
      `DOSA_INCIDENT_MONITOR_ENABLED` decidido de forma explícita.

## 2. Respaldo y restauración comprobada

- [ ] `pg_dump -Fc` de la base de destino, con fecha y tamaño verificados.
- [ ] `pg_restore -l` lista objetos del respaldo.
- [ ] **Restauración probada en una base desechable** y recuento de filas
      comparado con origen (`ecf_dosa_company_credentials`, `ecf_dosa_webhook_events`,
      `ecf_company_configurations`).
- [ ] Sin este paso verificado, no se avanza.

## 3. Migración

- [ ] Migraciones nuevas de esta rama (aditivas, solo tablas):
      `20261107120000_ecf_dosa_incidents` y `20261107180000_ecf_portal_enrollments`.
- [ ] `ecf_portal_enrollments` es la autorización del asistente **por empresa**
      (ver `docs/ecf/ECF_PORTAL_ENROLLMENT.md`). El backend anterior no la
      conoce: la tabla vacía se comporta como «nadie autorizado» y la decisión
      sigue cayendo en la lista heredada del entorno, así que un despliegue
      gradual es seguro.
- [ ] Antes de retirar `ECF_PORTAL_PILOT_COMPANY_IDS`, comprobar que cada
      empresa activa tiene su fila:
      ```sql
      SELECT c.id, c.name
        FROM companies c
       WHERE NOT EXISTS (
         SELECT 1 FROM ecf_portal_enrollments e
          WHERE e.company_id = c.id AND e.status = 'ACTIVE');
      ```
      Una lista vacía es la condición para vaciar la variable.
- [ ] Ensayada en UAT: `npx prisma migrate deploy` dos veces → la segunda informa
      «No pending migrations to apply».
- [ ] `npx prisma migrate status` → «Database schema is up to date».
- [ ] Comprobado que la tabla nueva no es usada por el backend anterior
      (despliegue gradual seguro).

## 4. Despliegue

- [ ] Ventana de mantenimiento acordada; responsable presente.
- [ ] Orden: migración → `daleventapos_backend` (`--update-order start-first`).
      `daleventapos_pwa` solo si cambió el bundle web.
- [ ] `docker service ps <servicio> --filter desired-state=running` → 1/1.

## 5. Revisión de salud

- [ ] `GET /api/health` → 200.
- [ ] `POST /api/webhook/dosa` sin firma → **401** `ECF_DOSA_WEBHOOK_BLOCKED`
      (nunca 503: un 401 no invita a reintentar).
- [ ] Webhook con `DOSA_WEBHOOK_ENABLED=false` → 503 `ENDPOINT_DISABLED`.
- [ ] `GET /ecf/config` de una empresa de prueba → `provider=DOSA`.
- [ ] Logs de arranque sin `Error` ni `DOSA_CREDENTIALS_KEY_MISSING`.

## 6. Verificación de credenciales (sin imprimir secretos)

```sql
SELECT company_id, rnc, environment, status,
       (present->>'apiKeyTest')       AS tiene_test,
       (present->>'apiKeyProduccion') AS tiene_prod,
       left(fingerprint, 8)           AS huella_8
  FROM ecf_dosa_company_credentials
 ORDER BY company_id, environment;
```

- [ ] Cada empresa tiene **una fila por ambiente**, y cada fila trae **solo su**
      clave identificadora (`test` → `apiKeyTest`; `production` → `apiKeyProduccion`).
- [ ] Todas en `PENDING_CONFIRMATION`. **Ninguna `ACTIVE`** salvo decisión humana
      registrada.
- [ ] Huellas distintas entre ambientes.
- [ ] Nunca `SELECT ciphertext, iv, auth_tag`.

## 7. Dry-run de reclasificación de FULLTECH

Sin `--apply` **no escribe nada**.

```powershell
$env:DOSA_CREDENTIALS_MASTER_KEY = <clave del entorno>   # no se imprime
npm run dosa:credentials:reclassify -- `
  --company-id 165e3fca-6225-479b-8805-d2205f10536c `
  --rnc 133080206
```

- [ ] Informa la fila `production` actual y el destino `test`.
- [ ] Informa `already` o `written` de forma coherente; huellas truncadas a 12.
- [ ] **No** propone eliminar la fila de producción.
- [ ] Si aparece `blockedReason`, se detiene el proceso y se escala.

**Criterios de aceptación del dry-run**

| Comprobación | Esperado |
| --- | --- |
| Fila de origen | `production`, `PENDING_CONFIRMATION`, con las dos claves presentes |
| Destino propuesto | `test`, con `apiKeyTest` |
| Clave de producción | se conserva, no se mueve ni se borra |
| Escrituras | 0 (sin `--apply`) |

## 8. Reclasificación real — **solo con autorización expresa**

- [ ] Autorización registrada en la tarea (no se hereda de pasos anteriores).
- [ ] `DOSA_CREDENTIALS_RECLASSIFY=CONFIRM` y `--apply`.
- [ ] Repetir la consulta del §6: dos filas, `production` y `test`, ambas
      `PENDING_CONFIRMATION`, huellas distintas.
- [ ] La clave que se puede abrir en `test` es la de TEST (verificable con
      `inspect`, sin imprimir el valor).

## 9. Post-despliegue (24 h)

- [ ] `POST /ecf/platform/dosa/incidents/sweep` como personal de plataforma → sin `errors`.
- [ ] `GET /ecf/platform/dosa/incidents` → incidencias esperadas y **ninguna repetida**
      tras un segundo barrido (`created=0`, `touched=N`).
- [ ] Webhooks del proveedor: `400`/`401` solo por causa real; sin `503` repetidos.
- [ ] Emisión sigue bloqueada: `emissionPathAvailable=false`.
- [ ] Ninguna empresa ve datos de otra (consulta con dos empresas de prueba).

## 10. Reversión

- [ ] `docker service rollback daleventapos_backend` probado en UAT.
- [ ] La migración es aditiva: revertir el código deja la tabla sin uso, sin borrar datos.
- [ ] Reclasificación: se revierte marcando la fila `test` como `REVOKED`, **nunca**
      borrándola.
- [ ] Respaldo del §2 disponible y con restauración ya verificada.

## Bloqueos conocidos que impiden autorizar el despliegue hoy

1. `api_secret` único o por ambiente **sin confirmar** por DOSA.
2. Interfaz del asistente **no validada en navegador real** (la herramienta de
   navegador estaba deshabilitada en la sesión de validación).
3. Reclasificación de FULLTECH **no ejecutada** (requiere autorización expresa).
4. Sin canal proactivo de aviso para incidencias: la alerta vive en la API
   administrativa, no se envía a nadie.
