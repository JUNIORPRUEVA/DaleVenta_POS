# F2 — Contrato HTTP de los endpoints `prepare*`

> **Estado: `F2 = GO (sin cambio de contrato)`.**
> La interpretación correcta ya existe en el cliente y está probada. La decisión
> tomada es **no** cambiar los códigos HTTP, por compatibilidad.

## 1. El hallazgo

Los endpoints de preparación responden **2xx con `ok:false`** en el cuerpo cuando
la preparación se rechaza:

```json
{ "ok": false, "code": "ECF_BUYER_DATA_REQUIRED",
  "safeMessage": "E31 exige identificar al receptor. Falta: RNC o cédula del cliente." }
```

Observado por HTTP real en esta misión y en la anterior. Un consumidor que solo
mire el código de estado creería que el comprobante se preparó.

## 2. Qué significa `ok:false` (HECHO)

No es una sola cosa, y por eso **no se puede convertir todo en excepción**:

| Categoría | Ejemplos reales observados |
| --- | --- |
| Datos obligatorios ausentes | `ECF_BUYER_DATA_REQUIRED` |
| Bloqueo de negocio | falta de secuencia, empresa sin e-CF |
| Clasificación fiscal no confirmada | `ECF_LINE_CLASSIFICATION_UNCONFIRMED` |
| Revisión humana requerida | respuesta correlacionada dudosa |
| Rechazo explícito del proveedor | `ECF_OBSERVED_REJECTED` |

Son desenlaces **explicables al usuario**, no fallos del sistema. Un `500` para
«falta el RNC del cliente» sería un error de diseño.

## 3. Auditoría de consumidores (HECHO)

### Cliente Flutter — ya interpreta el cuerpo correctamente

Los tres métodos de preparación inspeccionan `ok` en el cuerpo:

| Método | Comprobación |
| --- | --- |
| `prepareFromSale` | `if (payload['ok'] == true) { … }` → `success` o `failure` |
| `prepareConsumoFromSale` | igual |
| `prepareCreditNote` | igual |

Y devuelven un resultado tipado `EcfPreparationOutcome` (`ok`, `code`,
`message`). El propio código lo documenta: «(`ok: false` + código), no como error
de red: así la interfaz puede…».

### Interfaz — no muestra éxito falso

| Pantalla | Comportamiento verificado |
| --- | --- |
| `ecf_prepare_action.dart:266` | Título: `outcome.ok ? 'Borrador preparado' : 'No se pudo preparar'` |
| `ecf_prepare_action.dart:271` | Los detalles de éxito solo se pintan **si** `outcome.ok` |
| `ecf_prepare_action.dart:280-282` | En fallo muestra **Código** y mensaje |
| `ecf_credit_note_action.dart:269` | `outcome.ok ? 'Nota preparada' : 'No se pudo preparar'` |

**No hay ruta que muestre preparado cuando `ok` es `false`**, y no se avanza a
ninguna pantalla de documento emitido: la preparación **no** emite.

## 4. Decisión (y su justificación)

```text
NO se cambian los códigos HTTP de los endpoints prepare*.
```

Motivo: son endpoints **en uso por clientes desplegados**. Convertir un rechazo
explicable en `4xx` rompería a todo cliente que hoy espera leer el cuerpo, y el
riesgo de romper el flujo de preparación en producción es mayor que el beneficio
de estética REST. La política de la misión lo indica explícitamente: si no es
seguro cambiar el código, conservarlo y **fortalecer a los consumidores**.

Lo que sí se refuerza:

1. El contrato queda **documentado** en este fichero (incluido el hecho de que un
   `2xx` no significa preparado).
2. El cliente sigue leyendo `ok`, y hay pruebas que lo anclan.
3. Cualquier cliente futuro debe leer `ok`; el `status` solo informa del
   transporte.

Si en el futuro se quisiera normalizar, la vía compatible es **versionar** el
endpoint (nueva ruta) y migrar clientes, nunca cambiar el significado de un
`2xx` existente.

## 5. Pruebas que anclan el comportamiento

| Prueba | Qué fija |
| --- | --- |
| `test/features/ecf/ecf_dgii_habilitation_repository_test.dart` y la suite e-CF de Flutter | La interpretación de `ok` en el repositorio |
| `apps/api/src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts` | Un `2xx` con `ok:false` **no** deja documento ni evidencia a medias |
| Suites de preparación de backend | Los códigos concretos de cada rechazo |

## 6. Riesgo residual

| # | Riesgo | Estado |
| --- | --- | --- |
| R1 | Un cliente de terceros que solo mire el `status` | **Aceptado y documentado**; no existe hoy |
| R2 | Confundir `ok:false` con un fallo reintentable | Mitigado: `ok:false` **no** dispara reintento automático de operaciones fiscales |
| R3 | Que un `2xx` se interprete como «emitido» | Mitigado: la preparación no emite y la interfaz no muestra emisión |
