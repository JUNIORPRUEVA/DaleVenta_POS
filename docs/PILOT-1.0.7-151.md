# Piloto Windows `1.0.7+151` y sustitución de la release 150

Documento operativo del piloto en **un único equipo**. Nada de esto se ha ejecutado
todavía salvo lo indicado con ✅. Cada bloque requiere autorización del propietario.

---

## 0. Artefacto (verificado ✅ 2026-10-30 18:17 UTC)

| Dato | Valor |
| --- | --- |
| Instalador | `C:\src\fullpos-artifacts\FullPOS-Setup-1.0.7-151.exe` |
| Tamaño | 40.314.531 B |
| SHA256 | `06F9C31B3AA47D522F8FBA22A3E9CE4D254250E347C36CFE9D6BDC00F9435F60` |
| FileVersion | `1.0.7.151` · `ProductName=FullPOS` · **NotSigned** |
| Commit | `c0e4cda8e5dc67122b8de077580c909e29eba099` (`agent/guardian-151-release`) |
| Backend | producción (`daleventapos-backend.gcdndd.easypanel.host`), imagen 151 desplegada ✅ |

## 1. Antes de instalar (equipo piloto)

1. Cerrar FullPOS Cloud por completo (incluido el actualizador).
2. **No cerrar turnos de caja**: no hace falta y alteraría el estado del servidor.
3. Respaldo consistente (solo lectura del original). En este equipo ya está hecho ✅:
   - carpeta `C:\src\pilot151\backup-20261030T181726Z`
   - 6 bases copiadas con la API de backup de SQLite (incluye el WAL confirmado):
     `company_manual_local.db`, `cotizaciones_local.db`, `fulltech_offline.db` (88,9 MB),
     `fulltech_offline_uat.db`, `fulltech_printing.db`, `guardian_outbox.db`
   - `config/`, `logs/`, `shared_preferences.json` y `flutter_secure_storage.dat` copiados
   - manifiesto con SHA256 de los 18 ficheros originales (`manifest-original.json`)
4. Comprobar operaciones inciertas ✅ en este equipo: `pending_actions=0`, ventas
   offline `1` (ya `synced`, RD$500 del 2026-10-05), `sale_attempt_audit=0`,
   intents de inventario sin sincronizar `0`, `sale_cart_override=0`, `integrity_check=ok`.
   → momento seguro para actualizar: no hay nada en vuelo.

## 2. Instalación

El instalador está firmado como `PrivilegesRequired=admin`. **Requiere elevación (UAC)**:
la sesión del agente no es elevada, así que este paso lo debe lanzar el propietario o
un operador con permisos.

```powershell
Start-Process 'C:\src\fullpos-artifacts\FullPOS-Setup-1.0.7-151.exe'
```

Mismo `AppId` que la instalación actual ⇒ **actualiza en el sitio**: no crea una segunda
instalación ni pide otra carpeta. `[Files]` solo escribe en `{app}\app` y
`{app}\updater`; `[InstallDelete]` solo retira los accesos directos antiguos.

## 3. Después de instalar (verificación del piloto)

| Check | Cómo |
| --- | --- |
| Versión | Ajustes → Actualizaciones muestra **1.0.7+151**; `(Get-Item 'C:\Program Files\DaleVentas POS\app\fullpos_cloud.exe').VersionInfo.FileVersion` = `1.0.7+151` |
| Datos | mismos productos/clientes/ventas de antes; `databases\fulltech_offline.db` con `integrity_check = ok` |
| Login | entra con su usuario habitual (sin pedir contraseña nueva) |
| Caja | el turno abierto sigue abierto, mismo saldo |
| Inventario | existencias iguales |
| Panel Guardian | visible en Ajustes → Actualizaciones («Monitoreo APPYRA Guardian AI») |
| Recuperación V2 | al cobrar con respuesta incierta/409 aparece el flujo de **declaración** y se crea una **obligación pendiente** en Caja → Conciliación |
| Actualizador | consulta el canal y ve build 151 como más reciente (tras publicar) |
| Sin duplicados | una sola venta por operación; el saldo de caja no cambia por sí solo |

