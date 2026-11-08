# DOSA multiempresa — runbook de despliegue y reversión

Procedimiento **ejecutable** para llevar a producción los commits de la rama
`agent/dosa-credentials-split-20261107` y completar la reclasificación de las
credenciales TEST de FULLTECH.

> **No se ha ejecutado.** Ninguno de los pasos de este documento se ha corrido
> contra producción, ni se ha hecho push, merge, migración, despliegue, emisión
> ni modificación de credenciales reales.
>
> Producción es de **solo lectura** hasta que el responsable autorice el paso
> correspondiente, uno por uno.

## 0. Datos de partida (HECHO, leído de producción sin modificar nada)

| Dato | Valor |
| --- | --- |
| Empresa FULLTECH | `165e3fca-6225-479b-8805-d2205f10536c` |
| RNC | `133080206` |
| Fila de credenciales | 1, `environment = production`, `status = PENDING_CONFIRMATION` |
| Presencia | `apiKeyProduccion`, `apiKeyTest`, `apiSecret` — las tres en esa fila |
| Eventos de webhook | 2, ambos `COMPLETE`, con `dedupe_key` distinto |
| Config e-CF | `provider = ALANUBE`, `environment = SANDBOX`, `certification_status = NOT_STARTED`, `production_enabled = false` |
| Documentos electrónicos | 0 |
| Banderas | `DOSA_WEBHOOK_ENABLED=true`, `DOSA_EMISSION_ENABLED=false`, `DOSA_PRODUCTION_EMISSION_ENABLED=false` |

El `ALANUBE` es **dato histórico**: la fila se creó el 2026-11-03, antes de la
migración `20261105223000_ecf_provider_default_dosa`, que cambió el valor por
defecto de la columna a `DOSA`. El código no lo escribe así (`ensureConfig` crea
`DOSA` y `buildConfigUpdate` rechaza otro proveedor). No se corrigió por
inferencia: requiere un paso autorizado (§7).

## 1. Revisión e integración del código

```powershell
cd 'C:\src\fullpos-ecf-dosa-creds-split'
git log --oneline aad1e7b9..HEAD
git diff --stat aad1e7b9..HEAD
```

Esperado: los tres commits de credenciales/multiempresa más los de esta fase
(vigilancia de incidencias, códigos HTTP del webhook, sincronización de estado,
fixtures de pruebas) y **una sola migración aditiva**
(`20261107120000_ecf_dosa_incidents`).

Antes del merge, repetir las puertas sobre la rama:

```powershell
npm --workspace apps/api test          # esperado: 0 fallos
npm run api:build                      # esperado: exit 0
npx prisma validate                    # desde apps/api
```

El merge a `production-main` **no** forma parte de este runbook: lo autoriza el
responsable. No se hace push desde aquí.

## 2. Respaldo y verificación de restauración

```powershell
# En el servidor, con el contenedor de base de datos
docker exec daleventapos_database pg_dump -U postgres -Fc -d <bd> > dosa_pre_deploy.dump
docker exec daleventapos_database pg_restore -l /tmp/dosa_pre_deploy.dump | Measure-Object -Line
```

Criterio de éxito: el respaldo existe, pesa más de 0 y `pg_restore -l` lista
objetos. **Probar la restauración en una base desechable**, no sobre producción:

```powershell
docker run -d --name dosa-restore-check -e POSTGRES_PASSWORD=<local> -p 127.0.0.1:55499:5432 postgres:17
docker cp dosa_pre_deploy.dump dosa-restore-check:/tmp/
docker exec dosa-restore-check pg_restore -U postgres -d <bd_check> /tmp/dosa_pre_deploy.dump
docker exec dosa-restore-check psql -U postgres -d <bd_check> -c "SELECT count(*) FROM ecf_dosa_company_credentials"
```

Criterio: el recuento coincide con el de producción. Sin esto, no se avanza.

## 3. Despliegue

Migración **aditiva** únicamente (crea `ecf_dosa_incidents`; no altera nada
existente):

```powershell
# Ventana de mantenimiento corta. Con autorización explícita:
npx prisma migrate deploy
```

Después, los servicios necesarios y en este orden:

```powershell
docker service update --image <imagen-nueva> --update-order start-first daleventapos_backend
docker service ps daleventapos_backend --filter desired-state=running
```

`daleventapos_pwa` **no** necesita redespliegue: no se tocó Flutter.

Variables a revisar (no se cambian valores, solo se confirma su presencia):

```text
DOSA_CREDENTIALS_MASTER_KEY      presente y con 32 bytes en base64
DOSA_WEBHOOK_SIGNATURE_STRATEGY  HMAC_SHA256_TIMESTAMPED
DOSA_WEBHOOK_SECRET              presente
DOSA_INCIDENT_MONITOR_ENABLED    true (nuevo, opcional)
DOSA_EMISSION_ENABLED            false
DOSA_PRODUCTION_EMISSION_ENABLED false
```

## 4. Comprobaciones posteriores (sin exponer secretos)

```powershell
# Salud
curl.exe -s -o NUL -w "%{http_code}" https://<host>/api/health

# Webhook: la ruta existe y rechaza lo que debe rechazar
#   sin firma  -> 401 (antes 503)
curl.exe -s -o NUL -w "%{http_code}" -X POST https://<host>/api/webhook/dosa -H "content-type: application/json" -d "{}"
```

Criterios:

