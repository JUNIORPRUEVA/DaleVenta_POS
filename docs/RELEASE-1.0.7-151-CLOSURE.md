# Cierre de release `1.0.7+151` — evidencia y publicación preparada

Última actualización: 2026-11-01 (local) / 2026-11-01T16:10Z aprox.

---

## 1. GitHub

| Dato | Valor |
| --- | --- |
| Rama de integración | `agent/guardian-151-release` @ `bc429a6c` (subida a origin) |
| Merge en `production-main` | **`6241aa44`** (`--no-ff`, sin conflictos, sin force push) |
| Etiqueta | **`v1.0.7-151`** (anotada) sobre `6241aa44`, publicada en origin |
| Pull Request | no creado (no hay `gh` CLI ni token en el equipo). URL: `https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/new/agent/guardian-151-release` |
| Contenido verificado en `production-main` | `version: 1.0.7+151` · 2 migraciones V2 · 2 rutas V2 en `sales.controller.ts` · panel Guardian corregido |
| Validaciones previas al merge | `prisma validate` OK · `npm run api:build` exit 0 · `flutter analyze` sin issues · suites verdes sobre este mismo código (API 1186, Flutter 1533 PASS / 9 skip) |
| Secretos | sin `.env` en el diff; solo un nombre de variable y 2 contraseñas sintéticas de UAT |

## 2. Piloto Windows (equipo con la instalación real, antes `1.0.6+148`)

| Check | Resultado |
| --- | --- |
| Instalador | `FullPOS-Setup-1.0.7-151.exe` · 40.314.531 B · SHA256 `06F9C31B3AA47D522F8FBA22A3E9CE4D254250E347C36CFE9D6BDC00F9435F60` |
| Versión instalada | **`1.0.7+151`** · 149 ficheros en la instalación |
| Respaldo previo | `backup-wal-20261101T155700Z` (db + WAL, sin shm) · `backup-20261101T155636Z` · `backup-20261030T181726Z` · todas `integrity_check = ok` |
| Apertura | ventana **«FullPOS Cloud - Sistema de facturacion»**, proceso vivo, ~357 MB |
| Login | `POST /auth/login` **201** + `saveTokens` + `APP_BOOTSTRAP_READY` con `userId=f6a41e76…` y `companyId=165e3fca…` |
| Licencia / sesión | `GET /license` **200** (×11) · `/users/me` 200 · `/settings` 200 |
| Ventas | `GET /sales/open-tickets` **200**; ventas locales: 1 (ya `synced`), **sin duplicados** |
| Caja / turnos | `GET /cash/state` **200** (×3) |
| Inventario | `GET /products?page=1&limit=50` **200** (×2) + `/products/categories` 200 · caché local 488 entradas (antes 475) |
| SQLite / WAL | `integrity_check = ok` · `user_version = 5` · WAL activo (4.210.672 B) |
| Operaciones pendientes | `pending_actions = 0` · ventas offline sin sincronizar `0` · `sale_attempt_audit = 0` · `sale_cart_override = 0` |
| Guardian AI (servidor) | worker 151 con `DIAGNOSIS/ALERTS=true`, DeepSeek y WhatsApp intactos, latido al día |
| Recuperación V2 | API presente y desplegada; **la UI no se abrió**, así que la pantalla no está verificada visualmente (0 obligaciones pendientes en producción) |
| Actualizador | endpoint operativo; en esta sesión el cliente no consultó `/app-updates/check` |

### Efecto conocido de la actualización (documentar al cliente)

`storage_scope changed; clearing local auth session` → la app **cierra la sesión** al
cambiar de versión. No se pierde ningún dato, pero el usuario **debe volver a iniciar
sesión** la primera vez. Por eso el empleado necesita su contraseña a mano.

### Investigación de `user_version` (resuelta, sin tocar datos)

| Observación | Explicación |
| --- | --- |
| Lecturas `mode=ro` del `fulltech_offline.db` en `C:\Program Files\DaleVentas POS\databases` devolvían `3`; los respaldos del 30-10 devolvían `5` | El `PRAGMA user_version = 5` de la última migración vive en el `-wal`; una conexión de solo lectura que no puede construir el índice WAL (por `-shm` obsoleto) lee la cabecera previa al checkpoint (3) mientras las tablas ya están creadas |
| Estado real | **`user_version = 5`** con las 8 tablas (`cache_entries`, `pending_actions`, `offline_sales`, `offline_sale_items`, `offline_sale_payments`, `offline_inventory_intents`, `sale_attempt_audit`, `sale_cart_override`) e `integrity_check = ok` |
| Prueba | tras la sesión de la app (que hizo checkpoint) la misma lectura devuelve **5**; ninguna migración se revirtió |
| Seguridad extra | todas las migraciones usan `CREATE TABLE/INDEX IF NOT EXISTS` → re-ejecutarlas es idempotente |
| Acciones sobre datos | **ninguna**: no se restauró ni modificó nada manualmente |

