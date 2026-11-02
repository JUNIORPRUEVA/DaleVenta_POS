# DOSA — primera emisión TEST: procedimiento controlado

Estado (2026-11-02): **PREPARADO, NO EJECUTADO**. Este documento describe el
único envío controlado de un comprobante de prueba que se hará **cuando lo
autorice expresamente la persona responsable**, con credenciales y secuencia de
TEST. En esta tarea no se transmitió nada, ni TEST ni productivo.

---

## 1. Qué se va a enviar y qué queda fuera

| Elemento | Estado |
| --- | --- |
| E31 (factura de crédito fiscal) | **Cubierto** por el probador `dosa-test-emission.probe.cli.ts` |
| E32 (consumidor final) | Mapeado y validado por la barrera; **sin probador propio** |
| E34 (nota de crédito) | Mapeado y validado por la barrera; **sin probador propio** |
| Nota de crédito desde factura (`NotaDesdeFactura`) | Constante de ruta definida, **sin probador**: no hay ejemplo oficial de `codigoModificacion` |
| Consulta de estado posterior | **No existe** endpoint documentado: no se inventa |

Un único comprobante por ejecución, con una sola tentativa por documento
(`DOSA_RETRY_POLICY.maxAttemptsPerDocument = 1`).

---

## 2. Precondiciones (todas obligatorias)

1. **Autorización expresa** de la persona responsable, indicando el `eNCF` exacto.
2. `DOSA_EMISSION_ENVIRONMENT=TEST` y `DOSA_BASE_URL=https://dosasystem.com`.
3. `DOSA_TEST_API_KEY` con la clave de **TEST** entregada por DOSA (nunca la de
   producción; no hay sustitución entre entornos en ningún punto del código).
4. `DOSA_TEST_RNC` con el RNC de prueba acordado (por defecto `133306001`). Si no
   coincide con el emisor del comprobante, la compuerta bloquea con
   `TEST_RNC_MISMATCH`.
5. Rango de secuencia **autorizado por DOSA** en
   `DOSA_TEST_SEQUENCE_PREFIX` / `_FROM` / `_TO`. No se inventa un rango ni se
   reutiliza uno productivo.
6. **Código de unidad de medida** (`--unidad` o `DOSA_TEST_UNIT_OF_MEASURE`).
   DOSA la exige y su catálogo no está documentado en los materiales que
   tenemos: **no hay valor por defecto**, lo aporta el operador.
7. Almacén de evidencia escribible (`DOSA_PROBE_EVIDENCE_FILE`, por defecto
   `.dosa-probe/evidence.jsonl`).

Ninguna de estas variables se imprime en la salida del probador.

---

## 3. Paso 1 — dry-run (no toca la red)

Desde `apps/api`, con `dist` construido:

```
node dist/ecf/provider/dosa/dosa-test-emission.probe.cli.js \
  --encf=E31000113500 --unidad=<CODIGO> --dry-run
```

Qué comprueba, en este orden:

1. La configuración de entorno (entorno, URL base, RNC, rango de secuencia).
2. El cuerpo con **la misma barrera del punto de envío**
   (`assessDosaDocumentBarrier`): forma del contrato, `tipoeCF`/`eNCF`
   coherentes, emisor igual al RNC de la empresa, `unidadMedida` por línea,
   indicadores en catálogo, importes y totales que cuadran.
3. Que hay clave de TEST cargada y que el `token` de autorización es el
   esperado para ese `eNCF`.

Salida esperada: `{ "mode": "dry-run", "ready": true, ... }` y código de salida
`0`. Cualquier `blockedReasons` no vacío **detiene el procedimiento**: no se
envía nada.

Si falta la unidad de medida, el probador falla con
`DOSA_PROBE_UNIT_OF_MEASURE_REQUIRED`. Si el cuerpo no pasa la barrera, falla con
`DOSA_PROBE_DOCUMENT_BLOCKED` y la lista de motivos.

---

## 4. Paso 2 — envío único autorizado

Solo con la autorización del punto 2.1 y tras un dry-run en verde:

```
node dist/ecf/provider/dosa/dosa-test-emission.probe.cli.js \
  --encf=<ENCF_AUTORIZADO> --unidad=<CODIGO> --token=<TOKEN_DE_AUTORIZACION>
```

El `token` lo calcula `probeAuthorizationToken(encf)`; existe para que un envío
externo no pueda ocurrir por descuido (el dry-run lo imprime para que se sepa
qué valor hace falta, pero sin autorización el probador no envía).

---

## 5. Cómo interpretar la respuesta

La clasificación viene de `classifyDosaResponse` y **nunca** es una aprobación
fiscal nuestra:

| Respuesta | Lectura correcta |
| --- | --- |
| `codigo: 1` | `ACCEPTED` según la tabla del proveedor |
| `codigo: 2` | `REJECTED`; los `mensajes` de la DGII se muestran tal cual |
| `codigo: 3` | `IN_PROCESS`; no se reintenta solo |
| `codigo: 4` | `CONDITIONALLY_ACCEPTED`; `isDgiiApproval = false` |
| `codigo: 0` | **`UNRESOLVED`**: la tabla dice «No encontrado» y el ejemplo dice «Rechazado». No se elige una de las dos |
| Código desconocido | `UNRESOLVED` con `DOSA_STATUS_CODE_UNKNOWN` |
| HTTP 502 «Error de envío» | Único caso marcado como reenviable con el mismo `eNCF` (`safeToRetrySameEncf`) |
| Timeout / sin respuesta | `unconfirmed: true`; **no se reenvía automáticamente** |

Reglas de la política de reintentos (`DOSA_RETRY_POLICY`): una tentativa por
documento, sin reintento en desconocido, timeout ni rechazo, y
`requiresHumanReconciliationOnUnknown: true`.

Casos específicos a observar en la primera prueba:

- **E32 sin `trackId`** en la respuesta: se registra como ausencia de dato, no
  como aceptación. No se rellena con un valor inventado.
- **Nota de crédito (E34)**: si la respuesta no indica el comprobante modificado,
  se queda sin resolver; no se reinterpreta.
- **`secuenciaUtilizada`**: se guarda tal como lo reporte el proveedor, porque
  determina si un envío fallido consume la secuencia.

---

## 6. Condiciones de aborto

Detener el procedimiento y no reintentar si:

- El dry-run devuelve cualquier `blockedReasons`.
- El entorno no es `TEST` o la URL base no es la oficial.
- El `eNCF` ya aparece en `.dosa-probe/evidence.jsonl` (envío previo).
- La respuesta es `UNRESOLVED`, `unconfirmed` o `IN_PROCESS`: se escala a
  reconciliación manual con la evidencia guardada.
- Aparece cualquier indicio de credencial productiva.

Nunca se escala a producción ni se cambia de entorno dentro de este
procedimiento: `DOSA_PRODUCTION_EMISSION_ENABLED` es independiente y no se toca
aquí.

---

## 7. Qué NO hace este procedimiento

- No activa emisión electrónica de ninguna empresa.
- No crea postulaciones en la DGII.
- No habilita `ecf_enabled`.
- No consume secuencias productivas.
- No declara compatibilidad con DOSA: eso exige verificar una **firma auténtica**
  del webhook y una respuesta real aceptada, con evidencia guardada.
