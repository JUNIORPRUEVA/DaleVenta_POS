# Plan de despliegue e-CF en producción (para autorización)

Estado: **EJECUTADO el 2026-11-03 con autorización escrita del responsable.**
Esquema migrado, API nueva en producción y portal publicado y cerrado sin ticket.

---

## 0. Ejecución real (2026-11-03)

| Paso | Resultado |
| --- | --- |
| Preflight | 183 aplicadas / 54 en repo / **25 pendientes** / 154 histórico antiguo → GO |
| Backup | `daleventa-pre-ecf-20261103-132756.dump` · 7.168.686 bytes · **1.311 entradas** verificadas con `pg_restore -l` (dentro del contenedor y sobre la copia del host) |
| Rollback fijado | imagen anterior etiquetada `daleventapos-prod-api:pre-ecf-20261103-132814` |
| Migraciones | **25 de 25 aplicadas** desde contenedor desechable de la imagen candidata, con `PGOPTIONS='-c lock_timeout=5s'` · exit 0 |
| Esquema | 24 tablas `ecf_*` · columna `SaleItem.item_type_snapshot` · **208** migraciones vigentes · **0 fallidas** |
| e-CF | `ecf_company_configurations.enabled = true` → **0 empresas** (condición 4) |
| API | imagen `daleventapos-prod-api:1.0.7-ecf-pilot` en `daleventapos_backend`, `start-first` + rollback automático · `/health` 200 |
| Piloto | `ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-6225-479b-8805-d2205f10536c` (solo FULLTECH SRL) |
| Portal | `https://fullposcloud.fulltechrd.com/ecf/certificacion/` → 200 · sin ticket muestra «Falta el enlace de acceso» |
| Regresión | 0 errores 5xx en 10 min · PWA 200 · endpoints e-CF 401 sin sesión |

**Incidencia previa corregida:** la imagen no compilaba (`TS7006 bag/cert`).
Causa: `@types/node-forge` estaba solo en el `package.json` raíz y la imagen
construye con contexto `apps/api`. Se declaró en `apps/api/package.json`
(devDependency, sin efecto en runtime) y se actualizó el lockfile.

**Pendiente conocido:** la PWA en producción es anterior al módulo e-CF, así que
todavía **no tiene** el botón «Iniciar o continuar certificación». Para que el
administrador de FULLTECH abra el portal desde la app hace falta publicar la
versión de Flutter con ese botón (afecta a todos los clientes ⇒ requiere
autorización propia, condición 6). Mientras tanto el portal solo se abre con un
ticket emitido por la API.

---

## 1. Reconciliación de migraciones (183 vs 54)

| Dato | Valor |
| --- | --- |
| Filas en `_prisma_migrations` de producción | **185** |
| Terminadas y vigentes | **183** |
| Revertidas intencionadamente (`rolled_back_at`) | **2** |
| Directorios en `apps/api/prisma/migrations` | **54** |
| De esos 54, ya aplicados en producción | **29** |
| De esos 54, pendientes | **25** |
| Nombres en producción que ya no están en el repo | **154** |

**Por qué 183 > 54.** El repo se consolidó: 154 migraciones antiguas se
conservaron en la base (sus efectos siguen ahí) pero sus carpetas ya no existen
en `prisma/migrations`. No es un conflicto: `prisma migrate deploy` solo actúa
sobre las carpetas nuevas y **no toca el historial**.

**Checksums.** Comparé SHA-256 de los 29 ficheros comunes contra los registrados:
5 coincidían byte a byte y 24 no. Al normalizar fin de línea (CRLF del checkout de
Windows → LF) **los 29 coinciden exactamente**. Conclusión: **no hay drift real**,
solo diferencia de saltos de línea. No se modificó `_prisma_migrations`.

**Migraciones revertidas.** `20260814232000_open_sales_ticket_states` y
`20260818190000_phase6_baseline` tienen una fila con `rolled_back_at`. Ambas
aparecen además como aplicadas, así que son historia normal de un reintento y
**no bloquean** (`P3009` solo lo producen las que quedan sin terminar y sin
revertir, y aquí no hay ninguna).

**Procedimiento oficial.** `prisma migrate deploy` aplica únicamente lo pendiente,
advierte de los nombres que sobran en la base y **no exige** que el historial
coincida. Es seguro avanzar sin alterar nada existente.

---

## 2. Ensayo aislado (realizado)

Entorno: contenedor PostgreSQL **17** propio (`fullpos_ecf_rehearsal_pg`,
`127.0.0.1:56702`), independiente de producción y del contenedor de pruebas.

Metodología, sin datos de clientes:

1. `pg_dump --schema-only --no-owner --no-acl` de producción → 537 KB, **0
   errores** de restauración, **139 tablas**.