**No generar ventas reales de prueba sin autorización específica.** Las rutas ya están
validadas contra backend 151 (`/health`, `/license`, `/api/app-updates/check` = 200) y
el motor V2 con su suite de pruebas.

## 4. Reversión segura (si algo falla)

1. No borrar ninguna base de datos.
2. Ejecutar `fulltech_app\build\...` **no** aplica: la reversión es reinstalar el
   instalador anterior (`FullPOS-Setup-1.0.6-148.exe`) o usar el respaldo.
3. Restaurar solo si hay corrupción demostrada: cerrar la app, copiar
   `backup-<ts>\databases\*.db` sobre `C:\Program Files\DaleVentas POS\databases`
   (nunca al revés) y volver a abrir.
4. El backend no requiere cambios: 151 es compatible hacia atrás con 148/149.

---

## 5. Plan para que el actualizador ofrezca **151** y no 150

### Situación actual (verificada ✅, solo lectura)

| Build | Estado | Fichero | Publicada |
| --- | --- | --- | --- |
| 150 | **PUBLISHED** | `FullPOS-AutoEnroll-150-1.0.6-150.exe` | 2026-10-30 03:31 |
| 149 | PUBLISHED | `FullPOS-Guardian-Setup-1.0.6-149.exe` | 2026-10-30 01:16 |
| 148 | PUBLISHED | `FullPOS-Setup-1.0.6-148.exe` | 2026-10-28 21:36 |

Hoy cualquier cliente 148/149 recibe `updateAvailable=true, buildNumber=150` (Guardian
**sin** recuperación V2). El actualizador compara **solo `buildNumber`**
(`AppUpdateManifest.isNewerThan`), por lo que **151 gana a 150** sin tocar el historial.

### Pasos, en este orden y con autorización separada

1. **Publicar 151** (una sola operación atómica, sin borrar ni editar la 150):
   - subir `FullPOS-Setup-1.0.7-151.exe` a
     `releases/windows/stable/1.0.7-151/FullPOS-Setup-1.0.7-151.exe` en el bucket R2;
   - insertar **una fila nueva** en `app_releases`
     (`platform=WINDOWS`, `channel=STABLE`, `version=1.0.7`, `build_number=151`,
     `status=PUBLISHED`, `file_name`, `file_size=40314531`,
     `sha256=06F9C31B…35F60`, `download_url`, `storage_key`, `release_notes`,
     `commit_sha=c0e4cda8…`, `signed=false`, `published_at=now()`);
   - no modificar la fila 150.
2. **Comprobar**: `/api/app-updates/check?…&build=148` y `&build=150` devuelven
   `buildNumber=151`; `&build=151` devuelve `updateAvailable=false`.
3. **Archivar la 150** (`status=ARCHIVED`) solo después de que el piloto confirme 151 y
   de que haya clientes en 151. Archivar **no borra** ni el fichero ni la fila: mantiene
   el historial y permite rollback de publicación.
4. **Nunca** borrar filas de `app_releases` ni sobrescribir un fichero ya publicado
   (`prepare_windows_release.ps1` se niega a sobrescribir: esa protección se mantiene).

### Si hubiera que revertir la publicación

`UPDATE app_releases SET status='ARCHIVED' WHERE build_number=151` + republicar
`status='PUBLISHED'` en 149 si hiciera falta. Los clientes ya actualizados a 151 no
bajan de versión solos: se les reinstala el instalador anterior si fuera necesario.

---

## 6. Instrucciones para el empleado (texto listo)

1. Cierra FullPOS Cloud por completo.
2. Ejecuta `FullPOS-Setup-1.0.7-151.exe` y acepta. **No se borra nada**: ventas, caja,
   clientes y pendientes se conservan.
3. Abre la app y entra con tu usuario.
4. Si vuelve a aparecer «Esta operación necesita revisión»: **no repitas el cobro**.
   Abre **Caja → Conciliación** y revisa la obligación pendiente; la app ya no pierde
   la declaración del cobro.
5. Si tienes dudas, envía una captura de ese panel antes de volver a cobrar.
