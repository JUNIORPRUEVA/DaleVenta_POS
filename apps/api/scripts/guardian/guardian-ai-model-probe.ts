/**
 * APPYRA Guardian AI — sonda de modelos del proveedor de IA.
 *
 * NO SE EJECUTA AUTOMÁTICAMENTE. Requiere autorización explícita del
 * propietario porque realiza UNA petición externa (GET {base}/models), que es
 * una llamada de solo lectura y sin coste de tokens, pero sigue siendo tráfico
 * hacia un proveedor externo.
 *
 * Uso (solo tras autorización):
 *
 *   GUARDIAN_ENV_FILE=C:\Users\<usuario>\.guardian-uat\fullpos-backend.env \
 *     npx ts-node --transpile-only -P tsconfig.scripts.json \
 *     scripts/guardian/guardian-ai-model-probe.ts --confirm
 *
 * Salida: estado HTTP, número de modelos y lista de identificadores.
 * Nunca imprime la API key ni cabeceras de autenticación.
 *
 * Motivo: el código no valida el nombre del modelo; lo reenvía tal cual. Un
 * modelo inexistente produce AI_PROVIDER_ERROR en la primera llamada y el
 * diagnóstico cae a INSUFFICIENT (fail-safe, sin alertas ni coste de salida).
 * Esta sonda permite confirmar el catálogo ANTES de activar nada.
 */
import * as fs from 'node:fs';
import * as dotenv from 'dotenv';

const CONFIRM_FLAG = '--confirm';

async function main(): Promise<void> {
  if (!process.argv.includes(CONFIRM_FLAG)) {
    console.log('BLOQUEADO: falta --confirm. Esta sonda hace una peticion externa de solo lectura.');
    console.log('Requiere autorizacion explicita del propietario.');
    process.exitCode = 2;
    return;
  }

  const envFile = String(process.env.GUARDIAN_ENV_FILE ?? '').trim();
  if (envFile) {
    if (!fs.existsSync(envFile)) {
      console.log('ERROR: GUARDIAN_ENV_FILE no existe');
      process.exitCode = 1;
      return;
    }
    dotenv.config({ path: envFile, override: true, quiet: true });
  }

  const apiKey = String(process.env.GUARDIAN_AI_API_KEY ?? '').trim();
  const baseUrl = String(process.env.GUARDIAN_AI_BASE_URL ?? '').trim().replace(/\/+$/, '');
  const configuredModel = String(process.env.GUARDIAN_AI_MODEL ?? '').trim();

  if (!apiKey || !baseUrl) {
    console.log('ERROR: faltan GUARDIAN_AI_API_KEY o GUARDIAN_AI_BASE_URL');
    process.exitCode = 1;
    return;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15_000);

  try {
    const response = await fetch(`${baseUrl}/models`, {
      method: 'GET',
      signal: controller.signal,
      headers: { Accept: 'application/json', Authorization: `Bearer ${apiKey}` },
    });

    const text = await response.text().catch(() => '');
    let ids: string[] = [];
    try {
      const body: any = text ? JSON.parse(text) : {};
      const list = Array.isArray(body?.data) ? body.data : [];
      ids = list.map((item: any) => String(item?.id ?? '')).filter(Boolean).sort();
    } catch {
      ids = [];
    }

    console.log(
      JSON.stringify(
        {
          httpStatus: response.status,
          ok: response.ok,
          modelCount: ids.length,
          models: ids,
          configuredModel,
          configuredModelPresent: ids.length > 0 ? ids.includes(configuredModel) : null,
        },
        null,
        2,
      ),
    );

    if (!response.ok) process.exitCode = 1;
    else if (ids.length > 0 && !ids.includes(configuredModel)) process.exitCode = 3;
  } catch (error) {
    console.log(
      JSON.stringify({
        ok: false,
        reason: 'PROBE_FAILED',
        detail: error instanceof Error ? error.message.slice(0, 120) : 'error',
      }),
    );
    process.exitCode = 1;
  } finally {
    clearTimeout(timer);
  }
}

void main();
