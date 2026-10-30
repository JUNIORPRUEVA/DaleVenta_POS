import { Injectable } from "@nestjs/common";

export type EcfReconciliationPlan = {
  canQueryProvider: boolean;
  canUpdateFiscalStatus: boolean;
  nextAction:
    | "WAIT_FOR_OFFICIAL_QUERY_CONTRACT"
    | "MANUAL_REVIEW"
    | "QUERY_PROVIDER_SIMULATED";
  safeReason: string;
};

@Injectable()
export class AlanubeReconciliationService {
  planFor(document: {
    status: string;
    externalProviderId?: string | null;
  }): EcfReconciliationPlan {
    if (!document.externalProviderId) {
      return {
        canQueryProvider: false,
        canUpdateFiscalStatus: false,
        nextAction: "MANUAL_REVIEW",
        safeReason: "Documento sin identificador externo verificable.",
      };
    }
    return {
      canQueryProvider: false,
      canUpdateFiscalStatus: false,
      nextAction: "WAIT_FOR_OFFICIAL_QUERY_CONTRACT",
      safeReason:
        "Existe consulta pública documentada; autenticidad, correlación y semántica fiscal pendientes de verificar. Consulta remota bloqueada.",
    };
  }
}
