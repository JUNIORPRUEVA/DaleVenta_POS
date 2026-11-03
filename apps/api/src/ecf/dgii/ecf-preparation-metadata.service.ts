import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

import {
  evaluateSimulationMode,
  sanitizeVideoUrl,
} from "./ecf-preparation-metadata.policy";

/** Metadatos de preparación que consume la pantalla e-CF. */
export type EcfPreparationMetadata = {
  videoUrl: string | null;
  simulation: {
    available: boolean;
    badge: string;
    reason: string | null;
  };
};

@Injectable()
export class EcfPreparationMetadataService {
  constructor(private readonly config: ConfigService) {}

  get(companyId: string): EcfPreparationMetadata {
    const simulation = evaluateSimulationMode(
      {
        orchestrator: this.config.get<string>("ECF_CERTIFICATION_ORCHESTRATOR"),
        alanubeEnv: this.config.get<string>("ALANUBE_ENV"),
        activationTransport: this.config.get<string>("ECF_ACTIVATION_TRANSPORT"),
        allowedCompanyId: this.config.get<string>("ECF_SIMULATION_COMPANY_ID"),
      },
      companyId,
    );
    return {
      videoUrl: sanitizeVideoUrl(
        this.config.get<string>("ECF_HABILITATION_VIDEO_URL"),
      ),
      simulation,
    };
  }
}
