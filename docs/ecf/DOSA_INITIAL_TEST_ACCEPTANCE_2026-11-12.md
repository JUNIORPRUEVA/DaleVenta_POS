# DOSA: E31 y E34 aceptados con la credencial inicial TEST

Fecha local: **12/11/2026**, alrededor de las 23:10, UTC−4.

## Autorización y separación de identidades

El usuario autorizó probar con la combinación que Alejandro entregó en su
mensaje del 01/11/2026 a las 21:10:24, conservado en
`C:/Users/pc/Downloads/conversacion alejando.zip` (`chat.txt`):

- RNC emisor de pruebas: **133306001**.
- Rango TEST para todos los tipos: **113500–115500**.
- Vencimiento de las secuencias: **31/12/2028**.
- Clave: la credencial TEST inicial asociada a ese mensaje. Su valor no se
  imprime ni se guarda en el informe, los documentos o los logs de evidencia.

Esta identidad no se sustituyó por FULLTECH como emisor. FULLTECH figura
únicamente como receptor de prueba. El nombre y la dirección del emisor en
el documento son etiquetas explícitas de ensayo, no datos verificados de
una razón social comercial.

## Resultado — HECHO

Se hicieron **dos envíos**, uno por tipo. No hubo reintentos, cambios de fecha
para conseguir aceptación ni consumo de numeración de FULLTECH.

| Tipo | e-NCF | Importe | HTTP | Estado observado |
| --- | --- | --- | --- | --- |
| E31 | E310000113500 | RD$118.00 | 200 | Aceptado |
| E34, anulación total del E31 anterior | E340000113500 | RD$118.00 | 200 | Aceptado |

Ambas respuestas contienen código `1`, `secuenciaUtilizada=true`, identidad
del emisor y e-NCF coincidentes. La correlación del adaptador fue satisfactoria.

Referencias de seguimiento:

- E31: `df75d3da-ba24-4b12-94ac-7686ea9637da`.
- E34: `65dce8a3-aeb7-4064-93d3-94a69b0513a7`.

Se consultaron los QR oficiales por GET en
`https://ecf.dgii.gov.do/testecf/consultatimbre`. Ambos respondieron HTTP 200 y
mostraron su e-NCF y **Estado Aceptado**. No son comprobantes productivos.

## Evidencia e integridad

El ejecutor usó los módulos compilados de FullPOS: mapeador, barrera fiscal,
serializador, cliente de emisión y evaluador de respuestas. Primero pasó la
validación sin envío, incluido el rango autorizado y el vencimiento.

Antes de cada POST se creó de forma exclusiva un registro local con e-NCF,
request, huella e identificador de operación. Un registro existente impide
repetir el envío aun después de un error o resultado incierto. El E34 solo
se habilitó después del E31 aceptado, correlacionado y con QR de TEST.

El E34 se envió por `NotaDesdeFactura` con `nuevoENCF` en la query, referencia
al E31 original y sus importes completos. El servidor confirmó su aceptación.

Destino: exclusivamente `https://dosasystem.com`, sin seguir redirecciones.
Credencial: exclusivamente la clave inicial TEST, mantenida en memoria durante
la ejecución y retirada del entorno del proceso al finalizar. No se accedió
a PostgreSQL ni a las credenciales de FULLTECH; no se crearon ventas, caja,
inventario o documentos en su base compartida.

Evidencia local sin claves:

```text
C:/Users/pc/AppData/Local/Temp/dosa-initial-test-evidence-20261112/E310000113500.json
C:/Users/pc/AppData/Local/Temp/dosa-initial-test-evidence-20261112/E340000113500.json
```

| Tipo | SHA-256 del request | SHA-256 del objeto JSON de respuesta |
| --- | --- | --- |
| E31 | c32d3132901cab1f744e7f9476ba3ff38bde5f47a4c8e19ad2348a2eb09659cf | 08ad30acf90d65a2d9d4b2d82e0078001ae086f3842459ec8f8800192d77c1a2 |
| E34 | d1108321aedd7507f8169d043b176c4c724f64412f23a2b6fe953563f45d9768 | 6a717ded0ccc16115fe7dc78dc19b55427bda2632f7f222308b004f6c89eaf19 |

Las huellas de respuesta son del objeto JSON serializado, no de los bytes
originales de la respuesta HTTP. Las páginas QR tienen sus propias huellas
en los ficheros de evidencia.

## Validaciones ejecutadas

```text
node --check %TEMP%/dosa-initial-test-run-20261112.cjs
PASS

node %TEMP%/dosa-initial-test-run-20261112.cjs --dry-run
PASS: readiness=true, expires=31-12-2028, sin envío ni base de producción

node %TEMP%/dosa-initial-test-run-20261112.cjs
PASS: E31 y E34 HTTP 200, ACCEPTED, correlated=true, TEST confirmado

Consultas GET de los QR oficiales DGII TEST
PASS: ambos e-NCF visibles, Estado Aceptado

git diff --check
PASS
```

El ejecutor es temporal, está fuera del repositorio y no se instaló en ningún
servicio. No se modificó código de aplicación en este ciclo; por ello no se
repitió la batería de pruebas de código ya registrada en el informe anterior.

## Estado y límites

**GO para esta prueba externa de E31 y E34 con la identidad inicial TEST.**

Junto con los dos E32 previos de FULLTECH, los tres tipos tienen evidencia de
aceptación externa TEST, pero **en identidades distintas**. No equivale a
probar el flujo normal del POS ni E31/E34 con las credenciales propias de cada
cliente en la aplicación desplegada.

**NO-GO para declarar terminado o desplegado el módulo completo.** El E31 TEST
de FULLTECH con vencimiento 31/12/2027 sigue rechazado por código 145. La
aceptación con otro RNC, otra clave y otra numeración no demuestra cuál de
esos datos causa la discrepancia de FULLTECH. Su postulación, claves y rangos
se conservan sin cambios.

Referencia del caso anterior:
[ensayo FULLTECH](FULLTECH_TEST_EXECUTION_2026-11-12.md).
No hubo commit, push, despliegue ni activación de producción.

## Seguimiento local 2026-11-13

Se implementó y verificó la separación de numeración por ambiente y la conservación segura de metadatos del webhook. No hubo nuevas emisiones externas ni despliegue. Los resultados históricos anteriores conservan su alcance; véase [validación y pendientes](ECF_ENVIRONMENT_NUMBERING_2026-11-13.md).
