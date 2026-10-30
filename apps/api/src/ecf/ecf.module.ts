import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AlanubeSafeHttpClient } from "./alanube/alanube-safe-http.client";
import {
  ALANUBE_HTTP_TRANSPORT,
  createAlanubeHttpTransport,
} from "./alanube/alanube-transport.provider";
import { AlanubeReconciliationService } from "./alanube/alanube-reconciliation.service";
import { EcfDocumentIdempotencyService } from "./documents/ecf-document-idempotency.service";
import { EcfDocumentQueryService } from "./documents/ecf-document-query.service";
import { EcfLineClassificationService } from "./documents/ecf-line-classification.service";
import { EcfEmissionService } from "./documents/ecf-emission.service";
import { EcfSimulatedDispatchService } from "./documents/ecf-simulated-dispatch.service";
import { EcfE34CreditService } from "./documents/ecf-e34-credit.service";
import { EcfPreparationService } from "./documents/ecf-preparation.service";
import { EcfEvidenceIngestionService } from "./documents/ecf-evidence-ingestion.service";
import { EcfEvidenceAuthenticityVerifier } from "./documents/ecf-evidence.policy";
import { EcfBlockedAuthenticityVerifier } from "./documents/ecf-evidence-authenticity.service";
import { EcfAlanubeClient } from "./ecf-alanube.client";
import { EcfController } from "./ecf.controller";
import { EcfDocumentsController } from "./ecf-documents.controller";
import { EcfDgiiApplicationService } from "./dgii/ecf-dgii-application.service";
import { EcfDgiiActivationService } from "./dgii/ecf-dgii-activation.service";
import { EcfSupportGrantService } from "./dgii/ecf-support-grant.service";
import { EcfSupportGrantGuard } from "./dgii/ecf-support-grant.guard";
import { EcfDgiiDocumentStorage } from "./dgii/ecf-dgii-document.storage";
import { EcfDgiiDocumentsService } from "./dgii/ecf-dgii-documents.service";
import { EcfDgiiHabilitationService } from "./dgii/ecf-dgii-habilitation.service";
import { EcfPlatformController } from "./platform/ecf-platform.controller";
import { PlatformStaffGuard } from "./platform/platform-staff.guard";
import { EcfObservabilityService } from "./ecf-observability.service";
import { EcfProviderAuditService } from "./ecf-provider-audit.service";
import { EcfSecretReferenceService } from "./ecf-secret-reference.service";
import { EcfSecretResolverService } from "./ecf-secret-resolver.service";
import { EcfService } from "./ecf.service";

@Module({
  controllers: [EcfController, EcfDocumentsController, EcfPlatformController],
  providers: [
    EcfService,
    EcfDgiiHabilitationService,
    EcfDgiiApplicationService,
    EcfDgiiActivationService,
    EcfSupportGrantService,
    EcfSupportGrantGuard,
    EcfDgiiDocumentStorage,
    EcfDgiiDocumentsService,
    PlatformStaffGuard,
    EcfSecretReferenceService,
    {
      provide: EcfSecretResolverService,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => new EcfSecretResolverService(config),
    },
    EcfAlanubeClient,
    {
      provide: ALANUBE_HTTP_TRANSPORT,
      inject: [ConfigService],
      useFactory: createAlanubeHttpTransport,
    },
    AlanubeSafeHttpClient,
    AlanubeReconciliationService,
    EcfDocumentIdempotencyService,
    EcfDocumentQueryService,
    EcfLineClassificationService,
    EcfE34CreditService,
    EcfPreparationService,
    EcfEmissionService,
    EcfSimulatedDispatchService,
    EcfEvidenceIngestionService,
    { provide: EcfEvidenceAuthenticityVerifier, useClass: EcfBlockedAuthenticityVerifier },
    EcfProviderAuditService,
    EcfObservabilityService,
  ],
})
export class EcfModule {}

