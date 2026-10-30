import { Injectable } from "@nestjs/common";

export type EcfMetricScope = {
  companyId: string;
  status?: string;
  operation?: string;
};

@Injectable()
export class EcfObservabilityService {
  metricName(name: string, scope: EcfMetricScope) {
    return {
      name: `ecf.${name}`,
      companyId: scope.companyId,
      status: scope.status,
      operation: scope.operation,
    };
  }
}
