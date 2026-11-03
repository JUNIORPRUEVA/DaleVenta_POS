# Hallazgos de auditoría DGII — impacto en la Postulación Inteligente

Investigación independiente: **CA5244, CA5388, CA5241** y **Norma 10-21, artículo 14**.
Fecha de incorporación: 2026-11-01. Alcance: restricciones del procedimiento, **no** integraciones nuevas.

> Regla de este documento: nada de lo que aparece aquí se ha convertido en una conexión con la DGII ni
> con Alanube. Son límites que el producto **declara**, y que el motor aplica como garantía comprobable.
> Etiquetas: **HECHO** (verificado en el código de este repositorio), **HIPÓTESIS** (plausible, sin
> verificar con la DGII), **RECOMENDACIÓN** (propuesta).

---

## 1. Los cuatro hallazgos

| # | Hallazgo | Referencia | Qué NO se asume | Dónde se aplica (HECHO) |
|---|----------|-----------|-----------------|--------------------------|
| 1 | Una postulación en curso no puede coexistir con otra de un proveedor distinto; cambiar de proveedor obliga a reiniciar el trámite. | DGII **CA5244** | No existe cambio de proveedor en el producto, ni reutilización de un expediente entre proveedores. | Aviso en la guía de presentación (`_SubmissionGuide`, texto con `CA5244`). No hay código de traspaso: si se pide, es un rediseño del expediente, no un botón. |
| 2 | Existe una solicitud de delegación ligada al proveedor; su alcance técnico sigue sin confirmarse. | DGII **CA5388** | No se modela como paso automático ni se afirma que esté disponible. | El paso `SWORN_DECLARATION` y `DGII_POSTULATION` siguen siendo `CLIENT_ACTION`. |
| 3 | La norma contempla delegación para **firmar** comprobantes electrónicos bajo condiciones específicas. | **Norma 10-21, art. 14** | La delegación de firma **no** se extiende a la declaración jurada. | `DGII_NOT_COVERED_BY_DELEGATED_SIGNATURE` + `isCoveredByDelegatedSignature()`. `XML_SIGNATURE` (proveedor) y `SWORN_DECLARATION` (cliente) son pasos distintos y ninguno cierra por respuesta del transporte. |
| 4 | Una firma puede rechazarse por discrepancias entre certificado, **administrador e-CF** y datos del RNC. | DGII **CA5241** | Un certificado válido **no** garantiza aceptación: no se consulta el rol de administrador e-CF. | La comprobación local compara certificado ↔ expediente (`EcfCanonicalIdentityService`). El informe del certificado declara como *no comprobado* la coincidencia con el administrador e-CF. |

**HIPÓTESIS (no verificada):** que la DGII valide el rol de administrador e-CF contra el certificado en el
momento de la firma, y que la delegación de CA5388 cubra únicamente firma. Ambas cosas necesitan
confirmación de la DGII o del proveedor antes de modelarse.

---

## 2. Cinco operaciones administrativas sin API autorizada confirmada

Ninguna se implementa como llamada. Todas viven como **acción del cliente** y quedan registradas como
dependencia externa pendiente.

| Operación | Paso del catálogo | Tratamiento actual (HECHO) |
|-----------|-------------------|----------------------------|
| Postulación del emisor | `DGII_POSTULATION` | `CLIENT_ACTION`: guía + evidencia del acuse. |
| Presentación del XML de postulación | `DGII_POSTULATION` | El XML se valida y se guarda en el expediente; **presentarlo** en el portal es manual. |
| Carga del PDF del expediente | `DGII_POSTULATION` | Manual, con evidencia adjunta. |
| Registro de la URL de servicios | `SERVICE_URLS` | `CLIENT_ACTION` (requiere confirmación oficial para cerrarse). |
| Declaración jurada | `SWORN_DECLARATION` | `CLIENT_ACTION`; la delegación de firma no la cubre. |

Fuente única de esta tabla en código: `apps/api/src/ecf/dgii/dgii-external-dependencies.policy.ts`
(`DGII_OPERATIONS_WITHOUT_AUTHORIZED_API`).

---

## 3. Garantías que el motor aplica (HECHO)

1. **Nunca automático.** `activationClassOf()` fuerza `CLIENT_ACTION` para cualquier clave de
   `DGII_MANUAL_ONLY_STEP_KEYS`, aunque el catálogo la clasifique de otra forma.
2. **Nunca cerrado por el transporte.** `resolveStepStatus()` devuelve `AWAITING_CLIENT` para esas
   operaciones aunque el transporte responda «ok».
3. **Firma ≠ declaración jurada.** `isCoveredByDelegatedSignature('SWORN_DECLARATION') === false`, y
   `SWORN_DECLARATION` está en `ECF_STEPS_REQUIRING_OFFICIAL_CONFIRMATION`.
4. **Identidad parcial, declarada como tal.** El informe del certificado lista como *no comprobado* la
   cadena de confianza, la revocación, la coincidencia con el administrador e-CF y la delegación registrada.

Pruebas que fijan 1–3: `apps/api/src/ecf/dgii/dgii-external-dependencies.policy.spec.ts`.

---

## 4. Lo que sigue pendiente (dependencia externa)

- Confirmación de la DGII sobre el alcance de la delegación (**CA5388**) y sobre el rol de administrador
  e-CF (**CA5241**).
- Contrato autorizado, si existe, para las cinco operaciones de la tabla anterior.
- Del lado de Alanube: credenciales, `alanubeCompanyId`, `idSet` real de pruebas y allowlist de red.

Hasta que eso exista, el producto **no presenta nada en nombre del contribuyente** y lo dice en pantalla.

## 5. Recomendaciones

- **RECOMENDACIÓN**: si algún día se habilita el cambio de proveedor, debe tratarse como un expediente
  nuevo (nueva postulación), nunca como una edición del existente.
- **RECOMENDACIÓN**: cuando la DGII confirme el alcance de la delegación, revisar este documento y la
  política de dependencias en el mismo cambio, no por separado.
