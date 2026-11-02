import type { EcfEmissionWire, EcfEmissionWireRequest, EcfEmissionWireResult } from "../../documents/ecf-emission.service";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import type { DosaEmissionClient } from "./dosa-emission.client";

/**
 * Cable que conecta el cliente HTTP de DOSA con el orquestador de emisión real
 * de FullPOS (`EcfEmissionService.dispatchOnce`).
 *
 * Consecuencia importante: al pasar por `dispatchOnce`, la emisión DOSA hereda
 * gratis la maquinaria que ya existe y que está probada:
 *
 * * reclamación de la fila con `FOR UPDATE` **antes** de la red;
 * * una sola tentativa `SEND_TO_PROVIDER` por documento (nunca doble POST);
 * * registro de evidencia con huella del payload y del request;
 * * estado final `HUMAN_REVIEW_REQUIRED`, nunca aceptación fiscal automática.
 *
 * Este cable no decide: solo traduce. Las compuertas están antes, en
 * `DosaEmissionService`.
 */
export class DosaEmissionWire implements EcfEmissionWire {
  constructor(private readonly client: DosaEmissionClient) {}

  async execute(input: EcfEmissionWireRequest): Promise<EcfEmissionWireResult> {
    const result = await this.client.sendEcf({
      body: input.body as DosaEcfRequestBody,
      // La tentativa ya reclamada por el orquestador es la clave de
      // idempotencia: un mismo documento no puede salir dos veces.
      idempotencyKey: input.requestId,
    });

    if (result.ok) {
      return { ok: true, statusCode: result.status, body: result.raw };
    }

    if ("blockedReason" in result) {
      return {
        ok: false,
        errorCode: "BLOCKED",
        safeMessage: result.blockedReason,
      };
    }

    // Con respuesta HTTP legible se devuelve al orquestador para que evalúe la
    // correlación. Solo se convierte en fallo de transporte cuando no hubo
    // cuerpo que interpretar.
    if (result.raw !== null) {
      return {
        ok: true,
        statusCode: result.status ?? 0,
        body: result.raw,
      };
    }

    return {
      ok: false,
      errorCode: result.transportFailure === "TIMEOUT" ? "TIMEOUT" : "NETWORK_ERROR",
      safeMessage: `ECF_DOSA_${result.transportFailure}`,
    };
  }
}
