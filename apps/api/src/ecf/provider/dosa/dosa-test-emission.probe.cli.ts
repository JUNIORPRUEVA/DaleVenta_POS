import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import {
  DOSA_PROBE_ALLOWED_ORIGIN,
  DosaE31TestProbe,
  probeAuthorizationToken,
  type DosaProbeConfig,
  type DosaProbeEvidence,
} from "./dosa-test-emission.probe";
import { createFetchDosaTransport } from "./dosa-emission.client";

/**
 * CLI del probador E31 de TEST.
 *
 * Uso (desde `apps/api`, con `dist` construido):
 *
 * ```
 * node dist/ecf/provider/dosa/dosa-test-emission.probe.cli.js \
 *   --encf=E31000113500 --dry-run
 * ```
 *
 * Para un envío externo real hay que quitar `--dry-run` **y** pasar el token de
 * autorización:
 *
 * ```
 * node dist/.../dosa-test-emission.probe.cli.js \
 *   --encf=E31000113500 --token=AUTHORIZE-E31000113500
 * ```
 *
 * Variables de entorno (ninguna se imprime):
 *
 * | Variable | Uso |
 * | --- | --- |
 * | `DOSA_EMISSION_ENVIRONMENT` | debe ser `TEST` |
 * | `DOSA_BASE_URL` | debe ser `https://dosasystem.com` |
 * | `DOSA_TEST_API_KEY` | clave de TEST entregada por DOSA |
 * | `DOSA_TEST_RNC` | RNC de prueba, p. ej. `133306001` |
 * | `DOSA_TEST_SEQUENCE_PREFIX` | prefijo del rango, por defecto `E31` |
 * | `DOSA_TEST_SEQUENCE_FROM` / `_TO` | rango autorizado, p. ej. 113500 / 115500 |
 * | `DOSA_PROBE_EVIDENCE_FILE` | ruta del registro de intentos |
 */

function arg(name: string): string | null {
  const found = process.argv
    .slice(2)
    .find((item) => item === `--${name}` || item.startsWith(`--${name}=`));
  if (!found) return null;
  const [, value] = found.split("=");
  return value ?? "";
}

function fail(code: string, detail: string): never {
  // eslint-disable-next-line no-console
  console.error(JSON.stringify({ ok: false, code, detail }));
  process.exit(2);
}

/** E31 mínimo y coherente: una línea gravada al 18 %. */
export function buildCoherentE31(input: {
  encf: string;
  senderRnc: string;
  senderName: string;
  buyerRnc?: string;
  buyerName?: string;
  unitPrice: string;
  quantity: number;
  taxRate: number;
  issueDate: string;
  /**
   * Código de unidad de medida. DOSA la exige, y su catálogo no está
   * documentado en los materiales disponibles: **no se pone un valor por
   * defecto**, se recibe del operador en cada ejecución.
   */
  unitOfMeasure: string;
}): DosaEcfRequestBody {
  const priceCents = Math.round(Number.parseFloat(input.unitPrice) * 100);
  const amountCents = Math.round(priceCents * input.quantity);
  const itbisCents = Math.round((amountCents * input.taxRate) / 100);
  const totalCents = amountCents + itbisCents;
  const money = (value: number) => (value / 100).toFixed(2);

  return {
    encabezado: {
      version: "1.0",
      idDoc: {
        tipoeCF: "31",
        eNCF: input.encf,
        fechaEmision: input.issueDate,
      },
      emisor: {
        RNCEmisor: input.senderRnc,
        RazonSocialEmisor: input.senderName,
      },
      ...(input.buyerRnc
        ? {
            comprador: {
              RNCComprador: input.buyerRnc,
              ...(input.buyerName
                ? { RazonSocialComprador: input.buyerName }
                : {}),
            },
          }
        : {}),
      totales: {
        MontoGravadoTotal: money(amountCents),
        MontoGravadoI1: money(amountCents),
        MontoExento: "0.00",
        ITBIS1: String(input.taxRate),
        TotalITBIS: money(itbisCents),
        MontoTotal: money(totalCents),
      },
    },
    detallesItems: [
      {
        numeroLinea: 1,
        // 1 = Producto (naturaleza del ítem, no el indicador de impuesto).
        indicadorFacturacion: 1,
        nombreItem: "PRUEBA DE EMISION TEST",
        // 2 = Bien en DOSA (al revés que el código de la DGII).
        indicadorBienoServicio: 2,
        unidadMedida: input.unitOfMeasure,
        cantidadItem: String(input.quantity),
        precioUnitarioItem: money(priceCents),
        montoItem: money(amountCents),
      },
    ],
  };
}

/**
 * Unidad de medida del comprobante de prueba.
 *
 * Se exige explícitamente (`--unidad` o `DOSA_TEST_UNIT_OF_MEASURE`) porque
 * DOSA la considera obligatoria y su catálogo de códigos no está documentado en
 * los materiales que tenemos. Poner un valor por defecto sería inventar un
 * código fiscal; si falta, la prueba no se ejecuta.
 */
