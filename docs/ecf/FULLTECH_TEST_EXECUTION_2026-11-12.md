# FULLTECH: ejecución controlada DOSA TEST

Actualización posterior: E31 y E34 fueron aceptados con la **credencial inicial
de Alejandro**, RNC 133306001, rango 113500–115500 y vencimiento 31/12/2028.
Ver [evidencia del ensayo separado](DOSA_INITIAL_TEST_ACCEPTANCE_2026-11-12.md).
Eso no cambia el rechazo E31 de FULLTECH ni sus rangos/configuración.

Fecha local: 2026-11-12. Plan: `FULLTECH_TEST_20261112_SIX`.
Empresa: FULLTECH, SRL (`165e3fca-6225-479b-8805-d2205f10536c`).

## Autorización y límites

El usuario confirmó el rango TEST 1–1.000 y autorizó seis comprobantes como
máximo: dos E31, dos E32 y dos E34. Se mantienen los rangos declarados más
restrictivos de cada tipo (E31 1–150 y E34 1–50). Se acordó detener el lote
ante rechazo o incertidumbre. El usuario confirmó posteriormente el
vencimiento TEST E31 **31/12/2027**.

Se ejecutaron **tres envíos**. No se enviaron el segundo E31 ni los E34 tras
el rechazo del primer E31. No hubo reenvíos ni solicitudes duplicadas.

## Resultados externos — HECHO

| Tipo / escenario | e-NCF | HTTP | Respuesta DOSA | Secuencia usada según DOSA |
| --- | --- | --- | --- | --- |
| E32, efectivo, RD$118.00 | E320000000001 | 200 | Aceptado | sí |
| E32, transferencia, RD$118.00 | E320000000002 | 200 | Aceptado | sí |
| E31, efectivo, RD$118.00 | E310000000001 | 200 | Rechazado, código 145: fecha de vencimiento de secuencia inválida | no |

Ambos QR E32 se consultaron por GET en `fc.dgii.gov.do/testecf/` y mostraron
el e-NCF correspondiente y estado **Aceptado**. No se convirtió esa lectura
en una actualización automática a `DGII_ACCEPTED` en FullPOS.

### Trazabilidad

| e-NCF | Documento FullPOS | Intento de envío |
| --- | --- | --- |
| E320000000001 | 865834b2-9e9a-4b12-bb65-a216ec2db071 | 33a45e56-e45f-46de-baae-49a01cca2572 |
| E320000000002 | 45386133-9bbf-48a1-bf0d-5943b5100b55 | a90cc5d3-7ad5-4e1a-97eb-4802fbda39b1 |
| E310000000001 | ee934377-c272-4489-94dc-e3bc32fe2900 | 8acda0f3-5dec-4108-9d45-948d3fd87f36 |

Huellas SHA-256 de las respuestas:

- E32/1: `9893d42ed355a1e24a2ab4f399b34e7ad96835701b211f5d594c3aa1ca5a3b67`.
- E32/2: `b153fba327d54403888bbcbba9339ed55c3320414e3359bd6efde7f9aad91834`.
- E31/1: `b8a422b8b8f5293aca941077a45c2e5f2c6a2e60319e75824e41e1f6a4c52707`.

## Defectos encontrados y corregidos localmente

1. El despacho descartaba el tipo de ingreso, tipo de pago, plazo y vencimiento
   ya guardados. Ahora recupera esos metadatos del documento preparado.
2. Se conserva la forma de pago original en el documento fiscal. Para pagos
   mixtos/a crédito se descuentan las cobranzas posteriores registradas de esa
   misma venta y empresa. La evidencia incoherente bloquea la preparación.
3. El cuerpo DOSA incluye vencimiento E31, dirección y fecha del emisor, formas
   de pago y tipo de pago numérico. Los precios fiscales son netos, por lo que
   `indicadorMontoGravado=0`, conforme al formato DGII.
4. NotaDesdeFactura recibe `nuevoENCF`, tipo, motivo y fecha en la query. El
   cuerpo conserva el e-NCF y la fecha del original, y las partidas/importes
   que realmente se acreditan. Esto se verificó localmente, no por emisión E34.
