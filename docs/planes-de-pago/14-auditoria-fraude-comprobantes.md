# Auditoría de escenarios adversarios — lectura de comprobante y activación

Fecha: 2026-11-19 · Rama `agent/planes-de-pago-impl-20261116` · Base local `planes_local`
Alcance: `POST /license/orders/:id/evidence` → OCR → reglas → `applyPlan`.
Método: lectura del código real + **sondeo ejecutado** de `parseBankReceipt`/`validateBankTransfer` con 20
casos adversarios (el sondeo era temporal y se borró; no se modificó código de producción).

## 1. Lo que aguanta (medido, no supuesto)

| Escenario | Resultado medido |
| --- | --- |
| Importe exacto (5.000,00) | **ACTIVA** |
| 4.999,00 (1 peso menos) | rechaza `AMOUNT_EXACT` |
| 4.950,00 (−1%) y 4.949,00 | rechaza `AMOUNT_EXACT` |
| 5.050,00 (+1%) y 5.500,00 | rechaza `AMOUNT_EXACT` |
| Formato RD `5.000,00` / US `5,000.00` / sin decimales `5000` | lee 5.000 y **ACTIVA** |
| Referencia ya usada | rechaza `REFERENCE_NOT_REUSED` |
| Cuenta destino distinta | rechaza `DESTINATION_ACCOUNT` |
| Otro banco no reconocido | rechaza `BANK_IDENTIFIED` |
| Operación «pendiente» | rechaza `OPERATION_SUCCESSFUL` |
| Comprobante sin referencia | rechaza `BANK_REFERENCE` |
| Comprobante de hace 5 días | rechaza `RECEIPT_RECENT` + `DATE_COMPATIBLE_WITH_ORDER` |
| Mismo archivo dos veces (secuencial) | 409 `EVIDENCE_DUPLICATE`, no re-activa (cubierto por `license-orders.integration-spec.ts`) |
| Sin motor OCR | **no activa**: cae a revisión (`ocr-not-configured`) |
| Empresa suspendida | no activa (`companyActive` exige `status ACTIVE`) |

Conclusión parcial: la tolerancia del 1% de `evaluateEvidence` **no es explotable**, porque para activar se
exige además `bankValidation.passed`, que es exacto al céntimo.

## 2. Hallazgos

### A1 · ALTA · Doble subida concurrente no está serializada
- **Qué pasa:** la guarda «la orden sigue abierta» y la comprobación de duplicado se hacen **fuera** de la
  transacción (`license-orders.service.ts` ~L428-465), y el OCR tarda entre 1 y 45 s **antes** de abrirla.
  Dentro de la transacción (L548+) no se vuelve a leer la orden ni se bloquea la fila; `applyPlan` lee el
  vencimiento con `findUnique` y escribe un valor ya calculado (`license-activation.service.ts` L100 y L130).
- **Impacto:** dos comprobantes **distintos** subidos a la vez (o uno mientras el otro está en OCR) generan
  dos evidencias y dos activaciones: o se **suman dos veces** los meses, o la segunda pisa a la primera y el
  cliente **pierde un mes pagado**. El único `@@unique([companyId, sha256])` protege solo el **mismo** archivo.
- **Secundario:** el mismo archivo en paralelo revienta por `P2002` **sin traducir** → **500** en lugar de 409.
- **Corrección propuesta:**
  1. Al entrar en la transacción: `SELECT id, status FROM license_payment_orders WHERE id = $1 FOR UPDATE` y
     revalidar `status IN ('CREATED','AWAITING_TRANSFER')`; si ya no está abierta → `409 ORDER_NOT_PAYABLE`.
  2. Insertar la evidencia **antes** de activar y traducir `P2002` a `409 EVIDENCE_DUPLICATE`.
  3. En `applyPlan`, mover el cálculo a una escritura condicional (`updateMany` con `where` sobre el estado
     leído) y comprobar `count === 1`, o leer la empresa con `FOR UPDATE` dentro de la misma transacción.
  4. Prueba de regresión con dos subidas concurrentes (dos `Promise.all`, archivos distintos) que compruebe
     **un solo** periodo aplicado.

### A2 · MEDIA-ALTA · Un comprobante con fecha **futura** activa
- **Qué pasa:** medido. Con fecha de mañana, `RECEIPT_RECENT` y `DATE_COMPATIBLE_WITH_ORDER` pasan y el
  comprobante **ACTIVA**. Solo se comprueba el límite inferior (hoy o ayer), no el superior.
