# Matriz de requisitos de habilitación DGII — FullPOS Cloud

> **Estado de este documento.** Es una **matriz interna del producto**, no una
> transcripción del procedimiento oficial de la DGII. El catálogo que aparece
> aquí es el que implementa el backend
> (`ECF_DGII_REQUIREMENT_CATALOG` en
> `apps/api/src/ecf/dgii/ecf-dgii-habilitation.policy.ts`), derivado de las
> etapas de `EcfOnboardingStepKey`. **Ninguna fila de esta matriz ha sido
> contrastada con una comunicación oficial de la DGII dentro de este
> repositorio.** Cualquier afirmación sobre el procedimiento oficial queda
> marcada como pendiente de verificación externa.

## 1. Cómo se deriva el progreso (HECHO)

El progreso **no** lo calcula la aplicación ni el usuario:

| Elemento | Origen verificado |
| --- | --- |
| Catálogo de requisitos (el QUÉ) | `ECF_DGII_REQUIREMENT_CATALOG` (14 entradas) |
| Estado real de cada requisito | `EcfOnboardingStep.status` en PostgreSQL |
| Estados que cuentan como resueltos | `COMPLETED` y `CONFIRMED` |
| Porcentaje y pendientes obligatorios | `buildRequirementProgress(...)` |

Evidencia: `src/ecf/dgii/ecf-dgii-habilitation-postgres.integration-spec.ts`
(«refleja el progreso real de los requisitos obligatorios») y
`ecf-dgii-habilitation.policy.spec.ts`.

## 2. Catálogo implementado (HECHO)

| # | Clave | Etapa de onboarding | Etiqueta | Obligatorio | Automatizable por el producto |
| --- | --- | --- | --- | --- | --- |
| 1 | `FISCAL_DATA` | `FISCAL_CONFIG` | Datos fiscales de la empresa | Sí | Sí |
| 2 | `REQUIREMENTS` | `REQUIREMENTS` | Requisitos y documentación | Sí | No |
| 3 | `DIGITAL_CERTIFICATE` | `DIGITAL_CERTIFICATE` | Certificado digital | Sí | No |
| 4 | `ALANUBE_REGISTRATION` | `ALANUBE_REGISTRATION` | Registro en el proveedor | Sí | No |
| 5 | `DGII_POSTULATION` | `DGII_POSTULATION` | Solicitud de incorporación | Sí | No |
| 6 | `XML_SIGNATURE` | `XML_SIGNATURE` | Firma XML | Sí | No |
| 7 | `SET_TESTS` | `SET_TESTS` | Pruebas del SET | Sí | No |
| 8 | `SIMULATIONS` | `SIMULATIONS` | Simulaciones | Sí | No |
| 9 | `PRINTED_REPRESENTATION` | `PRINTED_REPRESENTATION` | Representación impresa | No | Sí |
| 10 | `SERVICE_URLS` | `SERVICE_URLS` | URLs de servicio | Sí | No |
| 11 | `SWORN_DECLARATION` | `SWORN_DECLARATION` | Declaración jurada | Sí | No |
| 12 | `FINAL_AUTHORIZATION` | `FINAL_AUTHORIZATION` | Autorización final | Sí | No |
| 13 | `ENCF_REQUEST` | `ENCF_REQUEST` | Solicitud de e-NCF | Sí | No |
| 14 | `PRODUCTION_ENABLEMENT` | `PRODUCTION_ENABLEMENT` | Habilitación de producción | Sí | No |

`automatable: true` significa **únicamente** que el producto puede *registrar* el
estado a partir de datos que él mismo controla (por ejemplo, los datos fiscales
de la empresa o el formato de representación impresa). No significa que el
trámite ante la DGII esté automatizado: no lo está.

## 3. Seguimiento interno por requisito (HECHO)

Cada requisito admite, además, un **seguimiento interno** (libreta de trabajo)
que se guarda en `EcfDgiiHabilitation.requirements`:

- `status`: `PENDING` | `IN_PROGRESS` | `BLOCKED` | `COMPLETED` | `NOT_APPLICABLE`
- `note` (≤ 500), `responsibleUserId` (UUID), `dueDate` (`AAAA-MM-DD`)
- `updatedAt`, `updatedByUserId`

**Invariante (HECHO, cubierto por pruebas):** el seguimiento interno **no**
altera el progreso real. Marcar `SET_TESTS` como `COMPLETED` en la libreta deja
el requisito **sin resolver** mientras `EcfOnboardingStep` no lo esté.
Evidencia: `ecf-dgii-habilitation-postgres.integration-spec.ts` y
`test/features/ecf/ecf_dgii_habilitation_repository_test.dart`.

El catálogo es **cerrado**: `PATCH /ecf/dgii/requirements/:key` responde `404`
para cualquier clave fuera del catálogo (HECHO, cubierto por pruebas E2E HTTP).

## 4. Quién es responsable de cada paso (responsabilidad declarada)

> Esta sección es la **lectura interna** del equipo. **No** es una fuente oficial
> y debe confirmarse con la DGII y con el proveedor antes de usarse como
> argumento ante un cliente.

| Fase | Responsable principal | Puede automatizarlo FullPOS |
| --- | --- | --- |
| Datos fiscales y representación impresa | Empresa (con FullPOS) | Sí |
| Certificado digital, declaración jurada, firma XML | Empresa | No |
| Registro en el proveedor (Alanube) | Empresa + proveedor | No |
| Solicitud de incorporación, pruebas del SET, simulaciones | Empresa ante la DGII | No |
| Autorización final y habilitación de producción | DGII | No |
| Registro del hecho de autorización | Empresa, con evidencia oficial | Solo el **registro** |

Regla de oro del producto: FullPOS puede **registrar** el hecho y **guardar la
evidencia**, pero **no puede conceder** la autorización. `APPROVED` solo se
alcanza registrando una fuente `DGII_OFFICIAL_RECORD` con documento oficial
revisado.

## 5. Pendiente de verificación externa (PENDIENTE)

| # | Afirmación a verificar | Cómo se verificaría |
| --- | --- | --- |
| P1 | Que las 14 etapas correspondan 1:1 con el procedimiento oficial vigente | Comunicación escrita de la DGII o su manual de incorporación |
| P2 | Si existe un orden obligatorio entre etapas | Manual oficial |
| P3 | Si `PRINTED_REPRESENTATION` es realmente opcional | Manual oficial |
| P4 | Si se exigen requisitos adicionales por tipo de contribuyente | Manual oficial |
| P5 | Si la «autorización final» se notifica por un canal que el producto pueda leer | Respuesta de la DGII / del proveedor |
| P6 | Vigencia y renovación de la habilitación | Manual oficial |

Mientras P1–P6 sigan abiertos, la interfaz presenta el catálogo como
**seguimiento interno** y nunca como «el procedimiento oficial de la DGII».
