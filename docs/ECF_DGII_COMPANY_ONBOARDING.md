# e-CF — Habilitación electrónica por empresa (onboarding) y plan DGII

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.

> **Actualización (2026-10-16, misma fecha):** esta pieza cubre el **onboarding por
> pasos** (`EcfOnboardingStep`) y su consumo en Flutter. Sobre ella se añadió el
> módulo de **habilitación DGII por empresa** (`EcfDgiiHabilitation`), que aporta
> un registro por empresa con **autorización oficial verificada**, evidencia con
> procedencia y una **puerta de emisión fail-closed**. Ver
> [`ECF_DGII_HABILITATION_MODULE.md`](ECF_DGII_HABILITATION_MODULE.md).
>
> La conclusión «no se creó ninguna migración» de §1 sigue siendo válida **para el
> onboarding de pasos**. La migración `20261016120000_ecf_dgii_company_habilitation`
> es aditiva y pertenece **solo** al módulo nuevo, no duplica el modelo de pasos.

---

## 1. Lo que YA existía (auditado, no se duplicó)

Antes de implementar nada se auditó el repositorio y se encontró que el **backend
del onboarding fiscal ya estaba construido**:

| Pieza | Ubicación |
| --- | --- |
| Pasos por empresa | Modelo `EcfOnboardingStep` (`ecf_onboarding_steps`), único por `[companyId, stepKey]` |
| Intentos de certificación | Modelo `EcfCertificationAttempt` (idempotencia por `[companyId, idempotencyKey]`) |
| Evidencia | Modelo `EcfEvidence` + `evidenceId` en el paso |
| Auditoría | Modelo `EcfAuditLog` (`GET /ecf/onboarding/history`) |
| Orden de pasos | `ECF_ONBOARDING_STEP_ORDER` (`PRODUCTION_ENABLEMENT` incluido) |
| Derivación de estado | `EcfService.deriveCertificationStatus` |
| Endpoints | `GET /ecf/onboarding`, `PATCH /ecf/onboarding/steps/:stepKey`, `GET /ecf/onboarding/history`, `GET /ecf/provider/status` |
| Permisos | `viewEcfOnboarding`, `manageEcfOnboarding`, `viewEcfConfig`, `manageEcfConfig` |

Reglas ya presentes y respetadas: `deriveCertificationStatus` es **conservador**
(`BLOCKED` si algún paso está bloqueado, `IN_PROGRESS` si hay pasos activos, si no
`NOT_STARTED`) y **nunca** concede un estado de autorización por completar pasos;
`productionEmissionEnabled` está fijado en `false`, y la autorización productiva
exige `productionEnabled && certificationStatus === PRODUCTION_READY`.

**Conclusión de la auditoría:** crear tablas nuevas habría duplicado el modelo. No
se creó ninguna migración.

## 2. La brecha real: Flutter no consumía el onboarding

La auditoría de la aplicación móvil/escritorio mostró **cero** referencias a
`/ecf/onboarding`: no había ruta, ni repositorio, ni pantalla. El usuario no podía
ver ni gestionar su proceso de habilitación desde FullPOS Cloud.

### Implementado

| Capa | Cambio |
| --- | --- |
| Rutas | `ApiRoutes.ecfOnboarding` y `ApiRoutes.ecfOnboardingStep(stepKey)` |
| Modelos | `EcfOnboardingView` (pasos, `certificationStatus`, `productionEnabled`, `progress`) y `EcfOnboardingStepView` (`isDone`, `isBlocked`, `canComplete`, etiqueta legible) |
| Repositorio | `onboarding()` (GET) y `updateOnboardingStep({stepKey, status})` (PATCH), más `ecfOnboardingProvider` |
| Interfaz | `EcfOnboardingSection` dentro de **Configuración de Empresa**, junto al interruptor e-CF |

La pantalla muestra: barra de progreso, estado de habilitación, lista de pasos con
su estado, y **el motivo del bloqueo** cuando lo hay. Solo permite marcar pasos
**pendientes o en curso**: un paso `BLOCKED` no se «arregla» marcándolo.

### Salvaguardas de la interfaz (por diseño)

- Solo aparece si la **empresa** tiene e-CF activado y el usuario puede gestionar la
  configuración (`manageEcfConfig`).
