import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { correctionReasonRefusal } from "./ecf-dgii-correction.policy";
import { ConfigService } from "@nestjs/config";
import {
  EcfAuditAction,
  EcfDgiiHabilitationState,
  EcfDgiiVerificationSource,
  EcfEvidenceReviewStatus,
  EcfEvidenceSource,
  Prisma,
} from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import {
  ECF_DGII_REQUIREMENT_CATALOG,
  buildRequirementProgress,
  evaluateEcfEmissionGate,
  evidenceGrantsOfficialAuthorization,
  evidenceLevel,
  evidenceQualityRefusal,
  evidenceReviewRefusal,
  hasOfficialAuthorization,
  authorizationRefusal,
  customerStateRefusal,
  stateUpdateRefusal,
  type EcfEmissionGateBlocker,
} from "./ecf-dgii-habilitation.policy";
import type {
  RecordEcfDgiiAuthorizationDto,
  RegisterEcfDgiiEvidenceDto,
  ReviewEcfDgiiEvidenceDto,
  UpdateEcfDgiiHabilitationDto,
  UpdateEcfDgiiRequirementDto,
} from "../dto/ecf-dgii.dto";

/**
 * Seguimiento interno de UN requisito del catálogo.
 *
 * Es información de gestión —quién lo lleva, para cuándo— y nunca sustituye al
 * progreso real, que se deriva de `EcfOnboardingStep`.
 */
export interface EcfDgiiRequirementTracking {
  status: string;
  note: string | null;
  responsibleUserId: string | null;
  dueDate: string | null;
  updatedAt: string;
  updatedByUserId: string | null;
}

/**
 * Habilitación DGII POR EMPRESA.
 *
 * Registra el SEGUIMIENTO del proceso de incorporación a la facturación
 * electrónica. Dos invariantes gobiernan todo el servicio:
 *
 *  1. Aislamiento multiempresa: cada consulta y cada escritura está acotada al
 *     `companyId` del contexto autenticado (`requireTenant`). No existe ninguna
 *     lectura cross-tenant, ni siquiera para informes.
 *  2. Una acción administrativa NUNCA concede autorización oficial. `APPROVED`
 *     solo es alcanzable con un registro oficial verificado y con evidencia
 *     documental referenciada; y aun así la emisión real permanece bloqueada
 *     porque no está implementada.
 */
