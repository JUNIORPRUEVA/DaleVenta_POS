import { createHash } from "node:crypto";
import type {
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "./alanube-safe-http.types";
import {
  type AlanubeSimulationScenario,
  simulateAlanubeResponse,
} from "./alanube-scenario.transport";

/**
 * Respuesta SIMULADA fiel al contrato LOCAL, para poder recorrer de extremo a
 * extremo la cadena completa: transporte → observación → correlación →
 * evidencia → estado → bandeja.
 *
 * Por qué existe una capa aparte:
 *
 * - `alanube-scenario.transport.ts` modela el comportamiento **de transporte**
 *   (timeout, 429, 500, conexión perdida, cuerpo malformado) con cuerpos que son
 *   deliberadamente suyos y no correlacionan. Sus 33 pruebas fijan eso y no se
 *   tocan.
 * - Para que `assessEcfProviderResponse` pueda **correlacionar**, el cuerpo debe
 *   respetar el contrato local ya establecido por la propia observación:
 *   `id` (26 caracteres), `documentNumber` = e-NCF esperado,
 *   `companyIdentification` = RNC emisor, `status` string,
 *   `sequenceConsumed` booleano y `legalStatus` (o un `status` de espera).
 *
 * No se inventa ningún campo del contrato EXTERNO: se reutilizan exactamente los
 * campos que el proyecto ya exige a una respuesta real, tomando la identidad del
 * propio payload DOM (`idDoc.encf`, `sender.rnc`).
 *
 * Lo que esta capa NO hace: no declara aceptación fiscal. `dispatchOnce` nunca
 * concede `DGII_ACCEPTED`; una observación correlacionada acaba en
 * `HUMAN_REVIEW_REQUIRED` para revisión humana, con su recibo de evidencia.
 */

/** Alfabeto admitido por el contrato local del `id` remoto. */
const REMOTE_ID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/**
 * Identificador remoto ESTABLE para el mismo `requestId`: un reintento devuelve
 * el mismo `id`, que es justo lo que hay que poder demostrar.
 */
export function deterministicRemoteId(requestId: string): string {
  const hash = createHash("sha256").update(requestId).digest();
  let body = "";
  for (let index = 0; index < 25; index += 1) {
    body += REMOTE_ID_ALPHABET[hash[index] % 32];
  }
  return `${"01234567"[hash[25] % 8]}${body}`;
}

type DomPayloadDraft = {
  idDoc?: { encf?: unknown };
  sender?: { rnc?: unknown };
};

function readString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/** Escenarios que representan una RESPUESTA del proveedor con contrato local. */
export const ALANUBE_CORRELATED_SCENARIOS: readonly AlanubeSimulationScenario[] = [
  "PROVIDER_ACCEPTED",
  "PROVIDER_REJECTED",
  "DGII_ACCEPTED_SIMULATED",
  "DGII_REJECTED_SIMULATED",
  "DUPLICATE_RESPONSE",
  "OUT_OF_ORDER",
  "IDEMPOTENT_RETRY",
  "RECEIVED",
  "PROCESS_RESTART",
  "PENDING_RECOVERY",
  "UNKNOWN_RESULT",
];

/**
 * Resultado simulado del escenario.
 *
 * Para los escenarios con contrato local devuelve **HTTP 201** y el cuerpo
 * correlacionable. Para los escenarios de transporte (timeout, 429, 500,
 * conexión perdida, cuerpo malformado…) delega en `simulateAlanubeResponse`, que
 * ya los modela y cuyas respuestas NO correlacionan a propósito.
 */
export function simulateAlanubeDispatchResponse(
  scenario: AlanubeSimulationScenario,
  request: AlanubeSafeRequest,
): AlanubeTransportResult {
  if (!ALANUBE_CORRELATED_SCENARIOS.includes(scenario)) {
    return simulateAlanubeResponse(scenario, request);
  }

  const payload = (request.body ?? {}) as DomPayloadDraft;
  const encf = readString(payload.idDoc?.encf);
  const senderTaxId = readString(payload.sender?.rnc);

  const envelope = (body: unknown): AlanubeTransportResult => ({
    ok: true,
    response: {
      statusCode: 201,
      headers: { "content-type": "application/json" },
      body,
      requestId: request.requestId,
    },
  });

  const identity = {
    id: deterministicRemoteId(request.requestId),
    documentNumber: encf,
    companyIdentification: senderTaxId,
  };

  switch (scenario) {
    case "PROVIDER_REJECTED":
    case "DGII_REJECTED_SIMULATED":
      return envelope({
        ...identity,
        status: "FINISHED",
        legalStatus: "REJECTED",
        sequenceConsumed: true,
      });

    case "RECEIVED":
    case "PROCESS_RESTART":
    case "PENDING_RECOVERY":
      // Pendiente de respuesta: NO hay legalStatus y la secuencia no se ha
      // consumido aún.
      return envelope({
        ...identity,
        status: "WAITING_RESPONSE",
        sequenceConsumed: false,
      });

    case "UNKNOWN_RESULT":
      // 201 con un estado que no es ninguno de los admitidos: debe fallar
      // cerrado y terminar en resultado desconocido, nunca en aceptación.
      return envelope({
        ...identity,
        status: "SOMETHING_ELSE",
        sequenceConsumed: true,
      });

    default:
      // PROVIDER_ACCEPTED, DGII_ACCEPTED_SIMULATED, DUPLICATE_RESPONSE,
      // OUT_OF_ORDER, IDEMPOTENT_RETRY.
      //
      // OJO: `legalStatus: ACCEPTED` describe lo que el PROVEEDOR comunicó en el
      // simulador. No es aceptación de la DGII y `dispatchOnce` no la concede.
      return envelope({
        ...identity,
        status: "FINISHED",
        legalStatus: "ACCEPTED",
        sequenceConsumed: true,
      });
  }
}