function unitOfMeasure(): string {
  const value = (arg("unidad") ?? process.env.DOSA_TEST_UNIT_OF_MEASURE ?? "").trim();
  if (value.length === 0) {
    fail(
      "DOSA_PROBE_UNIT_OF_MEASURE_REQUIRED",
      "usa --unidad=<codigo> (o DOSA_TEST_UNIT_OF_MEASURE); DOSA exige unidadMedida",
    );
  }
  return value;
}

async function main(): Promise<void> {
  const encf = (arg("encf") ?? "").trim();
  if (encf.length === 0) fail("DOSA_PROBE_ENCF_REQUIRED", "usa --encf=E31...");

  const dryRun = process.argv.slice(2).includes("--dry-run");
  const token = arg("token");

  const config: DosaProbeConfig = {
    environment:
      (process.env.DOSA_EMISSION_ENVIRONMENT ?? "").trim().toUpperCase() ===
      "PRODUCTION"
        ? "PRODUCTION"
        : "TEST",
    baseUrl: (process.env.DOSA_BASE_URL ?? "").trim() || DOSA_PROBE_ALLOWED_ORIGIN,
    apiKey: (process.env.DOSA_TEST_API_KEY ?? "").trim(),
    testRnc: (process.env.DOSA_TEST_RNC ?? "").trim(),
    sequenceRange: {
      prefix: (process.env.DOSA_TEST_SEQUENCE_PREFIX ?? "E31").trim() || "E31",
      from: Number.parseInt(process.env.DOSA_TEST_SEQUENCE_FROM ?? "113500", 10),
      to: Number.parseInt(process.env.DOSA_TEST_SEQUENCE_TO ?? "115500", 10),
    },
    timeoutMs: Number.parseInt(process.env.DOSA_EMISSION_TIMEOUT_MS ?? "20000", 10),
  };

  const evidenceFile =
    (process.env.DOSA_PROBE_EVIDENCE_FILE ?? "").trim() ||
    ".dosa-probe/evidence.jsonl";

  const body = buildCoherentE31({
    encf,
    senderRnc: config.testRnc,
    senderName: (process.env.DOSA_TEST_SENDER_NAME ?? "EMPRESA DE PRUEBA").trim(),
    buyerRnc: (process.env.DOSA_TEST_BUYER_RNC ?? "").trim() || undefined,
    buyerName: (process.env.DOSA_TEST_BUYER_NAME ?? "").trim() || undefined,
    unitPrice: (process.env.DOSA_TEST_UNIT_PRICE ?? "100.00").trim(),
    quantity: Number.parseInt(process.env.DOSA_TEST_QUANTITY ?? "1", 10),
    taxRate: Number.parseInt(process.env.DOSA_TEST_TAX_RATE ?? "18", 10),
    issueDate:
      (process.env.DOSA_TEST_ISSUE_DATE ?? "").trim() || ddMmYyyy(new Date()),
    unitOfMeasure: unitOfMeasure(),
  });

  const probe = new DosaE31TestProbe({
    transport: createFetchDosaTransport(),
    config,
    onEvidence: (evidence: DosaProbeEvidence) => {
      mkdirSync(dirname(evidenceFile), { recursive: true });
      appendFileSync(evidenceFile, `${JSON.stringify(evidence)}\n`, {
        encoding: "utf8",
        mode: 0o600,
      });
    },
  });

  if (dryRun) {
    // Sin autorización, el probador NO envía: solo valida y deja evidencia.
    const result = await probe.run({ body, encf, authorizationToken: null });
    // eslint-disable-next-line no-console
    console.log(
      JSON.stringify(
        {
          mode: "dry-run",
          ready: result.ok,
          blockedReasons: result.ok ? [] : result.blockedReasons,
          wouldSendTo: `${config.baseUrl.replace(/\/+$/, "")}/fe/api/emision/ecf/EnviarFactura`,
          encf,
          senderRnc: config.testRnc,
          apiKeyLoaded: config.apiKey.length > 0,
          tokenRequired: probeAuthorizationToken(encf),
          evidenceFile,
        },
        null,
        2,
      ),
    );
    process.exit(result.ok ? 0 : 3);
  }

  const result = await probe.run({ body, encf, authorizationToken: token });
  // eslint-disable-next-line no-console
  console.log(
    JSON.stringify(
      {
        mode: "external",
        ok: result.ok,
        blockedReasons: result.ok ? [] : result.blockedReasons,
        httpStatus: result.evidence.httpStatus,
        outcome: result.evidence.classification?.outcome ?? null,
        unresolvedReason: result.evidence.classification?.unresolvedReason ?? null,
        mensajes: result.evidence.classification?.mensajes ?? [],
        secuenciaUtilizada:
          result.evidence.classification?.secuenciaUtilizada ?? null,
        safeToRetrySameEncf: result.evidence.safeToRetrySameEncf,
        responseSha256: result.evidence.responseSha256,
        evidenceFile,
      },
      null,
      2,
    ),
  );
  // Código 0 = validación OK y respuesta registrada; 4 = bloqueado.
  process.exit(result.ok ? 0 : 4);
}

function ddMmYyyy(date: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${pad(date.getDate())}-${pad(date.getMonth() + 1)}-${date.getFullYear()}`;
}

if (require.main === module) {
  void main();
}