@Injectable()
export class EcfDgiiHabilitationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** Vista agregada de la habilitación de la empresa del contexto. */
  async getHabilitation(user: TenantUser) {
    const companyId = requireTenant(user);
    const record = await this.ensureRecord(companyId, user.id);
    const [steps, config, company, appConfig, evidence] = await Promise.all([
      this.prisma.ecfOnboardingStep.findMany({
        where: { companyId },
        select: { stepKey: true, status: true },
      }),
      this.prisma.ecfCompanyConfiguration.findUnique({ where: { companyId } }),
      this.prisma.company.findUnique({
        where: { id: companyId },
        select: { licenseStatus: true, licenseExpiresAt: true },
      }),
      // El RNC de la empresa vive en la configuración de la aplicación, que es
      // la fuente real que ya usa la emisión (`appConfig.rnc`).
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: { rnc: true },
      }),
      this.prisma.ecfEvidence.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 100,
      }),
    ]);

    return this.toView(record, steps, config, company, appConfig, evidence);
  }

  /** Historial de cambios de habilitación (solo de esta empresa). */
  async listHistory(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    const rows = await this.prisma.ecfAuditLog.findMany({
      where: {
        companyId,
        action: {
          in: [
            EcfAuditAction.DGII_HABILITATION_UPDATED,
            EcfAuditAction.DGII_EVIDENCE_REGISTERED,
            // La revisión interna debe ser VISIBLE para la empresa: si solo
            // quedara en la tabla de auditoría, el hecho sería indetectable.
            EcfAuditAction.DGII_EVIDENCE_REVIEWED,
            EcfAuditAction.DGII_AUTHORIZATION_RECORDED,
            EcfAuditAction.DGII_AUTHORIZATION_REVOKED,
            // Expediente: guardado del borrador, consentimiento aceptado y
            // envío de una versión. Sin estas tres, el cliente no vería en su
            // historial ni el consentimiento que firmó ni la versión enviada.
            EcfAuditAction.DGII_APPLICATION_DRAFT_SAVED,
            EcfAuditAction.DGII_CONSENT_ACCEPTED,
            EcfAuditAction.DGII_APPLICATION_SUBMITTED,
          ],
        },
      },
      orderBy: { createdAt: "desc" },
      take: 200,
    });
    return rows.map((row) => ({
      id: row.id,
      action: row.action,
      actorUserId: row.actorUserId,
      targetType: row.targetType,
      targetId: row.targetId,
      before: this.redact(row.before),
      after: this.redact(row.after),
      createdAt: row.createdAt,
    }));
  }

  /** Evidencias documentales registradas por esta empresa. */
  async listEvidence(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    const rows = await this.prisma.ecfEvidence.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take: 200,
    });
    return rows.map((row) => this.toEvidenceView(row));
  }

  /** Registra una evidencia. Distingue explícitamente su procedencia. */
  async registerEvidence(
    user: TenantUser,
    dto: RegisterEcfDgiiEvidenceDto,
  ) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    await this.ensureRecord(companyId, user.id);

    const evidence = await this.prisma.$transaction(async (tx) => {
      const created = await tx.ecfEvidence.create({
        data: {
          companyId,
          source: dto.source as EcfEvidenceSource,
          kind: dto.kind.trim(),
          storageRef: dto.storageRef.trim(),
          fileName: this.cleanNullable(dto.fileName),
          mimeType: this.cleanNullable(dto.mimeType),
          sha256: this.cleanNullable(dto.sha256),
          description: this.cleanNullable(dto.description),
          uploadedByUserId: user.id,
        },
      });
      await this.writeAudit(
        tx,
        companyId,
        user.id,
        EcfAuditAction.DGII_EVIDENCE_REGISTERED,
        "EcfEvidence",
        created.id,
        null,
        { source: created.source, kind: created.kind },
      );
      // Registrar evidencia no mueve el estado de habilitación por sí solo:
      // la evidencia es un soporte, no una aprobación.
      await tx.ecfDgiiHabilitation.update({
        where: { companyId },
        data: { updatedByUserId: user.id },
      });
      return created;
    });

    return this.toEvidenceView(evidence);
  }

  /**
   * Revisa INTERNAMENTE una evidencia.
   *
   * Es una decisión de producto: marcar una evidencia como revisada la vuelve
   * apta para sustentar un registro oficial, pero **no** autoriza nada. Solo el
   * registro con fuente oficial lo hace.
   */
  async reviewEvidence(
    user: TenantUser,
    evidenceId: string,
    dto: ReviewEcfDgiiEvidenceDto,
  ) {
    const companyId = requireTenant(user);
    const updated = await this.applyEvidenceReview(
      companyId,
      user.id,
      evidenceId,
      dto,
    );
    return this.toEvidenceView(updated);
  }

  /**
   * Revisión de evidencia con EMPRESA EXPLÍCITA (panel de plataforma).
   *
   * Aplica la misma política y la misma auditoría; solo cambia el origen del
   * `companyId`. Sigue exigiendo motivo para rechazar y sigue sin autorizar
   * nada: revisar una evidencia no la convierte en registro oficial.
   */
  async reviewEvidenceForCompany(input: {
    companyId: string;
    actorUserId: string;
    evidenceId: string;
    dto: ReviewEcfDgiiEvidenceDto;
  }) {
    const updated = await this.applyEvidenceReview(
      input.companyId,
      input.actorUserId,
      input.evidenceId,
      input.dto,
    );
    return this.toEvidenceView(updated);
  }

  /** Escritura única de la revisión de evidencia. */
  private async applyEvidenceReview(
    companyId: string,
    actorUserId: string,
    evidenceId: string,
    dto: ReviewEcfDgiiEvidenceDto,
  ) {
    await this.assertCompanyExists(companyId);

    const evidence = await this.prisma.ecfEvidence.findFirst({
      where: { id: evidenceId, companyId },
      select: {
        id: true,
        source: true,
        reviewStatus: true,
        reviewedByUserId: true,
      },
    });
    if (!evidence) throw new NotFoundException("Evidencia e-CF no encontrada");

    const refusal = evidenceReviewRefusal({
      decision: dto.decision,
      note: dto.note ?? null,
      currentStatus: evidence.reviewStatus,
      reviewedBySameUser: evidence.reviewedByUserId === actorUserId,
    });
    if (refusal) throw new BadRequestException(refusal);

    return this.prisma.$transaction(async (tx) => {
      const changed = await tx.ecfEvidence.updateMany({
        where: { id: evidence.id, companyId },
        data: {
          reviewStatus: dto.decision as EcfEvidenceReviewStatus,
          reviewedByUserId: actorUserId,
          reviewedAt: new Date(),
          reviewNote: this.cleanNullable(dto.note),
        },
      });
      if (changed.count !== 1) {
        throw new ConflictException(
          "La evidencia fue modificada por otra solicitud. Recarga el estado antes de continuar.",
        );
      }
      const after = await tx.ecfEvidence.findUniqueOrThrow({
        where: { id: evidence.id },
      });
      await this.writeAudit(
        tx,
        companyId,
        actorUserId,
        EcfAuditAction.DGII_EVIDENCE_REVIEWED,
        "EcfEvidence",
        after.id,
        { reviewStatus: evidence.reviewStatus },
        { reviewStatus: after.reviewStatus, note: after.reviewNote },
      );
      return after;
    });
  }

  /**
   * Actualiza el seguimiento de UN requisito del catálogo.
   *
   * No crea requisitos nuevos: el catálogo es cerrado y vive en la política. Solo
   * registra estado, responsable, fecha y observaciones de un requisito existente.
   */
  async updateRequirement(
    user: TenantUser,
    key: string,
    dto: UpdateEcfDgiiRequirementDto,
  ) {
    const companyId = requireTenant(user);
    await this.applyRequirementUpdate(companyId, user.id, key, dto);
    return this.getHabilitation(user);
  }

  /**
   * Revisión de un requisito con EMPRESA EXPLÍCITA (panel de plataforma).
   *
   * Reutiliza el mismo camino de escritura y la misma auditoría que la vía de la
   * empresa. Devuelve el seguimiento resultante, no la vista completa de la
   * empresa: el panel no necesita el payload del cliente.
   */
  async updateRequirementForCompany(input: {
    companyId: string;
    actorUserId: string;
    key: string;
    dto: UpdateEcfDgiiRequirementDto;
  }) {
    const tracking = await this.applyRequirementUpdate(
      input.companyId,
      input.actorUserId,
      input.key,
      input.dto,
    );
    return { companyId: input.companyId, key: input.key, tracking };
  }

  /**
   * Catálogo de requisitos con el seguimiento de ESTA empresa.
   *
   * El catálogo es cerrado y vive en la política; aquí solo se le añade el
   * seguimiento registrado, normalizado. Un requisito sin seguimiento devuelve
   * `null`, nunca un estado inventado.
   */
  async requirementsForCompany(companyId: string) {
    await this.assertCompanyExists(companyId);
    const record = await this.prisma.ecfDgiiHabilitation.findUnique({
      where: { companyId },
      select: { requirements: true },
    });
    const tracking = this.readRequirementTracking(
      record?.requirements ?? null,
    );
    return ECF_DGII_REQUIREMENT_CATALOG.map((requirement) => ({
      key: requirement.key,
      label: requirement.label,
      mandatory: requirement.mandatory,
      automatable: requirement.automatable,
      tracking: this.toTrackingView(tracking[requirement.key]),
    }));
  }

  /** Escritura única del seguimiento de un requisito. */
  private async applyRequirementUpdate(
    companyId: string,
    actorUserId: string,
    key: string,
    dto: UpdateEcfDgiiRequirementDto,
  ) {
    await this.assertCompanyExists(companyId);
    const known = ECF_DGII_REQUIREMENT_CATALOG.some(
      (requirement) => requirement.key === key,
    );
    if (!known) throw new NotFoundException("Requisito de habilitación no encontrado");

    const record = await this.ensureRecord(companyId, actorUserId);
    const current = this.readRequirementTracking(record.requirements);
    const next = {
      ...current,
      [key]: {
        status: dto.status,
        note: this.cleanNullable(dto.note) ?? null,
        responsibleUserId: this.cleanNullable(dto.responsibleUserId) ?? null,
        dueDate: this.cleanNullable(dto.dueDate) ?? null,
        updatedAt: new Date().toISOString(),
        updatedByUserId: actorUserId,
      },
    };

    await this.prisma.$transaction(async (tx) => {
      const changed = await tx.ecfDgiiHabilitation.updateMany({
        where: { id: record.id, companyId, updatedAt: record.updatedAt },
        data: {
          requirements: next as Prisma.InputJsonValue,
          ...(record.startedAt === null ? { startedAt: new Date() } : {}),
          updatedByUserId: actorUserId,
        },
      });
      if (changed.count !== 1) {
        throw new ConflictException(
          "La habilitación DGII fue modificada por otra solicitud. Recarga el estado antes de continuar.",
        );
      }
      await this.writeAudit(
        tx,
        companyId,
        actorUserId,
        EcfAuditAction.DGII_HABILITATION_UPDATED,
        "EcfDgiiHabilitation",
        record.id,
        { requirement: key, before: (current[key] ?? null) as Prisma.InputJsonValue },
        { requirement: key, after: next[key] as Prisma.InputJsonValue },
      );
    });

    return this.toTrackingView(next[key]);
  }

  /** Lee el JSON de seguimiento por requisito de forma tolerante. */
  private readRequirementTracking(
    value: Prisma.JsonValue | null,
  ): Record<string, unknown> {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return {};
    }
    return value as Record<string, unknown>;
  }

  /**
   * Normaliza el seguimiento de UN requisito a un contrato tipado.
   *
   * El contenido vive en un `Json`, así que se trata como dato no confiable:
   * si falta el mínimo (`status` y `updatedAt`), la vista devuelve `null` en vez
   * de propagar una forma ambigua al cliente.
   */
  private toTrackingView(value: unknown): EcfDgiiRequirementTracking | null {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    const row = value as Record<string, unknown>;
    const status = typeof row.status === "string" ? row.status : null;
    const updatedAt = typeof row.updatedAt === "string" ? row.updatedAt : null;
    if (status === null || updatedAt === null) return null;

    return {
      status,
      note: typeof row.note === "string" ? row.note : null,
      responsibleUserId:
        typeof row.responsibleUserId === "string" ? row.responsibleUserId : null,
      dueDate: typeof row.dueDate === "string" ? row.dueDate : null,
      updatedAt,
      updatedByUserId:
        typeof row.updatedByUserId === "string" ? row.updatedByUserId : null,
    };
  }

  /** Actualiza el seguimiento interno (estado, revisión, observaciones). */
  async updateHabilitation(
    user: TenantUser,
    dto: UpdateEcfDgiiHabilitationDto,
  ) {
    const companyId = requireTenant(user);
    // Propiedad del estado: la empresa solo declara lo que le corresponde.
    // Aceptar `IN_CERTIFICATION` o `APPROVED` desde aquí presentaría como hecho
    // un estado que únicamente la DGII o el proveedor pueden producir.
    if (dto.state) {
      const refusal = customerStateRefusal(dto.state);
      if (refusal) throw new ForbiddenException(refusal);
    }
    const updated = await this.applyHabilitationUpdate(
      companyId,
      user.id,
      dto,
    );

    return this.getHabilitation(user).then((view) => ({
      ...view,
      state: updated.state,
    }));
  }

  /**
   * Actualización de habilitación con EMPRESA EXPLÍCITA (panel de plataforma).
   *
   * Existe para que la revisión interna de Fulltech no duplique reglas: aplica
   * exactamente la misma política (`stateUpdateRefusal`, `correctionReasonRefusal`)
   * y la misma auditoría que la vía de la empresa. Lo único que cambia es de dónde
   * sale el `companyId`, que aquí es un parámetro y no el del contexto autenticado.
   *
   * No puede aprobar: `APPROVED` sigue exigiendo autorización oficial verificada.
   */
  async updateHabilitationForCompany(input: {
    companyId: string;
    actorUserId: string;
    dto: UpdateEcfDgiiHabilitationDto;
  }) {
    const updated = await this.applyHabilitationUpdate(
      input.companyId,
      input.actorUserId,
      input.dto,
    );
    return {
      companyId: updated.companyId,
      state: updated.state,
      reviewState: updated.reviewState,
      observations: updated.observations,
      startedAt: updated.startedAt,
      authorizedAt: updated.authorizedAt,
      authorizationSource: updated.authorizationSource,
      updatedAt: updated.updatedAt,
    };
  }

  /**
   * Escritura única de la habilitación.
   *
   * Recibe la empresa ya resuelta para que exista UN solo camino de escritura,
   * con las mismas validaciones y la misma auditoría, tanto si actúa la empresa
   * como si actúa el personal de plataforma.
   */
  private async applyHabilitationUpdate(
    companyId: string,
    actorUserId: string,
    dto: UpdateEcfDgiiHabilitationDto,
  ) {
    await this.assertCompanyExists(companyId);
    const before = await this.ensureRecord(companyId, actorUserId);

    if (dto.state !== undefined) {
      const refusal = stateUpdateRefusal(
        before.state,
        dto.state,
        hasOfficialAuthorization(before),
      );
      if (refusal) throw new ConflictException(refusal);
    }

    // Una corrección o un rechazo sin motivo deja al cliente sin saber qué
    // corregir y no es auditable. Se acepta el motivo nuevo o el ya registrado.
    const reasonRefusal = correctionReasonRefusal({
      nextState: dto.state ?? null,
      incomingReason: dto.observations ?? null,
      existingReason: before.observations ?? null,
    });
    if (reasonRefusal) throw new BadRequestException(reasonRefusal);

    return this.prisma.$transaction(async (tx) => {
      const result = await tx.ecfDgiiHabilitation.updateMany({
        where: { id: before.id, companyId, updatedAt: before.updatedAt },
        data: {
          ...(dto.state !== undefined ? { state: dto.state } : {}),
          ...(dto.reviewState !== undefined
            ? { reviewState: this.cleanNullable(dto.reviewState) }
            : {}),
          ...(dto.observations !== undefined
            ? { observations: this.cleanNullable(dto.observations) }
            : {}),
          ...(dto.responsibleUserId !== undefined
            ? { responsibleUserId: this.cleanNullable(dto.responsibleUserId) }
            : {}),
          ...(dto.state !== undefined && before.startedAt === null
            ? { startedAt: new Date() }
            : {}),
          updatedByUserId: actorUserId,
        },
      });
      if (result.count !== 1) {
        throw new ConflictException(
          "La habilitación DGII fue modificada por otra solicitud. Recarga el estado antes de continuar.",
        );
      }
      const after = await tx.ecfDgiiHabilitation.findUniqueOrThrow({
        where: { companyId },
      });
      await this.writeAudit(
        tx,
        companyId,
        actorUserId,
        EcfAuditAction.DGII_HABILITATION_UPDATED,
        "EcfDgiiHabilitation",
        after.id,
        this.toAuditSnapshot(before),
        this.toAuditSnapshot(after),
      );
      return after;
    });
  }

  /**
   * Registra la autorización declarada.
   *
   * Solo una fuente oficial produce autorización efectiva (`authorizedAt`,
   * estado `APPROVED`). Una declaración manual o del proveedor se guarda como
   * metadato y **nunca** habilita nada: es exactamente la diferencia entre un
   * registro interno y una resolución oficial.
   */
  async recordAuthorization(
    user: TenantUser,
    dto: RecordEcfDgiiAuthorizationDto,
  ) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    const before = await this.ensureRecord(companyId, user.id);

    const refusal = authorizationRefusal({
      source: dto.source,
      evidenceId: dto.evidenceId ?? null,
      externalId: dto.externalId ?? null,
    });
    if (refusal) throw new BadRequestException(refusal);

    // La evidencia debe pertenecer a ESTA empresa: nunca se referencia evidencia ajena.
    let linkedEvidence: {
      source: EcfEvidenceSource;
      reviewStatus: EcfEvidenceReviewStatus;
    } | null = null;
    if (dto.evidenceId) {
      linkedEvidence = await this.prisma.ecfEvidence.findFirst({
        where: { id: dto.evidenceId, companyId },
        select: { source: true, reviewStatus: true },
      });
      if (!linkedEvidence) throw new NotFoundException("Evidencia e-CF no encontrada");
      // Una declaración manual —o un documento sin revisar— no puede sustentar
      // una autorización oficial, aunque la fuente declarada sea la oficial.
      if (dto.source === EcfDgiiVerificationSource.DGII_OFFICIAL_RECORD) {
        const quality = evidenceQualityRefusal(linkedEvidence);
        if (quality) throw new BadRequestException(quality);
      }
    }

    const isOfficial = dto.source === EcfDgiiVerificationSource.DGII_OFFICIAL_RECORD;

    const updated = await this.prisma.$transaction(async (tx) => {
      const result = await tx.ecfDgiiHabilitation.updateMany({
        where: { id: before.id, companyId, updatedAt: before.updatedAt },
        data: {
          authorizationSource: dto.source as EcfDgiiVerificationSource,
          authorizationEvidenceId: this.cleanNullable(dto.evidenceId),
          externalId: this.cleanNullable(dto.externalId),
          authorizedAt: isOfficial ? new Date() : null,
          ...(isOfficial ? { state: EcfDgiiHabilitationState.APPROVED } : {}),
          ...(before.startedAt === null ? { startedAt: new Date() } : {}),
          updatedByUserId: user.id,
        },
      });
      if (result.count !== 1) {
        throw new ConflictException(
          "La habilitación DGII fue modificada por otra solicitud. Recarga el estado antes de continuar.",
        );
      }
      const after = await tx.ecfDgiiHabilitation.findUniqueOrThrow({
        where: { companyId },
      });
      await this.writeAudit(
        tx,
        companyId,
        user.id,
        EcfAuditAction.DGII_AUTHORIZATION_RECORDED,
        "EcfDgiiHabilitation",
        after.id,
        this.toAuditSnapshot(before),
        this.toAuditSnapshot(after),
      );
      return after;
    });

    return { ...(await this.getHabilitation(user)), state: updated.state };
  }

  /** Revoca una autorización registrada. La empresa vuelve a revisión. */
  async revokeAuthorization(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);
    const before = await this.ensureRecord(companyId, user.id);

    const updated = await this.prisma.$transaction(async (tx) => {
      const result = await tx.ecfDgiiHabilitation.updateMany({
        where: { id: before.id, companyId, updatedAt: before.updatedAt },
        data: {
          authorizationSource: EcfDgiiVerificationSource.NONE,
          authorizationEvidenceId: null,
          authorizedAt: null,
          state: EcfDgiiHabilitationState.REQUIRES_CORRECTION,
          updatedByUserId: user.id,
        },
      });
      if (result.count !== 1) {
        throw new ConflictException(
          "La habilitación DGII fue modificada por otra solicitud. Recarga el estado antes de continuar.",
        );
      }
      const after = await tx.ecfDgiiHabilitation.findUniqueOrThrow({
        where: { companyId },
      });
      await this.writeAudit(
        tx,
        companyId,
        user.id,
        EcfAuditAction.DGII_AUTHORIZATION_REVOKED,
        "EcfDgiiHabilitation",
        after.id,
        this.toAuditSnapshot(before),
        this.toAuditSnapshot(after),
      );
      return after;
    });

    return { ...(await this.getHabilitation(user)), state: updated.state };
  }

  // -------------------------------------------------------------------------
  // Interno
  // -------------------------------------------------------------------------

  private async ensureRecord(companyId: string, userId: string) {
    const existing = await this.prisma.ecfDgiiHabilitation.findUnique({
      where: { companyId },
    });
    if (existing) return existing;
    return this.prisma.ecfDgiiHabilitation.create({
      data: { companyId, createdByUserId: userId, updatedByUserId: userId },
    });
  }

  private async assertCompanyExists(companyId: string) {
    const exists = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });
    if (!exists) throw new NotFoundException("Empresa no encontrada");
  }

  private environment() {
    return (
      this.config.get<string>("APP_ENV") ??
      process.env.APP_ENV ??
      ""
    ).trim();
  }

  private toView(
    record: {
      companyId: string;
      state: EcfDgiiHabilitationState;
      reviewState: string | null;
      observations: string | null;
      responsibleUserId: string | null;
      externalId: string | null;
      startedAt: Date | null;
      authorizedAt: Date | null;
      authorizationSource: EcfDgiiVerificationSource;
      authorizationEvidenceId: string | null;
      requirements: Prisma.JsonValue | null;
      updatedAt: Date;
    },
    steps: readonly { stepKey: string; status: string }[],
    config: {
      enabled: boolean;
      certificationStatus: string;
      productionEnabled: boolean;
      credentialsSecretRef: string | null;
      certificateSecretRef: string | null;
    } | null,
    company: {
      licenseStatus: string;
      licenseExpiresAt: Date | null;
    } | null,
    appConfig: { rnc: string | null } | null,
    evidence: readonly {
      id: string;
      source: EcfEvidenceSource;
      kind: string;
      storageRef: string;
      fileName: string | null;
      mimeType: string | null;
      sha256: string | null;
      description: string | null;
      reviewStatus: EcfEvidenceReviewStatus;
      reviewedAt: Date | null;
      reviewNote: string | null;
      createdAt: Date;
    }[],
  ) {
    const progress = buildRequirementProgress(steps);
    const tracking = this.readRequirementTracking(record.requirements);
    const official = hasOfficialAuthorization(record);
    const licenseAllowsEcf = this.licenseAllowsEcf(company);
    const gateInput = {
      moduleEnabled: config?.enabled === true,
      certificationStatus: config?.certificationStatus ?? null,
      productionEnabled: config?.productionEnabled === true,
      fiscalConfigurationValid: Boolean(appConfig?.rnc?.trim()),
      licenseAllowsEcf,
      environment: this.environment(),
      officialAuthorization: official,
      pendingMandatoryRequirements: progress.pendingMandatory,
    };
    const gate = evaluateEcfEmissionGate(gateInput);

    return {
      companyId: record.companyId,
      state: record.state,
      reviewState: record.reviewState,
      observations: record.observations,
      responsibleUserId: record.responsibleUserId,
      externalId: record.externalId,
      startedAt: record.startedAt,
      updatedAt: record.updatedAt,
      // Distinción explícita entre seguimiento interno y autorización oficial.
      officialAuthorization: official,
      officialAuthorizationBlockers: this.officialAuthorizationBlockers(record, official),
      authorizationSource: record.authorizationSource,
      authorizedAt: record.authorizedAt,
      authorizationEvidenceId: record.authorizationEvidenceId,
      moduleEnabled: config?.enabled === true,
      certificationStatus: config?.certificationStatus ?? "NOT_STARTED",
      providerIntegrationConfigured: Boolean(
        config?.credentialsSecretRef && config?.certificateSecretRef,
      ),
      progress: {
        ...progress,
        // El catálogo aporta el QUÉ; el seguimiento aporta estado, responsable,
        // fecha y observaciones de cada requisito.
        requirements: progress.requirements.map((requirement) => ({
          ...requirement,
          tracking: this.toTrackingView(tracking[requirement.key]),
        })),
      },
      evidence: evidence.map((row) => this.toEvidenceView(row)),
      emission: {
        realEmissionAuthorized: gate.realEmissionAuthorized,
        simulatedDispatchAuthorized: gate.simulatedDispatchAuthorized,
        productionEmissionImplemented: gate.productionEmissionImplemented,
      },
      blockers: gate.blockers as EcfEmissionGateBlocker[],
      // El módulo es seguimiento: nunca sustituye una resolución oficial.
      isInternalTrackingOnly: true as const,
    };
  }

  /** Explica por qué NO hay autorización oficial reconocida. */
  private officialAuthorizationBlockers(
    record: {
      state: EcfDgiiHabilitationState;
      authorizationSource: EcfDgiiVerificationSource;
      authorizationEvidenceId: string | null;
      authorizedAt: Date | null;
      externalId: string | null;
    },
    official: boolean,
  ) {
    if (official) return [];
    const blockers: EcfEmissionGateBlocker[] = [];
    if (record.state !== EcfDgiiHabilitationState.APPROVED) {
      blockers.push({
        code: "ECF_DGII_STATE_NOT_APPROVED",
        message: "El seguimiento interno no está en estado aprobado.",
      });
    }
    if (record.authorizationSource !== EcfDgiiVerificationSource.DGII_OFFICIAL_RECORD) {
      blockers.push({
        code: "ECF_DGII_AUTHORIZATION_SOURCE_NOT_OFFICIAL",
        message:
          "La fuente registrada no es un registro oficial de la DGII; no autoriza emisión.",
      });
    }
    if (!record.authorizationEvidenceId) {
      blockers.push({
        code: "ECF_DGII_AUTHORIZATION_EVIDENCE_MISSING",
        message: "No hay evidencia documental que sustente la autorización.",
      });
    }
    if (!record.authorizedAt) {
      blockers.push({
        code: "ECF_DGII_AUTHORIZATION_DATE_MISSING",
        message: "No hay fecha de autorización registrada.",
      });
    }
    if (!record.externalId) {
      blockers.push({
        code: "ECF_DGII_AUTHORIZATION_EXTERNAL_ID_MISSING",
        message: "No hay identificador externo oficial registrado.",
      });
    }
    return blockers;
  }

  private licenseAllowsEcf(
    company: { licenseStatus: string; licenseExpiresAt: Date | null } | null,
  ): boolean {
    if (!company) return false;
    const status = (company.licenseStatus ?? "").trim().toUpperCase();
    if (status !== "TRIAL" && status !== "ACTIVE") return false;
    if (company.licenseExpiresAt && company.licenseExpiresAt.getTime() < Date.now()) {
      return false;
    }
    return true;
  }

  private toEvidenceView(row: {
    id: string;
    source: EcfEvidenceSource;
    kind: string;
    storageRef: string;
    fileName: string | null;
    mimeType: string | null;
    sha256: string | null;
    description: string | null;
    reviewStatus: EcfEvidenceReviewStatus;
    reviewedAt: Date | null;
    reviewNote: string | null;
    createdAt: Date;
  }) {
    return {
      id: row.id,
      source: row.source,
      // Una declaración manual NUNCA se presenta como documento oficial.
      isOfficialDocument: row.source === EcfEvidenceSource.OFFICIAL_DOCUMENT,
      kind: row.kind,
      fileName: row.fileName,
      mimeType: row.mimeType,
      sha256: row.sha256,
      description: row.description,
      // Revisión interna: dimensión SEPARADA del origen.
      reviewStatus: row.reviewStatus,
      reviewedAt: row.reviewedAt,
      reviewNote: row.reviewNote,
      level: evidenceLevel({ source: row.source, reviewStatus: row.reviewStatus }),
      // Explícito para que ningún consumidor lo deduzca por su cuenta.
      grantsOfficialAuthorization: evidenceGrantsOfficialAuthorization(),
      supportsOfficialAuthorization: evidenceQualityRefusal({
        source: row.source,
        reviewStatus: row.reviewStatus,
      }) === null,
      createdAt: row.createdAt,
    };
  }

  private toAuditSnapshot(record: {
    state: EcfDgiiHabilitationState;
    reviewState: string | null;
    responsibleUserId: string | null;
    externalId: string | null;
    authorizationSource: EcfDgiiVerificationSource;
    authorizedAt: Date | null;
  }) {
    return {
      state: record.state,
      reviewState: record.reviewState,
      responsibleUserId: record.responsibleUserId,
      externalId: record.externalId,
      authorizationSource: record.authorizationSource,
      authorizedAt: record.authorizedAt,
    };
  }

  private async writeAudit(
    tx: Prisma.TransactionClient,
    companyId: string,
    actorUserId: string,
    action: EcfAuditAction,
    targetType: string,
    targetId: string,
    before: Prisma.InputJsonValue | null,
    after: Prisma.InputJsonValue | null,
  ) {
    await tx.ecfAuditLog.create({
      data: {
        companyId,
        actorUserId,
        action,
        targetType,
        targetId,
        ...(before === null ? {} : { before }),
        ...(after === null ? {} : { after }),
      },
    });
  }

  private cleanNullable(value: string | null | undefined) {
    if (value === undefined) return undefined;
    if (value === null) return null;
    const trimmed = value.trim();
    return trimmed.length === 0 ? null : trimmed;
  }

  private redact(value: Prisma.JsonValue | null): Prisma.JsonValue | null {
    if (value === null) return null;
    if (Array.isArray(value)) return value.map((item) => this.redact(item));
    if (typeof value === "object") {
      const out: Record<string, Prisma.JsonValue> = {};
      for (const [key, item] of Object.entries(value)) {
        if (/secret|token|password|credential/i.test(key)) continue;
        out[key] = this.redact(item as Prisma.JsonValue);
      }
      return out;
    }
    return value;
  }
}
