# FINAL CUTOVER COMMANDS — Cafeteria la bomba
**FullPOS Local (SQLite) → FullPOS Cloud · ejecución autorizada por separado**

Marca de cada paso: **[READ ONLY]** · **[WRITE OPERATION]**
Nunca escribas credenciales en este archivo ni en el repositorio: expórtalas en tu propia terminal.

---

## 0. Preparación (una sola vez, en tu terminal)

```powershell
Set-Location 'C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS\apps\api'

# URL real de producción (credenciales SOLO en tu sesión; nunca en un archivo del repo)
$env:MIGRATION_DATABASE_URL = 'postgresql://<usuario-prod>:<password>@127.0.0.1:15432/daleventa'

# Constantes congeladas
$SHA   = 'A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA'
$TOKEN = 'CUTOVER:f3651f62-be10-41aa-bde7-663cf990eae8:A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA'
$CO    = 'f3651f62-be10-41aa-bde7-663cf990eae8'
$WH    = 'ffc9ef9b-9157-418d-8aa1-94112278bb68'
$SRC   = 'C:\Users\pc\Documents\fullpods.db'
$KEY   = "$env:USERPROFILE\.ssh\daleventas_codex"
```

### Túnel SSH (ruta verificada) — **[READ ONLY]**, no expone PostgreSQL

```powershell
ssh -i $KEY -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N -L 15432:127.0.0.1:25432 root@31.97.99.70
# en otra terminal:
Test-NetConnection -ComputerName 127.0.0.1 -Port 15432 | Select-Object TcpTestSucceeded   # debe ser True
```
Endpoint interno verificado: el puerto publicado del contenedor `daleventapos_database.1.*`
(`5432/tcp -> 0.0.0.0:25432`, PostgreSQL 17.11). Los IPs de contenedor (10.0.2.8 / 10.11.0.25) **no** son alcanzables desde el host: usar siempre `127.0.0.1:25432` como destino del túnel.

---

## A. GO GATE — **[READ ONLY]**

- [ ] Paquete congelado: `release_artifacts/cafeteria-la-bomba-cutover-<stamp>/` y su `.zip` con SHA256 registrado.
- [ ] Manifest identity fijada: content digest `119D354FE6833D4AD3695BCAC548EC61C311A54E320EC6D02FC2FC4FE650CAA1`.
- [ ] Autorización explícita del cutover en la tarea actual (sin ella: **NO ejecutar F**).
- [ ] Licencia usable (paso D) y fecha < `2026-09-23 16:18:24 UTC`.

## A2. VERIFICACIÓN PRE-VUELO AUTENTICADA — **[READ ONLY]** (obligatoria antes del backup)

Es la única verificación que puede dar GO **antes** de migrar: prueba red, autenticación, metadata viva del servidor,
identidad del tenant, baseline limpio y licencia, con **0 escrituras**.

```powershell
# la credencial se captura SOLO en memoria (nunca se imprime, nunca a disco)
$key = "$env:USERPROFILE\.ssh\daleventas_codex"
$remote = @'
CID=$(docker ps --filter "name=daleventapos_database.1." --format "{{.ID}}" | head -1)
docker exec "$CID" sh -c 'printf "%s\n%s\n%s\n" "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$POSTGRES_DB"'
'@ -replace "`r", ''
$raw = ((($remote | ssh -i $key -o BatchMode=yes root@31.97.99.70 "bash -s") -join "`n") -replace "`r", '')
$lines = @($raw -split "`n" | Where-Object { $_ -ne '' })
$env:MIGRATION_DATABASE_URL = 'postgresql://' + $lines[0] + ':' + [uri]::EscapeDataString($lines[1]) + '@127.0.0.1:15432/' + $lines[2]

npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts `
  --verify-preflight --environment=production --production-via-ssh-tunnel --ssh-tunnel-local-port=15432 `
  --database-url=$env:MIGRATION_DATABASE_URL `
  --target-company-id=$CO --target-warehouse-id=$WH `
  --source=$SRC --source-sha256=$SHA `
  --confirm-company-name="Cafeteria la bomba" --confirm-production-cutover=$TOKEN --confirm-write

# limpieza inmediata de la credencial
Remove-Item Env:\MIGRATION_DATABASE_URL -ErrorAction SilentlyContinue
```

Esperado (verificado el 2026-09-16): `Veredicto : GO` · `Servidor : 172.18.0.7/32:5432` · `Baseline … → FRESH` ·
`Licencia : ACTIVE/STANDARD/TRIAL · trialEndsAt 2026-09-23T16:18:24.380Z · usable=true · maxProducts 100 (en uso 0)` ·
`Checks : 15 (0 fallos)` · artefacto `out/preflight-verification.json`.
Si el veredicto no es GO → **STOP** (no hacer el backup, no ejecutar F).

## B. SOURCE SHA VERIFICATION — **[READ ONLY]**

```powershell
(Get-FileHash $SRC -Algorithm SHA256).Hash
# debe imprimir exactamente $SHA; si difiere -> STOP
```

## C. PRODUCTION BASELINE VERIFICATION — **[READ ONLY]**

```powershell
$sql = 'apps\api\scripts\migration\fullpos-legacy\production\production-preflight.sql'   # (desde la raíz del repo)
scp -i $KEY $sql root@31.97.99.70:/tmp/fp-preflight.sql
$run = 'CID=$(docker ps --filter "name=daleventapos_database.1." --format "{{.ID}}" | head -1); docker cp /tmp/fp-preflight.sql "$CID":/tmp/; docker exec "$CID" sh -c ''psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/fp-preflight.sql''; docker exec "$CID" rm -f /tmp/fp-preflight.sql; rm -f /tmp/fp-preflight.sql'
$run | ssh -i $KEY -o BatchMode=yes root@31.97.99.70 'bash -s'
```
Esperado: bloque **B** todo `0` para el tenant; `companies_total = 27`; warehouse/terminal/owner dentro de la empresa.
Si algo del tenant no es 0 → **STOP (NO-GO)**.

## D. LICENSE VERIFICATION — **[READ ONLY]**

Mismo bloque **C** del paso anterior: `license_status = TRIAL`, `trial_ends_at = 2026-09-23 16:18:24+00`, `license_current = t`, `license_blocked_at` vacío.
Si está expirada o bloqueada → **STOP (NO-GO)**.
(Tras el cutover: `countBillableProducts = 87 / maxProducts = 100`.)

## E. BACKUP + SHA + VERIFY — **[WRITE OPERATION]**

Crea un archivo en el host (no modifica la base). Script: `production/production-backup-plan.sh`.

```bash
# en el host, con el script copiado a /root/fullpos-cutover-backup.sh
bash /root/fullpos-cutover-backup.sh dump      # pg_dump -Fc -> /root/daleventas-backups/daleventa_before_cafeteria_labomba_<UTC>.dump (chmod 600 + .sha256)
bash /root/fullpos-cutover-backup.sh verify    # pg_restore --list (parsea el archivo) + sha256sum
bash /root/fullpos-cutover-backup.sh list
```
Requisitos confirmados: `pg_dump`/`pg_restore` presentes; PGDATA 320 MB; 13 GB libres; el dump se copia **fuera** del contenedor.
No continuar si el dump o su verificación fallan.

## F. EXECUTE MIGRATION — **[WRITE OPERATION]** ⚠️

```powershell
npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts `
  --execute --environment=production --production-via-ssh-tunnel `
  --database-url=$env:MIGRATION_DATABASE_URL `
  --target-company-id=$CO --target-warehouse-id=$WH `
  --source=$SRC --source-sha256=$SHA `
  --confirm-company-name="Cafeteria la bomba" `
  --confirm-production-cutover=$TOKEN `
  --confirm-write
