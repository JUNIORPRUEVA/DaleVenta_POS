import { ConflictException, Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import type { TenantUser } from "../../auth/tenant-context";
import { simulateAlanubeDispatchResponse } from "../alanube/alanube-simulated-dispatch.response";
import { isAlanubeRealTransportSelected } from "../alanube/alanube-transport.provider";
import type { AlanubeSimulationScenario } from "../alanube/alanube-scenario.transport";
import {
  type EcfEmissionWire,
  EcfEmissionService,
} from "./ecf-emission.service";
import { simulatedDispatchRefusal } from "./ecf-simulated-dispatch.policy";

/**
 * Despacho de un comprobante contra el ALANUBE SIMULADO.
 *
 * Es el único camino que cablea `EcfEmissionService.dispatchOnce` a una ruta
 * HTTP. Se apoya en el transporte SIMULADO puro (`simulateAlanubeResponse`), no
 * en el cliente HTTP real: no hay red, no hay URL externa, no hay credenciales y
 * no se consume numeración real.
 *
 * `dispatchOnce` mantiene toda la disciplina fiscal: reclama el intento antes de
 * la "red", persiste el estado y **nunca** concede aceptación de la DGII — una
 * observación correlacionada acaba en `HUMAN_REVIEW_REQUIRED`.
 */
@Injectable()
export class EcfSimulatedDispatchService {
  constructor(
    private readonly config: ConfigService,
    private readonly emission: EcfEmissionService,
  ) {}

  /**
   * Construye el "cable" simulado para un escenario.
   *
   * Se adapta `AlanubeTransportResult` a `EcfEmissionWireResult`, que solo admite
   * `TIMEOUT | NETWORK_ERROR | BLOCKED` como fallo. Un escenario bloqueado por
   * política se reporta como `BLOCKED`; el resto de fallos de transporte son
   * `NETWORK_ERROR`, salvo el timeout explícito.
   */
  private wire(scenario: AlanubeSimulationScenario): EcfEmissionWire {
    return {
      async execute(request) {
        const result = simulateAlanubeDispatchResponse(scenario, {
          method: request.method,
          url: request.path,
          headers: { "content-type": "application/json" },
          body: request.body,
          timeoutMs: 15000,
          requestId: request.requestId,
        });

        if (result.ok) {
          return {
            ok: true,
            statusCode: result.response.statusCode,
            body: result.response.body,
          };
        }

        const errorCode =
          result.errorCode === "TIMEOUT"
            ? ("TIMEOUT" as const)
            : result.errorCode === "REAL_CALLS_DISABLED" ||
                result.errorCode === "PRODUCTION_BLOCKED"
              ? ("BLOCKED" as const)
              : ("NETWORK_ERROR" as const);

        return { ok: false, errorCode, safeMessage: result.safeMessage };
      },
    };
  }

  async dispatch(
    user: TenantUser,
    documentId: string,
    scenario: AlanubeSimulationScenario,
  ) {
    const refusal = simulatedDispatchRefusal(
      {
        APP_ENV: this.read("APP_ENV"),
        UAT_LOCAL_ONLY: this.read("UAT_LOCAL_ONLY"),
      },
      isAlanubeRealTransportSelected(this.config),
    );

    if (refusal) {
      throw new ConflictException(refusal);
    }

    const outcome = await this.emission.dispatchOnce(
      user,
      documentId,
      this.wire(scenario),
    );

    // Marca explícita de origen: el cliente y la auditoría deben poder distinguir
    // sin ambigüedad un resultado SIMULADO de una aceptación fiscal oficial.
    return {
      ...outcome,
      simulated: true as const,
      officialFiscalAcceptance: false as const,
      scenario,
    };
  }

  private read(key: string): string | undefined {
    return this.config.get<string>(key) ?? process.env[key];
  }
}
