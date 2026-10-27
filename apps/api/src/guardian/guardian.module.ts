import { Logger, Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { GuardianIngestController } from './guardian.ingest.controller';
import { GuardianAdminController } from './guardian.admin.controller';
import { GuardianWebhookController } from './guardian.webhook.controller';
import { GuardianPlatformController } from './guardian.platform.controller';
import { GuardianPlatformService } from './guardian.platform.service';
import { GuardianPlatformGuard } from './guardian.platform.guard';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianIncidentsService } from './guardian.incidents.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianBackendCaptureService } from './guardian.backend-capture.service';
import { GuardianToolsService } from './guardian.tools.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianRetentionService } from './guardian.retention.service';
import { GUARDIAN_AI_PROVIDER } from './ai/guardian-ai.provider';
import { MockGuardianAiProvider } from './ai/mock-guardian-ai.provider';
import { OpenAiGuardianAiProvider } from './ai/openai-guardian-ai.provider';
import { describeGuardianAiRuntime } from './guardian.config';

/**
 * Proveedor de IA según entorno: sin credenciales usa el mock determinista,
 * de modo que el circuito funciona en UAT sin inventar credenciales externas.
 *
 * Solo se acepta `GUARDIAN_AI_API_KEY`: una clave de otro producto (por ejemplo
 * `OPENAI_API_KEY` de un proyecto distinto) nunca se reutiliza sin autorización
 * explícita, porque mezclaría facturación y cuotas de dos negocios.
 */
export function createGuardianAiProvider() {
  const apiKey = String(process.env.GUARDIAN_AI_API_KEY ?? '').trim();
  const runtime = describeGuardianAiRuntime();
  const logger = new Logger('GuardianAi');
  // Se registra el adaptador efectivo (sin credenciales) para que ninguna
  // variable sugiera un proveedor que el código no está usando.
  logger.log(
    `adaptador=${runtime.adapter} host=${runtime.baseUrlHost ?? 'por defecto'} ` +
      `modelo=${runtime.model || 'por defecto'} provider_var=${runtime.providerVariable ?? 'no definida'}`,
  );
  for (const warning of runtime.warnings) logger.warn(warning);

  if (!apiKey) return new MockGuardianAiProvider();
  return new OpenAiGuardianAiProvider({
    apiKey,
    baseUrl: process.env.GUARDIAN_AI_BASE_URL,
    model: process.env.GUARDIAN_AI_MODEL,
    timeoutMs: Number(process.env.GUARDIAN_AI_TIMEOUT_MS ?? 20_000),
    maxTokens: Number(process.env.GUARDIAN_AI_MAX_TOKENS ?? 900),
    maxConcurrent: Number(process.env.GUARDIAN_AI_MAX_CONCURRENCY ?? 2),
  });
}

@Module({
  imports: [NotificationsModule],
  controllers: [
    GuardianIngestController,
    GuardianAdminController,
    GuardianWebhookController,
    GuardianPlatformController,
  ],
  providers: [
    GuardianQuotaService,
    GuardianIngestService,
    GuardianIncidentsService,
    GuardianBackendCaptureService,
    GuardianToolsService,
    GuardianDiagnosisService,
    GuardianAlertService,
    { provide: GUARDIAN_AI_PROVIDER, useFactory: createGuardianAiProvider },
    GuardianPlatformService,
    GuardianPlatformGuard,
    GuardianRetentionService,
  ],
  exports: [
    GuardianQuotaService,
    GuardianIngestService,
    GuardianIncidentsService,
    GuardianBackendCaptureService,
    GuardianToolsService,
    GuardianDiagnosisService,
    GuardianAlertService,
  ],
})
export class GuardianModule {}
