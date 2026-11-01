# Runbook — Publicación FullPOS Cloud `1.0.7+150` (autocorrección V2)

Documento operativo. **Nada de esto se ejecutó todavía**: cada paso requiere
autorización explícita del propietario en la tarea en curso.

> **Aviso (2026-10-30, posterior a este documento).** Producción ya ejecuta
> Guardian AI (`easypanel/daleventapos/backend:autoenroll-5d8a5f98`, desplegada a
> las 03:35 UTC) con DeepSeek y WhatsApp activos. Por tanto, **el §3 de este
> runbook (despliegue backend con la imagen `1.0.7-150-c0f983b6`) queda
> SUPERSEDED**: esa imagen no contiene Guardian y desplegarla lo eliminaría.
> El despliegue del backend se hace con la imagen integrada del runbook
> `PRODUCTION-1.0.7-151-RUNBOOK.md`. El §1 (respaldo/restauración) y el §2
> (migraciones) siguen siendo válidos; el instalador 150 del §0 sigue siendo el
> artefacto de recuperación, no el de publicación final.

---

## 0. Datos de la release

| Dato | Valor |
| --- | --- |
| Rama destino | `production-main` (`origin/production-main`, hoy `31756a8d`, versión `1.0.6+149` con Guardian AI y la estable 148) |
| Rama de integración verificada | `agent/integrate-recovery-v2-prod`, commit **`c0f983b6`** |
| Versión | `1.0.7+150` (no reutiliza 148; **149 pertenece a la línea de producción actual**, por eso 150) |
| Instalador | `installer/output/FullPOS-Setup-1.0.7-150.exe` — 40.307.275 B |
| SHA256 vigente | **`C0F01AD558955C27F4DB35546B3BE00E45AD8D3A3823AF11B2F9A89F87180288`** |
| Firma | **NotSigned** (no hay certificado Authenticode) |
| Instalador 148 conservado | `releases/windows/stable/1.0.6-148/FullPOS-Setup-1.0.6-148.exe` (R2) — **no se toca** |

### Verificaciones ya ejecutadas sobre `c0f983b6`

| Check | Resultado |
| --- | --- |
| `npx prisma validate` | **válido** |
| `npm run api:build` | **exit 0** |
| `npm --workspace apps/api test` | **112 suites / 1136 tests PASS**, 0 fail |
| `flutter analyze` | **No issues found** |
| `flutter test` | **1523 PASS / 9 skip / 0 FAIL** |
| Guardian intacto | `git diff origin/production-main -- apps/api/src/guardian` **vacío**; `guardianEnabled @default(false)` conservado; las 2 migraciones tienen **0** referencias a Guardian |
| El binario abre | ventana real, `FullPOS Cloud - Sistema de facturacion`, base creada en la raíz aislada |
| Config de producción | `app.so`: `easypanel`×7, `daleventapos-backend`×5, `app-updates`, `/releases/`; `127.0.0.1:4010`=0, `FULLPOS_UAT_PROFILE`=0, `C:\src\`=0 |
| Identidad del instalador | `ProductName=FullPOS`, `FileVersion=1.0.7.150` |

---

## 1. Respaldo de PostgreSQL + restauración de prueba

```bash
# 1.1 Respaldo (solo lectura sobre producción)
TS=$(date +%Y%m%d_%H%M)
pg_dump --format=custom --no-owner --file="fullpos_${TS}.dump" "$PROD_DATABASE_URL"
sha256sum "fullpos_${TS}.dump"

# 1.2 Verificación estructural
pg_restore --list "fullpos_${TS}.dump" | head -n 20
pg_restore --list "fullpos_${TS}.dump" | grep -c 'TABLE DATA'

# 1.3 Restauración de prueba en una base APARTE (nunca en producción)
createdb "$RESTORE_TEST_DB"
pg_restore --no-owner --dbname="$RESTORE_TEST_DB" "fullpos_${TS}.dump"
psql "$RESTORE_TEST_DB" -c 'SELECT count(*) FROM "Sale";'
psql "$RESTORE_TEST_DB" -c 'SELECT count(*) FROM "Company";'
# Comparar con producción ANTES de seguir; si no coincide, NO continuar.

