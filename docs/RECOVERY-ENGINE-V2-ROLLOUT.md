# Motor de recuperación v2 + obligaciones de conciliación — plan de despliegue

Documento de trabajo para la rama `agent/recovery-engine-v2`. **No es una
autorización**: describe qué habría que hacer, en qué orden y cómo volver atrás.
Nada de este documento se ha ejecutado contra producción.

Versión publicada de referencia: Windows **1.0.6+148**.

---

## 1. Qué entra en esta entrega

### Backend (compatible con el cliente 148 que ya está instalado)

| Cambio | Tipo | Riesgo de compatibilidad |
| --- | --- | --- |
| Tabla `sale_reconciliation_obligations` | Migración **aditiva** (solo `CREATE TABLE` + índices) | Nulo: ninguna tabla existente se altera |
| `POST /sales/attempts/:clientRequestId/declaration` | Endpoint nuevo | Nulo: nadie lo llama en 145–148 |
| `GET /sales/reconciliation-obligations` | Endpoint nuevo (solo lectura, por empresa) | Nulo |
| `scripts/import-sale-declarations.ts` | Script manual, dry-run por defecto | Nulo: no está en ningún arranque automático |

Los clientes 145–148 siguen funcionando exactamente igual si el backend se
despliega antes que la app nueva. **El backend puede ir primero sin esperar al
cliente.** El orden inverso no: un cliente nuevo contra un backend viejo
recibiría `404` al declarar y la declaración quedaría en la cola como `failed`
(no se pierde, pero no se concilia).

### Cliente

- Motor de recuperación automática (arranque, reconexión, tras sincronizar,
  periódico) con single-flight, backoff persistente y respeto de `Retry-After`.
- Declaración durable de «dinero recibido» por la cola existente
  (`sales.declaration`), idempotente, sin crear venta/caja/inventario.
- Centro de recuperación con estado del motor, obligaciones pendientes y
  declaraciones por enviar.
- Exportación de auditoría histórica para el importador (solo portapapeles).

Sin migración de SQLite: la cola `pending_actions` ya existía.

---

## 2. Verificación previa (obligatoria antes de tocar producción)

```powershell
# API
npm ci
npm run api:build                     # prisma generate + tsc
npm --workspace apps/api test         # suites completas
cd apps/api; npx prisma validate

# App
cd apps/fulltech_app
flutter pub get
flutter analyze
flutter test
```

Criterio de GO: build 0, `analyze` sin issues, suites verdes y `prisma validate`
válido. Cualquier fallo ⇒ NO-GO.

---

## 3. Migraciones en la base de datos

Son **dos**, ambas aditivas en lo estructural y en este orden:

| # | Migración | Qué hace |
| --- | --- | --- |
| 1 | `20261029190000_sale_reconciliation_obligations` | Crea la tabla de obligaciones + 3 índices. Solo `CREATE`. |
| 2 | `20261029210000_reconciliation_single_active_obligation` | Tabla de eventos + columnas (`declaration_count`, `version`, `last_declared_at_utc`) + índice único **parcial** `WHERE status='PENDING'`. |

La única escritura de datos de la migración 2 marca como `SUPERSEDED` las
obligaciones `PENDING` duplicadas de una misma operación **si ya existieran**
(no borra filas; reserva el estado y conserva la evidencia). En una base nueva
esa parte no toca nada.

### Procedimiento con respaldo verificado

1. **Respaldo completo** antes de cualquier paso:
   ```bash
   pg_dump --format=custom --no-owner --file=fullpos_$(date +%Y%m%d_%H%M).dump "$DATABASE_URL"
   ```
2. **Verificar el respaldo** (no basta con que exista):
   ```bash
   pg_restore --list fullpos_*.dump | head -n 20          # legible y con tablas
   pg_restore --clean --if-exists --no-owner \
     --dbname="$RESTORE_TEST_URL" fullpos_*.dump           # restaurar en una base aparte
   psql "$RESTORE_TEST_URL" -c 'SELECT count(*) FROM "Sale";'
   ```
