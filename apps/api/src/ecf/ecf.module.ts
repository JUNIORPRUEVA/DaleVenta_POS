import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaService } from "../prisma/prisma.service";
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
import { EcfCertificateService } from "./dgii/certificate/ecf-certificate.service";
import { EcfCanonicalIdentityService } from "./dgii/certificate/ecf-canonical-identity.service";
import { EcfAlanubeCertificationClient } from "./alanube/certification/ecf-alanube-certification.client";
import { EcfCertificationAttemptsService } from "./dgii/certification/ecf-certification-attempts.service";
import { EcfCertificationRecoveryService } from "./dgii/certification/ecf-certification-recovery.service";
import { EcfPreparationMetadataService } from "./dgii/ecf-preparation-metadata.service";
import { EcfCertificationOrchestratorService } from "./dgii/ecf-certification-orchestrator.service";
import { EcfPlatformController } from "./platform/ecf-platform.controller";
import { PlatformStaffGuard } from "./platform/platform-staff.guard";
import { EcfObservabilityService } from "./ecf-observability.service";
import { EcfProviderAuditService } from "./ecf-provider-audit.service";
import {
  ECF_FISCAL_PROVIDER_REGISTRY,
  createEcfFiscalProviderRegistryFromConfig,
} from "./provider/ecf-provider.registry";
import { DosaWebhookReceiverService } from "./provider/dosa-webhook-receiver.service";
import {
  ECF_DOSA_SESSION_STORE,
  EcfDosaSessionService,
} from "./provider/dosa/ecf-dosa-session.service";
import { DosaWebhookController } from "./provider/dosa/dosa-webhook.controller";
import {
  ECF_DOSA_COMPANY_RESOLVER,
  ECF_DOSA_WEBHOOK_STORE,
  DosaWebhookService,
} from "./provider/dosa/dosa-webhook.service";
import { PrismaDosaCompanyResolver } from "./provider/dosa/dosa-company-resolver.service";
import {
  DosaCredentialService,
  ECF_DOSA_CREDENTIAL_STORE,
  PrismaDosaCredentialStore,
  type DosaCredentialStore,
} from "./provider/dosa/dosa-credential.service";
import { DosaCredentialVault } from "./provider/dosa/dosa-credential-vault.service";
import { PrismaDosaCompanyFiscalConfigReader } from "./provider/dosa/dosa-company-fiscal-config";
import {
  DosaEmissionService,
  ECF_DOSA_EMISSION_TRANSPORT,
  ECF_DOSA_FISCAL_CONFIG,
  type DosaCompanyFiscalConfigReader,
} from "./provider/dosa/dosa-emission.service";
import {
  createFetchDosaTransport,
  readDosaEmissionConfig,
  type DosaHttpTransport,
} from "./provider/dosa/dosa-emission.client";
import { EcfSecretReferenceService } from "./ecf-secret-reference.service";
import { EcfSecretResolverService } from "./ecf-secret-resolver.service";
import { EcfService } from "./ecf.service";