5. La primera respuesta real E32 incluía `rncEmisor`, `urlQR` y TrackId nulo.
   Se aceptan esos aliases y se contempla RFCE sin TrackId únicamente cuando
   hay evidencia completa y coincidente de la DGII. E31/E34 conservan el
   requisito de TrackId. Los RNC contradictorios se rechazan.
6. El primer QR contenía un `+` sin codificar en el código de seguridad. Se
   corrige esa discrepancia específica en hosts DGII; después el QR oficial
   mostró el E32 aceptado. La respuesta original y su hash se conservan.

La primera observación E32 se revisó contra el hash de la respuesta guardada y
pasó de `UNKNOWN_RESULT` a `HUMAN_REVIEW_REQUIRED`. No hubo otra llamada de
emisión para conciliarla. El segundo E32 correlacionó en su primera respuesta.

## Ejecución y límites de la evidencia

No se desplegó la aplicación. El ensayo se ejecutó en un proceso administrativo
separado, cargando en memoria los módulos compilados y las credenciales TEST
de la empresa. El proceso de servicio y sus archivos no se reemplazaron.

Antes de enviar se verificaron configuración SANDBOX, producción desactivada,
cadena de autorización, identidad de la empresa y credencial TEST activa. La
clave se abrió solo después de las compuertas y nunca salió del servidor.

**Sí se escribieron registros de ensayo en la base compartida de FULLTECH**,
con autorización del usuario: documentos manuales de prueba, reserva de
numeración, intentos, hashes y logs de estado. El actor se dejó nulo como
acción de sistema; no se inventó un usuario. Una transacción con bloqueos
reservó el número y guardó el intento antes del POST. Un intento previo o un
resultado pendiente/rechazado impide continuar automáticamente.

No se crearon ventas, productos, clientes, movimientos de caja ni inventario.
No se cambiaron credenciales ni parámetros de producción. Esto es evidencia
externa del adaptador y su contrato; el recorrido normal del POS se verificó
por separado en las pruebas locales con transporte simulado/HTTP local.

Lectura posterior:

- E31: próximo número **2**. El 1 permanece reservado localmente para conservar
  trazabilidad, aunque DOSA reportó `secuenciaUtilizada=false`.
- E32: próximo número **3**.
- E34: próximo número **1**, sin envío externo.
- E32/1 y E32/2: `HUMAN_REVIEW_REQUIRED`, observación de proveedor aceptada.
- E31/1: `PROVIDER_REJECTED`.
- Configuración: DOSA / SANDBOX / PRODUCTION_READY / `production_enabled=false`.

## Rechazo E31: revisión concreta

HECHO: la fecha declarada y confirmada por el usuario es 31/12/2027. Se
reconstruyó el JSON desde el documento congelado y sus metadatos: el campo
`encabezado.idDoc.fechavencimientosecuencia` fue **31-12-2027**, con la misma
huella que la tentativa enviada:
`08dd8bd640c88ed9cb16b7ac11e34baf3ce27a3b2daea8422b26de623afb4798`.
La fecha de emisión fue 12-11-2026.

HECHO: ese nombre de campo y formato DD-MM-YYYY coinciden con el README
oficial de DOSA. No se cambió la fecha a 2028 ni se intentaron variantes.

HIPÓTESIS: existe una discrepancia entre la autorización de secuencia en TEST
y la validación/conversión de DOSA/DGII. El error 145 por sí solo no permite
atribuir la causa a FullPOS, DOSA o la configuración de DGII.

### Mensaje preparado para Alejandro — no enviado

> FULLTECH, SRL, en TEST, recibió rechazo DGII 145 al emitir
> E310000000001. El vencimiento confirmado es 31/12/2027 y enviamos
> encabezado.idDoc.fechavencimientosecuencia = "31-12-2027", según su contrato.
> TrackId: ea234daf-74d3-48d0-8aac-ed33ad983375. DOSA respondió HTTP 200,
> estado Rechazado y secuenciaUtilizada=false. Los E32/1 y E32/2 sí fueron
> aceptados. ¿Pueden verificar el vencimiento autorizado de E31 en TEST y el
> valor que llegó al XML de DGII? No solicitamos rotación ni reenvío de claves.

## Validaciones locales

