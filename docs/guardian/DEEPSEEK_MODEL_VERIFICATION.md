# Verificación del modelo DeepSeek sin consumir la API

Estado: **modelo configurado = forma válida, disponibilidad NO verificada**.
No se ha realizado ninguna petición a DeepSeek.

---

## 1. Qué hace el código con el modelo (HECHO)

`apps/api/src/guardian/ai/openai-guardian-ai.provider.ts`:

```ts
const model = this.options.model ?? 'gpt-4o-mini';
...
body: JSON.stringify({ model, temperature: 0, max_tokens, response_format: { type: 'json_object' }, messages: [...] })
```

- El valor de `GUARDIAN_AI_MODEL` se envía **tal cual**: no hay validación ni
  lista blanca en el código.
- La URL efectiva es `${GUARDIAN_AI_BASE_URL}/chat/completions`.
- `response_format: { type: 'json_object' }` (modo JSON) y `temperature: 0`.

`createGuardianAiProvider()` selecciona el adaptador **solo** por
`GUARDIAN_AI_API_KEY`. `GUARDIAN_AI_PROVIDER` no cambia nada (ver
`guardian.ai.runtime.spec.ts`, que fija ese comportamiento y hace que el
arranque registre una advertencia explícita).

## 2. Por qué no se puede confirmar aquí (HECHO)

La lista de modelos de un proveedor externo solo la confirma el proveedor.
En este entorno no hay acceso autorizado a la API ni documentación local con el
catálogo, así que **no se puede afirmar** que `deepseek-flash` exista. Tampoco
se inventa un sustituto como «confirmado».

Consecuencia práctica si el nombre no existe: la primera llamada devuelve
`AI_PROVIDER_ERROR` (HTTP 4xx), el diagnóstico se registra como `INSUFFICIENT`
y **no se envía ninguna alerta ni se consume presupuesto de salida**. El fallo
es seguro y visible en el expediente.

## 3. Sonda preparada (no ejecutada)

`apps/api/scripts/guardian/guardian-ai-model-probe.ts`

- Hace **una** petición `GET {base}/models` (solo lectura, sin coste de tokens).
- Exige el flag `--confirm`; sin él sale con código 2 y no hace nada.
- Salida: estado HTTP, número de modelos, identificadores y si el modelo
  configurado está en la lista. **Nunca** imprime la API key.

Comando para cuando se autorice:

```powershell
cd C:\src\guardian-integration-uat\apps\api
$env:GUARDIAN_ENV_FILE = "$env:USERPROFILE\.guardian-uat\fullpos-backend.env"
npx ts-node --transpile-only -P tsconfig.scripts.json scripts/guardian/guardian-ai-model-probe.ts --confirm
```

Criterios:

| Resultado | Acción |
| --- | --- |
| `configuredModelPresent: true` | mantener el modelo actual |
| `configuredModelPresent: false` (lista obtenida) | elegir uno de `models` y actualizar `GUARDIAN_AI_MODEL` |
| HTTP 401/403 | la clave no sirve para ese host: revisar proyecto/entorno |
| HTTP 404 | `GUARDIAN_AI_BASE_URL` incorrecta |

## 4. Plan de respaldo preparado

Se dejó un archivo alternativo en la configuración privada
(`C:\Users\pc\.guardian-uat\fullpos-backend.deepseek-alt.env`), idéntico salvo
`GUARDIAN_AI_MODEL`. Cambiar de modelo es copiar un archivo, no editar valores.

Criterio para elegir el alternativo: el que la sonda confirme en `models`.
No se escribe un nombre «a ciegas» en la configuración activa.

## 5. Salvaguardas que ya están en el código (HECHO)

| Salvaguarda | Dónde |
| --- | --- |
| Evidencia tratada como no confiable + regla anti-inyección | `SYSTEM_PROMPT` y `buildUntrustedEvidenceBlock()` |
| Veredicto acotado a `CONFIRMED｜PROBABLE｜INSUFFICIENT` | `normalizeVerdict()` |
| JSON estricto con extracción tolerante | `extractJsonObject()` |
| Timeout + abort | `GUARDIAN_AI_TIMEOUT_MS` (20 s por defecto) |
| Concurrencia limitada | `GUARDIAN_AI_MAX_CONCURRENCY` (semáforo) |
| Presupuesto diario de tokens por empresa | `GUARDIAN_AI_TOKENS_PER_COMPANY_DAY` (200 000 por defecto) |
| Reintentos acotados con backoff y `Retry-After` | `guardian.diagnosis.service.ts` |
| Sin clave → mock, nunca llamada externa | `createGuardianAiProvider()` |