---

## 3. Publicación `1.0.7+151` — PREPARADA, no ejecutada

Estado actual del canal (verificado): build **150 PUBLISHED** (2026-10-30 03:31),
148 y 149 PUBLISHED. El actualizador compara **solo `buildNumber`**, así que 151 lo
supera sin tocar el historial.

### 3.1 Subir el artefacto (requiere credenciales R2 del propietario)

```text
origen : C:\src\fullpos-artifacts\FullPOS-Setup-1.0.7-151.exe
destino: s3://<bucket>/releases/windows/stable/1.0.7-151/FullPOS-Setup-1.0.7-151.exe
tamaño : 40314531
sha256 : 06F9C31B3AA47D522F8FBA22A3E9CE4D254250E347C36CFE9D6BDC00F9435F60
```

Ruta nueva e inmutable: no sobrescribe 148, 149 ni 150.

### 3.2 Registrar la release (una sola fila nueva; no se edita la 150)

```sql
INSERT INTO app_releases (
  id, platform, channel, version, build_number, status,
  file_name, file_size, sha256, download_url, storage_key,
  release_notes, commit_sha, signed, mandatory, published_at, created_at, updated_at
) VALUES (
  gen_random_uuid(), 'WINDOWS', 'STABLE', '1.0.7', 151, 'PUBLISHED',
  'FullPOS-Setup-1.0.7-151.exe', 40314531,
  '06F9C31B3AA47D522F8FBA22A3E9CE4D254250E347C36CFE9D6BDC00F9435F60',
  'https://<public-base>/releases/windows/stable/1.0.7-151/FullPOS-Setup-1.0.7-151.exe',
  'releases/windows/stable/1.0.7-151/FullPOS-Setup-1.0.7-151.exe',
  '["Recuperacion automatica de cobros: si un cobro queda sin confirmar, se declara y se concilia sin perder la venta.","Panel de conciliacion en Caja para revisar cobros pendientes.","Guardian AI: monitoreo tecnico con control y desactivacion desde Ajustes.","Se conservan todos los datos locales y el trabajo offline."]'::jsonb,
  '6241aa442a5294d0792bf5f6143c80d66e7430d2', false, false, now(), now(), now()
);
```

> Ajustar `id`/columnas al esquema real antes de ejecutar (columnas verificadas:
> `platform, channel, version, build_number, status, file_name, published_at`).

### 3.3 Verificación posterior (obligatoria)

| Comprobación | Esperado |
| --- | --- |
| `/api/app-updates/check?…&build=148` | `buildNumber=151` |
| `…&build=149` | `buildNumber=151` |
| `…&build=150` | `buildNumber=151` |
| `…&build=151` | `updateAvailable=false` |
| Instaladores 148/149/150 | siguen accesibles, sin cambios |

### 3.4 Reversión de la publicación (sin borrar nada)

```sql
UPDATE app_releases SET status = 'ARCHIVED' WHERE build_number = 151;
```

Archivar oculta la oferta y conserva fila, fichero y trazabilidad. No se borra nada.

### 3.5 Orden recomendado

1. Subir el artefacto a R2 y comprobar su hash de bajada.
2. Insertar la fila PUBLISHED.
3. Ejecutar la verificación 3.3.
4. Mantener el 150 **sin archivar** hasta confirmar que hay clientes en 151.
5. Archivar el 150 solo con autorización explícita.

---

## 4. Rollback seguro del piloto

1. No borrar bases ni `-wal`.
2. Reinstalar el instalador anterior (`FullPOS-Setup-1.0.6-148.exe`) si hubiera que volver.
3. Restaurar datos **solo** si hay corrupción demostrada: cerrar la app y copiar
   `backup-wal-20261101T155700Z\*.db` sobre `C:\Program Files\DaleVentas POS\databases`.
4. El backend no requiere cambios: 151 es compatible con 148/149 y la base ya tiene las
   2 tablas V2 (inertes para el cliente antiguo).
