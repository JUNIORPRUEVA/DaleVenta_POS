# Orquestación de emisión DOSA multiempresa

Estado: **implementada y probada con transporte falso**. Emisión real: **no
autorizada**.

Este documento describe el eslabón que faltaba entre una venta del POS y el
proveedor DOSA. Antes existían las piezas (mapeador, barrera, compuerta, bóveda,
cliente, cable) pero **nadie las unía**: `DosaEmissionService.emit` no tenía
llamadores y `DosaEmissionWire` nunca se instanciaba.

## 1. Dónde queda conectado

```text
POST /ecf/documents/:id/dispatch-dosa          ← la acción autorizada
  └─ DosaEmissionDispatchService.dispatch()    ← EL ORQUESTADOR (nuevo)
       ├─ 1. documento por { companyId, id }   ← aislamiento
       ├─ 2. e-NCF y RNC de la emisión preparada
       ├─ 3. mapEcfToDosaDraft(fiscalDocument) ← cuerpo DOSA, no el DOM interno
       ├─ 4. autorización fiscal                ← company enabled + provider DOSA
       │                                          + certificationStatus autorizado
       ├─ 5. DosaEmissionService.authorizeForDispatch()
       │       ├─ assessDosaDocumentBarrier     (contenido del comprobante)
       │       ├─ assessDosaEmissionGate        (credencial, ambiente, banderas)
       │       └─ credentials.openForEmission    (bóveda, clave del ambiente)
       ├─ 6. DosaEmissionWire(client)
       └─ 7. EcfEmissionService.dispatchOnce(documentId, wire, { body, fingerprint })
                ├─ reclamo FOR UPDATE
                ├─ una sola tentativa SEND_TO_PROVIDER
                ├─ envío por el transporte
                ├─ evidencia con huella de lo ENVIADO
                └─ estado final (nunca aceptación fiscal automática)
```

## 2. Qué código existente se reutilizó

| Pieza | Archivo | Uso |
| --- | --- | --- |
| Mapeador DOSA | `dosa-ecf.mapper.ts` | Construye `encabezado` + `detallesItems` |
| Barrera del documento | `dosa-emission.barrier.ts` | Valida forma, e-NCF, emisor, unidades y totales |
| Compuerta fiscal | `dosa-emission.gate.ts` | Empresa, proveedor, credencial, ambiente, banderas |
| Bóveda de credenciales | `dosa-credential.service.ts` | Clave por `(empresa, ambiente)` |
| Cliente DOSA | `dosa-emission.client.ts` | Idempotencia, cortacircuitos, clasificación de respuesta |
| Cable | `dosa-emission.wire.ts` | Traduce el cliente al orquestador común |
| Orquestador común | `ecf-emission.service.ts` (`dispatchOnce`) | Reclamo, envío único, evidencia, estado |

No se duplicó ninguna de esas reglas. El único cambio en código existente es que
`dispatchOnce` acepta un `override` opcional con el cuerpo del proveedor y su
huella, para que la evidencia registre **lo que realmente salió** y no el payload
interno preparado.

## 3. Cómo se seleccionan empresa, RNC, ambiente y credenciales

| Dato | Origen | Regla |
| --- | --- | --- |
| `companyId` | `requireTenant(user)` del JWT | El documento se busca con `{ companyId, id }`: un id ajeno se comporta como inexistente |
| RNC emisor | `payloadSummary.emission.senderTaxId` de la emisión preparada | La barrera exige que el cuerpo lleve **ese** RNC; si no, bloquea |
| Ambiente | `DOSA_EMISSION_ENVIRONMENT` del servidor | `TEST` o `PRODUCTION`; nunca lo elige el cliente |
| Credencial | `ecf_dosa_company_credentials` por `(empresa, RNC, ambiente)` | Sin fallback: si falta la del ambiente, no se envía |

## 4. Protección del e-NCF

