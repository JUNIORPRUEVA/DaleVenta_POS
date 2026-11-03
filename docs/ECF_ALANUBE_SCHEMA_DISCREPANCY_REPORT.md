# e-CF — Discrepancia entre el contrato oficial de Alanube (GET) y la respuesta real del sandbox

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-16**.

**Estado: CARACTERIZADA Y CONTROLADA. No resuelta — requiere respuesta de Alanube.**
Este documento **no se ha enviado** al proveedor.

---

## 1. Origen de la observación

Evidencia histórica, no reproducida ni alterada:

| Dato | Valor |
| --- | --- |
| Fichero | `artifacts/e32-first-trial/recovery-get-observation.json` |
| Petición | `GET https://sandbox.alanube.co/dom/v1/invoices/01M4Y3DEPXXG27G8BNQGMNQ04B` |
| Momento | `2026-10-14T21:16:52.201Z` |
| Endpoint | HTTP **200**, `responseBytes` 5984, `responseSha256` `b607a039…` |
| Esquema de referencia | `https://developer.alanube.co/reference/checkinvoices` |
| `schemaSha256` | `5443aedd…` |
| Archivo cifrado | `encryptedArchiveSaved: true` |
| Intentos | `authenticatedGetAttempts: 1`, `fiscalPosts: 0` |
| Estado previo | `credentialPredatesOriginalPost: true` |

Contraste declarado en el propio artefacto:

```json
"assessment": {
  "checks": { "HTTP_200": true, "OFFICIAL_GET_SCHEMA": false, "REMOTE_ID_MATCH": true,
              "ENCF_MATCH": true, "EMITTER_MATCH": true, "ACCEPTED": true,
              "SEQUENCE_CONSUMED": true, "STATUS_KNOWN": true },
  "sufficientForProviderReview": false,
  "canUpdateFiscalStatus": false,
  "canRetryGet": false
}
```

## 2. Campos en discrepancia

Errores de validación registrados por el evaluador (`schemaErrors`):

| Ruta | Palabra clave | Lectura |
| --- | --- | --- |
| `/stampDate` | `format` | El valor no cumple el formato declarado en el contrato oficial |
| `/trackId` | `type` | El tipo observado no es el declarado en el contrato oficial |
| `/signatureDate` | `format` | El valor no cumple el formato declarado en el contrato oficial |

Hallazgo adicional del mismo artefacto: `trackId` venía **nulo** en la observación
(`"trackId": null`) mientras el contrato lo declara con un tipo concreto.

## 3. Análisis por campo

| Campo | Naturaleza | Riesgo fiscal | Tratamiento adoptado |
| --- | --- | --- | --- |
| `stampDate` | Fecha de sellado | **Medio** — dato temporal del comprobante | No se normaliza: se conserva como observación y el documento queda en revisión humana |
| `signatureDate` | Fecha de firma | **Alto** — se relaciona con la integridad/firma | No se normaliza. La firma **no** se infiere ni se rellena |
| `trackId` | Trazabilidad del documento | **Medio** — identificador de seguimiento | No se normaliza. Nulo se conserva como nulo, nunca como valor inventado |

Ninguno de los tres afecta a la identidad verificada de la operación, que **sí**
coincidió: `REMOTE_ID_MATCH`, `ENCF_MATCH`, `EMITTER_MATCH`.

## 4. Decisión de implementación

1. **No se alteró el contrato oficial** para ocultar la diferencia.
2. **No se modificó la evidencia histórica original.**
3. **No se implementó ninguna capa de normalización** todavía. Motivo: dos de los
   tres campos (`signatureDate`, `trackId`) tocan **firma y trazabilidad**. Tolerar
   una diferencia ahí sin confirmación del proveedor debilitaría precisamente los
   campos cuya integridad hay que preservar.
4. El comportamiento actual del sistema es **el correcto y se mantiene**:
   `sufficientForProviderReview: false` ⇒ el documento no se reclasifica, no se
   marca aceptado y permanece en revisión humana. Un HTTP 200 nunca se interpretó
   como aceptación fiscal.

**RECOMENDACIÓN:** implementar una capa de normalización **explícita y documentada**
solo si Alanube confirma el formato correcto de `stampDate` y `signatureDate`. Para
`trackId` la normalización depende de si el nulo es admisible.

## 5. Preguntas concretas para Alanube

1. `stampDate`: ¿cuál es el formato exacto (`date` o `date-time`)? ¿Admite zona horaria?
   ¿Qué se devuelve cuando el comprobante no está sellado?
2. `signatureDate`: ¿mismo formato que `stampDate`? ¿Se omite o se envía nulo cuando
   aún no hay firma?
3. `trackId`: ¿de qué tipo es? ¿Es **nullable**? ¿Qué significa su ausencia: aún sin
   traza, o fallo de generación?
4. ¿El esquema publicado en `developer.alanube.co/reference/checkinvoices` es el
   vigente para el sandbox, o sandbox y producción difieren en estos tres campos?
5. ¿Existe una versión de esquema versionada (por ejemplo `v1` vs `v2`) que explique
   la diferencia?

## 6. Riesgo si no se resuelve

- Un reconciliador que exigiera el esquema oficial estricto **nunca** podría cerrar
  una recuperación contra sandbox: todo quedaría en revisión humana.
- Un reconciliador que relajara los tres campos a ciegas aceptaría como válidos
  documentos con fecha de firma y traza no verificadas. **Riesgo fiscal.**
- Por eso hoy se mantiene la revisión humana y **no** se firma ni se clasifica nada
  a partir de esta observación.
