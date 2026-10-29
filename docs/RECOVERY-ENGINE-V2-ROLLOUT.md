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

## 3. Migración en la base de datos

La migración `20261029190000_sale_reconciliation_obligations` es **solo
aditiva**. No hay `ALTER`, `DROP`, `UPDATE` ni `DELETE`.

Procedimiento:

1. **Respaldo completo** de PostgreSQL antes de cualquier paso (el respaldo
   existente de la plataforma o `pg_dump` a un destino fuera del servidor).
2. Verificar el respaldo (tamaño, restauración de prueba si es posible).
3. `npx prisma migrate deploy` en UAT primero.
4. Comprobar que la tabla existe y está vacía:
   ```sql
   SELECT count(*) FROM sale_reconciliation_obligations;
   ```
5. Repetir en producción **en ventana de baja actividad**.

Rollback de la migración: **no se revierte**. La tabla puede quedarse sin uso
(no afecta a ninguna consulta existente). Borrarla sí destruiría evidencia
financiera, y eso está prohibido.

---

## 4. Despliegue gradual

| Paso | Alcance | Criterio de avance |
| --- | --- | --- |
| 0 | UAT con datos sintéticos | Todos los escenarios de `docs/TESTING.md` + los del informe |
| 1 | Backend en producción (sin cliente nuevo) | 148 sigue vendiendo; ningún error nuevo en logs |
| 2 | Instalador candidato en 1 equipo piloto (nunca el de un cliente crítico sin aviso) | 24–48 h: ventas, caja, NCF, inventario y arranque sin incidencias |
| 3 | 5 % de equipos | Igual + revisar obligaciones creadas |
| 4 | Resto | — |

El actualizador de Windows ya está probado en 148: descarga, verifica checksum y
preserva datos. **El instalador de esta entrega debe publicarse como DRAFT
primero** y probarse la actualización 148 → nueva versión en un equipo real antes
de publicar.

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
