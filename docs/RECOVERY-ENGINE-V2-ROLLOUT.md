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

### Instalador candidato (identidad separada de la 148)

- Nombre probado: `FullPOS-UAT-Setup-1.0.7-rc.1-150000.exe`.
- `AppId {{4C1F9E6A-2D74-4E33-9B57-7A0E5F1C8D21}}` y carpeta
  `DaleVentas POS UAT`, **distintos** de la instalación estable
  (`{{0ED49D5E-…}}` / `DaleVentas POS`): instalarlo no puede sobrescribir la 148.
- Versión `1.0.7-rc.1` (build 150000): no reutiliza 148 ni reserva 149.
- **Bloqueo:** el binario queda **NotSigned** (no hay certificado de firma de
  código en el equipo). No se usó ningún certificado falso. La publicación debe
esperar a un certificado real, porque SmartScreen bloqueará la instalación masiva.
- Instalar/desinstalar para probar el rollback requiere **elevación (UAC)**, que
  no se puede automatizar desde aquí: pendiente de una sesión manual.

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

## 8. Lo que falta para publicar

- [ ] UAT con datos sintéticos de todos los escenarios del informe.
- [ ] Instalador candidato construido con `scripts/release/build_windows_release.ps1`.
- [ ] Prueba de actualización 148 → candidato en un equipo real, verificando que
      los datos se conservan.
- [ ] Autorización explícita para: migración en producción, despliegue del
      backend, publicación del instalador.
- [ ] Importación histórica: solo si el negocio aporta los importes con
      evidencia (caso Siarah incluido).