- `npm run api:build`: PASS en la copia aislada, sin `.env` del proyecto.
- `npm --workspace apps/api test -- --testPathPatterns='dosa|ecf-sale'`:
  45 suites / 737 pruebas PASS; 14 suites y 142 pruebas omitidas.
- `npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts`:
  2 suites / 25 pruebas PASS, código 0.
- Suite completa antes del ajuste RFCE: 269 suites / 3217 pruebas PASS,
  13 suites y 101 pruebas omitidas, código 0.
- `npm --workspace apps/api test -- --testPathPatterns='dosa-provider-response|dosa-emission.spec|dosa-request.serializer|dosa-contract-completion|ecf-sale-payment-forms'`:
  5 suites / 70 pruebas PASS, código 0.
- Una pasada de regresión final falló por errores de conexión local
  `EADDRINUSE 127.0.0.1:55500`/servidor no accesible durante las integraciones
  PostgreSQL. El contenedor respondió a `pg_isready` y la conexión TCP posterior
  fue exitosa. La repetición limpia, sin cambiar código ni debilitar pruebas,
  terminó con **269 suites y 3228 pruebas PASS**, 13 suites y 101 pruebas
  omitidas, sin suites fallidas (`fullpos-ecf-metadata-all-clean.log`).
- `git diff --check`: PASS.

Logs: `%TEMP%/fullpos-ecf-metadata-*` y `%TEMP%/fullpos-ecf-rfce-*`.
El ejecutor temporal quedó con `send=false` y no se instaló en el servicio.

## Archivos modificados en este ciclo

```text
apps/api/src/ecf/fiscal-core/ecf-fiscal-document.ts
apps/api/src/ecf/pos/ecf-sale-adapter.ts
apps/api/src/ecf/pos/ecf-sale-fiscal.adapter.ts
apps/api/src/ecf/pos/ecf-sale-payment-forms.ts
apps/api/src/ecf/pos/ecf-sale-payment-forms.spec.ts
apps/api/src/ecf/provider/dosa/dosa-ecf.contract.ts
apps/api/src/ecf/provider/dosa/dosa-ecf.mapper.ts
apps/api/src/ecf/provider/dosa/dosa-ecf.spec.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts
apps/api/src/ecf/provider/dosa/dosa-emission.client.ts
apps/api/src/ecf/provider/dosa/dosa-emission.spec.ts
apps/api/src/ecf/provider/dosa/dosa-emission.wire.ts
apps/api/src/ecf/provider/dosa/dosa-request.serializer.ts
apps/api/src/ecf/provider/dosa/dosa-request.serializer.spec.ts
apps/api/src/ecf/provider/dosa/dosa-contract-completion.spec.ts
apps/api/src/ecf/provider/dosa/dosa-provider-response.ts
apps/api/src/ecf/provider/dosa/dosa-provider-response.spec.ts
apps/api/src/ecf/provider/dosa/dosa-response.mapper.ts
docs/PRODUCT_SPEC.md
docs/ecf/DOSA_TEST_PREFLIGHT_2026-11-12.md
docs/ecf/FULLTECH_TEST_EXECUTION_2026-11-12.md
```

## Estado

NO-GO para declarar terminado el módulo: dos E32 externos aceptados y un E31
rechazado; E31 restante y E34 pendientes. Sin commit, push, despliegue ni
activación de emisión productiva.

## Seguimiento local 2026-11-13

Se implementó y verificó la separación de numeración por ambiente y la conservación segura de metadatos del webhook. No hubo nuevas emisiones externas ni despliegue. Los resultados históricos anteriores conservan su alcance; véase [validación y pendientes](ECF_ENVIRONMENT_NUMBERING_2026-11-13.md).

## Resolución posterior — 2026-11-13

Alejandro confirmó vencimiento TEST 31/12/2028 y rango TEST 1–10.000.000 para FULLTECH. Con autorización del usuario se emitieron un E31 nuevo y su E34 de anulación; ambos fueron aceptados y comprobados en DGII TEST bajo RNC 133080206. El rechazo histórico E31/1 se conserva; no se reutilizó su numeración. Véase [aceptación FULLTECH E31/E34](FULLTECH_TEST_ACCEPTANCE_2026-11-13.md). El pendiente externo de ese ensayo está resuelto; el despliegue y recorrido completo POS mantienen sus verificaciones pendientes.
