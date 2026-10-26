# Despliegue backend — candidato `f95b8d75` (turnos de caja)

Documento de preparación **sin ejecución**. No se despliega nada hasta autorización expresa.

- Fecha de preparación: 2026-10-26
- Candidato: rama `agent/antonio-turnos-fix`, commit **`f95b8d757936cb32a6adb56d180e70d3b703ffe2`**, árbol `1a8bd078d03d1000b1e37a9e010ebeb14c7929fd`
  - `9d531e65` (primer candidato) queda **superseded**: la repetición del arnés detectó un defecto grave en él, corregido en `f95b8d75` (§0)
- Base: `53aa9bb1` (misma revisión que la imagen desplegada)
- Imagen a sustituir: `fullpos/daleventapos-backend:offline-144`
  - `Id=sha256:e2884dae0fb60634f4a467551facef9749b0202a97c8236677359447d881205b`
  - label `org.opencontainers.image.revision=53aa9bb1143168ee56697da20ff1612860e1bcfc`, `version=1.0.6-144`
- Migraciones nuevas en el candidato: **ninguna**
- Variables de entorno nuevas obligatorias: **ninguna** (`CASH_SHIFT_MAX_SPAN_HOURS`, `CASH_SHIFT_CLOCK_SKEW_MINUTES` son opcionales con valores por defecto 24 h y 5 min, techo duro 72 h / 30 min)

## 0. Historial del candidato y defecto detectado durante la preparación

| Commit | Estado | Nota |
| --- | --- | --- |
| `9d531e65` | **superseded** | 137 comprobaciones en verde en su primera ejecución, pero **intermitente** |
| `f95b8d75` | **candidato final** | corrige la pérdida silenciosa descrita abajo |

**Defecto F-3 (crítico, encontrado al repetir la suite de concurrencia):** el primer candidato capturaba el `P2034` de `telemetry_outbox` dentro de la transacción del dominio. En PostgreSQL eso **no** neutraliza el fallo: la transacción queda abortada y el `COMMIT` posterior se comporta como `ROLLBACK`. Efecto observado con PostgreSQL real: la API respondía `201` y emitía `cash.session.opened` mientras la fila del turno **no existía** (pérdida silenciosa de datos financieros, peor que el `500` original).

Corrección en `f95b8d75`: `enqueueBusinessEvent` escribe siempre con la conexión propia del servicio, **fuera** de la transacción del negocio, y registra/descarta cualquier fallo. Se prefiere perder un evento de telemetría antes que perder una operación de caja.

Evidencia de la corrección: la suite de concurrencia se ejecutó **3 veces seguidas** sobre base limpia (31/31 cada vez) verificando además la persistencia real de las filas (empresa A: 5 sesiones, empresa B: 1).

## 1. Comparación con la imagen desplegada

La imagen `offline-144` declara la revisión `53aa9bb1…`, que es exactamente la base del candidato. El delta es, por tanto, **solo** el commit `9d531e65`:

```
 apps/api/src/cash/cash-operation-window.ts              | 220 ++++ (nuevo)
 apps/api/src/cash/cash.controller.ts                    |  28 +     (2 endpoints ADMIN)
 apps/api/src/cash/cash.service.ts                       | 468 +++- (ventana, cierre admin, caja diaria)
 apps/api/src/cash/dto/cash.dto.ts                       |  39 +-     (occurredAt, AdminClose DTO)
 apps/api/src/sales/sales.controller.ts                  |  10 +-     (ParseUUIDPipe)
 apps/api/src/sales/sales.service.ts                     |  47 +      (ventana en ventas/offline/legacy)
 apps/api/src/usage-telemetry/usage-telemetry.service.ts |  35 +-     (enqueue no bloqueante)
 (+ 5 archivos de test)
```

- No se elimina ningún endpoint, DTO, servicio, guard ni módulo existente.
- No cambia `package.json`, `Dockerfile`, `tsconfig` ni dependencias: el artefacto compila con la misma cadena.
- Configuración de producción verificada (solo lectura): `FINANCIAL_LEGACY_COMPAT=true`, `CASH_CLOSE_LEGACY_COMPAT=false`, `RUN_MIGRATIONS=false`, `PRODUCTS_SOURCE=LOCAL`, `REDIS_ENABLED=false`. Valores compatibles con el candidato; no se requiere cambio.
- Observación previa (no bloqueante): la variable `GIT_SHA` del servicio no coincide con la revisión real de la imagen (dato informativo desactualizado).

