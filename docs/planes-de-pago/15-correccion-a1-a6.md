# Corrección A1–A6 del flujo de comprobantes — informe PASS/FAIL

Fecha: 2026-11-19 · Rama `agent/planes-de-pago-impl-20261116` · Base local `planes_local` y base aislada
`appyra_license_e2e` (127.0.0.1:56701). Sin despliegues, sin producción, sin precios ni planes tocados.

## Resultado

| # | Debilidad | Estado | Cómo se comprobó |
| --- | --- | --- | --- |
| A1 | Doble activación concurrente / periodos pisados | **PASS** | Lock `FOR UPDATE` de la orden y de la empresa + revalidación dentro de la transacción; P2002 → 409. Pruebas de concurrencia reales |
| A2 | Comprobante con fecha futura | **PASS** | Regla `RECEIPT_NOT_FUTURE` (tolerancia 30 min de reloj); `daysForward` por defecto 0 |
| A3 | Cuenta destino no comprobada por mala configuración | **PASS** | `BANK_ACCOUNT_CONFIGURED`: el sufijo debe ser 4 dígitos; si no, la validación **falla** (no se omite) |
| A4 | Referencia reutilizada entre empresas / fail-open | **PASS** | Búsqueda de la referencia en **todas** las empresas; si la consulta falla, se trata como reutilizada |
| A5 | Importes y fechas mal interpretados | **PASS** | Espacios de miles, `5,000`/`5.000`, cifras ambiguas rechazadas, fecha ISO aceptada |
| A6 | Topes incoherentes e intentos fallidos | **PASS** | Tope único 8 MB (almacén, validación y controlador) y 5 intentos por **día local** |
| A7 | El OCR no demuestra el pago | **MANTENIDO** | La activación sigue siendo provisional: verificado en BD (`activation_state = PROVISIONAL`, pago `UNCONFIRMED`) |

## Cambios aplicados

### A1 — concurrencia e idempotencia (`license-orders.service.ts`, `license-activation.service.ts`)
- La transacción bloquea la orden (`SELECT … FOR UPDATE`), **revalida** `status` abierto y
  `activation_state = NONE`; si ya está cerrada responde `409 ORDER_NOT_PAYABLE` o
  `409 ORDER_ALREADY_ACTIVATED`.
- La evidencia se inserta **antes** de activar: el índice único `(companyId, sha256)` decide, y su
  `P2002` se traduce a `409 EVIDENCE_DUPLICATE` (antes era un 500).
- `applyInTransaction` bloquea la fila de la empresa antes de leer el vencimiento, así que el cálculo
  del periodo siempre parte del valor confirmado.

### A2 — fechas (`bank-transfer.analysis.ts`)
- Nueva comprobación `RECEIPT_NOT_FUTURE` con 30 minutos de tolerancia para relojes desfasados.
- `daysForward` pasa de 1 a **0**: un comprobante de mañana ya no activa.

### A3 — cuenta de cobro (`bank-transfer.analysis.ts`, `license-orders.service.ts`)
- `authorizedAccountSuffix()` distingue "sin configurar" (usa la cuenta por defecto `0753`) de
  "configurada mal" (devuelve `null`, se registra un aviso y la validación falla).
- `DESTINATION_ACCOUNT` exige un sufijo válido de 4 dígitos: nunca se omite en silencio.

### A4 — referencia bancaria (`license-orders.service.ts`)
- La comprobación es global (la cuenta de cobro es única para todas las empresas).
- El `catch` devuelve `true` (tratada como reutilizada): si no se puede comprobar, el comprobante va a
  revisión en lugar de activar.

### A5 — lectura de cifras y fechas (`bank-transfer.analysis.ts`)
- Se normalizan espacios especiales (no separable, fino, cuarto de eme) y se admiten en el importe.
- `toNumber`: `5,000` y `5.000` se leen como 5.000 (antes, como **5**); `0.500` sigue siendo 0,5 y las
  cifras ambiguas (`1,2,3`, `5,0000`) devuelven `null` → revisión, nunca una cantidad inventada.
- `parseDate` acepta ISO (`2026-11-17 14:35`) además de `dd/mm/aaaa`.

### A6 — límites (`license-evidence.storage.ts`, `license-evidence.validation.ts`, `license-orders.service.ts`)
- **Un solo tope**: `MAX_EVIDENCE_BYTES` se deriva de `EVIDENCE_MAX_BYTES` (8 MB) y lo usan el almacén,
  la validación documental y el límite de subida del controlador.
- `MAX_DAILY_UPLOADS`: 3 → **5** intentos y el día se cuenta en horario de República Dominicana (antes
  el cupo cambiaba a las 8 de la noche).

## Pruebas ejecutadas

