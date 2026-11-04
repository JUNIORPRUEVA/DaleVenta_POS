# e-CF/DOSA: plan para una sola liberación controlada

Este plan prepara la liberación; no autoriza desplegar, migrar, reconciliar el intento existente, emitir e-CF ni presentar nada ante la DGII.

## Condiciones previas del propietario

1. Aprobar el PR y confirmar la imagen exacta de API y PWA que se instalará. Conservar ambas imágenes anteriores para reversión.
2. Verificar la base y el entorno de producción sin mostrar credenciales. Obtener un respaldo PostgreSQL consistente, verificar que puede leerse y registrar su hora y punto de restauración. Mantener el respaldo fuera del contenedor que se reemplazará.
3. Confirmar, con lectura de `_prisma_migrations`, que `20261104120000_ecf_intent_provider_reconciliation` y `20261104120100_ecf_intent_provider_reconciliation_unique` terminaron correctamente. Confirmar el valor `INTENT_PROVIDER_RECONCILED` en `ecf_audit_action`, el índice único parcial `ecf_intent_provider_reconciliation_once` y ausencia de reconciliaciones duplicadas. Si falta algo, detener el despliegue y solicitar aprobación separada para aplicar esas migraciones, tras respaldo y ensayo en UAT. No editar migraciones ya aplicadas.
4. Revisar `RUN_MIGRATIONS`, `PRISMA_SYNC_MODE`, `MIGRATION_STRICT` y `RUN_SEED` antes de iniciar la API: el arranque puede ejecutar migraciones por defecto y `MIGRATION_STRICT` tiene valor predeterminado `false`. Para esta liberación, verificar `RUN_MIGRATIONS=false`, `RUN_SEED=false` y `PRISMA_SYNC_MODE=migrate` antes de publicar la nueva API. Si se aprueba una migración pendiente, ejecutarla como paso separado y comprobar su resultado; nunca dejar que el despliegue la aplique de forma implícita ni continúe tras un fallo.
5. Confirmar presencia de la configuración del portal, dominio autorizado, clave pública, piloto y validación de webhooks sin imprimir valores. La reconciliación administrativa debe continuar deshabilitada hasta completar la revisión de evidencias.

La conexión SSH autorizada al VPS permitió consultar en modo de solo lectura `daleventapos_database` / `daleventa` el 2026-11-04. Las dos migraciones de PR #8, el enum y el índice **faltaban**; no había reconciliaciones duplicadas. La consulta siguiente queda disponible para repetir la verificación antes de cualquier migración; las dos migraciones, el enum, el índice y la ausencia de duplicados deben devolver `true` después de aplicarlas con autorización separada:

```sql
WITH required(name) AS (
  VALUES ('20261104120000_ecf_intent_provider_reconciliation'),
         ('20261104120100_ecf_intent_provider_reconciliation_unique')
)
SELECT 'migration:' || name AS check_name,
       EXISTS (
         SELECT 1 FROM _prisma_migrations
         WHERE migration_name = name
           AND finished_at IS NOT NULL AND rolled_back_at IS NULL
       )::text AS result
FROM required
UNION ALL
SELECT 'postgres_version', current_setting('server_version')
UNION ALL
SELECT 'audit_table_size', pg_size_pretty(pg_total_relation_size('ecf_audit_logs'))
UNION ALL
SELECT 'audit_enum', EXISTS (
  SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname = 'ecf_audit_action'
    AND e.enumlabel = 'INTENT_PROVIDER_RECONCILED'
)::text
UNION ALL
SELECT 'reconciliation_unique_partial_index', EXISTS (
  SELECT 1 FROM pg_indexes
  WHERE schemaname = current_schema()
    AND tablename = 'ecf_audit_logs'
    AND indexname = 'ecf_intent_provider_reconciliation_once'
    AND indexdef ILIKE '%UNIQUE INDEX%'
    AND indexdef LIKE '%company_id%'
    AND indexdef LIKE '%target_id%'
    AND indexdef LIKE '%INTENT_PROVIDER_RECONCILED%'
    AND indexdef LIKE '%DOSA_CERTIFICATION_INTENT%'
)::text
UNION ALL
SELECT 'no_duplicate_reconciliations', (NOT EXISTS (
  SELECT 1 FROM ecf_audit_logs
  WHERE action::text = 'INTENT_PROVIDER_RECONCILED'
    AND target_type = 'DOSA_CERTIFICATION_INTENT'
  GROUP BY company_id, target_id HAVING COUNT(*) > 1
))::text;
```

