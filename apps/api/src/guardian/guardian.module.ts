import { Logger, Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { GuardianIngestController } from './guardian.ingest.controller';
import { GuardianEnrollmentController } from './guardian.enrollment.controller';
import { GuardianEnrollmentService } from './guardian.enrollment.service';
import { GuardianMachineController } from './guardian.machine.controller';
import { GuardianMachineGuard } from './guardian.machine.guard';
import { GuardianMachineService } from './guardian.machine.service';
import { GuardianTelemetryBridgeService } from './telemetry/guardian.telemetry.bridge.service';
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
import { guardianSecretValue } from './guardian.secret';
import { GUARDIAN_AI_PROVIDER } from './ai/guardian-ai.provider';
import { MockGuardianAiProvider } from './ai/mock-guardian-ai.provider';
import { OpenAiGuardianAiProvider } from './ai/openai-guardian-ai.provider';
import { describeGuardianAiRuntime, resolveGuardianAiRuntime } from './ai/guardian.ai.runtime';

/**
 * Proveedor de IA según entorno.
 *
 * La selección la resuelve `resolveGuardianAiRuntime`, que SÍ honra
 * `GUARDIAN_AI_PROVIDER` (`deepseek` | `openai` | `mock`). Sin credencial, con
 * un modelo no admitido o con una base URL incoherente, el adaptador es el mock
 * determinista: nunca se envía una clave a un host que no corresponde.
 *
 * Solo se acepta `GUARDIAN_AI_API_KEY`: una clave de otro producto (por ejemplo
 * `OPENAI_API_KEY` de un proyecto distinto) nunca se reutiliza sin autorización
 * explícita, porque mezclaría facturación y cuotas de dos negocios.
 */
export function createGuardianAiProvider() {
  const runtime = resolveGuardianAiRuntime();
  const logger = new Logger('GuardianAi');
  // Se registra el adaptador efectivo (nunca la credencial) para que ninguna
  // variable sugiera un proveedor que el código no está usando.
  logger.log(describeGuardianAiRuntime(runtime));
  for (const warning of runtime.warnings) logger.warn(warning);

  if (runtime.adapter === 'mock') return new MockGuardianAiProvider();

  return new OpenAiGuardianAiProvider({
    apiKey: guardianSecretValue(process.env, 'GUARDIAN_AI_API_KEY'),
    baseUrl: runtime.baseUrl ?? undefined,
    model: runtime.model,
    timeoutMs: runtime.timeoutMs,
    maxTokens: runtime.maxTokens,
    maxConcurrent: runtime.maxConcurrent,
    adapter: runtime.adapter,
  });
}

@Module({
  imports: [NotificationsModule],
  controllers: [
    GuardianIngestController,
    GuardianEnrollmentController,
    GuardianMachineController,
    GuardianAdminController,
    GuardianWebhookController,
    GuardianPlatformController,
  ],
  providers: [
    GuardianQuotaService,
    GuardianIngestService,
    GuardianEnrollmentService,
    GuardianMachineService,
    GuardianMachineGuard,
    GuardianTelemetryBridgeService,
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
