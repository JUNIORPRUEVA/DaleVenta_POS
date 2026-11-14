# FULLTECH: aceptación externa TEST E31 y E34 — 2026-11-13

## Resultado

HECHO: dos envíos nuevos y únicos de FULLTECH SRL, RNC 133080206, aceptados por DOSA y comprobados mediante GET en las consultas oficiales TEST de DGII. E31 por RD$118.00 y E34 de anulación total del mismo E31 por RD$118.00. No se emitió ningún comprobante productivo.

## Confirmación del proveedor y autorización

El usuario transcribió la respuesta de Alejandro: vencimiento TEST 31/12/2028 y rango TEST del 1 al 10.000.000 para su RNC. Después autorizó expresamente ejecutar las pruebas E31/E34. Esta confirmación reemplaza la fecha TEST 31/12/2027 utilizada en el ensayo rechazado; no altera la fecha productiva del correo.

El ensayo se limitó a un E31 nuevo y, solo tras aceptación correlacionada, un E34 que lo anula. Se conservaron los rangos operativos más restrictivos ya registrados (E31 1–150 y E34 1–50). No se amplió ningún rango a diez millones ni se modificaron autorizaciones productivas. La fecha confirmada de 2028 se incorporó a los metadatos de este ensayo TEST, sin sobrescribir las declaraciones históricas.

## Resultados

| Tipo | e-NCF | Importe | DOSA | DGII TEST |
| --- | --- | --- | --- | --- |
| E31 | E310000000002 | RD$118.00 | HTTP 200, Aceptado, secuencia usada | HTTP 200, Aceptado |
| E34 | E340000000001 | RD$118.00 | HTTP 200, Aceptado, secuencia usada | HTTP 200, Aceptado |

El E34 referencia al E31 E310000000002 y su documento FullPOS. Ambos emisores coinciden con RNC 133080206. Las respuestas incluyen TrackId, numeración y secuencia utilizada; el evaluador existente devolvió correlated=true. Las páginas oficiales incluyen el e-NCF exacto y la celda Aceptado. El navegador de búsqueda no pudo abrir la consulta E31; la verificación se completó por GET HTTP directo, guardando el hash de cada página.