@Module({
  controllers: [EcfController, EcfDocumentsController, EcfPlatformController, DosaWebhookController],
  providers: [
    EcfService,
    EcfDgiiHabilitationService,
    EcfDgiiApplicationService,
    EcfDgiiActivationService,
    EcfSupportGrantService,
    EcfCertificateService,
    EcfCanonicalIdentityService,
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
    // Registro de proveedores fiscales (puerto EcfFiscalProvider). Es solo
    // lectura: describe qué adaptador existe y si puede emitir. Por defecto
    // todos quedan apagados, así que no habilita ninguna emisión real.
    {
      provide: ECF_FISCAL_PROVIDER_REGISTRY,
      inject: [ConfigService],
      useFactory: createEcfFiscalProviderRegistryFromConfig,
    },
    // Recepcion de eventos DOSA. NO hay controlador HTTP: el servicio rechaza
    // siempre mientras el contrato de firma no este resuelto por el proveedor,
    // y un evento nunca autoriza emision por si solo.
    DosaWebhookReceiverService,
    // Sesion de certificacion DOSA: control de duplicados TRANSACCIONAL por
    // indice unico (company_id, rnc). No pide sesiones al proveedor.
    {
      provide: ECF_DOSA_SESSION_STORE,
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) => prisma,
    },
    EcfDosaSessionService,
    // Webhook DOSA: ruta detras de bandera, fail-closed y sin autoridad fiscal.
    {
      provide: ECF_DOSA_WEBHOOK_STORE,
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) => prisma,
    },
    PrismaDosaCompanyResolver,
    {
      provide: ECF_DOSA_COMPANY_RESOLVER,
      inject: [PrismaDosaCompanyResolver],
      useFactory: (resolver: PrismaDosaCompanyResolver) => resolver,
    },
    DosaWebhookService,
    // Credenciales fiscales DOSA: cifradas (AES-256-GCM), aisladas por
    // empresa/RNC/entorno. Sin clave maestra la boveda falla cerrado y no se
    // guarda nada; nunca hay texto claro ni valor por defecto.
    {
      provide: ECF_DOSA_CREDENTIAL_STORE,
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) => new PrismaDosaCredentialStore(prisma),
    },
    {
      provide: DosaCredentialVault,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        new DosaCredentialVault(config.get<string>("DOSA_CREDENTIALS_MASTER_KEY")),
    },
    {
      provide: DosaCredentialService,
      inject: [ECF_DOSA_CREDENTIAL_STORE, DosaCredentialVault],
      useFactory: (store: DosaCredentialStore, vault: DosaCredentialVault) =>
        new DosaCredentialService(store, vault),
    },
    {
      // El webhook recibe la boveda por token: la escritura de credenciales es
      // opcional para el receptor, que sigue funcionando sin ella.
      provide: DosaWebhookService.CREDENTIALS,
      inject: [DosaCredentialService],
      useFactory: (credentials: DosaCredentialService) => credentials,
    },
    // Emision DOSA detras de compuertas. Sin `DOSA_EMISSION_ENABLED=true` el
    // cliente no hace ni una peticion.
    {
      provide: ECF_DOSA_FISCAL_CONFIG,
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) =>
        new PrismaDosaCompanyFiscalConfigReader(prisma),
    },
    {
      provide: ECF_DOSA_EMISSION_TRANSPORT,
      useFactory: () => createFetchDosaTransport(),
    },
    {
      provide: DosaEmissionService,
      inject: [
        ECF_DOSA_FISCAL_CONFIG,
        DosaCredentialService,
        ECF_DOSA_EMISSION_TRANSPORT,
      ],
      useFactory: (
        fiscalConfig: DosaCompanyFiscalConfigReader,
        credentials: DosaCredentialService,
        transport: DosaHttpTransport,
      ) =>
        new DosaEmissionService({
          fiscalConfig,
          credentials,
          config: readDosaEmissionConfig(process.env),
          transport,
        }),
    },
    EcfAlanubeCertificationClient,
    {
      // El orquestador lee solo el `alanubeCompanyId` por empresa.
      provide: "ECF_ORCHESTRATOR_PRISMA",
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) => prisma,
    },
    {
      provide: EcfCertificationAttemptsService,
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) =>
        // El cliente Prisma real cumple la forma que el servicio necesita; el
        // tipo estrecho existe para poder probar la política con un doble.
        new EcfCertificationAttemptsService(prisma as never),
    },
    EcfCertificationOrchestratorService,
    EcfPreparationMetadataService,
    {
      provide: EcfCertificationRecoveryService,
      inject: [PrismaService],
      useFactory: (prisma: PrismaService) =>
        new EcfCertificationRecoveryService(prisma as never),
    },
  ],
})
export class EcfModule {}

