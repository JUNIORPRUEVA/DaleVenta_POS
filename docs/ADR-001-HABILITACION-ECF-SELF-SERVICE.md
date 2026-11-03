# ADR-001 — Habilitación e-CF self-service

Estado: **aceptado** · Fecha: 2026-10-19 · Rama: `feature/ecf-alanube`

## Contexto

Hoy la habilitación es un **expediente asistido**: el cliente declara, adjunta,
consiente y envía; Fulltech revisa y el trámite externo se hace a mano. El
objetivo es que el cliente pueda **iniciar y seguir su habilitación desde
Fullpos**, con la sencillez de Alegra, sin que Fulltech intervenga en cada paso.

Restricción que manda sobre el diseño: **no inventar capacidades de Alanube ni de
la DGII**, y **no simular aprobaciones oficiales**.

## Auditoría de los 14 pasos (código real)

Catálogo `ECF_DGII_REQUIREMENT_CATALOG`
(`apps/api/src/ecf/dgii/ecf-dgii-habilitation.policy.ts`):

| # | key | Etapa persistida | Obligatorio | Clase de ejecución |
| --- | --- | --- | --- | --- |
| 1 | `FISCAL_DATA` | `FISCAL_CONFIG` | sí | **AUTOMÁTICO LOCAL** |
| 2 | `REQUIREMENTS` | `REQUIREMENTS` | sí | **ACCIÓN DEL CLIENTE** |
| 3 | `DIGITAL_CERTIFICATE` | `DIGITAL_CERTIFICATE` | sí | **ACCIÓN DEL CLIENTE** |
| 4 | `ALANUBE_REGISTRATION` | `ALANUBE_REGISTRATION` | sí | **ESPERA PROVEEDOR** |
| 5 | `DGII_POSTULATION` | `DGII_POSTULATION` | sí | **ESPERA PROVEEDOR** |
| 6 | `XML_SIGNATURE` | `XML_SIGNATURE` | sí | **ESPERA PROVEEDOR** (requiere certificado) |
| 7 | `SET_TESTS` | `SET_TESTS` | sí | **ESPERA PROVEEDOR** (respuesta asíncrona) |
| 8 | `SIMULATIONS` | `SIMULATIONS` | sí | **ESPERA PROVEEDOR** |
| 9 | `PRINTED_REPRESENTATION` | `PRINTED_REPRESENTATION` | no | **AUTOMÁTICO LOCAL** |
| 10 | `SERVICE_URLS` | `SERVICE_URLS` | sí | **ESPERA PROVEEDOR** |
| 11 | `SWORN_DECLARATION` | `SWORN_DECLARATION` | sí | **ACCIÓN DEL CLIENTE** (acto legal) |
| 12 | `FINAL_AUTHORIZATION` | `FINAL_AUTHORIZATION` | sí | **ESPERA AUTORIDAD** |
| 13 | `ENCF_REQUEST` | `ENCF_REQUEST` | sí | **ESPERA PROVEEDOR** |
| 14 | `PRODUCTION_ENABLEMENT` | `PRODUCTION_ENABLEMENT` | sí | **ESPERA AUTORIDAD** |

**Recuento:** 2 automáticos locales · 3 acciones del cliente · 7 esperas del
proveedor · 2 esperas de la autoridad.

## Decisión

1. El motor de activación **solo ejecuta por sí mismo** los pasos de clase
   `AUTOMATIC_LOCAL`.
2. Los pasos `PROVIDER_WAIT` se ejecutan contra un **transporte**, que hoy es
   **simulado** y que en producción será el cliente HTTP de Alanube cuando exista
   contrato. El transporte real está **desactivado por defecto** y el servicio
   **se niega a arrancar** si se intenta activar sin contrato declarado.
3. Los pasos `CLIENT_ACTION` **no se pueden marcar como hechos desde el motor**:
   quedan en estado `AWAITING_CLIENT` con la razón exacta. Solo el cliente los
   resuelve (subir certificado, firmar declaración).
4. Los pasos `AUTHORITY_WAIT` quedan en `AWAITING_AUTHORITY`. **Ningún resultado
   del transporte puede marcarlos como completados**; solo un registro oficial
   verificado (flujo ya existente) puede hacerlo.
5. La revisión interna de Fulltech **deja de ser un paso obligatorio del flujo**:
   pasa a supervisión/soporte, sin desaparecer.

## Invariantes que no se tocan

- `APPROVED` sigue exigiendo `DGII_OFFICIAL_RECORD` + evidencia + fecha +
  identificador externo.
- La emisión real sigue sin estar implementada: no hay ruta que emita.
- Snapshots inmutables, consentimiento versionado, auditoría append-only,
  aislamiento multiempresa y permisos de plataforma intactos.
- Un estado `COMPLETED` de una simulación **no** se presenta como habilitación.

## Consecuencias

**Positivas:** el cliente ve un solo botón y un progreso real; las excepciones se
piden con el motivo exacto; el día que exista contrato solo se cambia el
transporte.

**Negativas / costes:** aparecen dos estados nuevos (`AWAITING_CLIENT`,
`AWAITING_AUTHORITY`) que la interfaz debe distinguir de "hecho" y de "error";
el motor necesita idempotencia por paso para sobrevivir a reintentos.

## Contrato pendiente de confirmar con Alanube

Preguntas concretas, cada una atada al paso que desbloquea:

1. **¿API de registro de contribuyente?** → `ALANUBE_REGISTRATION`.
   Necesitamos: método, ruta, payload mínimo, códigos de error, y si devuelve un
   identificador de empresa en el proveedor.
2. **¿API de postulación/incorporación ante DGII?** → `DGII_POSTULATION`.
   ¿La inicia Alanube o la inicia el contribuyente en un portal?
3. **¿Firma XML y envío de pruebas del SET?** → `XML_SIGNATURE`, `SET_TESTS`.
   ¿Firman ustedes con el certificado del cliente? ¿Qué formato de certificado
   aceptan? ¿Cómo se consulta el resultado (callback, polling, ambos)?
4. **¿Simulaciones?** → `SIMULATIONS`. Escenarios exigidos y criterio de éxito.
5. **¿URLs de servicio?** → `SERVICE_URLS`. ¿Las registra el proveedor o las
   declaramos nosotros?
6. **¿Solicitud de rangos de e-NCF?** → `ENCF_REQUEST`. ¿Automática o manual ante
   la DGII?
7. **¿Consulta de estado?** → `FINAL_AUTHORIZATION`, `PRODUCTION_ENABLEMENT`.
   ¿Existe endpoint de estado oficial? Sin él, esos dos pasos **no pueden**
   automatizarse y deben quedar en `AWAITING_AUTHORITY` con comprobación manual.
8. **¿Custodia del certificado?** ¿Lo emiten ustedes, lo custodian, o lo aporta el
   cliente en cada firma?
9. **¿Declaración jurada?** → `SWORN_DECLARATION`. ¿La gestionan ustedes o exige
   firma del contribuyente?

Sin respuestas 1–7 el motor queda en simulación. Eso es deliberado.

## Alternativas descartadas

- **Marcar los pasos como completados al simular**: daría una demo bonita y una
  mentira operativa. Descartado.
- **Pedir a Fulltech que ejecute los pasos desde el panel**: reintroduce el
  trabajo manual que se quiere eliminar.
- **Guardar el certificado en claro**: inaceptable.