| Comprobación | Esperado |
| --- | --- |
| `/api/health` | `200` |
| Webhook sin firma | `401` con `code = ECF_DOSA_WEBHOOK_BLOCKED` |
| Webhook con `DOSA_WEBHOOK_ENABLED=false` | `503` `ENDPOINT_DISABLED` |
| Tabla de incidencias | existe y está vacía o con lo detectado |
| Credenciales de FULLTECH | **siguen intactas** (1 fila, `PENDING_CONFIRMATION`) |
| Aislamiento | una consulta de incidencias nunca devuelve filas de otra empresa |

Verificación sin imprimir valores:

```sql
SELECT company_id, rnc, environment, status,
       (present->>'apiKeyTest') AS tiene_test,
       (present->>'apiKeyProduccion') AS tiene_produccion
  FROM ecf_dosa_company_credentials;
```

Nunca `SELECT ciphertext`, `iv`, `auth_tag` ni `fingerprint` completos en un log.

## 5. Reclasificación TEST de FULLTECH — **dry-run**

La herramienta no escribe nada sin `--apply`, e imprime solo ambientes, estados y
huellas truncadas.

```powershell
$env:DOSA_CREDENTIALS_MASTER_KEY = <la del entorno>   # no se imprime
npm run dosa:credentials:reclassify -- `
  --company-id 165e3fca-6225-479b-8805-d2205f10536c `
  --rnc 133080206
```

Resultado esperado: describe la fila `production` actual y el destino `test`, sin
escribir. Si informa `blockedReason`, se detiene aquí.

## 6. Verificar que PRODUCCIÓN conserva lo suyo

Antes de aplicar, confirmar que la fila `production` mantiene hoy **las dos**
claves y que el paso §5 no propone borrar nada:

- La reclasificación **crea/mueve** la clave TEST a `environment = test`.
- La fila de producción **no se elimina** en ningún caso.
- Si la herramienta propusiera eliminar la fila original, es un fallo: detenerse.

## 7. Reclasificación real y corrección del proveedor — **solo con autorización expresa**

```powershell
$env:DOSA_CREDENTIALS_RECLASSIFY = "CONFIRM"
$env:DOSA_CREDENTIALS_MASTER_KEY = <la del entorno>
npm run dosa:credentials:reclassify -- `
  --company-id 165e3fca-6225-479b-8805-d2205f10536c `
  --rnc 133080206 --apply
```

Corrección del `provider` histórico (dato, no esquema) — **decisión aparte**, con
su propia autorización:

```sql
-- Solo si el responsable lo autoriza:
UPDATE ecf_company_configurations
   SET provider = 'DOSA', updated_at = NOW()
 WHERE company_id = '165e3fca-6225-479b-8805-d2205f10536c'
   AND provider = 'ALANUBE';
```

No se cambia `certification_status` a mano. Si hay evidencia de un evento
completo, la próxima actualización de una etapa lo promoverá a
`READY_FOR_REVIEW` por sí sola; llegar a `AUTHORIZED_SANDBOX` o
`PRODUCTION_READY` exige el acto humano documentado que ya existe.

## 8. Confirmar estados sin exponer secretos

```sql
SELECT environment, status, updated_at,
       left(fingerprint, 8) AS huella_8
  FROM ecf_dosa_company_credentials
 WHERE company_id = '165e3fca-6225-479b-8805-d2205f10536c'
 ORDER BY environment;
```

Esperado tras §7: dos filas, `production` y `test`, ambas `PENDING_CONFIRMATION`,
con huellas distintas. Ninguna se activa: `ACTIVE` es un acto humano aparte.

## 9. Reversión

**Código** (segundos):

```powershell
docker service rollback daleventapos_backend
```

o `git revert` de los commits y volver a desplegar la imagen anterior.

**Datos**:

- La migración es **aditiva**: revertir el código deja la tabla
  `ecf_dosa_incidents` sin uso. No es necesario borrarla; si se hace, es
  `DROP TABLE` y requiere autorización.
- Reclasificación: **no se borra** la fila `test`. Se marca `REVOKED`:

```sql
UPDATE ecf_dosa_company_credentials
   SET status = 'REVOKED', updated_at = NOW()
 WHERE company_id = '165e3fca-6225-479b-8805-d2205f10536c'
   AND environment = 'test';
```

- Restauración completa solo si el respaldo de §2 se verificó: `pg_restore` sobre
  una base nueva y conmutación, nunca `pg_restore --clean` sobre la viva sin
  ventana.

## 10. Vigilancia posterior

Durante las primeras 24 h:

```powershell
docker service logs --since 1h daleventapos_backend | Select-String "Incidencias DOSA|webhook/dosa"
```

Qué mirar:

| Señal | Significado | Acción |
| --- | --- | --- |
| `Incidencias DOSA: nuevas=0 … errores=0` | Nada pendiente | Nada |
| `nuevas>0` de tipo `CREDENTIAL_CONFLICT_REVIEW` | Llegó material distinto | Revisar en la bandeja antes de rotar |
| `escaladas>0` | Se agotaron los reintentos automáticos | Revisión humana |
| `errores>0` | Fallo de acceso a datos | Revisar log con `company_id` |
| Webhooks con `401` | Firma inválida real | No subir la tolerancia: revisar secreto/unidad de `t` |
| Webhooks con `503` | Receptor mal configurado | Revisar `DOSA_WEBHOOK_SECRET` |

Y la comprobación que no se puede delegar: **la emisión sigue bloqueada**
(`DOSA_EMISSION_ENABLED=false` y `DOSA_PRODUCTION_EMISSION_ENABLED=false`) hasta
que exista autorización fiscal explícita.
