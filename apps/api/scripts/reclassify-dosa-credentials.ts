/**
 * Reclasificación de credenciales DOSA ya guardadas — **herramienta manual**.
 *
 * Qué corrige
 * -----------
 * Antes del 07/11/2026 el receptor guardaba el paquete completo del webhook bajo
 * el `ambiente` declarado por el evento (`Produccion`). La clave TEST quedaba
 * encerrada en la fila de producción y la emisión de pruebas no podía usarla.
 *
 * Este comando **reparte** ese paquete ya cifrado entre sus ambientes, sin
 * pedirle al proveedor un reenvío y **sin tocar** la fila de origen.
 *
 * Seguridad
 * ---------
 * * **Dry-run por defecto.** Sin `--apply` no escribe nada.
 * * `--apply` exige además `DOSA_CREDENTIALS_RECLASSIFY=CONFIRM` en el entorno.
 *   Dos llaves distintas para una operación que descifra: imposible por descuido.
 * * No imprime valores. Solo empresa, RNC, ambientes, estados y huellas.
 * * No activa nada: lo que escriba entra como `PENDING_CONFIRMATION`.
 * * No modifica el ambiente de origen.
 * * Idempotente: si el ambiente destino ya tiene la misma huella, no escribe.
 *
 * Uso
 * ---
 * ```bash
 * # 1) Ver qué haría (no escribe)
 * npm run dosa:credentials:reclassify -- --company-id <uuid> --rnc 133080206
 *
 * # 2) Aplicar (requiere confirmación explícita en el entorno)
 * DOSA_CREDENTIALS_RECLASSIFY=CONFIRM \
 *   npm run dosa:credentials:reclassify -- --company-id <uuid> --rnc 133080206 --apply
 * ```
 */
import { Client } from "pg";
import { DosaCredentialService, PrismaDosaCredentialStore } from "../src/ecf/provider/dosa/dosa-credential.service";
import { DosaCredentialVault } from "../src/ecf/provider/dosa/dosa-credential-vault.service";

/** Adaptador mínimo: la bóveda y el almacén esperan `$queryRaw` con parámetros. */
class PgRawClient {
  constructor(private readonly client: Client) {}

  async $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T> {
    const sql = query.reduce(
      (acc, part, index) =>
        acc + part + (index < values.length ? `$${index + 1}` : ""),
      "",
    );
    const result = await this.client.query(sql, values as unknown[]);
    return result.rows as T;
  }
}

function argValue(name: string): string | null {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return null;
  const value = process.argv[index + 1];
  return typeof value === "string" && !value.startsWith("--") ? value.trim() : null;
}

async function main(): Promise<void> {
  const companyId = argValue("company-id");
  const rnc = argValue("rnc");
  const apply = process.argv.includes("--apply");

  if (!companyId || !rnc) {
    console.error(
      "Uso: reclassify-dosa-credentials --company-id <uuid> --rnc <rnc> [--apply]",
    );
    process.exitCode = 1;
    return;
  }

  if (apply && (process.env.DOSA_CREDENTIALS_RECLASSIFY ?? "").trim() !== "CONFIRM") {
    console.error(
      "Aplicar requiere DOSA_CREDENTIALS_RECLASSIFY=CONFIRM en el entorno. No se ha escrito nada.",
    );
    process.exitCode = 2;
    return;
  }

  const masterKey = (process.env.DOSA_CREDENTIALS_MASTER_KEY ?? "").trim();
  if (!masterKey) {
    console.error("Falta DOSA_CREDENTIALS_MASTER_KEY. No se ha escrito nada.");
    process.exitCode = 1;
    return;
  }

  const connectionString = (process.env.DATABASE_URL ?? "").trim();
  if (!connectionString) {
    console.error("Falta DATABASE_URL. No se ha escrito nada.");
    process.exitCode = 1;
    return;
  }

  const pg = new Client({ connectionString });
  await pg.connect();

  try {
    const store = new PrismaDosaCredentialStore(new PgRawClient(pg));
    const service = new DosaCredentialService(store, new DosaCredentialVault(masterKey));

    const result = await service.reclassifyStoredCredentials({
      companyId,
      rnc,
      sourceEnvironment: "production",
      authorized: true,
      dryRun: !apply,
    });

    // Solo metadatos: sin valores, sin criptogramas.
    console.log(
      JSON.stringify(
        {
          modo: apply ? "APPLY" : "DRY_RUN",
          ok: result.ok,
          motivo: result.blockedReason ?? null,
          empresa: companyId,
          rnc,
          escritos: result.written.map((entry) => ({
            ambiente: entry.environment,
            estado: entry.status,
            huella: entry.fingerprint.slice(0, 12),
          })),
          ya_correctos: result.already,
        },
        null,
        2,
      ),
    );

    if (!result.ok) process.exitCode = 3;
  } finally {
    await pg.end();
  }
}

void main().catch((error: unknown) => {
  // Sin volcar datos sensibles: solo el mensaje.
  console.error(
    "Error en la reclasificación:",
    error instanceof Error ? error.message : "desconocido",
  );
  process.exitCode = 1;
});
