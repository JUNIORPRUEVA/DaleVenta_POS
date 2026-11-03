import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { EcfAuditAction, EcfSupportScope, Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import {
  ECF_SUPPORT_GRANT_MAX_DAYS,
  isValidGrantExpiry,
  normalizeScopes,
  supportGrantRefusal,
  supportGrantAllows,
  type EcfSupportScope as Scope,
} from "./ecf-support-grant.policy";

export type CreateEcfSupportGrantInput = {
  scopes: readonly string[];
  expiresAt: string | Date;
  reason?: string | null;
};

/**
 * Concesiones de asistencia de una EMPRESA al personal de FULLTECH.
 *
 * Dos caminos distintos y deliberadamente separados:
 *  - `create` / `list` / `revoke`: los usa la empresa, con su propio `companyId`.
 *  - `assertStaffAccess`: lo usa la plataforma antes de tocar un expediente ajeno.
 *
 * `assertStaffAccess` no sabe si el actor es staff: eso lo garantiza
 * `PlatformStaffGuard` antes. Aquí solo se comprueba la parte que la empresa
 * controla: que exista una concesión vigente que cubra el alcance pedido.
 */
@Injectable()
export class EcfSupportGrantService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Registro append-only de un evento de asistencia.
   *
   * Nunca guarda contenido documental, certificados, contraseñas ni tokens:
   * solo identificadores, alcances y el motivo de la decisión. Un fallo al
   * auditar no debe tumbar la operación, salvo en el alta/revocación donde el
   * registro es parte del acto.
   */
  private async auditSafe(entry: {
    companyId: string;
    actorUserId: string | null;
    action: EcfAuditAction;
    targetId?: string | null;
    after?: Prisma.InputJsonValue;
  }) {
    try {
      await this.prisma.ecfAuditLog.create({
        data: {
          companyId: entry.companyId,
          actorUserId: entry.actorUserId,
          action: entry.action,
          targetType: "EcfSupportGrant",
          targetId: entry.targetId ?? null,
          after: entry.after ?? {},
        },
      });
    } catch {
      // Una denegación puede referirse a una empresa inexistente (el guard se
      // evalúa antes que la existencia): no se puede auditar contra una FK
      // inválida, y rechazar por eso sería peor que no registrar.
    }
  }

  private activeGrantWhere(companyId: string) {
    return {
      companyId,
      revokedAt: null,
    } satisfies Prisma.EcfSupportGrantWhereInput;
  }

  async create(user: TenantUser, input: CreateEcfSupportGrantInput) {
    const companyId = requireTenant(user);
    const scopes = normalizeScopes(input.scopes ?? []);
    if (scopes.length === 0) {
      throw new BadRequestException("ECF_SUPPORT_SCOPES_REQUIRED");
    }
    if (!isValidGrantExpiry(input.expiresAt)) {
      throw new BadRequestException({
        message: "ECF_SUPPORT_GRANT_INVALID_EXPIRY",
        maxDays: ECF_SUPPORT_GRANT_MAX_DAYS,
      });
    }

    try {
      const { created, expired } = await this.prisma.$transaction(async (tx) => {
        // Serialización por empresa: dos altas simultáneas no pueden dejar dos
        // concesiones efectivas. El índice único parcial sigue siendo la última
        // defensa, pero el lock evita que la segunda falle por carrera.
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${companyId}))`;

        // Una concesión CADUCADA ya no es efectiva, así que deja de ocupar el
        // índice único parcial. Se cierra dejando rastro (no se borra): la
        // historia de autorizaciones se conserva intacta. Se leen los ids ANTES
        // de cerrarlas para poder registrarlas individualmente en la auditoría.
        const stale = await tx.ecfSupportGrant.findMany({
          where: {
            companyId,
            revokedAt: null,
            expiresAt: { lte: new Date() },
          },
          select: { id: true, expiresAt: true },
        });
        if (stale.length > 0) {
          await tx.ecfSupportGrant.updateMany({
            where: { id: { in: stale.map((row) => row.id) }, revokedAt: null },
            data: { revokedAt: new Date(), revokedByUserId: null },
          });
        }

        const row = await tx.ecfSupportGrant.create({
          data: {
            companyId,
            grantedByUserId: user.id,
            scopes: scopes as EcfSupportScope[],
            reason: input.reason ?? null,
            expiresAt: new Date(input.expiresAt),
          },
        });
        return { created: row, expired: stale };
      });
      // La caducidad se audita ANTES del alta: el orden refleja el hecho real.
      for (const row of expired) {
        await this.auditSafe({
          companyId,
          actorUserId: null,
          action: EcfAuditAction.SUPPORT_GRANT_EXPIRED,
          targetId: row.id,
          after: { expiresAt: row.expiresAt.toISOString() },
        });
      }
      await this.auditSafe({
        companyId,
        actorUserId: user.id,
        action: EcfAuditAction.SUPPORT_GRANT_CREATED,
        targetId: created.id,
        after: {
          scopes: created.scopes,
          expiresAt: created.expiresAt.toISOString(),
        },
      });
      return created;
    } catch (error) {
      // Índice único parcial: una sola concesión activa por empresa.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        throw new ConflictException("ECF_SUPPORT_GRANT_ALREADY_ACTIVE");
      }
      throw error;
    }
  }

  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    const rows = await this.prisma.ecfSupportGrant.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take: 50,
    });
    const now = new Date();
    return {
      companyId,
      items: rows.map((row) => ({
        id: row.id,
        scopes: row.scopes,
        reason: row.reason,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        revokedAt: row.revokedAt,
        active: supportGrantAllows(row, "VIEW_DOSSIER", now) ||
          supportGrantAllows(row, "REVIEW_EVIDENCE", now) ||
          supportGrantAllows(row, "REQUEST_CORRECTION", now),
        revoked: Boolean(row.revokedAt),
        expired: !row.revokedAt && new Date(row.expiresAt).getTime() <= now.getTime(),
      })),
    };
  }

  async revoke(user: TenantUser, grantId: string) {
    const companyId = requireTenant(user);
    const grant = await this.prisma.ecfSupportGrant.findFirst({
      where: { id: grantId, companyId },
      select: { id: true, revokedAt: true },
    });
    // Un identificador de otra empresa responde igual que uno inexistente.
    if (!grant) throw new NotFoundException("ECF_SUPPORT_GRANT_NOT_FOUND");
    if (grant.revokedAt) return { id: grant.id, revokedAt: grant.revokedAt };

    const updated = await this.prisma.ecfSupportGrant.update({
      where: { id: grant.id },
      data: { revokedAt: new Date(), revokedByUserId: user.id },
    });
    await this.auditSafe({
      companyId,
      actorUserId: user.id,
      action: EcfAuditAction.SUPPORT_GRANT_REVOKED,
      targetId: updated.id,
      after: { revokedAt: updated.revokedAt?.toISOString() ?? null },
    });
    // Efecto inmediato: la siguiente petición del staff ya no encuentra
    // concesión activa, porque se busca con `revokedAt: null`.
    return { id: updated.id, revokedAt: updated.revokedAt };
  }

  /**
   * Concesión EFECTIVA de una empresa, para que el personal de plataforma vea
   * con qué alcance está accediendo.
   *
   * No es una lectura pública: solo se sirve después de que el guard haya
   * autorizado la petición con `VIEW_DOSSIER`. Si no hay concesión vigente, la
   * petición ni siquiera llega aquí.
   */
  async activeGrantForCompany(companyId: string, now: Date = new Date()) {
    const grant = await this.prisma.ecfSupportGrant.findFirst({
      where: { companyId, revokedAt: null, expiresAt: { gt: now } },
      orderBy: { createdAt: "desc" },
    });
    if (!grant) return null;
    return {
      id: grant.id,
      scopes: grant.scopes,
      reason: grant.reason,
      grantedAt: grant.createdAt,
      expiresAt: grant.expiresAt,
    };
  }

  /**
   * Empresas con concesión EFECTIVA en este instante.
   *
   * La usa la bandeja del panel para no exponer ni un nombre de empresa sin
   * permiso. Filtra por vigencia en la consulta: una concesión caducada no
   * aparece aunque no esté revocada.
   */
  async activeCompanyIds(now: Date = new Date()): Promise<string[]> {
    const rows = await this.prisma.ecfSupportGrant.findMany({
      where: { revokedAt: null, expiresAt: { gt: now } },
      select: { companyId: true },
    });
    return [...new Set(rows.map((row) => row.companyId))];
  }

  /**
   * Comprueba que existe una concesión vigente con el alcance pedido.
   *
   * Se evalúa en CADA petición (no se cachea) para que revocación y expiración
   * surtan efecto inmediato. Lanza 403 con el motivo exacto.
   */
  async assertStaffAccess(
    companyId: string,
    scope: Scope,
    actorUserId: string | null = null,
    now: Date = new Date(),
  ) {
    // Se lee la ÚLTIMA concesión sin filtrar por revocación: así el mensaje
    // distingue «revocada» de «inexistente». Filtrar por `revokedAt: null`
    // ocultaba la revocación y la reportaba como si nunca hubiera existido.
    const grant = await this.prisma.ecfSupportGrant.findFirst({
      where: { companyId },
      orderBy: { createdAt: "desc" },
    });
    const refusal = supportGrantRefusal(grant, scope, now);
    if (refusal) {
      await this.auditSafe({
        companyId,
        actorUserId,
        action: EcfAuditAction.SUPPORT_ACCESS_DENIED,
        targetId: grant?.id ?? null,
        after: { scope, reason: refusal },
      });
      throw new ForbiddenException({ message: refusal, scope, companyId });
    }
    await this.auditSafe({
      companyId,
      actorUserId,
      action: EcfAuditAction.SUPPORT_ACCESS_GRANTED,
      targetId: grant?.id ?? null,
      after: { scope },
    });
    return grant;
  }
}