3. `npx prisma migrate deploy` en UAT primero y repetir las comprobaciones:
   ```sql
   SELECT status, count(*) FROM sale_reconciliation_obligations GROUP BY status;
   SELECT max(c) FROM (SELECT count(*) c FROM sale_reconciliation_obligations
                        WHERE status='PENDING' GROUP BY company_id, client_request_id) x;
   -- debe devolver 1 (o NULL si no hay filas)
   ```
4. Repetir en producción **en ventana de baja actividad**, con el respaldo
   verificado y el plan de rollback leído.

Rollback de las migraciones: **no se revierten**. Las tablas pueden quedarse sin
uso (ninguna consulta existente las toca). Borrarlas destruiría evidencia
financiera: prohibido.

---

## 4. Despliegue gradual (backend-first)

| Paso | Alcance | Criterio de avance |
| --- | --- | --- |
| 0 | UAT con datos sintéticos (hecho: 25 casos HTTP + 4 de integración) | Todo PASS |
| 1 | **Backend** en producción sin cliente nuevo | 148 sigue vendiendo; sin errores nuevos en logs; `/sales/reconciliation-obligations` responde 200 |
| 2 | Instalador en 1 equipo piloto (con aviso al cliente) | 24–48 h: ventas, caja, NCF, inventario y arranque sin incidencias |
| 3 | 5 % de equipos | Igual + revisar obligaciones creadas y eventos |
| 4 | Resto | — |

El backend **debe ir primero**: un cliente nuevo contra un backend viejo recibe
404 al declarar y la declaración queda en la cola como `failed` (visible, no se
pierde), pero no se concilia hasta actualizar el servidor.

### Instalador candidato final (identidad de producción)

- Versión definitiva: **`1.0.7+150`** (ver §7.1). Artefacto:
  `installer/output/FullPOS-Setup-1.0.7-150.exe` — 40.304.215 B ·
  SHA256 `3530BBDB61415254D70522EC8285A2F540B701E73436B2B581BE63CA818592DF`.
- Identidad estable de siempre: AppId `{{0ED49D5E-6E78-4F11-8E78-6D37FDE2078A}}`
  y carpeta `DaleVentas POS` (actualiza la instalación del cliente, no crea una
  segunda). **No ejecutar este artefacto en el equipo de desarrollo**: existe
  una instalación real en `C:\Program Files\DaleVentas POS`.
- Variantes de ensayo (identidad separada, nunca publicables):
  AppId `{{4C1F9E6A-2D74-4E33-9B57-7A0E5F1C8D21}}`, carpeta
  `DaleVentas POS UAT`, salida `FullPOS-UAT-Setup-<ver>-<build>.exe`.
- **Bloqueo de firma:** todos los artefactos quedan **NotSigned** (no hay
  certificado de firma de código en el equipo). No se usó ningún certificado
  falso. Ver §7.4 para las advertencias esperables de SmartScreen.
- Instalar/desinstalar la variante de ensayo **sí** se pudo ejecutar en modo
  administrador (§7.3); lo que queda pendiente es solo la firma y la ejecución
  del candidato de producción, que es una decisión del propietario.

---

## 5. Rollback

### Si el problema es la app

1. Reinstalar el instalador 1.0.6+148 (está guardado en R2 como
   `releases/windows/stable/1.0.6-148/…`).
2. La base SQLite local es compatible: no se añadió ninguna tabla ni columna.
   Los datos de ventas no se tocan.
3. Las declaraciones que ya estén en la cola local siguen ahí (no se pierden),
   pero la versión 148 no sabe enviarlas. Si se vuelve a subir a la versión
   nueva, se envían solas.

### Si el problema es el backend

1. Revertir el servicio a la imagen anterior (`docker service rollback`).
2. La tabla nueva se queda sin uso; ninguna versión la consulta si el código es
   antiguo.
3. No borrar filas de `sale_reconciliation_obligations`: son evidencia.

---

## 6. Importación de declaraciones históricas (145–148)

Las declaraciones de esas versiones **solo existen en el equipo**, en la
auditoría local (`MANUAL_MONEY_RECEIVED`). No viajaron nunca al servidor.

Procedimiento (requiere autorización explícita en la tarea):

1. En cada equipo afectado: Centro de recuperación → menú → **Copiar plantilla
   de importación**. Se copia un JSON con las operaciones y **`totalDeclared`
   en `null`**.
