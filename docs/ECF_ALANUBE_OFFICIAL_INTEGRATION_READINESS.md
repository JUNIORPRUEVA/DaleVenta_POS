# e-CF — Preparación para la integración oficial con Alanube

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.
Sin `commit`, sin `push`, sin `deploy`. Ninguna llamada a la API de Alanube.

> **Alcance de las consultas externas de esta misión.** Se leyeron **páginas de
> documentación pública** en `developer.alanube.co` (GET a un sitio de
> documentación, HTTP 200). **No** se llamó a `sandbox.alanube.co` ni a
> `api.alanube.co`: ninguna operación fiscal, ninguna credencial, ningún e-NCF.

---

## 1. Fuentes oficiales consultadas (con fecha)

| Fuente | URL | Estado de lectura |
| --- | --- | --- |
| Autenticación | `https://developer.alanube.co/docs/autenticación.md` | **Leída** (`updatedAt: 2025-09-23T21:02:35Z`) |
| Índice para agentes | `https://developer.alanube.co/llms.txt` | **Leído** (enumeración de páginas) |
| Introducción / getting started | `https://developer.alanube.co/docs/getting-started` | Alcanzada (HTTP 200); renderizada por JS, **no extraíble** |
| Webhooks | `https://developer.alanube.co/docs/webhooks.md` | Enumerada en el índice; **no leída** |
| Set de pruebas (certificación) | `https://developer.alanube.co/reference/createsettest.md` | Enumerada; **no leída** |
| Simulación de recepción desde la DGII | `https://developer.alanube.co/reference/post_reception-dgii-receive-document.md` | Enumerada; **no leída** |
| Proceso de certificación | `https://developer.alanube.co/docs/proceso-de-certificación` | **No alcanzada** de forma fiable |

Las páginas de documentación son un sitio ReadMe renderizado en cliente. El índice
`llms.txt` expone versiones markdown bajo `/docs/<slug>.md`, que es lo que permitió
leer la autenticación. El resto queda **BLOQUEADO** a nivel de campo (§4).

## 2. Contrato confirmado por fuente oficial

| Operación | Fuente | Endpoint / esquema | Implementación actual | Certeza |
| --- | --- | --- | --- | --- |
| Autenticación | `docs/autenticación.md` | **JWT suministrado por Alanube**, esquema **Bearer Authentication**, cabecera `Authorization: Bearer <token>` | `AlanubeSafeHttpClient` envía `Authorization` con el token resuelto por referencia | **CONFIRMADO_PUBLICO** |
| Host de sandbox | `docs/autenticación.md` (ejemplo oficial `https://sandbox.alanube.co/dom/v1/company`) | `https://sandbox.alanube.co/dom/v1` | `ALANUBE_DOM_SANDBOX_BASE_URL` | **CONFIRMADO_PUBLICO** |
| Host de producción | Contrato local curado del proyecto | `https://api.alanube.co/dom/v1` | `ALANUBE_DOM_PRODUCTION_BASE_URL`, y **bloqueado** por la política de sandbox | **CONFIRMADO_LOCAL** |
| Webhooks | `llms.txt` | `general.governmentStatusChanged`, `documents.emissionFinished`, `documents.reception` | `alanube-webhook.contract.ts` (contrato local) | **ENUMERADO** (nombre oficial; esquema sin leer) |
| Proceso de certificación | `llms.txt` | `reference/createsettest` (generar set de pruebas); `reference/post_reception-dgii-receive-document` (simular recepción desde la DGII, **solo pruebas**) | No implementado | **ENUMERADO** |
| Emisión E31 | Contrato local curado | `POST /fiscal-invoices` | `ALANUBE_DOM_ENDPOINTS` | **CONFIRMADO_LOCAL** |
| Emisión E32 | Contrato local curado | `POST /invoices` | `ALANUBE_DOM_ENDPOINTS` | **CONFIRMADO_LOCAL** |
| Notas de crédito E34 | Contrato local curado | `POST /credit-notes` | `ALANUBE_DOM_ENDPOINTS` | **CONFIRMADO_LOCAL** |
| Esquemas de campos | `contracts/alanube-dom-schemas.generated.ts` (132 KB, generado) | — | `AlanubeSchemaValidator` valida respuestas | **CONFIRMADO_LOCAL** |

