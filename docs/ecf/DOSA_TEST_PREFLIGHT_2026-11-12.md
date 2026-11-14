# DOSA TEST: comprobación externa y corrección del envoltorio de líneas

Esta nota conserva la fase histórica de preflight. El usuario confirmó después
el rango y el vencimiento TEST. La ejecución posterior, con dos E32 aceptados
y un rechazo E31, está en [FULLTECH TEST](FULLTECH_TEST_EXECUTION_2026-11-12.md).

Revisión iniciada el 2026-11-12 (hora local). Las dos comprobaciones de forma
respondieron el 2026-11-13 a las 02:01:59 UTC. Empresa: FULLTECH, SRL.

## Alcance y seguridad

HECHO: no se repitió la postulación, no se cambiaron credenciales y no se
habilitó emisión productiva. Las consultas a la base compartida se ejecutaron
en transacciones READ ONLY. Las claves se abrieron únicamente en memoria del
servidor para las comprobaciones TEST autorizadas; no se copiaron al equipo,
al repositorio ni al informe.

Las peticiones de comprobación a EnviarFactura carecían de e-NCF, emisor y
partidas facturables. No son emisiones ni pruebas de aceptación fiscal.

## Resultado externo observado

Destino documentado: https://dosasystem.com/fe/api/emision/ecf/EnviarFactura.
La documentación oficial consultada fue el README de
https://github.com/alapaix13/DosaInvoicecloud-Documentation y el JavaScript
público de https://dosasystem.com/dosainvoicecloud/developers.

| Comprobación | HTTP | Resultado observado |
| --- | --- | --- |
| EnviarFactura, sin clave y cuerpo vacío | 401 | Ruta de emisión alcanzable; exige autenticación |
| EnviarFactura, clave TEST de FULLTECH y cuerpo vacío | 400 | Rechazo de datos incompletos, sin documento fiscal |
| ValidarDatos, clave TEST y consulta del propio RNC | 404 | La ruta mostrada en los ejemplos no está disponible; no demuestra que la clave sea inválida |
| EnviarFactura, detallesItems como array vacío, sin e-NCF | 400 | «La solicitud no contiene datos válidos.» |
| EnviarFactura, detallesItems como objeto con items vacío, sin e-NCF | 400 | «El campo eNCF es obligatorio y debe tener 13 caracteres.» |

Huellas SHA-256 de los cuerpos de respuesta de las dos últimas comprobaciones:

- Array: `1e76976e982d05a649f35197a38ebf20ddbbf832e75f30644d3117dffa375838`.
- Objeto: `7393c18cad73fb87aa1e04a7ba355f78f71057de364f154c1335e6a856bf92fc`.

HECHO: el contrato publicado exige `detallesItems.items`. El cliente enviaba el
array interno directamente. Las respuestas externas distinguen ambas formas;
no constituyen validación de un documento completo.

## Corrección local

- Un serializador compartido conserva el borrador interno y genera el
  envoltorio de líneas del proveedor.
- Lo usan el cliente HTTP, el probador TEST y el orquestador antes de calcular
  la huella del request. Serializar un cuerpo ya convertido no lo envuelve de
  nuevo.
- Se conservan empresa, identidad fiscal, API Key, comprobante, importes,
  referencia de E34 y reglas de envío único.
- Las pruebas de despacho inspeccionan ahora el cuerpo HTTP con `items`.
- No se cambió ningún esquema Prisma ni se añadieron migraciones.

## Lo que esta corrección no acredita

La aceptación por DOSA de un comprobante completo sigue pendiente. También
debe revisarse el resto del contrato antes de ese envío: el orquestador actual
llama al mapeador solo con el e-NCF y no recupera los metadatos fiscales ya
guardados en el payload preparado; el mapeador documenta además la omisión de
`tablaFormasPago`. No se deben inventar esos datos para conseguir una respuesta
positiva del proveedor.

El procedimiento `docs/ECF_DOSA_PRIMERA_EMISION_TEST.md` exige un rango
autorizado para TEST y prohíbe reutilizar uno productivo. Las declaraciones de
FULLTECH existen (E31 1–150, E32 1–1.000, E34 1–50), pero por sí solas no
identifican un rango separado o expresamente habilitado por DOSA para TEST.
Se solicitó esa confirmación sin pedir claves ni repetir adjuntos.

## Validaciones

- `flutter analyze`: PASS, sin incidencias.
- Pruebas Flutter de Empresa/drawer, modos fiscales y selector: 46 PASS.
- Pruebas focalizadas de serialización, cliente, selección de claves y probador:
  4 suites, 73 PASS.
- `npm run api:build` en copia aislada: PASS antes del ajuste equivalente que
  guarda el resultado del serializador en una variable local.
- Repetición del build mientras Jest seguía abierto: EPERM de Windows al
  reemplazar la DLL de Prisma; no es un error de TypeScript. La validación final
  se repitió después de que terminaron las pruebas: `npm run api:build`, PASS,
  código 0, con generación de Prisma y compilación de TypeScript.
- E2E DOSA con PostgreSQL y transporte simulado/HTTP local: 2 suites, 25 PASS
  y código de salida 0. Apareció el aviso preexistente de cierre tardío de Jest.
- `npm --workspace apps/api test` con PostgreSQL e-CF local habilitado: 267
  suites y 3209 pruebas PASS; 13 suites y 101 pruebas omitidas; código 0.
- `npx tsc -p tsconfig.build.json --noEmit` sobre la fuente final: PASS,
  código 0.
- El primer intento E2E falló en la preparación del entorno porque no se
  aplicó el usuario predeterminado `postgres`; se corrigió solo el comando de
  ejecución y se repitió. No se cambiaron permisos ni pruebas para resolverlo.

Los logs locales usan el prefijo `%TEMP%/fullpos-ecf-wire-`.

La consulta posterior en READ ONLY confirmó los tres contadores en 1, cero
documentos fiscales y `production_enabled=false` para FULLTECH. No se consumió
numeración con las comprobaciones externas.

## Archivos de esta corrección

```text
apps/api/src/ecf/provider/dosa/dosa-request.serializer.ts
apps/api/src/ecf/provider/dosa/dosa-request.serializer.spec.ts
apps/api/src/ecf/provider/dosa/dosa-emission.client.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts
apps/api/src/ecf/provider/dosa/dosa-emission.wire.ts
apps/api/src/ecf/provider/dosa/dosa-test-emission.probe.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
docs/ecf/DOSA_TEST_PREFLIGHT_2026-11-12.md
docs/design-research/2026-11-12/ecf-settings-restored/VALIDATION.md
```

## Estado

NO-GO para declarar terminado el módulo o desplegar esta corrección como cierre
de emisión fiscal. Falta validar el contrato completo, el rango TEST y una
emisión externa trazable. No se realizó commit, push ni despliegue.