- **Impacto:** rebaja el listón del fraude: basta un texto con importe exacto, cuenta correcta y **cualquier
  fecha de hoy en adelante** (el OCR no distingue un comprobante fabricado).
- **Corrección propuesta:** nueva comprobación `RECEIPT_NOT_FUTURE` (tolerancia de ~30 min por desfase de
  reloj) dentro de `validateBankTransfer`; y un caso en `bank-transfer.analysis.spec.ts`.

### A3 · MEDIA · La cuenta destino deja de comprobarse con una configuración mala
- **Qué pasa:** medido. Con sufijo `''` o de un solo dígito (`'3'`), el comprobante **ACTIVA**: la regla
  `DESTINATION_ACCOUNT` se omite en vez de fallar. El sufijo sale de `authorizedAccountSuffix()` (últimos 4
  de `LICENSE_BANK_ACCOUNT`) con respaldo `AUTHORIZED_ACCOUNT_SUFFIX = '0753'`.
- **Impacto:** un error de configuración desactiva en silencio el control que impide pagar a la cuenta de
  otra persona.
- **Corrección propuesta:** validar que el sufijo tenga **4 dígitos** al leerlo; si no, registrar el error y
  **rechazar** la validación (fallo cerrado), no omitirla.

### A4 · MEDIA · Ámbito y fallo abierto de la referencia bancaria
- **Qué pasa:** `referenceAlreadyUsed()` busca por `companyId`, así que la **misma** referencia puede usarse
  en otra empresa (mismo dueño con dos negocios). Y si el filtro JSON falla, el `catch` devuelve `false`:
  se permite reutilizar la referencia.
- **Corrección propuesta:** decidir el ámbito (global es lo correcto para una cuenta bancaria única) y
  convertir el `catch` en fallo cerrado: marcar la evidencia para revisión y **no** activar.

### A5 · MEDIA-BAJA · Falsos negativos de lectura (pagan clientes legítimos)
- **Qué pasa:** medido. `5 000.00` (espacio de miles) se lee como **5** → rechazo; una fecha en formato ISO
  (`2026-11-18`) **no se reconoce** → rechazo. Ambos van a revisión manual: no es fraude, es fricción y
  trabajo para soporte.
- **Corrección propuesta:** normalizar separadores (espacio normal, espacio fino, apóstrofo) antes de parsear
  el importe, y aceptar ISO además de `dd/mm/aaaa`.

### A6 · BAJA · Inconsistencias de límites y de mensajes
- Dos topes distintos: `MAX_EVIDENCE_BYTES = 10 MB` (storage) y `EVIDENCE_MAX_BYTES = 8 MB` (validación).
- `MAX_DAILY_UPLOADS = 3` por empresa y día: un cliente que se equivoque tres veces queda bloqueado hasta
  mañana (el mensaje lo dice, pero conviene revisar si 3 es el número correcto).

### A7 · RIESGO ACEPTADO · El OCR transcribe, no verifica
Un comprobante fabricado con el texto correcto (banco, cuenta, importe exacto, referencia nueva, fecha de
hoy) activa. La defensa real es la **activación provisional** (`UNCONFIRMED`) más la revisión humana y la
referencia única. Debe quedar escrito en la documentación de soporte, no presentarse como «pago verificado».

## 3. Limitaciones de esta auditoría
- A1 está **confirmada por lectura del código**, **no reproducida en vivo** (haría falta montar dos subidas
  simultáneas con imágenes distintas). Se puede reproducir en local con un script si se autoriza.
- No se probaron: PDF escaneado real, foto borrosa, comprobante de otro país ni manipulación de imagen.
- El sondeo usó textos sintéticos; el OCR real (RapidOCR) se validó por separado en la fase anterior.

## 4. Prioridad recomendada
1. **A1** (dinero: meses duplicados o perdidos) y **A2** (fecha futura) — antes de cualquier uso real.
2. **A3** y **A4** — configuraciones que desactivan controles en silencio.
3. **A5** — calidad de servicio (falsos rechazos).
4. **A6** y **A7** — documentación y coherencia.

Ningún cambio de esta auditoría está aplicado: hay que autorizarlo y, si se aplica, ejecutar
`npm test`, los e2e de licencias y `license-scenarios-evidence.ps1 -RunSuites` para confirmar que la empresa
ACTIVO sigue intacta.