# 1.4 Limpieza
dropdb "$RESTORE_TEST_DB"
```

Criterio de avance: el dump se lista, restaura sin errores y los conteos de
`Sale`, `Company`, `CashSession` e `InventoryMovement` coinciden con producción.

---

## 2. Migraciones (dos, aditivas)

### Estado verificado de producción (2026-10-30 03:00 UTC)

- Base `daleventa` · PostgreSQL 17.11 · 66 MB · contenedor `daleventapos_database.1.…`
- `_prisma_migrations`: **183 filas** = 181 aplicadas + **2 con `rolled_back_at`**
  (`20260814232000_open_sales_ticket_states`, `20260818190000_phase6_baseline`,
  ya resueltas: **no bloquean**).
- Última migración aplicada: `20261028180000_guardian_company_optin`.
- Pendientes según el repo: **exactamente las dos de V2**.
- `RUN_MIGRATIONS=false` en el servicio → la migración **hay que ejecutarla a mano**.

### Deuda histórica aceptada: `20260329140000_add_fifteen_minutes_pending_job`

Existe en producción y no en el repositorio. Fila: checksum `ace03ac6…77b8`,
aplicada 2026-08-07 02:42:39Z, `applied_steps_count = 0`, **no creó ninguna tabla**
(se marcó como aplicada sin ejecutar SQL: migración vacía o `migrate resolve --applied`).

**Tratamiento correcto: no tocarla.**

- `prisma migrate deploy` solo aplica carpetas pendientes; las filas extra se
  informan como *“not found locally”* y no afectan al despliegue.
- Prohibido: borrar la fila, crear una carpeta falsa con ese nombre (falsearía la
  historia), `migrate reset`, o `migrate resolve --rolled-back` sobre ella.
- Si en el futuro se quiere conciliar, se documenta en este runbook; no se altera
  la tabla de migraciones.

### Comando exacto para aplicar las dos migraciones (autorización aparte)

```bash
# 1) URL de la base leída del propio servicio, SIN imprimirla
DU=$(docker service inspect daleventapos_backend \
  --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
  | sed -n 's/^DATABASE_URL=//p')
