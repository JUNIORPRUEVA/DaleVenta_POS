import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  EcfAuditAction,
  EcfCertificationStatus,
  EcfEnvironment,
  EcfOnboardingStepKey,
  EcfOnboardingStepMode,
  EcfOnboardingStepStatus,
  EcfProvider,
  Prisma,
} from "@prisma/client";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import {
  ECF_ALLOWED_DOCUMENT_TYPES,
  ECF_DEFAULT_STEP_MODES,
  ECF_ONBOARDING_STEP_ORDER,
} from "./ecf.constants";
import {
  EcfEvidenceReferenceDto,
  UpdateEcfConfigDto,
  UpdateEcfOnboardingStepDto,
} from "./dto/ecf.dto";
import type { AlanubeRuntimeState } from "./ecf-alanube.client";
import { EcfSecretReferenceService } from "./ecf-secret-reference.service";

@Injectable()
export class EcfService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly secretRefs: EcfSecretReferenceService,
  ) {}

  async getConfig(user: TenantUser) {
    const companyId = requireTenant(user);
    const config = await this.ensureConfig(companyId, user.id);
    return this.toConfigResponse(config);
  }

  async updateConfig(user: TenantUser, dto: UpdateEcfConfigDto) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    const before = await this.ensureConfig(companyId, user.id);
    const data = this.buildConfigUpdate(dto, user.id);
    const config = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.ecfCompanyConfiguration.update({
        where: { companyId },
        data,
      });
      await this.writeAudit(
        tx,
        companyId,
        user.id,
        EcfAuditAction.CONFIG_UPDATED,
        "EcfCompanyConfiguration",
        updated.id,
        this.toConfigAuditSnapshot(before),
        this.toConfigAuditSnapshot(updated),
      );
      return updated;
    });
    return this.toConfigResponse(config);
  }

  async getOnboarding(user: TenantUser) {
    const companyId = requireTenant(user);
    const config = await this.ensureConfig(companyId, user.id);
    await this.ensureDefaultSteps(companyId);
    const [steps, latestAudits] = await Promise.all([
      this.prisma.ecfOnboardingStep.findMany({
        where: { companyId },
        include: { evidence: true },
      }),
      this.prisma.ecfAuditLog.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 25,
      }),
    ]);
    return {
      config: this.toConfigResponse(config),
      steps: this.sortSteps(steps).map((step) => this.toStepResponse(step)),
      latestAudits: latestAudits.map((audit) => this.toAuditResponse(audit)),
    };
  }

  async updateStep(
    user: TenantUser,
    rawStepKey: string,
    dto: UpdateEcfOnboardingStepDto,
  ) {
    const companyId = requireTenant(user);
    const stepKey = this.parseStepKey(rawStepKey);
    await this.assertCompanyExists(companyId);
    await this.ensureConfig(companyId, user.id);
    await this.ensureDefaultSteps(companyId);

    const before = await this.prisma.ecfOnboardingStep.findUnique({
      where: { companyId_stepKey: { companyId, stepKey } },
      include: { evidence: true },
    });
    if (!before) throw new NotFoundException("Etapa e-CF no encontrada");

    const updated = await this.prisma.$transaction(async (tx) => {
      const evidenceId = await this.resolveEvidence(tx, companyId, user.id, dto);
      const status = dto.status ?? before.status;
      this.assertAllowedStepUpdate(
        stepKey,
        status,
        evidenceId ?? before.evidenceId,
        dto,
      );
      const updatedStep = await tx.ecfOnboardingStep.updateMany({
        where: { id: before.id, companyId, updatedAt: before.updatedAt },
        data: {
          ...(dto.status ? { status } : {}),
          ...(dto.mode ? { mode: dto.mode } : {}),
          ...(evidenceId !== undefined ? { evidenceId } : {}),
          ...(dto.resultSummary !== undefined
            ? { resultSummary: this.cleanNullable(dto.resultSummary) }
            : {}),
          ...(dto.lastErrorCode !== undefined
            ? { lastErrorCode: this.cleanNullable(dto.lastErrorCode) }
            : {}),
          ...(dto.lastError !== undefined
            ? { lastError: this.cleanNullable(dto.lastError) }
            : {}),
          ...(dto.blockedReason !== undefined
            ? { blockedReason: this.cleanNullable(dto.blockedReason) }
            : {}),
          ...(status === EcfOnboardingStepStatus.IN_PROGRESS && !before.startedAt
            ? { startedAt: new Date() }
            : {}),
          ...(status === EcfOnboardingStepStatus.COMPLETED ||
          status === EcfOnboardingStepStatus.CONFIRMED
            ? { completedAt: before.completedAt ?? new Date() }
            : {}),
          ...(status === EcfOnboardingStepStatus.CONFIRMED
            ? { confirmedAt: before.confirmedAt ?? new Date() }
            : {}),
          updatedByUserId: user.id,
        },
      });
      if (updatedStep.count !== 1) {
        throw new ConflictException(
          "La etapa e-CF fue modificada por otra solicitud. Recarga el estado antes de continuar.",
        );
      }
      const step = await tx.ecfOnboardingStep.findUnique({
        where: { companyId_stepKey: { companyId, stepKey } },
        include: { evidence: true },
      });
      if (!step) throw new NotFoundException("Etapa e-CF no encontrada");
      await tx.ecfCompanyConfiguration.update({
        where: { companyId },
        data: {
          certificationStatus: await this.deriveCertificationStatus(
            tx,
            companyId,
          ),
          updatedByUserId: user.id,
        },
      });
      await this.writeAudit(
        tx,
        companyId,
        user.id,
        EcfAuditAction.STEP_UPDATED,
        "EcfOnboardingStep",
        step.id,
        this.toStepAuditSnapshot(before),
        this.toStepAuditSnapshot(step),
      );
      return step;
    });

    return this.toStepResponse(updated);
  }

  async listAudit(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    return this.prisma.ecfAuditLog.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take: 100,
    }).then((audits) => audits.map((audit) => this.toAuditResponse(audit)));
  }

  async getProviderStatus(user: TenantUser, runtime: AlanubeRuntimeState) {
    const companyId = requireTenant(user);
    const config = await this.ensureConfig(companyId, user.id);
    return {
      runtime,
      company: {
        companyId,
        enabled: config.enabled,
        environment: config.environment,
        certificationStatus: config.certificationStatus,
        issuance: this.toIssuanceState(config),
        secrets: {
          credentialsConfigured: Boolean(config.credentialsSecretRef),
          certificateConfigured: Boolean(config.certificateSecretRef),
          webhookConfigured: Boolean(config.webhookSecretRef),
        },
      },
    };
  }

  private buildConfigUpdate(dto: UpdateEcfConfigDto, userId: string) {
    if (dto.environment === EcfEnvironment.PRODUCTION) {
      throw new ForbiddenException(
        "Producción e-CF no está habilitada en esta fase.",
      );
    }
    if (dto.provider && dto.provider !== EcfProvider.ALANUBE) {
      throw new BadRequestException("Proveedor e-CF no soportado");
    }
    const allowedTypes = dto.allowedTypes
      ? this.normalizeAllowedTypes(dto.allowedTypes)
      : undefined;
    return {
      ...(dto.enabled !== undefined ? { enabled: dto.enabled } : {}),
      ...(dto.provider !== undefined ? { provider: dto.provider } : {}),
      ...(dto.environment !== undefined ? { environment: dto.environment } : {}),
      ...(dto.alanubeCompanyId !== undefined
        ? { alanubeCompanyId: this.cleanNullable(dto.alanubeCompanyId) }
        : {}),
      ...(dto.credentialsSecretRef !== undefined
        ? {
            credentialsSecretRef: this.secretRefs.normalizeOptionalReference(
              dto.credentialsSecretRef,
            ),
          }
        : {}),
      ...(dto.certificateSecretRef !== undefined
        ? {
            certificateSecretRef: this.secretRefs.normalizeOptionalReference(
              dto.certificateSecretRef,
            ),
          }
        : {}),
      ...(dto.webhookSecretRef !== undefined
        ? {
            webhookSecretRef: this.secretRefs.normalizeOptionalReference(
              dto.webhookSecretRef,
            ),
          }
        : {}),
      ...(allowedTypes !== undefined
        ? { allowedTypes: allowedTypes as Prisma.InputJsonValue }
        : {}),
      ...(dto.notes !== undefined ? { notes: this.cleanNullable(dto.notes) } : {}),
      updatedByUserId: userId,
    } satisfies Prisma.EcfCompanyConfigurationUpdateInput;
  }

  private normalizeAllowedTypes(values: string[]) {
    const unique = [...new Set(values.map((value) => value.trim()))];
    for (const value of unique) {
      if (!ECF_ALLOWED_DOCUMENT_TYPES.includes(value as any)) {
        throw new BadRequestException(`Tipo e-CF no soportado: ${value}`);
      }
    }
    return unique;
  }

  private async ensureConfig(companyId: string, userId?: string) {
    await this.assertCompanyExists(companyId);
    const existing = await this.prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
    });
    if (existing) return existing;
    return this.prisma.$transaction(async (tx) => {
      const config = await tx.ecfCompanyConfiguration.create({
        data: {
          companyId,
          enabled: false,
          provider: EcfProvider.ALANUBE,
          environment: EcfEnvironment.SANDBOX,
          certificationStatus: EcfCertificationStatus.NOT_STARTED,
          productionEnabled: false,
          allowedTypes: [...ECF_ALLOWED_DOCUMENT_TYPES],
          createdByUserId: userId,
          updatedByUserId: userId,
        },
      });
      await this.writeAudit(
        tx,
        companyId,
        userId ?? null,
        EcfAuditAction.CONFIG_CREATED,
        "EcfCompanyConfiguration",
        config.id,
        null,
        this.toConfigAuditSnapshot(config),
      );
      return config;
    });
  }

  private async ensureDefaultSteps(companyId: string) {
    await this.prisma.ecfOnboardingStep.createMany({
      data: ECF_ONBOARDING_STEP_ORDER.map((stepKey) => ({
        companyId,
        stepKey,
        status: EcfOnboardingStepStatus.PENDING,
        mode: ECF_DEFAULT_STEP_MODES[stepKey],
      })),
      skipDuplicates: true,
    });
  }

  private async resolveEvidence(
    tx: Prisma.TransactionClient,
    companyId: string,
    userId: string,
    dto: UpdateEcfOnboardingStepDto,
  ) {
    if (dto.evidenceId !== undefined && dto.evidence) {
      throw new BadRequestException(
        "Usa evidenceId o evidence, no ambos en la misma operación.",
      );
    }
    if (dto.evidenceId !== undefined) {
      const clean = this.cleanNullable(dto.evidenceId);
      if (!clean) return null;
      const existing = await tx.ecfEvidence.findFirst({
        where: { id: clean, companyId },
      });
      if (!existing) throw new BadRequestException("Evidencia e-CF inválida");
      return existing.id;
    }
    if (!dto.evidence) return undefined;
    const evidence = this.normalizeEvidence(dto.evidence);
    const created = await tx.ecfEvidence.create({
      data: {
        companyId,
        ...evidence,
        uploadedByUserId: userId,
      },
    });
    await tx.ecfAuditLog.create({
      data: {
        companyId,
        actorUserId: userId,
        action: EcfAuditAction.EVIDENCE_LINKED,
        targetType: "EcfEvidence",
        targetId: created.id,
        after: this.toEvidenceAuditSnapshot(created) as Prisma.InputJsonValue,
      },
    });
    return created.id;
  }

  private normalizeEvidence(dto: EcfEvidenceReferenceDto) {
    const storageRef = dto.storageRef.trim();
    if (!/^(storage|s3|r2|evidence|uat):\/\/[A-Za-z0-9._:\/@_-]{3,512}$/.test(storageRef)) {
      throw new BadRequestException(
        "La evidencia debe usar una referencia protegida, no contenido embebido.",
      );
    }
    return {
      kind: dto.kind.trim().toUpperCase(),
      storageRef,
      fileName: this.cleanNullable(dto.fileName),
      mimeType: this.cleanNullable(dto.mimeType),
      sha256: this.cleanNullable(dto.sha256)?.toLowerCase() ?? null,
      description: this.cleanNullable(dto.description),
    };
  }

  private assertAllowedStepUpdate(
    stepKey: EcfOnboardingStepKey,
    status: EcfOnboardingStepStatus,
    evidenceId: string | null | undefined,
    dto: UpdateEcfOnboardingStepDto,
  ) {
    if (
      stepKey === EcfOnboardingStepKey.PRODUCTION_ENABLEMENT &&
      status === EcfOnboardingStepStatus.CONFIRMED
    ) {
      throw new ForbiddenException(
        "La habilitación productiva no puede confirmarse en esta fase.",
      );
    }
    if (status === EcfOnboardingStepStatus.CONFIRMED && !evidenceId) {
      throw new BadRequestException(
        "Para confirmar una etapa debes vincular evidencia protegida.",
      );
    }
    // Etapa V del instructivo de Alanube: la asignación de roles solo puede
    // darse por resuelta con evidencia oficial. Marcarla a mano como COMPLETED
    // no basta, porque lo que la DGII comprueba es la delegación real en la OFV.
    if (
      stepKey === EcfOnboardingStepKey.ROLE_ASSIGNMENT &&
      (status === EcfOnboardingStepStatus.COMPLETED ||
        status === EcfOnboardingStepStatus.CONFIRMED) &&
      !evidenceId
    ) {
      throw new BadRequestException(
        "La asignación de roles exige evidencia oficial de aceptación en la Oficina Virtual.",
      );
    }
    if (
      status === EcfOnboardingStepStatus.BLOCKED &&
      !this.cleanNullable(dto.blockedReason)
    ) {
      throw new BadRequestException(
        "Una etapa bloqueada requiere una razón documentada.",
      );
    }
  }

  private async deriveCertificationStatus(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    const steps = await tx.ecfOnboardingStep.findMany({
      where: { companyId },
      select: { status: true },
    });
    if (steps.some((step) => step.status === EcfOnboardingStepStatus.BLOCKED)) {
      return EcfCertificationStatus.BLOCKED;
    }
    const activeStatuses = new Set<EcfOnboardingStepStatus>([
      EcfOnboardingStepStatus.IN_PROGRESS,
      EcfOnboardingStepStatus.COMPLETED,
      EcfOnboardingStepStatus.CONFIRMED,
      EcfOnboardingStepStatus.FAILED,
    ]);
    if (
      steps.some((step) => activeStatuses.has(step.status))
    ) {
      return EcfCertificationStatus.IN_PROGRESS;
    }
    return EcfCertificationStatus.NOT_STARTED;
  }

  private parseStepKey(value: string) {
    const normalized = value.trim().toUpperCase();
    if (!ECF_ONBOARDING_STEP_ORDER.includes(normalized as EcfOnboardingStepKey)) {
      throw new BadRequestException("Etapa de habilitación e-CF inválida");
    }
    return normalized as EcfOnboardingStepKey;
  }

  private async assertCompanyExists(companyId: string) {
    const exists = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });
    if (!exists) throw new NotFoundException("Empresa no encontrada");
  }

  private sortSteps<T extends { stepKey: EcfOnboardingStepKey }>(steps: T[]) {
    const order = new Map(
      ECF_ONBOARDING_STEP_ORDER.map((stepKey, index) => [stepKey, index]),
    );
    return [...steps].sort(
      (a, b) => (order.get(a.stepKey) ?? 999) - (order.get(b.stepKey) ?? 999),
    );
  }

  private toConfigResponse(config: {
    id: string;
    companyId: string;
    enabled: boolean;
    provider: EcfProvider;
    environment: EcfEnvironment;
    certificationStatus: EcfCertificationStatus;
    productionEnabled: boolean;
    alanubeCompanyId: string | null;
    credentialsSecretRef: string | null;
    certificateSecretRef: string | null;
    webhookSecretRef: string | null;
    allowedTypes: Prisma.JsonValue | null;
    notes: string | null;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: config.id,
      companyId: config.companyId,
      enabled: config.enabled,
      provider: config.provider,
      environment: config.environment,
      certificationStatus: config.certificationStatus,
      productionEnabled: config.productionEnabled,
      issuance: this.toIssuanceState(config),
      alanubeCompanyId: config.alanubeCompanyId,
      allowedTypes: config.allowedTypes ?? [...ECF_ALLOWED_DOCUMENT_TYPES],
      notes: config.notes,
      secrets: {
        credentialsConfigured: Boolean(config.credentialsSecretRef),
        certificateConfigured: Boolean(config.certificateSecretRef),
        webhookConfigured: Boolean(config.webhookSecretRef),
      },
      createdAt: config.createdAt,
      updatedAt: config.updatedAt,
    };
  }

  private toStepResponse(step: {
    id: string;
    stepKey: EcfOnboardingStepKey;
    status: EcfOnboardingStepStatus;
    mode: EcfOnboardingStepMode;
    evidenceId: string | null;
    resultSummary: string | null;
    lastErrorCode: string | null;
    lastError: string | null;
    blockedReason: string | null;
    startedAt: Date | null;
    completedAt: Date | null;
    confirmedAt: Date | null;
    createdAt: Date;
    updatedAt: Date;
    evidence?: { id: string; kind: string; storageRef: string } | null;
  }) {
    return {
      id: step.id,
      stepKey: step.stepKey,
      status: step.status,
      mode: step.mode,
      evidenceId: step.evidenceId,
      evidence: step.evidence
        ? {
            id: step.evidence.id,
            kind: step.evidence.kind,
          }
        : null,
      resultSummary: step.resultSummary,
      lastErrorCode: step.lastErrorCode,
      lastError: step.lastError,
      blockedReason: step.blockedReason,
      startedAt: step.startedAt,
      completedAt: step.completedAt,
      confirmedAt: step.confirmedAt,
      createdAt: step.createdAt,
      updatedAt: step.updatedAt,
    };
  }

  private toIssuanceState(config: {
    enabled: boolean;
    environment: EcfEnvironment;
    certificationStatus: EcfCertificationStatus;
    productionEnabled: boolean;
    credentialsSecretRef: string | null;
    certificateSecretRef: string | null;
  }) {
    const providerConfigured = Boolean(
      config.enabled &&
        config.environment === EcfEnvironment.SANDBOX &&
        config.credentialsSecretRef &&
        config.certificateSecretRef,
    );
    const sandboxAuthorized =
      config.certificationStatus === EcfCertificationStatus.AUTHORIZED_SANDBOX;
    const productionAuthorized =
      config.productionEnabled &&
      config.certificationStatus === EcfCertificationStatus.PRODUCTION_READY;
    return {
      configurationEnabled: config.enabled,
      providerIntegrationReady: providerConfigured,
      sandboxCertificationAuthorized: sandboxAuthorized,
      productionAuthorized,
      productionEmissionEnabled: false,
      canEmit: false,
      blockedReason:
        "La emisión e-CF no está implementada ni habilitada en esta fase.",
    };
  }

  private toConfigAuditSnapshot(config: unknown) {
    const row = config as {
      enabled?: boolean;
      provider?: EcfProvider;
      environment?: EcfEnvironment;
      certificationStatus?: EcfCertificationStatus;
      productionEnabled?: boolean;
      alanubeCompanyId?: string | null;
      allowedTypes?: Prisma.JsonValue | null;
      notes?: string | null;
      credentialsSecretRef?: string | null;
      certificateSecretRef?: string | null;
      webhookSecretRef?: string | null;
    } | null;
    if (!row) return null;
    return {
      enabled: row.enabled,
      provider: row.provider,
      environment: row.environment,
      certificationStatus: row.certificationStatus,
      productionEnabled: row.productionEnabled,
      alanubeCompanyId: row.alanubeCompanyId,
      allowedTypes: row.allowedTypes,
      notes: row.notes,
      secrets: {
        credentialsConfigured: Boolean(row.credentialsSecretRef),
        certificateConfigured: Boolean(row.certificateSecretRef),
        webhookConfigured: Boolean(row.webhookSecretRef),
      },
    };
  }

  private toStepAuditSnapshot(step: unknown) {
    const row = step as {
      stepKey?: EcfOnboardingStepKey;
      status?: EcfOnboardingStepStatus;
      mode?: EcfOnboardingStepMode;
      evidenceId?: string | null;
      resultSummary?: string | null;
      lastErrorCode?: string | null;
      lastError?: string | null;
      blockedReason?: string | null;
    } | null;
    if (!row) return null;
    return {
      stepKey: row.stepKey,
      status: row.status,
      mode: row.mode,
      evidenceId: row.evidenceId,
      resultSummary: row.resultSummary,
      lastErrorCode: row.lastErrorCode,
      lastError: row.lastError,
      blockedReason: row.blockedReason,
    };
  }

  private toEvidenceAuditSnapshot(evidence: unknown) {
    const row = evidence as {
      id?: string;
      kind?: string;
      fileName?: string | null;
      mimeType?: string | null;
      sha256?: string | null;
    };
    return {
      id: row.id,
      kind: row.kind,
      fileName: row.fileName,
      mimeType: row.mimeType,
      sha256: row.sha256,
    };
  }

  private toAuditResponse(audit: {
    id: string;
    companyId: string;
    actorUserId: string | null;
    action: EcfAuditAction;
    targetType: string | null;
    targetId: string | null;
    before: Prisma.JsonValue | null;
    after: Prisma.JsonValue | null;
    metadata: Prisma.JsonValue | null;
    createdAt: Date;
  }) {
    return {
      id: audit.id,
      companyId: audit.companyId,
      actorUserId: audit.actorUserId,
      action: audit.action,
      targetType: audit.targetType,
      targetId: audit.targetId,
      before: this.redactSensitiveJson(audit.before),
      after: this.redactSensitiveJson(audit.after),
      metadata: this.redactSensitiveJson(audit.metadata),
      createdAt: audit.createdAt,
    };
  }

  private redactSensitiveJson(value: Prisma.JsonValue | null): Prisma.JsonValue | null {
    if (value === null) return null;
    if (Array.isArray(value)) {
      return value.map((item) => this.redactSensitiveJson(item)) as Prisma.JsonArray;
    }
    if (typeof value === "object") {
      const output: Prisma.JsonObject = {};
      for (const [key, item] of Object.entries(value)) {
        if (this.isSensitiveResponseKey(key)) continue;
        if (item === undefined) continue;
        output[key] = this.redactSensitiveJson(item) as Prisma.JsonValue;
      }
      return output;
    }
    return value;
  }

  private isSensitiveResponseKey(key: string) {
    const normalized = key.toLowerCase();
    return (
      normalized === "storageref" ||
      normalized.endsWith("secretref") ||
      normalized.includes("secret") ||
      normalized.includes("token") ||
      normalized.includes("password")
    );
  }

  private async writeAudit(
    tx: Prisma.TransactionClient,
    companyId: string,
    actorUserId: string | null,
    action: EcfAuditAction,
    targetType: string,
    targetId: string,
    before: unknown,
    after: unknown,
  ) {
    await tx.ecfAuditLog.create({
      data: {
        companyId,
        actorUserId,
        action,
        targetType,
        targetId,
        before: before as Prisma.InputJsonValue,
        after: after as Prisma.InputJsonValue,
      },
    });
  }

  private cleanNullable(value: string | null | undefined) {
    if (value === undefined) return undefined;
    const clean = `${value ?? ""}`.trim();
    return clean.length > 0 ? clean : null;
  }
}