Las migraciones solo agregan un valor al enum y un índice único parcial sobre la auditoría e-CF; no borran ni actualizan registros, ni cambian tablas del POS tradicional. El índice se crea sin `CONCURRENTLY` y puede bloquear escrituras en `ecf_audit_logs` durante su construcción: medir el tamaño, ejecutar en ventana controlada y no prometer impacto nulo. La secuencia de dos migraciones separadas permite usar el nuevo valor del enum después de que la primera transacción se confirme. La validación local de PR #9 aplicó las 70 migraciones en PostgreSQL 17 desechable; producción usa PostgreSQL 17.11 y aún carece de las dos migraciones de PR #8.

## Configuración DOSA, sin revelar valores

| Requisito | Estado en código | Comprobación de producción |
| --- | --- | --- |
| Dominio HTTPS del portal, `ECF_PORTAL_API_BASE` y build arg `DOSA_ASSISTANT_PUBLISHABLE_KEY` | **Confirmado**: el Dockerfile rechaza una clave pública ausente y el portal usa `/ecf/certificacion/` | **Pendiente**: inspeccionar el build publicado, dominio autorizado y valores presentes sin mostrarlos |
| `ECF_PORTAL_PILOT_COMPANY_IDS` con el ID de FULLTECH SRL | **Confirmado**: la elegibilidad y el ticket comparten una compuerta cerrada por defecto | **Pendiente**: comprobar pertenencia del ID autenticado, sin ampliar el piloto |
| JWT, `manageEcfOnboarding` y rol administrador | **Confirmado**: la reconciliación exige los tres controles y consulta por `companyId` | **Pendiente**: comprobar permisos de la cuenta administradora real |
| `ECF_DOSA_INTENT_RECONCILIATION_ENABLED` | **Confirmado**: apagado por defecto | **Bloqueante para reconciliar**; mantenerlo apagado durante el despliegue |
| `DOSA_WEBHOOK_ENABLED`, estrategia de firma, secreto y URL `/api/webhook/dosa` | **Confirmado**: ruta y validación HMAC con rechazo por defecto; no concede autorización fiscal | **Pendiente**: presencia de configuración y confirmación con evento auténtico, sin activar un modo de laboratorio |
| `DOSA_BASE_URL` y banderas de emisión DOSA/e-CF | **Confirmado**: cliente y barreras de emisión separadas del portal | **Bloqueante para emitir**; mantener emisión desactivada hasta aprobación distinta |
| `DOSA_ASSISTANT_ENABLED` del Flutter embebido | **Confirmado**: apagado por defecto; el portal estático usa su propia clave pública | **Pendiente** solo si se pretende usar el componente embebido, no requisito demostrado del portal actual |

## Respaldo previo y prueba aislada — preparado, NO ejecutado

Preflight de solo lectura del 2026-11-04: `daleventapos_database` / `daleventa` usa PostgreSQL 17.11; `pg_dump` y `pg_restore` 17.11 están disponibles; la base ocupa aproximadamente 74 MB, hay aproximadamente 53,7 GB libres en el sistema de archivos de `/root` y `/var/lib/docker`, y `/root` pertenece a root con permisos `0700`. La ruta propuesta `/root/daleventa-pr9-pre-migration-20261104.dump` y su variante `.partial` no existían. Repetir estos controles al ejecutar. El respaldo incluye todos los esquemas, datos y objetos de **esa base**, pero no roles ni otras bases del clúster.

**Requiere aprobación específica para escribir el archivo.** Ejecutar en la sesión SSH autorizada del VPS, en una ventana de baja carga, sin detener la API ni ejecutar migraciones:

```sh
set -eu
umask 077
db=$(docker ps --filter name=daleventapos_database --format '{{.ID}}' | head -n 1)
test -n "$db"
test "$(docker inspect -f '{{index .Config.Labels "com.docker.swarm.service.name"}}' "$db")" = daleventapos_database
archive=/root/daleventa-pr9-pre-migration-20261104.dump
partial="$archive.partial"
test ! -e "$archive" && test ! -e "$partial"
docker exec "$db" sh -c 'nice -n 10 ionice -c2 -n7 pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --compress=6' > "$partial"
test -s "$partial"
docker exec -i "$db" pg_restore --list < "$partial" > /dev/null
mv -n -- "$partial" "$archive"
test -s "$archive" && test ! -e "$partial"
stat -c '%a %s %n' "$archive"
sha256sum "$archive"
```