# 2) red del contenedor de PostgreSQL
DBNET=$(docker inspect "$(docker ps --format '{{.ID}} {{.Names}}' \
  | awk '/daleventapos_database\.1\./ {print $1; exit}')" \
  --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
# 3) aplicar con la IMAGEN NUEVA (que sí contiene las dos carpetas)
docker run --rm --network "$DBNET" -e "DATABASE_URL=$DU" -e RUN_MIGRATIONS=false \
  daleventapos-prod-api:1.0.7-150-c0f983b6 npx prisma migrate deploy
# 4) confirmar
docker run --rm --network "$DBNET" -e "DATABASE_URL=$DU" \
  daleventapos-prod-api:1.0.7-150-c0f983b6 npx prisma migrate status
```

### Verificación posterior (mismos números que en el clon)

```sql
select count(*) from _prisma_migrations where finished_at is not null;          -- 183
select count(*) from information_schema.tables
 where table_name in ('sale_reconciliation_obligations',
                      'sale_reconciliation_declaration_events');                -- 2
select count(*) from "Sale";                 -- 11.828
select count(*) from "SaleItem";             -- 17.884
select count(*) from "Product";              -- 526
select count(*) from inventory_movements;    -- 8.541
select count(*) from cash_sessions;          -- 279
select count(*) from cashbox_daily;          -- 179
select count(*) from information_schema.tables
 where table_name like 'guardian%';          -- 12 (Guardian intacto)
```

| Migración | Efecto |
| --- | --- |
| `20261029190000_sale_reconciliation_obligations` | `CREATE TABLE` + 3 índices |
| `20261029210000_reconciliation_single_active_obligation` | tabla de eventos + 3 columnas + índice único parcial `WHERE status='PENDING'`; un `UPDATE` marca `SUPERSEDED` duplicados existentes (no borra filas) |

La única sentencia `ALTER TABLE` de las dos migraciones apunta a la tabla **nueva**
de la migración 1: ninguna tabla existente (ventas, caja, inventario, Guardian)
se modifica.

---

## 3. Despliegue backend-first + rollback

### Imagen preparada y probada (sin tocar el servicio activo)

| Dato | Valor |
| --- | --- |
| Imagen | `daleventapos-prod-api:1.0.7-150-c0f983b6` |
| Image ID | `sha256:a47a0f94bf58997f4598a9074fbef3072fe2e1c75864cf79864dd2ef3b77aa34` |
| Tamaño | 763 MB |
| Base | `node:20-bookworm-slim` (Dockerfile de `apps/api`) |
| En producción ahora | `easypanel/daleventapos/backend:guardian-tz-05e0761c-20261030T003159Z` (**rollback = esta etiqueta**) |

**Smoke test completo ejecutado en clon local** (misma imagen, misma base restaurada):

| Check | Resultado |
| --- | --- |
| Arranque del contenedor | `healthy`, `Nest application successfully started` |
| `/health` | **200** |
| Migraciones al arrancar (`RUN_MIGRATIONS=true`) | 181 → **183** |
| `tablas_v2` | **2** |
| Datos | Sale 11.828 · SaleItem 17.884 · Product 526 · inventario 8.541 · caja 279 · caja diaria 179 · sesiones 21.061 → **idénticos** |
| Tablas de Guardian | **12** (sin cambios) |
| `/sales/open-tickets` (ruta que usan los 148) | **401** (existe y sigue protegida) |
| `/sales/reconciliation-obligations` (nueva) | **401** (existe) |

### Pasos

```bash
# 3.0 Etiquetar la imagen actual como referencia de rollback (no la borra)
IMG_ACTUAL=$(docker service inspect daleventapos_backend \
  --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
docker image tag "$IMG_ACTUAL" daleventapos-prod-api:rollback-pre-150

# 3.1 Llevar la imagen nueva al servidor (construida en local, NO en el servidor)
#     en el equipo de build:
docker save daleventapos-prod-api:1.0.7-150-c0f983b6 | gzip > api-150.tgz
scp api-150.tgz root@31.97.99.70:/root/
#     en el servidor:
gunzip -c /root/api-150.tgz | docker load

# 3.2 Desplegar (start-first: el servicio no se cae durante el cambio)
docker service update --image daleventapos-prod-api:1.0.7-150-c0f983b6 \
  --update-order start-first --no-resolve-image daleventapos_backend
docker service update --image daleventapos-prod-api:1.0.7-150-c0f983b6 \
  --update-order start-first --no-resolve-image daleventapos_guardian_worker
docker service ps daleventapos_backend --filter desired-state=running

# 3.3 Rollback
docker service rollback daleventapos_backend
docker service rollback daleventapos_guardian_worker
```

Alternativa oficial: push del merge a `production-main` y build desde EasyPanel.
**No recomendada ahora**: el servidor tiene 1 vCPU y 25 contenedores; el `docker build`
(npm install + tsc) puede afectar a los vecinos. La imagen ya está construida y probada.

---

## 4. Comprobaciones inmediatas (clientes 148 deben seguir funcionando)

Ejecutar en los primeros 15 minutos tras el deploy del backend:

| # | Comprobación | Comando / criterio |
| --- | --- | --- |
| 1 | Salud del servicio | `GET /health` → 200 |
| 2 | Login de una empresa real | `POST /auth/login` → 201/200, token válido |
| 3 | Venta 148 (contrato intacto) | `POST /sales` de un POS 148 en piloto → 201, `saleId` |
| 4 | Caja | `GET /cash/state` → 200 con `cashboxToday` |
| 5 | Inventario | `GET /products?page=1&limit=50` → 200 |
| 6 | Reconciliación (nuevo) | `GET /sales/reconciliation-obligations` → 200 (vacío si no hay) |
| 7 | Errores nuevos en logs | `docker service logs fullpos_api --since 15m | grep -iE "error|exception"` sin patrones nuevos |
| 8 | Latencia | p95 de `/sales` sin degradación respecto a la línea base |

Si 1–7 fallan en bloque → `docker service rollback fullpos_api` y detener la
publicación.

---

## 5. Piloto 148 → 150

1. Elegir **1 equipo y 1 empresa piloto** con 148 en uso real (con aviso al cliente).
2. Respaldo local antes de instalar (copiar la carpeta de datos):
   `%ProgramFiles%\DaleVentas POS\databases` completo (`fulltech_offline.db`,
   `-wal`, `-shm`) a una carpeta externa.
3. Ejecutar `FullPOS-Setup-1.0.7-150.exe` (UAC + SmartScreen: «Más información» →
   «Ejecutar de todas formas» por estar sin firmar).
4. Comprobar en el equipo: abre, login, POS, caja abierta, una venta en efectivo
   con ticket, inventario y `Sync` sin pendientes anómalos.
5. Comprobar en la base local que `user_version` sigue en 5 y que
   `offline_sales`, `offline_sale_items`, `offline_sale_payments` e
   `offline_inventory_intents` conservan las filas previas.
6. 24–48 h de observación: ventas, caja, NCF, inventario y arranque sin incidencias.
7. Rollback del piloto: reinstalar `FullPOS-Setup-1.0.6-148.exe` (la base es
   compatible hacia atrás; el esquema no cambió).

---

## 6. Publicación gradual (actualizador)

1. Registrar el release en el canal `stable` con
   `scripts/release/prepare_windows_release.ps1` (requiere token y `-AllowUnsignedProduction`
   o el certificado) y publicar el objeto en
   `releases/windows/stable/1.0.7-150/FullPOS-Setup-1.0.7-150.exe`.
2. Verificar el feed: `GET /app-updates/check?currentVersion=1.0.6&buildNumber=149&channel=stable&platform=windows`
   debe ofrecer `1.0.7-150` con el SHA256 publicado.
3. Olas: **1 equipo piloto → 5 % → 25 % → resto**, con las comprobaciones del §4
   tras cada ola.
4. La 148 permanece publicada y descargable durante toda la ola (rollback = servir
   148 y reinstalar).

---

## 7. Intocables

- Registros históricos de **Siarah**: no se importa nada (`reconciliation:import`
  sigue en dry-run).
- Instalador y carpeta `1.0.6-148` del canal `stable`: no se borran ni se mueven.
- Base local del cliente en este equipo de desarrollo: no se abre ni se modifica.