- Texto explícito en la propia pantalla: *«Proceso INTERNO de preparación. Completar
  estos pasos no acredita certificación ante la DGII»*.
- **Nunca** declara a la empresa certificada: el estado que pinta es el que reporta
  el backend, y la emisión real sigue bloqueada por su propia compuerta.
- Protección contra doble pulsación e indicador de progreso mientras guarda.
- No se piden ni almacenan credenciales de la Oficina Virtual DGII, ni claves
  privadas, ni tokens en claro.

## 3. Los cuatro estados que no deben confundirse

| Plano | Qué es | Dónde vive |
| --- | --- | --- |
| **A. Estado oficial demostrado** | Lo que la DGII reconoce. **No** se deduce de nada interno | Fuera de FullPOS; se referencia como evidencia |
| **B. Estado interno administrativo** | Pasos del proceso (`EcfOnboardingStep`) | `ecf_onboarding_steps` |
| **C. Estado técnico de la integración** | Configuración del proveedor, ambiente, certificación | `ecf_company_configurations` |
| **D. Activación efectiva de emisión** | Interruptor que permite emitir de verdad | `enabled` + `productionEnabled` + estado de certificación |

**Regla dura:** ningún plano se deriva de otro por conveniencia. Completar B no
produce A, y D exige autorización explícita.

## 4. Plan de habilitación DGII (Fase 9) — reproducible

Separación de responsabilidades, sin inventar pasos oficiales:

| Paso | Responsable | Automatizable por FullPOS |
| --- | --- | --- |
| Alta y datos fiscales (RNC, razón social, representante) | Contribuyente | Registrar en el onboarding (B) |
| Trámite en la **Oficina Virtual DGII** (solicitud, firma digital) | Contribuyente ante la DGII | **No** |
| Firma digital / certificado | Contribuyente + DGII | Almacenar solo la **referencia** al secreto, nunca el contenido |
| Creación de la compañía en el proveedor | Alanube | Llamada documentada, cuando exista token |
| Set de pruebas y certificación | Alanube / DGII | Registrar evidencia e intentos (`EcfCertificationAttempt`) |
| Configuración del proveedor (credenciales, webhooks) | FullPOS + Alanube | Sí, con referencias a secretos |
| **Autorización de emisión real** | Humana, en FullPOS | Sí, explícita y auditada |
| Emisión productiva | FullPOS (software) | Tras la autorización anterior |

**Evidencia que hay que conservar:** acuse y constancia de la DGII, resultado del
set de pruebas, referencias de la compañía en el proveedor, y el registro de
auditoría interno de quién autorizó la activación y cuándo.

### A vs B: dos rutas distintas, no equivalentes

- **A. FullPOS como software conectado a un proveedor autorizado.** Es la ruta
  actual: la responsabilidad de la facturación electrónica recae en el proveedor
  (Alanube) y en el contribuyente; FullPOS es la herramienta.
- **B. FULLTECH solicitando autorización propia como proveedor de servicios de
  facturación electrónica.** Es un procedimiento **distinto**, con requisitos
  propios de la DGII, y **no** se alcanza completando A. No se asume equivalencia.

**Ruta recomendada para la etapa actual:** **A**. Permite incorporar empresas ya,
sin asumir las obligaciones regulatorias de un proveedor propio.

## 5. Pruebas de esta pieza

```
flutter test test/features/ecf/ecf_onboarding_test.dart   -> 3 pruebas
  · lee pasos y estado interno (progreso 1/3, paso bloqueado no completable)
  · tolera una carga útil incompleta sin romper la pantalla
  · PATCH al paso correcto con el cuerpo esperado
```

Cubren el contrato de datos y las reglas de la interfaz. **No** sustituyen a una
observación visual de la pantalla (§6).

## 6. Lo que sigue bloqueado

- **Recorrido visual**: la sección no se ha visto en ejecución (misma limitación de
  automatización gráfica que el resto de la UAT).
- **Contraste con el contrato oficial**: los nombres y el orden de los pasos son
  **internos**. Si la DGII/Alanube exigen un orden o unas evidencias concretas, el
  `ECF_ONBOARDING_STEP_ORDER` deberá ajustarse contra esa fuente, no por suposición.