## 2. Contratos HTTP y clientes antiguos (130 / 132)

Fuente: código de las builds en el repo — `5278477e` (1.0.6+132) y `69dd871b` (1.0.6+130).

| Uso | 130 | 132 | Candidato |
| --- | --- | --- | --- |
| `GET /cash/state` campos leídos | `businessDate`, `canOperate`, `activeSession.*`, `cashboxToday` | igual | mismos campos + `staleBusinessDate`, `requiresClosure`, `requiresReview` (adicionales, ignorados por clientes antiguos) |
| Venta con `originCashSessionId` | **no lo envía** (ruta legacy) | sí | aceptado en ambos caminos, con validación de ventana en los dos |
| `saleOccurredAt` | se envía | se envía | base de la validación de ventana (nunca `now()`) |
| Cierre `POST /cash/sessions/close` | identificado | identificado | sin cambios de contrato |
| `GET /cash/sales` campos | mismos | mismos | sin cambios |

Cambios de comportamiento que **sí** notarán los clientes antiguos (todos intencionados):

1. **Venta en turno vencido** (`occurredAt` fuera de la vida del turno o > 24 h): antes se aceptaba y se imputaba a un cierre de otro día; ahora `409` con `code=CASH_SESSION_STALE` y mensaje legible. Los clientes antiguos muestran el mensaje y el turno sigue apareciendo en `/cash/state` con `activeSession`, así que pueden cerrarlo (validado en C5/C7 de preproducción).
2. **Abrir turno con uno de otro día**: antes devolvía el turno viejo en silencio; ahora `409 CASH_CLOSE_PREVIOUS_REQUIRED` con `sessionId` y `businessDate`. Un cliente que ignore el cuerpo verá un error y deberá cerrar el turno; el cierre sigue funcionando igual.
3. **Movimiento de caja con `operationId` pero sin `sessionId`** (petición parcial): ahora `409 INVALID_PARTIAL_FINANCIAL_REQUEST` en lugar de aceptarse. Ninguna build 130/132 envía ese payload parcial (verificado en código).
4. **UUID malformado** en rutas con `:id`: antes `500` (P2023), ahora `400`. Los clientes trataban ambos como error.
5. **Payload de plataforma de ventas**: campos nuevos del candidato son opcionales; los payloads de 130/132 siguen siendo válidos (validado en el arnés, C1–C7).

Riesgo residual: un cliente muy antiguo (anterior a 130) que no envíe `saleOccurredAt` usa `now()` del servidor; con un turno vencido recibirá igualmente el `409` informativo. No hay pérdida de datos, pero requiere que el usuario cierre el turno.

## 3. Esquema y migraciones

- Candidato: 32 carpetas de migración, idénticas a la base `53aa9bb1`. **Cero migraciones nuevas.**
- Producción (solo lectura): `_prisma_migrations` con **174 filas, 0 sin terminar**; las tres migraciones históricamente ausentes de `production-main` están aplicadas:
  - `20261013180000_wholesale_price_lists` (2026-10-19 02:24)
  - `20261014113000_inventory_movement_operation_id` (2026-10-19 11:38)
  - `20261014153000_offline_operation_payload_hash` (2026-10-19 11:38)
- Artefactos de esquema verificados en producción (4/4 columnas presentes): `inventory_movements.operation_id`, `inventory_movements.operation_payload_hash`, `Product.create_payload_hash`, `companies.wholesale_price_lists_enabled`.
- Conclusión: **despliegue sin migración** (`RUN_MIGRATIONS=false` se mantiene). No hay drift pendiente entre el candidato y producción.

## 4. Estado de datos en producción relevante para el despliegue (solo lectura)

Turnos abiertos en el momento de la auditoría: **9** (2 del día, 7 de días anteriores).