- El número se consume al **preparar**, con `operationKey` estable
  (`SALE:<id>`): un reintento de la misma venta reutiliza el consumido.
- `dispatchOnce` reclama con `SELECT … FOR UPDATE` y exige cero tentativas
  `SEND_TO_PROVIDER` previas: el segundo despacho del mismo documento es un
  conflicto, no un segundo POST.
- El cliente DOSA mantiene además un conjunto de claves de idempotencia ya
  enviadas y otro de peticiones en vuelo.
- Probado: segundo despacho → `409` y **una sola** tentativa persistida.

## 5. Estados que se persisten

| Momento | Estado del documento | Registro |
| --- | --- | --- |
| Preparado | `LOCAL_VALIDATED` | `payload_summary.emission` (e-NCF, RNC, payload interno) |
| Reclamo | `SEND_IN_PROGRESS` | `ecf_electronic_document_attempts` (`SEND_TO_PROVIDER`) |
| Respuesta correlacionada | `HUMAN_REVIEW_REQUIRED` | `ecf_evidence_receipts` + `status_logs` |
| Fallo de transporte | `UNKNOWN_RESULT` | intento con resultado desconocido |

`DGII_ACCEPTED` **no se escribe nunca** de forma automática.

## 6. Transporte falso y seguridad

`DOSA_EMISSION_TRANSPORT`:

- `FETCH` (por defecto) → cliente HTTP real.
- `FAKE` → `FakeDosaHttpTransport`: no abre sockets, captura la petición y
  devuelve una respuesta canónica.

`FAKE` **sólo** se acepta con `APP_ENV=uat` o `UAT_LOCAL_ONLY=true`. En cualquier
otro entorno la fábrica lanza al arrancar (`ECF_DOSA_FAKE_TRANSPORT_FORBIDDEN`):
un despliegue que herede la variable no puede quedar apuntando a un proveedor
simulado en silencio. Un valor desconocido también lanza
(`ECF_DOSA_TRANSPORT_UNKNOWN`).

Ninguna bandera productiva cambia: `DOSA_EMISSION_ENABLED=false` y
`DOSA_PRODUCTION_EMISSION_ENABLED=false` siguen siendo el valor por defecto, y
con ellas apagadas la compuerta rechaza antes de tocar el transporte.

## 7. Pruebas

| Archivo | Qué demuestra |
| --- | --- |
| `dosa-emission-dispatch.e2e-spec.ts` | 12 casos por HTTP contra el orquestador real con transporte falso: cuerpo con RNC/e-NCF/clave propios, aislamiento, idempotencia, conflicto de credenciales, certificación suspendida, PRODUCCIÓN bloqueada, concurrencia, reinicio y venta normal del POS |
| `dosa-emission.fake-transport.spec.ts` | 9 casos: la selección del transporte falso falla cerrado fuera de UAT local |

## 8. Qué sigue bloqueado por falta de evidencia contractual

Habilitar el transporte real exige resolver, con el proveedor:

- **P1** unidad de `t` en la firma del webhook (segundos o milisegundos).
- **P2** el secreto de 64 hex: ¿texto literal o 32 bytes decodificados?
- **P6** ¿`api_secret` único por empresa o distinto por TEST/PRODUCCIÓN?
- **P9** procedimiento autorizado de rotación y revocación.
- Formato de respuesta de aceptación/rechazo de `EnviarFactura` en producción
  (los estados observados son de la muestra de credenciales, no de emisión).

Mientras eso no esté confirmado, `DOSA_EMISSION_TRANSPORT=FETCH` con la emisión
encendida enviaría documentos a un contrato cuya firma y respuesta no están
verificadas. Por eso el encendido es un acto explícito y no está hecho.

## 9. Qué falta para validar la interfaz

El procedimiento manual con evidencia exigida está en
`docs/ecf/ECF_PORTAL_UI_VALIDATION_PROCEDURE.md`. No se ejecutó: Playwright está
deshabilitado en el entorno de trabajo. Compilar no es validar.