| Prueba | Resultado |
| --- | --- |
| `npx tsc -p tsconfig.build.json --noEmit` | **PASS** · 0 errores |
| `npm test` (backend, sin e2e) | **PASS** · 259 suites / **3.023 pruebas**, 0 fallos |
| E2E de licencias + puente CRM | **PASS** · 12/12 |
| `license-orders.integration-spec` contra PostgreSQL real | **PASS** · **16/16** |
| Evidencia de la empresa ACTIVO (`license-scenarios-evidence.ps1 -RunSuites`) | **PASS** · 11/11 suites y foto idéntica antes/después |

### Las 12 pruebas del flujo completo (base `appyra_license_e2e`)
1. Crear orden con referencia única y vida de renovación.
2. Activar al instante y dejar el pago por verificar.
3. Rechazar el mismo comprobante dos veces (secuencial).
4. **Renovar sumando al vencimiento existente** (periodo pagado conservado).
5. **Bajar de plan** apagando lo que el plan no incluye.
6. **Dos subidas simultáneas a la misma orden** → una sola activación y **un solo periodo** (A1).
7. **El mismo archivo en dos órdenes a la vez** → 409 y una sola evidencia (A1).
8. **Orden ya cerrada** → rechazo (A1).
9. **Comprobante con la referencia de otra empresa** → no activa; la empresa sigue en TRIAL (A4).
10. **Comprobante con fecha de mañana** → no activa, `RECEIPT_NOT_FUTURE` (A2).
11. **Cuenta de cobro mal configurada** → no activa, `BANK_ACCOUNT_CONFIGURED` (A3).
12. **Reversión** del pago no acreditado → licencia vencida sin periodo pagado y orden `REVERTED`.
13. **Cinco subidas simultáneas del mismo archivo** a cinco órdenes abiertas → **una** evidencia y **un** periodo.
14. **Cinco subidas simultáneas de archivos distintos** a la misma orden → **una** activación.
15. **Misma referencia en dos comprobantes distintos** de la misma empresa → la segunda **no** activa
    (`REFERENCE_NOT_REUSED`).
16. **Tras un comprobante rechazado**, uno válido activa **una sola vez** (2 evidencias, 1 activación).

### Verificación directa en PostgreSQL (después de las pruebas)
```
 Empresa           | plan | estado | vence            | evidencias
 Empresa de prueba | pro  | ACTIVE | 2026-12-19 12:16 |     1
 Empresa B         |      | TRIAL  |                  |     1

 referencia    | plan | amount  | status            | activación | desde      | hasta
 FP-2026-…813  | pro  | 3500.00 | UNCONFIRMED       | PROVISIONAL| 2026-11-19 | 2026-12-19
 FP-2026-…121  | pro  | 3500.00 | EVIDENCE_RECEIVED | NONE       |            |
```
Se ve lo que importa: **un solo periodo de un mes** (19/11 → 19/12) para la empresa que pagó, activación
**provisional**, y la segunda empresa **sin plan ni vencimiento** aunque subió un comprobante con la
misma referencia.

## Pruebas de regresión añadidas
- `bank-transfer.analysis.spec.ts`: fecha de mañana, tolerancia de 30 min, sufijo inválido (vacío y de un
  dígito), `5,000`/`5.000`, cifras ambiguas, fecha ISO e importe con espacio de miles (23/23).
- `license-orders.integration-spec.ts`: las siete pruebas descritas (6–12).
- `license-active-protection.spec.ts`: el doble de transacción incluye `$queryRaw` (el lock nuevo).

## Riesgos que permanecen
1. **OCR no verificado con imágenes reales en producción**: el fixture no tiene motor. La lógica está
   probada con textos; las fotos borrosas y los PDF escaneados siguen sin probar y acabarán en revisión.
2. **El tope de 5 intentos es por empresa y día**: un cliente con muchas sucursales bajo empresas
   distintas podría seguir generando trabajo, aunque cada intento queda auditado.
3. **La referencia es global**: un comprobante de prueba antiguo que compartiera referencia bloquearía
   uno real (iría a revisión, nunca a activación automática).
4. **No se ha probado la subida desde la app Windows** con una imagen real (limitación ya conocida de la
   ventana Flutter en este equipo).
5. `daysForward` sigue existiendo como parámetro (por defecto 0) por compatibilidad; ninguna ruta de
   producción lo usa.
6. **Caducidad de la orden**: `uploadEvidence` no ejecuta el barrido de órdenes vencidas (lo hacen
   `createOrder` y `listOrders`). Si se llama a la API directamente con una orden de más de 48 h cuyo
   estado sigue abierto, el comprobante puede aceptarse. **No produce duplicados ni periodos pisados**
   (el lock y la revalidación siguen actuando), pero conviene decidir si un pago tardío debe ir a
   revisión; endurecerlo cambia una regla de negocio y no se ha hecho sin autorización.

## Veredicto

**PASS** para A1–A6 en local: los periodos pagados se conservan, no hay activaciones duplicadas, la
empresa ACTIVO queda intacta y la activación automática sigue siendo provisional (A7). Sigue **NO-GO a
producción** mientras no se pruebe el OCR con comprobantes reales en el servidor y no se configure el
motor y la cuenta de cobro.