Registrar el tamaño y la suma de comprobación en el acta privada, sin divulgar el archivo. Un `pg_dump -Fc` usa una instantánea consistente de PostgreSQL y no escribe en tablas; puede consumir E/S y CPU. El proceso tiene prioridad reducida, pero **no puede prometerse latencia cero** para clientes: observar salud y carga, y detener el procedimiento ante degradación. Si falla, el archivo `.partial` no es respaldo válido; limpiar solo esa ruta exacta con autorización.

**Requiere una segunda aprobación específica para levantar el contenedor y restaurar datos en él.** Usar la misma imagen PostgreSQL 17.11 que corre en producción, sin red, sin puertos, sin volúmenes de la aplicación y con recursos limitados. El archivo se monta en solo lectura; el volumen anónimo de datos del contenedor se elimina con `--rm` al detenerlo:

```sh
set -eu
archive=/root/daleventa-pr9-pre-migration-20261104.dump
test -r "$archive"
db=$(docker ps --filter name=daleventapos_database --format '{{.ID}}' | head -n 1)
image=$(docker inspect -f '{{.Image}}' "$db")
probe=$(docker run --rm -d --name daleventa-pr9-restore-check --network none \
  --cpus=0.5 --memory=768m --memory-swap=768m --pids-limit=128 \
  --mount "type=bind,src=$archive,dst=/backup/production.dump,readonly" \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=restore_check "$image")
trap 'docker stop "$probe" > /dev/null 2>&1 || true' EXIT
test "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$probe")" = none
ready=false
for n in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec "$probe" pg_isready -U postgres -d restore_check > /dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
test "$ready" = true
docker exec "$probe" pg_restore --exit-on-error --single-transaction \
  --no-owner --no-acl -U postgres -d restore_check /backup/production.dump > /dev/null
source_count=$(docker exec "$db" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT COUNT(*) FROM _prisma_migrations"')
restored_count=$(docker exec "$probe" psql -U postgres -d restore_check -Atqc 'SELECT COUNT(*) FROM _prisma_migrations')
test "$source_count" = "$restored_count"
echo 'Restauración aislada completa; historial migratorio coincidente.'
```

No publicar puertos, unir el contenedor a redes de la aplicación ni dejar copias permanentes de la base de prueba. Una prueba exitosa valida el archivo en ese entorno; una futura restauración de **producción** sería una operación distinta, con autorización y plan para preservar las ventas posteriores al respaldo.

## Orden propuesto, sujeto a autorización separada

1. Cerrar cambios, revisar resultados del CI y comprobar UAT con datos sintéticos: rutas Nginx, restauración de expediente, certificado vencido, aislamiento entre empresas, elegibilidad piloto, portal, webhooks, bloqueo de emisión y POS tradicional. PR #9 pasó CI; no equivale a aceptación de producción.
2. Tomar un respaldo PostgreSQL consistente con herramientas del operador, guardar la versión de PostgreSQL y la hora de corte, calcular una suma de comprobación y probar la restauración en **otra base aislada**. Verificar tablas y conteos básicos sin copiar certificados ni datos de clientes a un entorno inseguro. El propietario debe conservar instrucciones y acceso al respaldo; no basta con que exista un archivo.
3. Revisar el resultado de la consulta anterior, estado migratorio, ausencia de duplicados, tamaño de auditoría y restricciones. Si faltan las dos migraciones, obtener aprobación de migración distinta de la de despliegue y aplicarlas en orden, una sola vez, durante una ventana controlada: primero `20261104120000_ecf_intent_provider_reconciliation`, después `20261104120100_ecf_intent_provider_reconciliation_unique`. Repetir la consulta antes de publicar imágenes; detenerse ante cualquier error. Mantener `RUN_MIGRATIONS=false` en el arranque posterior.
4. Con autorización explícita de despliegue, publicar **una sola versión** de la API; comprobar `/health`, `/health/db`, autenticación, diagnóstico y ausencia de emisiones o intentos nuevos.
5. Publicar la PWA del mismo commit. Verificar `/ecf`, `/ecf/`, `/ecf/certificacion/`, sesión, empresa y que no hay redirección de HTTPS a HTTP. Comprobar catálogo, POS, NCF y caja sin crear ventas reales.
6. Con el administrador autenticado, leer el diagnóstico de Intento 1. Preservar número, estado, proveedor registrado e historia. No abrir portal ni generar ticket hasta que la atribución efectiva y las autorizaciones estén verificadas.

## Reversión