```
Esperado: `IMPORTED` · products 91 · warehouseStocks 87 · shifts 50 · sales 7179 · saleItems 9746 · `Reconciliación DB: GO`.
Si aborta: no se escribió nada (transacción única). Si la reconciliación post-escritura no es GO → ir a **J (ROLLBACK)**.

## G. VERIFY (post-escritura, mismos guards) — **[READ ONLY]**

⚠️ Este `--verify` exige que el conjunto importado YA exista (91 productos / 7 179 ventas). Ejecutado **antes** de
migrar aborta por diseño con `VERIFY_SAMPLE_MISMATCH` (la autenticación y los guards sí pasan). Para el gate
pre-migración usar **A2** (`--verify-preflight`).

```powershell
npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts `
  --verify --environment=production --production-via-ssh-tunnel `
  --database-url=$env:MIGRATION_DATABASE_URL `
  --target-company-id=$CO --target-warehouse-id=$WH `
  --source=$SRC --source-sha256=$SHA `
  --confirm-company-name="Cafeteria la bomba" --confirm-production-cutover=$TOKEN --confirm-write
```
Esperado: `Veredicto : GO`, estado 91/87/4 · 87 stocks · 50 turnos · 7179 ventas · 9746 líneas, y `destination-verification.json` en `out/`.
Si aparece `PRODUCTION_TUNNEL_UNVERIFIED` → **STOP**: el túnel no se está viendo como producción; no continuar.

## H. PRODUCTION RECONCILIATION SQL — **[READ ONLY]**

```powershell
scp -i $KEY 'apps\api\scripts\migration\fullpos-legacy\production\production-reconciliation.sql' root@31.97.99.70:/tmp/fp-recon.sql
$run2 = 'CID=$(docker ps --filter "name=daleventapos_database.1." --format "{{.ID}}" | head -1); docker cp /tmp/fp-recon.sql "$CID":/tmp/; docker exec "$CID" sh -c ''psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/fp-recon.sql''; docker exec "$CID" rm -f /tmp/fp-recon.sql; rm -f /tmp/fp-recon.sql'
$run2 | ssh -i $KEY -o BatchMode=yes root@31.97.99.70 'bash -s'
```
Esperado: bloques **1-7 y 9 = PASS**, bloque **8 = PASS** (monotónico: otros tenants no pierden filas), bloque 10 con los flags de licencia intactos.

## I. MANUAL APPLICATION CHECKS — **[READ ONLY]**

Los 23 puntos del paquete (`docs/phase5-final-cutover-readiness.md`, §12): login, 87 productos activos, stock 1.557, historial de ventas/turnos, reporte de utilidad, sin clientes, NCF deshabilitado y **una venta nueva de prueba** (paso 20-22: afecta stock actual, no altera snapshots históricos).

## J. GO / ROLLBACK

**GO** si F `IMPORTED` + G `GO` + H PASS + I completo.

**ROLLBACK quirúrgico — [WRITE OPERATION]** (solo ids deterministas de este perfil):
```powershell
npx ts-node -P tsconfig.scripts.json --transpile-only scripts/migrate-fullpos-legacy.ts `
  --rollback --environment=production --production-via-ssh-tunnel `
  --database-url=$env:MIGRATION_DATABASE_URL `
  --target-company-id=$CO --target-warehouse-id=$WH `
  --source=$SRC --source-sha256=$SHA `
  --confirm-company-name="Cafeteria la bomba" --confirm-production-cutover=$TOKEN --confirm-write
```
Borra SaleItem → Sale → CashSession → WarehouseStock → Product (ids del manifest) y deja la base limpia.

**RESTORE COMPLETO (catástrofe) — [WRITE OPERATION]**, solo con la API detenida:
```bash
docker cp /root/daleventas-backups/<dump> <CONTAINER>:/tmp/restore.dump
docker exec -i <CONTAINER> sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner /tmp/restore.dump'
docker exec <CONTAINER> rm -f /tmp/restore.dump
# reiniciar API y repetir H
```
