# Confirmación para primera prueba E32 — borrador NO ENVIADO

Asunto: Dirección válida del emisor para primera E32 Sandbox — Fullpos Cloud / FULLTECH

Hola, equipo Alanube:

Estamos listos para completar la preparación local de una única factura E32
sintética en DOM Sandbox. Todavía no hemos emitido ni consumido numeración.
Ya recibimos oficialmente estos datos de pruebas:
RNC 132109122, rango numérico 9805001–9806000 y vencimiento 31/12/2028.
No solicitamos certificación productiva. Según el formato del contrato E32 y
sus ejemplos, el candidato es E320009805001, aún no enviado por nuestra integración.

Hicimos una única consulta autorizada GET /dom/v1/company con HTTP 200.
Devuelve id 01M3T6Y4R9BH35XGJ5PP12KV0T, identification=132109122 y type=main.
No necesitamos reconfirmar el vínculo ni crear una empresa asociada.

Por favor aclaren únicamente:

Conservaremos el nombre FULLTECH y RNC 132109122 devueltos por la API.
El perfil devuelve address="address", que no usaremos como domicilio. El schema
oficial E32 requiere sender.address (string, máximo 100 caracteres), pero no
encontramos una regla pública DOM que responda estas preguntas:

1. ¿Admiten una dirección sintética, identificada expresamente como dato de
   prueba, para esta E32 Sandbox? Faciliten una cadena concreta permitida o
   confirmen la regla y su referencia oficial. No queremos inventar una dirección real.
2. ¿sender.address debe coincidir con company.address del perfil Sandbox?
3. Si ese perfil sigue con el placeholder, ¿es necesario que ustedes lo corrijan
   antes de la prueba o basta declarar la dirección permitida en el payload?

No solicitamos ejecutar cambios remotos ni emitir documentos. No envíen tokens
ni claves. Solo necesitamos la dirección/regla Sandbox para cerrar el preflight.

Nuestro procedimiento hará como máximo un POST /invoices y, solo si la respuesta
se correlaciona, una consulta GET. Después detendrá nuevos envíos hasta revisión.
Los estados del proveedor se registrarán como observaciones; HTTP 200/201 no se
interpretará como aceptación DGII. No habilitaremos producción ni webhooks públicos.

Gracias. Agradecemos referencias oficiales/versionadas y datos de prueba no secretos.

Este texto se entrega para envío manual del usuario. No se envió automáticamente.
Solo usar si estos datos no están ya en el paquete o portal entregado; no pedir
otra vez la autorización Sandbox que el usuario confirmó. JWT/configuración UAT
son asuntos locales de FULLTECH y no requieren una respuesta de Alanube.