2. Se replicó el historial: **183 filas** en `_prisma_migrations` (solo nombre,
   checksum y estado; **ni un dato de cliente**).
3. `prisma migrate status` → reproduce exactamente la situación de producción
   (54 locales, último común `20261008120000_service_order_soft_delete_tombstones`).
4. `prisma migrate deploy`.

**Resultado:**

```
All migrations have been successfully applied.
DURACION_MS = 1893   (25 migraciones)
_prisma_migrations : 208 filas · 0 fallidas
Tablas ecf_* : 24 · Claves foráneas : 31 · Índices : 93
ecf_certification_portal_tickets / _sessions : creadas
"SaleItem" : 40 columnas, + item_type_snapshot (nullable, sin default)
```

**`SaleItem` bajo volumen** (proxy estructural: clon con las mismas columnas,
200.000 filas — 10× producción, que tiene 18.546):

```
ALTER TABLE ... ADD COLUMN item_type_snapshot product_item_type;
   Tiempo: 3,066 ms   · valores rellenados: 0   · filas reescritas: 0
```

Columna nullable sin default ⇒ PostgreSQL 11+ solo cambia el catálogo: no
reescribe la tabla. El bloqueo `ACCESS EXCLUSIVE` existe pero dura milisegundos.
El tipo `product_item_type` **ya existe** en producción, así que la dependencia
está satisfecha.

**Lo que el ensayo NO reproduce (declarado):** datos reales de clientes (no se
copiaron, por seguridad) y concurrencia de escritura real durante las
migraciones. Con 18.546 filas y DDL aditivo, el riesgo residual es bajo, pero no
es un PASS sobre volumen real de escritura concurrente.

### 2.b Bloqueos bajo concurrencia (medido después del ensayo)

Prueba adicional sobre un clon de 50.000 filas con una transacción de escritura
abierta en paralelo:

| Escenario | Resultado |
| --- | --- |
| `ALTER` sin nadie escribiendo | **3,066 ms** (200k filas) |
| `ALTER` con una escritura en vuelo de 4 s | **esperó 3.255 ms** y luego aplicó |
| `SET lock_timeout='2s'` con la misma escritura | **abortó en 2.103 ms** con `canceling statement due to lock timeout` |

**Lectura:** el `ALTER` toma `ACCESS EXCLUSIVE` y **espera** a que terminen las
transacciones vivas. Sin límite, una transacción larga puede hacer que el DDL (y
las escrituras que se encolan detrás) queden esperando. Con `lock_timeout` falla
rápido y **no aplica nada**, lo que permite reintentar en un momento tranquilo.

**Mitigación adoptada en el procedimiento:** ejecutar `prisma migrate deploy` con
`PGOPTIONS='-c lock_timeout=5s'`. Si se agota, se reintenta; nunca se queda
colgado con el POS esperando.


---

## 3. Compatibilidad con clientes actuales

**Cambios fuera de `ecf/` en la rama (revisados uno a uno):**

| Archivo | Cambio | Impacto |
| --- | --- | --- |
| `sales.service.ts` | +13 líneas: guarda `itemTypeSnapshot` del producto | Aditivo; no altera totales, NCF, impuestos ni inventario |
| `settings.service.ts` | añade `ecfEnabled` a la respuesta | Campo nuevo; los clientes antiguos lo ignoran |
| `mis_ventas_screen.dart` | widget `EcfPrepareAction` | Se oculta solo si e-CF está off o falta permiso |
| `account_menu_screens.dart` | UI de configuración e-CF | Solo visible con e-CF activado |
| `app_navigation.dart` | entrada de menú e-CF | Condicionada a `ecfEnabled` |

**Prueba de compatibilidad real sobre el esquema migrado:** una venta tradicional
insertada **sin** mencionar la columna nueva funciona y deja
`item_type_snapshot = NULL` (transacción revertida). Es decir, una versión
antigua del cliente sigue escribiendo igual.

**Suites ejecutadas:** `src/sales src/cash src/inventory src/clients` →
**22 suites, 199 pruebas, 0 fallos**.

**Orden obligatorio:** **primero migraciones, después API.** El `sales.service.ts`
nuevo escribe `itemTypeSnapshot`; contra una base sin la columna fallaría. Al
revés (migración sin API nueva) no se rompe nada: la columna queda a NULL.

---

## 4. Piloto (revalidado)

```
Allowlist vacía (valor por defecto)            → TICKET=403  (portal cerrado)
Allowlist = empresa piloto                     → TICKET=201 → EXCHANGE=201 → CONTEXT=200
Otra empresa (admin con todos sus permisos)    → TICKET=403
Sin ticket en la URL                           → 401 / mensaje de portal cerrado
```

