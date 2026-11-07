# Credenciales DOSA: reparto por ambiente (TEST / PRODUCCIÓN)

Corrección del 07/11/2026. Estado: **rama aislada, sin desplegar**.

## Causa raíz

DOSA entrega las dos claves (`api_key_test` y `api_key_produccion`) en un único
evento cuyo campo `ambiente` describe la **certificación de la empresa**
(`Produccion`), no el ambiente de cada clave.

El receptor guardaba el paquete completo bajo `environment = environmentOf(ambiente)`.
Resultado real verificado en producción:

| Fecha | Evento | Filas creadas | Claves en la fila `production` |
| --- | --- | --- | --- |
| 06/11 23:15 | `Produccion` | 1 (`production`) | `apiKeyProduccion`, `apiSecret` |
| 07/11 13:54 | `Produccion` | 1 (`production`) | `apiKeyProduccion`, **`apiKeyTest`**, `apiSecret` |

La clave TEST quedó **cifrada y correcta, pero en la fila equivocada**: la compuerta
de emisión busca `(empresa, rnc, environment='test')`, no la encontraba, y la prueba
en TEST era imposible sin pedir un reenvío.

## Qué cambió

1. **`dosa-credential-environments.ts` (nuevo)** — reparto puro del paquete:
   `apiKeyProduccion` → `production`, `apiKeyTest` → `test`, `apiSecret` acompaña a
   ambas. Un ambiente solo se escribe si trae **su** clave; si no, no se toca.
2. **`ingestFromProvider`** — usa ese reparto. El `environment` de la entrada queda
   como evidencia del evento; ya no decide dónde va cada clave. Devuelve además
   `stored` (qué se escribió) y `skipped` (qué no se tocó).
3. **`upsert` (SQL)** — tres reglas nuevas:
   - nunca rebaja `CONFIRMED`/`ACTIVE` (`CASE WHEN status IN ('CONFIRMED','ACTIVE')`);
   - no reescribe si el `fingerprint` no cambió (`WHERE ... IS DISTINCT FROM EXCLUDED.fingerprint`);
   - `created_at` no se actualiza nunca.
4. **`reclassifyStoredCredentials`** — camino auditado para repartir un paquete ya
   guardado. Requiere `authorized`, admite `dryRun`, no modifica la fila de origen y
   es idempotente.
5. **Bóveda** — `open()` acepta un propósito cerrado más, `REMEDIATION`, usado solo
   por la herramienta de mantenimiento. Sigue exigiendo `authorized: true`.
6. **`scripts/reclassify-dosa-credentials.ts`** + `npm run dosa:credentials:reclassify`.

## Qué NO cambia

- Verificación HMAC, tolerancia de 300 s y cuerpo crudo: intactos.
- **Deduplicación: intacta** (`sha256(postulacion_id|estado_certificacion|disponibles_desde)`).
  No se reprocesan eventos antiguos.
- Cifrado AES-256-GCM con HKDF y AAD `empresa:rnc:ambiente`: intacto.
- Aislamiento por `(company_id, rnc, environment)`: intacto.
- Nada se activa solo: todo entra como `PENDING_CONFIRMATION`.
- Las banderas de emisión siguen en `false`.

## Estrategia para las credenciales ya guardadas

La clave TEST **ya está** en la bóveda. No hace falta otro webhook.

```bash
# 1) Ver qué haría (no escribe, no requiere confirmación)
npm run dosa:credentials:reclassify -- \
  --company-id 165e3fca-6225-479b-8805-d2205f10536c --rnc 133080206

# 2) Aplicar (exige DOSA_CREDENTIALS_RECLASSIFY=CONFIRM en el entorno)
DOSA_CREDENTIALS_RECLASSIFY=CONFIRM npm run dosa:credentials:reclassify -- \
  --company-id 165e3fca-6225-479b-8805-d2205f10536c --rnc 133080206 --apply
```

Qué hace exactamente: lee la fila `production` de esa empresa (descifrado con
propósito `REMEDIATION`), reparte el paquete y **escribe solo `test`**. La fila de
producción no se toca. Si el destino ya coincide (misma huella), informa `already`
y no escribe. La salida no incluye valores: ambientes, estados y huellas truncadas.

## `DOSA_TEST_RNC`

Hoy vale `133306001` en local y **no está configurado en producción**. Para una
emisión TEST de FULLTECH hay que decidir su valor:

- La política `verifyFiscalIdentity` exige que, en TEST, el emisor sea exactamente
  `DOSA_TEST_RNC`; si no, bloquea con `TEST_RNC_MISMATCH`.
- La regla del proveedor exige que el RNC del payload coincida con el de la API Key.

Consecuencia: si la clave TEST de FULLTECH es de su propio RNC, `DOSA_TEST_RNC`
debe ser `133080206` **para esa prueba**. Es una decisión consciente y debe
autorizarse; el cambio es de configuración, no de código, y **no se ha hecho**.

## Plan de despliegue (para aprobación)

1. Revisión del diff y de esta nota.
2. `npm test` en verde (ver §Pruebas).
3. Desplegar **solo** `daleventapos_backend` con las banderas sin tocar
   (`DOSA_EMISSION_ENABLED=false`, `DOSA_PRODUCTION_EMISSION_ENABLED=false`,
   `DOSA_WEBHOOK_ENABLED=true`).
4. Ejecutar el comando en **dry-run** y revisar la salida.
5. Con autorización explícita, `--apply`.
6. Verificar con `SELECT` que existen dos filas (`production`, `test`) y que la de
   producción conserva su `created_at`.

## Reversión

- Revertir el commit y redesplegar: la tabla no cambia de forma, así que la vuelta
  atrás es limpia.
- Los datos son compatibles en ambos sentidos: la fila `production` **nunca** se
  modificó; la fila `test` es aditiva.
- Si hiciera falta deshacer la reclasificación: marcar la fila `test` como
  `REVOKED` (no borrar) para conservar la auditoría.

## Riesgos pendientes

| Riesgo | Estado |
| --- | --- |
| La dedupe no incluye las credenciales: un reenvío idéntico no actualizaría claves | **Asumido a propósito** en esta fase (instrucción: no tocar la deduplicación). Requiere un cambio aparte, probado, si el proveedor rota claves. |
| Un evento que solo traiga `apiSecret` no se guarda | Aceptado: no puede crear ni dejar filas a medias sin descifrar la existente. |
| `DOSA_TEST_RNC` sin configurar en producción | Pendiente de decisión; bloquea la prueba TEST. |
| Rotación de claves sobre una fila `ACTIVE` | Se permite (conserva el estado), pero sin histórico de versiones anteriores. |

## Pruebas

`dosa-credential-environments.spec.ts` (19 casos): reparto de ambas claves, paquete
parcial, vacíos, ingesta con `ambiente=Produccion` y dos llaves → dos filas, no
borrado de la llave ausente, empresa distinta con el mismo RNC, criptograma que no
abre en otro contexto, reclasificación sin autorización / con autorización /
idempotente / dry-run / fila inexistente, y las cuatro propiedades del `upsert`
(no degrada, no reescribe si no cambia, conserva `created_at`, mantiene la clave
única).