2. Una persona conoce el importe real y lo completa con evidencia (comprobante,
   arqueo, compra del cliente). **El sistema nunca inventa el monto.**
3. Dry-run:
   ```powershell
   npm --workspace apps/api run reconciliation:import -- `
     --file .\declaraciones-equipo.json --company <uuid>
   ```
4. Revisar el resumen: `wouldCreate`, `duplicate`, `invalid`.
5. Con autorización, aplicar:
   ```powershell
   npm --workspace apps/api run reconciliation:import:apply -- `
     --file .\declaraciones-equipo.json --company <uuid>
   ```
6. Reejecutar es seguro: lo ya importado sale como `duplicate`.

Garantías del importador: no crea ventas, pagos, movimientos de caja ni
inventario; no toca turnos históricos; exige `--company` explícito; rechaza el
archivo si su `companyId` no coincide; rechaza filas sin importe válido.

---

## 7. Riesgos residuales conocidos

1. **Web/PWA**: la declaración usa `requireDatabase: true` y falla cerrada en
   navegador. No cierra la incidencia; muestra un mensaje claro. Se puede
   habilitar el respaldo en `shared_preferences` si el negocio lo necesita.
2. **401 durante el envío**: la acción queda `auth_blocked` y se rehabilita al
   volver a iniciar sesión (`releaseAuthBlocked`, solo para el tipo
   `sales.declaration`). Si el usuario no reinicia sesión ni reinicia la app, la
   declaración espera.
3. **Obligaciones sin UI de resolución**: esta entrega las muestra y las deja
   auditables, pero no implementa el flujo administrativo de «conciliado». Se
   resuelven fuera de la app (o en una entrega posterior) para no inventar un
   flujo contable.
4. **Una re-declaración legítima posterior** (misma operación, otro importe)
   crea una obligación nueva: es intencionado y queda visible, no es un
   duplicado silencioso.
5. **Interferencia con fases posteriores a 148**: cualquier trabajo nuevo sobre
   `sales`, `cash` o `offline` debe asumir que existe el tipo de cola
   `sales.declaration` y que el motor de recuperación es el único dueño del
   barrido de `sales.attempt`.

---

## 8. Estado del cierre técnico (2026-10-29)

### 8.1 Versión definitiva

| Candidato | Valor | Motivo |
| --- | --- | --- |
| Versión / build | **`1.0.7+150`** | No reutiliza 148 (publicada) y **no ocupa 149**, que queda libre para la línea de Windows que ya lo tuviera reservado. |
| Instalador | `FullPOS-Setup-1.0.7-150.exe` | Identidad estable (AppId `0ED49D5E…`, carpeta `DaleVentas POS`). |
| Canal | `stable` **sin tocar** | No se ejecutó ninguna publicación: el canal sigue sirviendo solo `1.0.6-148`. |

`apps/fulltech_app/pubspec.yaml` queda en `1.0.7+150` para que el corte de
release sea reproducible (el script lee la versión del pubspec).

### 8.2 Integración sobre la línea con Guardian AI

- Rama aislada: **`agent/integrate-recovery-v2-guardian`**, creada desde
  `agent/guardian-phase12` (`de724dca`), merge de `agent/recovery-engine-v2`
  → commit `5fe89192`.
- Solo 4 archivos se solapaban; 2 conflictos reales, resueltos a mano:
  - `apps/api/prisma/schema.prisma`: se conservan los modelos de Guardian
    (Fase 1–13) y se añaden las dos tablas de conciliación.
  - `windows_product_paths.dart`: conviven `FULLPOS_UAT_PROFILE` (falla cerrada
    con `StateError`) y `DALEVENTAS_POS_UAT_ISOLATION` (devuelve `null`).
    Ninguna resuelve la raíz real sin `DALEVENTAS_POS_ROOT`.
- Regresiones en esa rama: `prisma validate` OK · `api:build` OK ·
  **1125 tests API PASS** (111 suites, 0 fail) · `flutter analyze` sin issues ·
  **1517 tests Flutter PASS** (9 skip, 0 fail).
- **Alcance:** la integración es una *preparación*. El release financiero debe
  cortarse desde la línea de recuperación; las funcionalidades de Guardian no
  forman parte de este release aunque compartan rama de integración.