`jest src/ecf/portal` → **18 pruebas, 0 fallos**. Preparación y emisión siguen
separadas: el contexto devuelve `ecfEnabled=false` y no existe ninguna ruta del
portal que active e-CF o envíe nada a la DGII.

---

## 5. Inventario exacto de lo que se publica

**Base de datos** — 25 migraciones, en este orden:
`20261014120000` … `20261103210000` (lista completa en
`docs/ECF_CERTIFICATION_PILOT.md` §3), todas aditivas; la única que toca una tabla
existente es `sale_item_type_snapshot`.

**Backend** (`apps/api`): imagen nueva con los módulos `src/ecf/**` (incluye
`src/ecf/portal/**`), `src/app.module.ts`, `src/main.ts`,
`src/common/redact-secrets.ts`, `src/common/uat-safety.ts`,
`src/sales/sales.service.ts`, `src/settings/settings.service.ts`, `prisma/schema.prisma`
y la migración nueva. **Ningún endpoint existente cambia de contrato.**

**Portal**: un único archivo estático
`/usr/share/nginx/html/ecf/certificacion/index.html` dentro de `daleventapos_pwa`.

**Flutter**: nada obligatorio para el piloto. La PWA productiva no se toca; la
acción «Iniciar o continuar certificación» llegará con el próximo release normal
de la app.

---

## 6. Procedimiento de ejecución (cuando se autorice)

Herramientas ya preparadas (no ejecutan nada por sí solas):

```powershell
# 1) Preflight: SOLO LECTURA. Recalcula pendientes contra produccion y aborta
#    si no son exactamente 25. Ejecutado el 2026-11-03 -> GO.
pwsh -File scripts/ops/ecf-migrations-preflight.ps1

# 2) Plan del despliegue (dry-run, no toca nada)
pwsh -File scripts/ops/ecf-deploy-migrations.ps1

# 3)[solo con autorizacion] backup + migraciones con lock_timeout + verificacion
pwsh -File scripts/ops/ecf-deploy-migrations.ps1 -Apply `
  -Authorization "Autorizado por <nombre>, <fecha>. Alcance: migraciones 25 + portal."
```

1. **Backup**: `pg_dump -Fc` completo + `pg_restore --list` para validar que el
   dump se puede leer. Guardar fuera del contenedor.
2. **Ventana**: mínimo tráfico. El ensayo tardó 1,9 s, pero el backup y la
   verificación son lo que ocupa tiempo.
3. **Migraciones**: `npx prisma migrate deploy` con el listado de pendientes
   verificado **antes** (deben ser exactamente 25; si aparece otra, detenerse) y
   con `PGOPTIONS='-c lock_timeout=5s'` para no quedar esperando bloqueos.
4. **Verificación de esquema**: 24 tablas `ecf_*`, la columna nueva en `SaleItem`,
   0 filas fallidas en `_prisma_migrations`.
5. **API**: desplegar la imagen nueva. Health: `/health` 200,
   `/ecf/certification-portal/context` → 401 (ruta viva y cerrada).
6. **Humo funcional**: crear una venta tradicional en un tenant de prueba y
   comprobar que se guarda; abrir caja y cerrarla.
7. **Piloto**: definir `ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-…` y publicar el
   portal; verificar el recorrido y `cert:ready`.

---

## 7. Reversión (sin pérdida de datos)

| Nivel | Acción | Efecto |
| --- | --- | --- |
| Portal | borrar `/usr/share/nginx/html/ecf` | Inmediato, sin tocar la PWA |
| Piloto | vaciar `ECF_PORTAL_PILOT_COMPANY_IDS` | Portal cerrado al instante, sin desplegar |
| API | volver a la imagen anterior por tag | El POS tradicional sigue igual: el esquema nuevo es compatible hacia atrás |
| Migraciones | **no revertir** | Son tablas nuevas vacías + una columna nullable. Revertir el código **no** revierte el esquema, y no hace falta: el código antiguo lo ignora |

**Nunca** `DROP TABLE`/`DROP COLUMN` automático ni `migrate reset`. Si algún día
se decide eliminar, será manual, con backup y con autorización explícita.

---

## 8. Monitoreo y criterio de suspensión

Vigilar durante las primeras 24 h:

- `/health` y tasa de errores 5xx del backend.
- Errores en `POST /sales` y en cierre de caja (los dos flujos que tocan el
  esquema modificado).
- Consultas lentas en `SaleItem` (la tabla más grande).
- Logs de `ecf/certification-portal` (401/403 inesperados).

**Suspender y revertir** (vaciar la allowlist o volver la imagen) si aparece
cualquiera de estos:

- algún cliente no puede registrar ventas o cerrar caja;
- errores 5xx sostenidos por encima de la línea base;
- una empresa distinta de la piloto consigue abrir el portal;
- cualquier indicio de activación de e-CF o de emisión no solicitada.