## 3. Implementado en esta misión

**Política de acceso al sandbox (nueva, con compuerta fail-closed).**

`apps/api/src/ecf/alanube/alanube-sandbox-access.policy.ts` + integración en la
fábrica de transportes:

- El transporte **real** solo se construye si se cumple **todo**: interruptor de
  transporte, interruptor de llamadas reales, `ALANUBE_ENV=sandbox`, URL **https**
  del host oficial `sandbox.alanube.co` y una **referencia de token** válida
  (`env://`, `secret://`, `vault://`, `uat://`).
- Se rechaza explícitamente la URL de producción (`api.alanube.co`) y la
  infraestructura remota conocida (easypanel, gcdndd, hostinger, 31.97.99.70).
- Si algo falta, **no falla el arranque**: se queda en el **simulador local** (fallo
  cerrado). Un token en claro no cuenta como referencia válida.
- Motivos tipados: `..._ENVIRONMENT`, `..._BASE_URL_REQUIRED`,
  `..._PRODUCTION_URL`, `..._INSECURE_TRANSPORT`, `..._NOT_SANDBOX_HOST`,
  `..._TOKEN_REFERENCE_REQUIRED`, `..._TOKEN_REFERENCE_INVALID`.

Cobertura: `alanube-sandbox-access.policy.spec.ts` (7 pruebas) +
`alanube-transport.provider.spec.ts` ampliado (incluye el caso «interruptores
puestos pero sin token → simulador»).

## 4. Brechas reales para la integración oficial

| # | Brecha | Estado |
| --- | --- | --- |
| 1 | **Token JWT de sandbox** para pruebas reales | BLOQUEADO: lo suministra Alanube |
| 2 | Contrato de **creación de una compañía** (campos, respuesta, `companyId`) | BLOQUEADO: página enumerada, esquema sin leer |
| 3 | Campos obligatorios y respuestas por tipo (E31/E32/E34) contra el contrato oficial vigente | **PARCIAL**: validados contra el esquema local generado; falta contraste con el oficial |
| 4 | **Webhooks**: URL de callback, firma y esquema de los 3 eventos | BLOQUEADO: nombres oficiales confirmados, esquema sin leer |
| 5 | **Set de pruebas / certificación**: flujo oficial, evidencias exigidas | BLOQUEADO |
| 6 | Consulta de estados y consulta de salud de la API | BLOQUEADO |
| 7 | Límites de tasa, política de reintentos y códigos de error oficiales | BLOQUEADO |
| 8 | Rotación de secretos y custodia del certificado digital | Diseño local (`EcfSecretResolverService`); sin contrato oficial |

Ninguna de estas brechas se ha rellenado por suposición: **no se inventó ningún
endpoint, campo ni estado.**

## 5. Qué NO se hizo (y por qué)

- **No** se activó el transporte real: `ALANUBE_HTTP_TRANSPORT_ENABLED=false` y
  `ALANUBE_ENABLE_REAL_CALLS=false` en todo el entorno de validación.
- **No** se llamó al sandbox ni a producción.
- **No** se implementaron endpoints ni estados a partir de documentación no leída.
- **No** se creó ninguna migración: el esquema no necesitó cambios.

## 6. Estado y siguiente paso

**Estado: GO WITH BLOCKERS.** Toda la preparación verificable localmente está hecha
(política de sandbox, cliente, resolución de secretos, separación de ambientes,
simulador, contrato local tipado y validado). Lo que falta depende de terceros.

**Siguiente paso exacto:** solicitar a Alanube el **token de sandbox** y el acceso
a los contratos de creación de compañía, emisión, consulta de estados y webhooks
(§4 y `docs/ECF_SANDBOX_ACCESS_REQUIREMENTS.md`), y al recibirlos contrastar el
contrato oficial con `alanube-dom-schemas.generated.ts` antes de activar el
transporte real en un entorno aislado.