- Ante un problema de PWA, restaurar la imagen PWA anterior y comprobar rutas, sesión y caché/service worker. Ante un problema de API sin cambio de esquema, restaurar la imagen API anterior y repetir salud, autenticación y aislamiento. No apuntar un binario antiguo a un esquema desconocido sin verificar compatibilidad.
- Si se aplicaron migraciones, no ejecutar SQL inverso improvisado. El enum no se revierte con seguridad mediante un `DROP`; el índice nuevo puede permanecer sin alterar registros. Detener acciones fiscales y decidir entre mantener el esquema compatible o una restauración puntual del respaldo **probado**, considerando todas las escrituras posteriores. La restauración de producción requiere aprobación separada, ventana controlada y plan para evitar pérdida de ventas del POS.
- Mantener reconciliación, emisión y postulación detenidas mientras se investiga. Registrar hora, imagen, migración y evidencia del fallo.

## Aceptación después del despliegue

- Salud de API y PostgreSQL, migraciones y restricciones verificadas; sin errores de inicio.
- PWA HTTPS entrega Flutter en `/ecf`, redirección relativa desde `/ecf/` y portal estático en `/ecf/certificacion/`; resto de rutas intacto.
- Misma empresa y expediente al recargar, cambiar dispositivo y cerrar/abrir sesión; otra empresa no ve ese progreso.
- Certificado con validación persistida y vigente avanza sin nueva carga. Una validación anterior sin metadatos persistidos exige una revalidación explícita, sin inferir vigencia a partir de un marcador visual.
- Intento 1 sigue único y sin cambios hasta una reconciliación administrativa aprobada; historial ALANUBE visible solo en diagnóstico autorizado. Sin creación automática de intención, ticket, sesión ni envío a DGII.
- Elegibilidad piloto, portal y webhook respetan autorización y aislamiento; emisión fiscal sigue bloqueada.
- POS tradicional, NCF, catálogo y caja conservan comportamiento básico.

## Reconciliación posterior, separada de este despliegue

El diagnóstico autenticado ya obtenido describe Intento 1 como no iniciado, registrado históricamente en ALANUBE y sin referencias externas. **Esto no prueba origen local ni ausencia de actividad externa.** Antes de reconciliar, un administrador debe obtener en lectura el `intentId`, `sourceAuditId`, `createdByUserId`, fecha y metadatos `created/rnc/attemptNo/provider` de `ONBOARDING_STARTED`; comprobar que empresa, intento y actor coinciden con el expediente actual. Revisar logs locales de salida, intentos ALANUBE, webhooks DOSA, tickets y sesiones desde la creación. Obtener evidencia independiente del proveedor o su respuesta documentada que descarte actividad externa. Si hay discrepancia, **detener**.

Con esas evidencias, el propietario debe aprobar **por separado** la reconciliación del intento exacto y aportar `externalReviewReference`, `ownerApprovalReference` y motivo. Solo entonces una ventana administrativa autorizada podría habilitar temporalmente `ECF_DOSA_INTENT_RECONCILIATION_ENABLED`, ejecutar una vez `POST /ecf/dosa/certification-intent/reconcile-provider` con confirmación explícita y volver a apagar la bandera. PR #8 exige rol ADMIN/ADMINISTRADOR, `manageEcfOnboarding`, empresa piloto, estado `NOT_STARTED`, intento 1 más reciente, ausencia de referencias y actividad local externa, y una auditoría de origen coherente; escribe `INTENT_PROVIDER_RECONCILED` sin borrar la atribución ALANUBE. Releer el diagnóstico y comprobar proveedor efectivo DOSA, historial intacto e intento único.

Una prueba controlada del portal es **otro acto distinto**: requiere autorización específica para emitir un ticket y abrirlo. `cert:ready` solo demostraría que cargó el asistente; no acredita sesión oficial, pruebas DGII ni habilitación fiscal. No activar emisión ni presentar una solicitud con esta liberación.

## Decisión GO / NO-GO

**GO para solicitar una única ventana de despliegue** solo cuando CI y UAT estén aprobados, el respaldo haya sido restaurado en aislamiento, la consulta de producción confirme esquema compatible o exista aprobación específica para migrarlo, las configuraciones estén verificadas sin mostrar secretos y las imágenes anteriores estén disponibles. **NO-GO** ante migración incierta, respaldo no restaurable, configuración piloto/portal desconocida, riesgo de aislamiento o fallo de POS. La autorización de despliegue no incluye reconciliar Intento 1 ni empezar la certificación.