### 8.3 Ciclo completo del instalador (modo administrador, real)

Ejecutado sobre la variante UAT aislada, con el instalador compilado con
privilegios de administrador (`PrivilegesRequired=admin`):

| Paso | Resultado |
| --- | --- |
| Instalación | `exit 0`, **modo administrativo** (`User privileges: Administrative`), destino `C:\Program Files\DaleVentas POS UAT`, 82 archivos |
| Reinstalación misma versión | `exit 0`, añade al log de desinstalación existente (`Will append to existing uninstall log`) |
| Actualización `1.0.7-rc.2-150002` → `1.0.7-rc.3-150003` | `exit 0`, `Installation process succeeded` |
| Datos tras reinstalar y actualizar | `databases/prueba_ventas.db`, `config/empresa.json`, `updates/pendiente.txt` intactos con su contenido |
| Desinstalación | `exit 0`; se eliminan `app/`, `updater/` y los accesos directos; **se conservan** `databases/ config/ logs/ media_cache/ updates/` **y sus archivos** |
| Instalación estable `C:\Program Files\DaleVentas POS` | 147 archivos: **0 añadidos, 0 eliminados, 0 modificados** antes y después de todo el ciclo |
| Accesos directos de la estable | Ninguno borrado (el bloque `[InstallDelete]` que los eliminaba ahora está excluido en las variantes UAT; verificado en el binario compilado: la cadena `DaleVentas POS.lnk` ya no existe) |

Hallazgo corregido en este cierre: el bloque `[InstallDelete]` (que borra los
accesos directos antiguos de "DaleVentas POS") solo estaba excluido para
`MyAppUatMayoreo`. Una instalación UAT con privilegios de administrador habría
borrado los accesos directos **de todos los usuarios** de la instalación real.
Ahora está excluido también para `MyAppUat`.

Nota menor: tras desinstalar queda la carpeta vacía `C:\Program Files\DaleVentas POS UAT`
(sin contenido) porque el proceso no elevado no puede eliminar el directorio;
se borra con una sesión elevada.

### 8.4 Estado de firma digital

- Todos los artefactos (`FullPOS-Setup-1.0.7-150.exe`,
  `FullPOS-UAT-Setup-1.0.7-rc.2-150002.exe`, `-rc.3-150003.exe`) están
  **NotSigned**: no hay certificado Authenticode en el equipo y no se fabricó
  ninguno.
- Consecuencias esperables al distribuir sin firmar:
  1. **SmartScreen**: "Windows protegió su PC · Aplicación desconocida" →
     *Más información* → *Ejecutar de todas formas*. Con pocas instalaciones,
     el aviso se repite en cada equipo y en cada versión.
  2. **Aviso de editor desconocido** en el diálogo de UAC.
  3. Algunos antivirus/EDR pueden poner el `.exe` en cuarentena los primeros días.
  4. El actualizador integrado descarga y ejecuta el instalador: si el equipo
     bloquea ejecutables no firmados, la actualización automática falla.
- Mitigación mientras no haya certificado: publicar el SHA256 junto al enlace y
  distribuir por el canal de descarga autenticado (no por enlaces públicos
  anónimos). Con certificado (EV o standard + reputación) desaparecen 1–3.

### 8.5 Acciones que requieren autorización del propietario

Ninguna de estas se ejecutó:

1. **Integrar** `agent/recovery-engine-v2` (o la rama de integración verificada)
   en la rama de producción y hacer el merge/push correspondiente.
2. **Migrar PostgreSQL en producción**: `npx prisma migrate deploy` con el
   respaldo verificado del §3.
3. **Desplegar el backend** con la imagen que incluye este código (backend-first).
4. **Publicar** `FullPOS-Setup-1.0.7-150.exe` en el canal `stable` y actualizar
   el registro de release (`scripts/release/prepare_windows_release.ps1`).
5. **Ejecutar el instalador de producción** en un equipo piloto (requiere UAC en
   ese equipo y el aviso al cliente).
6. **Importación histórica de declaraciones** (incluido el caso Siarah): solo
   con importes aportados con evidencia.
7. **Borrar** `C:\Program Files\DaleVentas POS UAT` (carpeta vacía) en una sesión
   elevada.
