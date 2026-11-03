# Investigación pública contractual DOM — fases 65–66

Fecha: 2026-10-14. Solo HTTPS público sin Authorization contra developer.alanube.co.
No API autenticada, Try It, MCP Alanube, emisión, registro ni DGII.

## Evidencia reproducible

`scripts/isolated-uat/download-alanube-public-contracts.ps1` extrae únicamente
`document.api.schema` del script público `ssr-props`; no guarda configuración
del sitio ni credenciales. Versiones OpenAPI 3.0.3, info API FE DOM / 1.0.0.
Los archivos son snapshots de operaciones y sus referencias locales, no una
distribución consolidada oficial de toda la API.

| Página oficial | Snapshot local ignorado en artifacts/alanube-public-contracts | SHA-256 |
| --- | --- | --- |
| [E31](https://developer.alanube.co/reference/createinvoicefiscals) | createinvoicefiscals.openapi.json | 8E665554B8EFC8F41189449E64327F5888F44B05625E48B90BD09F6B8EAE3459 |
| [E32](https://developer.alanube.co/reference/createinvoices) | createinvoices.openapi.json | 483A7220F503AF4FAEEE1D42CF2124449CF8524105F94172D633099CEAF836DF |
| [E34](https://developer.alanube.co/reference/createcreditnotes) | createcreditnotes.openapi.json | 7B118AC204B241B79E5F4EAF7D2445C094933B6A979D83BDBB56AB53B18698E0 |

`llms.txt` y la variante `.md` no fueron accesibles mediante la herramienta web.
El HTML público sí contiene los schemas. Esto corrige la limitación histórica
de “schema no obtenido”; no demuestra conformidad del mapper existente.

## Resultado y aplicación local

VERIFIED: se recuperaron required anidados y respuestas con refs locales.
El borrador local usa nombres y metadatos insuficientes. La comprobación
ejecutable `alanube-official-required-fields.ts` detecta ausencias, no valida
schema completo ni condiciones legales. El mapper conserva BLOCKED_PENDING_SCHEMA
y añade las rutas faltantes; no inventa numeración, certificados ni fechas.

El registry distingue CONFIRMED_OFFICIAL (campos observados), PARTIAL_OFFICIAL
(integración incompleta), UNVERIFIED (alias locales no confirmados) y
BLOCKED_PENDING_PROVIDER (garantías externas pendientes). La barrera exige
aprobación completa en registry; ni CONFIRMED_PARTIAL ni una afirmación del
mapper pueden habilitar emisión.

## Consultas y respuestas

Confirmados endpoints GET por id en los recursos
[E31](https://developer.alanube.co/reference/checkinvoicefiscals),
[E32](https://developer.alanube.co/reference/checkinvoices),
[E34](https://developer.alanube.co/reference/checkcreditnotes).
No fueron invocados. No se conectó conciliación real; consulta por id no
resuelve por sí sola un timeout que no devuelve el identificador.

Los snapshots exponen estados de procesamiento REGISTERED, TO_SEND,
WAITING_RESPONSE, TO_NOTIFY y FINISHED. El snapshot E32 además presenta
legalStatus. No se equiparan estados de procesamiento ni HTTP 2xx a aceptación
DGII. El intérprete mantiene UNKNOWN_RESULT mientras no exista interpretación
completa validada por tipo y contexto. Errores HTTP tienen esquema code/message;
no se añadió un parser que acepte cuerpos arbitrarios como evidencia fiscal.

## Otros hallazgos públicos y límites

- [Introducción](https://developer.alanube.co/docs/getting-started) y
  [autenticación](https://developer.alanube.co/docs/autenticaci%C3%B3n): HTTPS,
  Bearer y Sandbox. No se repitió la autenticación de fase31.
- [getcompany-1](https://developer.alanube.co/reference/getcompany-1) documenta
  `/company/{id}`; el ejemplo de autenticación usa `/company`. No confundirlos.
- [Errores DOM](https://developer.alanube.co/reference/documents): hay catálogo
  público; no reemplaza pruebas de interpretación ni garantías de reintento.
- [Webhooks DOM](https://developer.alanube.co/changelog/api-fe-dom-mejoras-en-lo-webhooks-para-notificaciones-de-documentos-electr%C3%B3nicos): se documenta
  autenticación previa configurable. No confirma firma criptográfica/replay.
- [Certificación](https://developer.alanube.co/docs/proceso-de-certificaci%C3%B3n):
  describe OFV, certificado y alta de compañía para producción; Sandbox es
  simulación. No acredita autorización fiscal de FULLTECH o sus clientes.
- La búsqueda encontró [idempotencia Colombia](https://developer.alanube.co/v1.0-COL/docs/idempotencia).
  Se excluyó como garantía DOM: país y API diferentes.
- No se verificó contrato DOM completo de idempotencia, rate limits,
  firma/replay de webhooks, reseller ni activación contractual de clientes.

## Dependencias

Prisma instalado/generado: 5.22.0. Context7 no está expuesto en esta sesión;
se consultó la [documentación oficial Prisma sobre transacciones](https://www.prisma.io/docs/orm/fundamentals/transactions).
El manejo de P2002 se hace fuera de la transacción fallida; las garantías
concurrentes se probaron con el Prisma 5.22 real y PostgreSQL 16.15 local.
No se cambió versión de ninguna dependencia.

Estado: 65 PASS (investigación), 66 PARTIAL (presencia y evidencia ejecutables;
mapper oficial completo y validación contractual integral pendientes).
