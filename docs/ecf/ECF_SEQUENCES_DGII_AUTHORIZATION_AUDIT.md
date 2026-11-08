# Auditoría — numeración e-CF por empresa y autorización DGII

Fecha: 2026-11-08 · Rama: `agent/dosa-credentials-split-20261107`
Método: lectura del código real de `apps/api/src/ecf` y de los datos de FULLTECH en producción.
Etiquetas: **HECHO** = verificado en código o en datos · **HIPÓTESIS** = plausible, sin verificar ·
**RECOMENDACIÓN** = propuesta.

---

## 1. Pregunta que responde

Una empresa cierra su certificación con la DGII y esta le autoriza **un rango por tipo de
comprobante** (con cantidad aprobada y, a veces, vencimiento). ¿El sistema obliga a declarar
exactamente lo autorizado, por empresa y por tipo? **Hoy no.**

## 2. Estado actual — HECHO

| Pieza | Comportamiento real |
| --- | --- |
| `EcfSequence` | Ya es **por empresa**: `companyId` + `documentType`, una sola fila activa por tipo |
| `EcfSequenceService.assertType` | Solo acepta `E31` y `E34` (`ALLOCATABLE = ["E31","E34"]`); cualquier otro lanza `ECF_SEQUENCE_TYPE_UNSUPPORTED` |
| Patrón de e-NCF | Regex fija `^E(31|34)\d{10}$` — un e-NCF de otro tipo se rechaza con `ECF_SEQUENCE_PREFIX_INVALID` |
| `assertRange` | Solo coherencia aritmética: entero, `>= 1`, `fin >= inicio`, `<= 9 999 999 999`. **No compara con lo autorizado por la DGII** |
| `register` / `renew` | Impiden dos rangos activos del mismo tipo y prohíben reutilizar números ya consumidos (`ECF_SEQUENCE_REUSE_BLOCKED`) |
| `allocate` | `FOR UPDATE`, consumo permanente, idempotente por `operationKey`, con `ecf_sequence_audit_log`. Correcto |
| `E32` | **Excluido a propósito** del flujo comercial: *«E32 keeps its own single-use sandbox slot: it is deliberately NOT allocatable here»* (`ecf-sequence.service.ts:10`, `ecf-document-query.service.ts:96`) |
| Emisión | El orquestador genérico cubre **solo E31/E34** (`ecf-emission.service.ts:15`) |
| Compuerta DOSA | `DOSA_GATE_SUPPORTED_TYPES = E31, E32, E34` |
| Dónde vive lo autorizado por la DGII | **En ningún sitio**. No hay tabla con número de autorización, rango aprobado, cantidad ni vencimiento |
| UI de numeración | Tarjeta fija en `E31` (`registerSequence(documentType: 'E31')`), sin selector de tipo |

## 3. Lo que ya está bien — HECHO

- El aislamiento multiempresa es correcto: todas las consultas y mutaciones van por
  `companyId` del contexto autenticado; la app nunca envía `companyId`.
- La asignación de números es segura bajo concurrencia e idempotente por operación.
- El consumo no se puede retroceder: `renew` no permite empezar por debajo del número ya entregado.

Esto es la base correcta. El problema no es estructural, es de **validación contra la autorización
real** y de **tipos soportados**.

## 4. Brechas — HECHO

1. **No hay registro de la autorización DGII.** Nada impide declarar 1–1.000 cuando la DGII aprobó
   150. El sistema acepta el rango si es aritméticamente coherente.
2. **`E32` no se puede declarar** en el flujo comercial, aunque la DGII autoriza rangos reales de
   E32 en producción (FULLTECH: 1–10.000).
3. **La UI solo ofrece `E31`**, así que ni siquiera `E34` es declarable desde la aplicación.
4. **El patrón de e-NCF está cerrado a 31/34**, por lo que ampliar tipos exige tocarlo.

## 5. La decisión de diseño que hay que tomar: `E32`

**HECHO**: `E32` está modelado como una **prueba de sandbox de un solo uso**
(`ecf_sandbox_e32_trials`, slot `FIRST_E32_SANDBOX`, URL y dirección sintéticas propias).

**HIPÓTESIS**: esa restricción viene del proceso de **certificación** (la DGII permite una sola
prueba de E32 durante la certificación), no de la operación normal.

**RECOMENDACIÓN**: separar los dos conceptos en lugar de reutilizar el mismo camino.

- `E32` **certificación**: sigue como está, un solo uso, sin tocar.
- `E32` **producción**: rango normal, como `E31`/`E34`, validado contra la autorización.

Separarlos evita romper el flujo de certificación y habilita facturar consumo con rangos reales.

## 6. Alcance propuesto

**Fase A — registro de la autorización DGII (base de todo)**

- Tabla nueva `ecf_dgii_authorized_sequences`: `companyId`, `documentType`, `authorizationNumber`,
  `rangeFrom`, `rangeTo`, `approvedQuantity`, `expiresAt`, `evidenceId`, `source`, timestamps.
  Una fila por empresa y tipo.
- `EcfSequenceService.assertRange` pasa a validar contra esa fila: el rango declarado debe quedar
  **dentro** del autorizado y no superar la cantidad aprobada; si no hay autorización registrada,
  **fail-closed** con código propio.
- Migración aditiva; sin tocar datos existentes.

**Fase B — tipos soportados**

- `E31`, `E32`, `E34` como asignables (los tres que la compuerta DOSA sabe emitir).
- Patrón de e-NCF derivado de la lista de tipos, no escrito a mano.
- `E32` de producción separado del sandbox (ver §5).

**Fase C — interfaz**

- Selector de tipo en la tarjeta de numeración, mostrando por tipo: autorización, rango autorizado,
  aprobado, vencimiento y lo declarado.
- Mensaje explícito cuando se intenta declarar más de lo aprobado.

**No se toca**: compuerta fiscal, bóveda de credenciales, idempotencia, auditoría de asignación ni
el flujo de certificación de `E32`.

## 7. Pruebas que debe traer

- Unitarias de validación: rango dentro / fuera / solapado / cantidad excedida / sin autorización.
- Integración PostgreSQL: declarar `E31` 1–150 con autorización 1–150 (ok) y 1–1.000 (rechazo).
- Integración: `E32` de producción asigna rango; `E32` de sandbox sigue con un solo uso.
- Regresión: `renew` no permite reutilizar números ya consumidos.
- Multiempresa: dos empresas con rangos distintos no se interfieren.

## 8. Preguntas abiertas

1. ¿La autorización la registra el cliente o el administrador de FullPOS?
2. ¿Se adjunta el PDF/XML de la DGII como evidencia obligatoria?
3. ¿Qué tipos debe ofrecer la UI desde el primer día: solo los emitibles (E31/E32/E34) o todos los
   autorizables aunque aún no se emitan?
4. Para `E32`: ¿se confirma que producción usa rango normal y que el sandbox queda solo para la
   certificación?

## 9. Conclusión

**HECHO**: el diseño multiempresa es correcto y la asignación de números es sólida.
**HECHO**: lo que falta es el registro de la autorización DGII y la validación contra él, más
soportar `E32` de producción y el selector de tipo en la interfaz.
**RECOMENDACIÓN**: proceder con las fases A → B → C, en rama aparte y sin tocar lo desplegado.
