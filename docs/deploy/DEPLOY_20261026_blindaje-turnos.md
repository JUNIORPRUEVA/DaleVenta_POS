# Registro de despliegue — blindaje financiero de turnos (2026-10-26)

## Identidad

| Elemento | Valor |
| --- | --- |
| Rama oficial de despliegue | `production-main` (contiene a `main`) |
| SHA original de `production-main` | `c123e211b0571bcad9a4e7d89e4bdf4ba251f4e7` |
| SHA del merge (imagen desplegada) | `5ee95e8765513a78374c03a2f11b01b9591cc3fd` |
| SHA de referencia `main` | `50254e2354a7e6d77d031b83c6f5c07412abd85d` (ancestro de `production-main`) |
| Rama del blindaje integrada | `agent/antonio-turnos-fix` @ `7eb77805` (código aprobado `700553bc`) |
| Referencia de recuperación Git | `backup/pre-cash-turnos-20261026` → `c123e211` |

## Integración

- Worktree limpio `C:/src/fullpos-main-integration` creado desde `origin/production-main`.
- `git merge --no-ff agent/antonio-turnos-fix` → **0 conflictos**. `installer/setup.iss` se fusionó automáticamente
  conservando *ambos* bloques (`MyAppUatMayoreo` de producción y `MyAppUat` del blindaje).
- Resultado: **34 archivos, +4395/−95, 0 archivos eliminados**.
- `apps/api` resultante es **byte-idéntico** al árbol validado (`git diff 53aa9bb1..700553bc -- apps/api` ==
  `git diff 53aa9bb1..HEAD -- apps/api`), es decir, el backend en producción es exactamente el código probado.
- Migraciones: 32 locales, la última sigue siendo `20261014153000_offline_operation_payload_hash`. **Sin migraciones nuevas.**
- `package.json`, `Dockerfile` y `tsconfig.build.json` sin cambios.

## Pruebas ejecutadas sobre el árbol integrado

```
npm run api:build                → exit 0
npm --workspace apps/api test    → 797 passed · 8 skipped · 0 failed (78 suites)
flutter analyze                  → No issues found!
flutter test                     → 1395 passed · 7 skipped
UAT PostgreSQL aislado           → run-uat 64/64 · preprod 27/27 · fase5 31/31
                                   fase4 15/15 · fase6 26/26  → 163/163 · 0 fallos
Contenedor (imagen de main)      → 137/137 · /health 200 tras reinicio ×4
```

## Artefacto desplegado

| Dato | Valor |
| --- | --- |
| Tag | `fullpos/daleventapos-backend:main-cash-turnos-5ee95e87` |
| Id local (build) | `sha256:4d02555b32c276fb1b96c6bdbb698e7251f69d414c7388ef42626b8e2f109f6f` |
| Id en el host (tras `docker load`) | `sha256:b6349debc7ecb159536415dd8c63178f2dbed431b266c9eb561a6e83826a7e1f` |
| Archivo transferido | `/root/images/main-5ee95e87.tar` · 152.7 MB · sha256 `61937263…4C65E` |
| Contenido | `/app/dist` huella `16e67b0acf2a028d8c313b0dabb1ec67764980677618ef509f212397dbec6d5c` **idéntica** en local y host |
| OCI labels | `revision=5ee95e8765513a78374c03a2f11b01b9591cc3fd`, `version=1.0.6+145-main-cash-turnos`, `baseline=offline-144` |
| Plataforma | `linux/amd64` · Node 20 |
| Rollback | `fullpos/daleventapos-backend:offline-144` (`sha256:e2884dae…205b`) presente en el host |

El Id cambia al empaquetar con `docker save`/`load` (repacking del manifiesto); por eso la verificación se hizo por
huella de contenido y por el label `revision`, no solo por el Id.

## Respaldo (antes del despliegue)

```
/root/backups/fullpos-cash-turnos-20261026T173118Z/
  daleventa-pre-cash-turnos-20261026T173118Z.dump   6 617 050 bytes
  .sha256   707b209d511db43704ccc6db25565b347ec916d2c6548fe9dc91a9cdd5be723f
  toc.txt   1198 entradas verificadas con pg_restore --list (contenedor postgres:17 aparte)
  METADATA.txt
copia fuera del servidor: C:\src\fullpos-uat-antonio\prod-backups\ (mismo tamaño y SHA256)
```

Conteos financieros antes/después: turnos_abiertos 9/9 · turnos_total 269/269 · ventas_total 11 757/11 757 ·
cierre_efectivo_total 3 146 585.50/3 146 585.50 · migraciones aplicadas 172/172.

## Despliegue

`docker service update --image fullpos/daleventapos-backend:main-cash-turnos-5ee95e87 --no-resolve-image daleventapos_backend`

- Estrategia respetada: `start-first`, `parallelism 1`, `failure_action=rollback`, `monitor 60s` (una sola réplica;
  solape ≤60 s entre versiones, ambas compatibles con el mismo esquema y con los mismos flags).
- Configuración intacta: `FINANCIAL_LEGACY_COMPAT=true`, `CASH_CLOSE_LEGACY_COMPAT=false`, `RUN_MIGRATIONS=false`,
  `PRODUCTS_SOURCE=LOCAL`, `REDIS_ENABLED=false`.
- Resultado: `update=completed`, tarea `Running`, tarea anterior `Shutdown`. Sin rollback.

## Comprobaciones posdespliegue

| Comprobación | Resultado |
| --- | --- |
| `/health` público (Traefik) | **200** `{"status":"ok"}` |
| `/cash/state` sin token | 401 (routing y auth vivos) |
| `POST /cash/sessions/:id/admin-close` sin token | 401 → **ruta nueva presente** (no 404) |
| `GET /cash/sessions/stale` sin token | 401 → **ruta nueva presente** |
| Errores 5xx / `ExceptionsHandler` / `P2034` en el log | 0 |
| Conteos financieros | sin cambios |
| Migraciones aplicadas | 172 (sin cambios) |
| Aislamiento multiempresa | sin cambios en el código de scoping (solo consultas `requireTenant`) |

## Regularización pendiente (no ejecutada: requiere conteo del negocio)

Ver `FASE7-regularizacion-turnos-vencidos.md`. Los 7 negocios con turno vencido siguen igual; sus usuarios pueden
cerrar y reabrir desde la app (autoservicio) o soporte puede usar el nuevo endpoint de cierre administrativo con el
conteo declarado por el negocio.