- [Consulta oficial E31](https://ecf.dgii.gov.do/testecf/consultatimbre?RNCEmisor=133080206&RncComprador=133306001&ENCF=E310000000002&FechaEmision=13-11-2026&MontoTotal=118.00&FechaFirma=13-11-2026%2008%3A45%3A19&CodigoSeguridad=S9Qvrj)
- [Consulta oficial E34](https://ecf.dgii.gov.do/testecf/consultatimbre?RNCEmisor=133080206&RncComprador=133306001&ENCF=E340000000001&FechaEmision=13-11-2026&MontoTotal=118.00&FechaFirma=13-11-2026%2008%3A46%3A17&CodigoSeguridad=a2tJ/S)
- [Evidencia estructurada sin credenciales](FULLTECH_TEST_ACCEPTANCE_2026-11-13.json)

## Trazabilidad

| Tipo | Documento FullPOS | Intento SEND_TO_PROVIDER |
| --- | --- | --- |
| E31 | ae731f98-d425-4a9e-8358-14b8be7904cd | f88f76ac-197e-41d7-96d2-5ae462ef3496 |
| E34 | 501d9c0b-a4fe-489a-bf7e-5185e7847daf | dddfcd52-7f11-4322-8f4e-9414ec27f781 |

Plan: FULLTECH_TEST_20261113_CONFIRMED. Hashes de las respuestas:

- E31: 371bedfad7c0161f06c872b3474bbf40eacf10960f4e7119c8ea7796da63af40
- E34: 81f4ad79db1f19817e49744a97b1d057d3bc73e2907450f720bca6a01e9c5c82

La lectura posterior READ ONLY comprobó un intento de envío por documento y el vínculo originalDocumentId del E34. La base mantiene estado HUMAN_REVIEW_REQUIRED para ambos, con evidencia externa ACCEPTED correlacionada: no se forzó DGII_ACCEPTED ni se cambió la política conservadora de conciliación.

## Operaciones realizadas y límites

Se usó un proceso administrativo temporal separado, con los módulos fiscales compilados y verificados localmente, las compuertas existentes y la credencial TEST cifrada de la empresa. La clave solo se abrió en memoria del servidor y nunca se imprimió ni se copió al repositorio. El proceso normal del servicio no se reemplazó ni se reinició. Solo se permitieron las dos rutas de emisión documentadas bajo https://dosasystem.com; sin redirecciones ni reintentos automáticos.

SÍ hubo escrituras de ensayo autorizadas en la base compartida de FULLTECH: reservas de numeración, documentos manuales TEST, intentos y registros de estado. Los contadores existentes quedaron E31 siguiente=3, E32 siguiente=3, E34 siguiente=2. Estos números no deben reutilizarse. El ensayo utilizó el motor desplegado anterior a la migración de ambiente; la evidencia TEST queda explícita en controlledTest y la clasificación histórica sigue siendo necesaria antes de desplegar la migración nueva.

La consulta posterior confirmó environment=SANDBOX, productionEnabled=false y certificationStatus=PRODUCTION_READY. No se cambiaron configuración, credenciales ni rangos productivos. No se crearon ventas comerciales, productos, clientes, caja ni movimientos de inventario. El ejecutor temporal quedó con send=false, incluso si se le pasa --send.

## Validaciones realmente ejecutadas

- node /tmp/fulltech-confirmed-test-20261113.cjs: preflight E31 PASS, sin envío.
- node /tmp/fulltech-confirmed-test-20261113.cjs --send: E31 ACCEPTED correlacionado.
- node /tmp/fulltech-confirmed-test-20261113.cjs --e34: preflight E34 PASS, sin envío.
- node /tmp/fulltech-confirmed-test-20261113.cjs --e34 --send: E34 ACCEPTED correlacionado.
- GET a cada consulta oficial DGII TEST: HTTP 200, e-NCF exacto y Aceptado.
- node /tmp/fulltech-test-postcheck-20261113.cjs: READ ONLY PASS, dos documentos, un intento por documento, vínculo E34 correcto y producción desactivada.
- node --check del ejecutor temporal local y remoto: PASS, código 0.

Logs locales: %TEMP%/fulltech-confirmed-e31-20261113.log, fulltech-confirmed-e34-20261113.log y fulltech-test-postcheck-20261113.json. No se repitieron análisis/build/tests del producto porque en este ciclo no se modificó su código; se reutilizó el build validado en el informe de separación de ambientes.

Referencia contractual consultada: [DOSA NotaDesdeFactura](https://github.com/alapaix13/DosaInvoicecloud-Documentation/blob/main/NOTAS_CREDITO_DESDE_FACTURA.md).

## Alcance del GO

GO para el ensayo externo E31 y E34 de FULLTECH. Junto con los dos E32 anteriores, FULLTECH tiene evidencia externa de aceptación TEST para E31, E32 y E34 bajo su propia identidad.

No equivale a GO de despliegue o cierre total del módulo: faltan la clasificación histórica/migración por ambiente y la validación externa del recorrido normal del POS con la versión desplegada. No hubo commit, push, migración, despliegue ni activación de emisión productiva en este ciclo.

## Archivos de este ciclo

- docs/ecf/FULLTECH_TEST_ACCEPTANCE_2026-11-13.md
- docs/ecf/FULLTECH_TEST_ACCEPTANCE_2026-11-13.json
- docs/ecf/FULLTECH_TEST_EXECUTION_2026-11-12.md (enlace de actualización)
- docs/ecf/ECF_ENVIRONMENT_NUMBERING_2026-11-13.md (resolución de la confirmación pendiente)