| Empresa | Usuario | Abierto | Día comercial | Ventas | Movimientos |
| --- | --- | --- | --- | --- | --- |
| yahaPublicidad | Yahaira rodriguez | 2026-08-11 00:15 | 2026-08-11 | 1 | 0 |
| Solimac | Prueva123 | 2026-09-15 16:46 | 2026-09-15 | 13 | 1 |
| Puerta y Ventana. Aquino | Nandy Aquino | 2026-09-20 02:54 | 2026-09-19 | 13 | 2 |
| jc distribuidores | JOEL CASTILLO | 2026-09-24 14:13 | 2026-09-24 | 1 | 0 |
| pureva7 | pureva7 | 2026-10-08 12:42 | 2026-10-08 | 0 | 0 |
| FULLTECH, SRL | Yunior Lopez | 2026-10-08 21:12 | 2026-10-08 | 10 | 0 |
| Siarah Beer & Café | Juan Núñez | 2026-10-22 14:33 | 2026-10-22 | 185 | 0 |
| SIJO TELA | Sammy Guerrero | 2026-10-26 13:05 | 2026-10-26 | 2 | 0 |
| Antonio Celulares | Antonio Lauture | 2026-10-26 13:08 | 2026-10-26 | 4 | 0 |

Implicación: tras el despliegue, las 7 empresas con turno vencido **dejarán de poder vender** hasta cerrar el turno (comportamiento correcto: evita imputar ventas al cierre de otro día). Antonio Celulares ya opera con un turno del día. Los cierres administrativos se podrán hacer con el nuevo endpoint (`POST /cash/sessions/:id/admin-close`, rol ADMIN) o desde el propio cliente.

## 5. Seguridad de la transacción de cierre, telemetría y caja diaria

- **Cierre de turno**: `updateMany` condicionado por identidad (`id + companyId + openedByUserId/status=OPEN/closedAt=null`). Solo una petición puede transicionar; el resto recibe `409`. Idempotente ante reenvíos y reintentos; no depende de estado en memoria.
- **Telemetría no bloqueante**: `enqueueBusinessEvent` captura cualquier error del outbox y lo registra (`telemetry.enqueue.skipped`). Un fallo de telemetría ya no puede revertir una venta, un movimiento ni un cierre. Efecto secundario aceptado: se pierde ese evento de telemetría (no el dato de negocio).
- **Caja diaria**: el importe se deriva de `SUM(closingAmount)` de los turnos CLOSED del día. La finalización se repite **después** del commit con `SELECT … FOR UPDATE` sobre `cashbox_daily`, de modo que cierres simultáneos se serializan y el último deja el total real. La finalización post-commit es best-effort: si el proceso muere justo entre el commit del cierre y la finalización, el turno queda correctamente cerrado y **solo** el agregado diario puede quedar desactualizado; se corrige en el siguiente cierre de esa caja o con la verificación de posdespliegue (SQL incluido abajo).
- **Reinicios**: no hay estado en memoria ni locks de proceso; el bloqueo es de fila en PostgreSQL y se libera al terminar la transacción. Un reinicio en medio de un cierre deja la transacción abortada (rollback) sin efectos parciales.
- **Reintentos**: `retryOnWriteConflict` reintenta hasta 5 veces con backoff exponencial y jitter solo en `P2034`; la transacción es idempotente, así que un reintento no duplica turnos ni cierres.

SQL de verificación de posdespliegue (solo lectura):

```sql
-- turnos que quedaron abiertos de días anteriores (deben ir a 0 tras la limpieza)
SELECT company_id, count(*) FROM cash_sessions
WHERE status = 'OPEN' AND "businessDate" < to_char(now() AT TIME ZONE 'America/Santo_Domingo','YYYY-MM-DD')
GROUP BY company_id;

-- cajas diarias cuyo importe no coincide con la suma de sus cierres
SELECT b.id, b."businessDate", b."currentAmount", coalesce(sum(s."closingAmount"),0) AS suma
FROM cashbox_daily b
LEFT JOIN cash_sessions s ON s."cashboxDailyId" = b.id AND s.status = 'CLOSED'
WHERE b."businessDate" >= current_date - 7
GROUP BY b.id, b."businessDate", b."currentAmount"
HAVING abs(coalesce(b."currentAmount",0) - coalesce(sum(s."closingAmount"),0)) > 0.01;
```

## 6. Procedimiento de despliegue controlado (a ejecutar solo con autorización)

