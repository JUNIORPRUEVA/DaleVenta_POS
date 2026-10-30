# Runbook — Publicación FullPOS Cloud `1.0.7+150` (autocorrección V2)

Documento operativo. **Nada de esto se ejecutó todavía**: cada paso requiere
autorización explícita del propietario en la tarea en curso.

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

```bash
cd apps/api
npx prisma migrate status        # deben aparecer 2 pendientes
npx prisma migrate deploy
```

| Migración | Efecto |
| --- | --- |
| `20261029190000_sale_reconciliation_obligations` | `CREATE TABLE` + 3 índices |
| `20261029210000_reconciliation_single_active_obligation` | tabla de eventos + 3 columnas + índice único parcial `WHERE status='PENDING'`; un `UPDATE` marca `SUPERSEDED` duplicados existentes (no borra filas) |

Verificación inmediata:

```sql
SELECT count(*) FROM sale_reconciliation_obligations;
SELECT max(c) FROM (
  SELECT count(*) c FROM sale_reconciliation_obligations
   WHERE status='PENDING' GROUP BY company_id, client_request_id
) x;   -- debe ser 1 o NULL
```

**Rollback de migraciones: no se revierten.** Las tablas quedan sin uso y ningún
código antiguo las consulta. Borrarlas destruiría evidencia financiera: prohibido.

---

## 3. Despliegue backend-first + rollback

```bash
# 3.1 Imagen nueva (mismo backend, código con las 2 migraciones)
docker service update --image <registry>/fullpos-api:1.0.7-150 --update-order start-first fullpos_api
docker service ps fullpos_api --filter desired-state=running

# 3.2 Rollback si falla
docker service rollback fullpos_api
```

El backend va **primero**: un cliente 150 contra un backend viejo recibe 404 al
declarar (la declaración queda en cola, visible y reintentable, sin perderse).

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
