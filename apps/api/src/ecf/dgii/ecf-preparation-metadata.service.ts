import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { R2Service } from "../../storage/r2.service";

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
  private readonly logger = new Logger(EcfPreparationMetadataService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly r2: R2Service,
  ) {}

  async get(companyId: string): Promise<EcfPreparationMetadata> {
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
      videoUrl: await this.videoUrl(),
      simulation,
    };
  }

  private async videoUrl(): Promise<string | null> {
    const configured = sanitizeVideoUrl(
      this.config.get<string>("ECF_HABILITATION_VIDEO_URL"),
    );
    if (configured) return configured;

    const objectKey = (
      this.config.get<string>("ECF_HABILITATION_VIDEO_OBJECT_KEY") ?? ""
    ).trim();
    // Solo material tutorial global aprobado; nunca archivos de una empresa.
    if (!/^uploads\/tutorials\/ecf\/[a-zA-Z0-9_-]+\.mp4$/.test(objectKey)) {
      return null;
    }
    try {
      return sanitizeVideoUrl(await this.r2.createPresignedGetUrl({
        objectKey,
        expiresInSeconds: 86400,
      }));
    } catch {
      // No registrar el error del SDK: puede incluir una URL firmada.
      this.logger.warn("No se pudo preparar el enlace del tutorial de bienvenida");
      return null;
    }
  }
}