1. **Respaldo**: `pg_dump` completo de `daleventa` a almacenamiento externo + verificación de tamaño y `pg_restore --list`. Sin respaldo válido no se continúa.
2. **Artefacto**: construir la imagen desde `f95b8d75` (árbol `1a8bd078…`) en el host de build y publicarla con etiqueta inmutable `fullpos/daleventapos-backend:cash-turnos-f95b8d75`. Registrar el `sha256` del manifiesto de la imagen. Referencia de integridad del `dist` ya compilado: manifiesto de 227 archivos con `sha256 0E61ACA958368ECB4DDEE2F7B1811387327E9C76FC64ED22B26221A1AF1AEABA`. Nota: el daemon de Docker **no está disponible** en esta máquina, así que la imagen debe construirse en el host de build/CI; el artefacto verificable aquí es el commit + el manifiesto del `dist`.
3. **Preflight de esquema**: `npx prisma migrate status` contra producción (solo lectura) — debe reportar "Database schema is up to date".
4. **Despliegue**: actualizar el servicio `daleventapos_backend` a la nueva etiqueta con `--update-order start-first` y `--update-parallelism 1`, manteniendo **todas** las variables actuales sin cambios.
5. **Health checks** (minuto 0–5):
   - `GET /health` (o el endpoint de salud usado por Traefik) responde 200.
   - Login de un usuario de prueba interno.
   - `GET /cash/state` de una cuenta controlada responde 200.
   - Log del contenedor sin `P2034`, sin `ExceptionsHandler`, sin `telemetry.enqueue.skipped` en avalancha.
6. **Verificación funcional** (10 min): apertura de turno en cuenta interna, venta en efectivo, movimiento de caja, cierre de turno, y apertura en un turno vencido de prueba (debe responder `CASH_CLOSE_PREVIOUS_REQUIRED`).
7. **Limpieza asistida** de los turnos vencidos listados en §4 (cierre administrativo con importe = esperado), uno por uno, confirmando antes con cada empresa cuando el importe no sea 0.
8. **Observación 60–120 min** con los criterios de rollback de §7.

Rollback: `docker service rollback daleventapos_backend` (vuelve a `offline-144`, misma revisión `53aa9bb1`). No hay migraciones que deshacer; el esquema es común.

## 7. Señales de rollback inmediato

- Cualquier `5xx` nuevo en `/cash/*` o `/sales` por encima del ruido previo (baseline: 0 en la auditoría).
- Ventas rechazadas con `CASH_SESSION_STALE` en turnos del **mismo día** (falso positivo de la ventana operativa).
- Errores `P2034` no recuperados tras los reintentos, o incremento de latencia de apertura/cierre por encima de 2 s p95.
- Duplicación de cierres, turnos abiertos nuevos creados por reintentos, o diferencia entre `cashbox_daily.currentAmount` y la suma de cierres del día.
- Caída del login o del realtime (`socket.io`) en más de un cliente.
- Cualquier indicio de acceso cruzado entre empresas.

## 9. Verificación de que las pruebas corresponden al commit final

Ejecutado **después** del commit `f95b8d75`, con el backend recompilado desde ese commit (árbol `1a8bd078…`) y la base recreada antes de cada suite:

```
run-uat.mjs                → Total 64 · OK 64 · FALLOS 0
run-preprod-checks.mjs     → Total 27 · OK 27 · FALLOS 0
run-phase5-multitenant.mjs → Total 31 · OK 31 · FALLOS 0   (repetida 3× adicionales: 31/31 cada una)
run-phase4-offline48.mjs   → Total 15 · OK 15 · FALLOS 0
─────────────────────────────────────────────────────────
comprobaciones totales = 137 · fallos = 0
```

Otras validaciones sobre el mismo árbol: `npm run api:build` exit 0; `npm --workspace apps/api test` → 797 passed, 8 skipped, 0 failed (78 suites); `flutter test` 1394 passed / 7 skipped y `flutter analyze` sin errores (sin cambios Dart respecto al árbol ya validado).

Hallazgo metodológico: la primera corrida de 137 se hizo sobre `9d531e65` y pasó; fue la **repetición** la que destapó la intermitencia. Motivo: el `P2034` del outbox solo ocurre bajo concurrencia real, no en cada ejecución. Conclusión aplicada: el arnés de concurrencia debe repetirse, no ejecutarse una sola vez.
