import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { LicensePlanRequestStatus, Prisma } from '@prisma/client';
import { randomInt } from 'node:crypto';
import { isAdminLike, requireTenant, type TenantUser } from '../../auth/tenant-context';
import { PrismaService } from '../../prisma/prisma.service';

export type PlanRequestView = {
  id: string;
  reference: string;
  status: LicensePlanRequestStatus;
  currentPlanCode: string | null;
  requestedPlanCode: string | null;
  message: string | null;
  createdAt: Date;
};

/**
 * Solicitud de mejora de plan cuando la empresa **ya** esta en el plan mas
 * alto del catalogo.
 *
 * No cambia la licencia: abre un ticket para que soporte decida la excepcion.
 * El ticket es unico por empresa y plan mientras siga abierto, para que pulsar
 * dos veces no cree dos solicitudes.
 */
@Injectable()
export class LicensePlanRequestService {
  constructor(private readonly prisma: PrismaService) {}

  async create(
    user: TenantUser,
    dto: { planCode?: unknown; message?: unknown },
  ): Promise<{ ok: true; reused: boolean; request: PlanRequestView }> {
    const companyId = requireTenant(user);
    if (!isAdminLike(user)) {
      throw new BadRequestException({
        code: 'PLAN_REQUEST_FORBIDDEN',
        message: 'Solo el propietario o un administrador puede solicitar el cambio.',
      });
    }
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { planCode: true },
    });
    if (!company) throw new NotFoundException('Empresa no encontrada');

    const requestedPlanCode =
      String(dto.planCode ?? '').trim().toLowerCase() || null;
    const message = String(dto.message ?? '').trim().slice(0, 800) || null;

    const existing = await this.prisma.licensePlanRequest.findFirst({
      where: {
        companyId,
        status: { in: [LicensePlanRequestStatus.OPEN, LicensePlanRequestStatus.CONTACTED] },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (existing) {
      return { ok: true, reused: true, request: toView(existing) };
    }

    const request = await this.prisma.$transaction(async (tx) => {
      const created = await tx.licensePlanRequest.create({
        data: {
          companyId,
          currentPlanCode: company.planCode,
          requestedPlanCode,
          message,
          reference: await this.nextReference(tx),
          createdByUserId: user.id,
        },
      });
      await tx.companyLicenseAuditLog.create({
        data: {
          companyId,
          actorId: user.id,
          actorEmail: null,
          action: 'license.plan_upgrade_requested',
          reason: created.reference,
          after: {
            reference: created.reference,
            currentPlanCode: company.planCode,
            requestedPlanCode,
          } satisfies Prisma.InputJsonValue,
        },
      });
      return created;
    });

    return { ok: true, reused: false, request: toView(request) };
  }

  /** Solicitud abierta de la empresa, si la hay (para pintar el estado). */
  async myOpen(user: TenantUser) {
    const companyId = requireTenant(user);
    const row = await this.prisma.licensePlanRequest.findFirst({
      where: {
        companyId,
        status: {
          in: [LicensePlanRequestStatus.OPEN, LicensePlanRequestStatus.CONTACTED],
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    return { request: row ? toView(row) : null };
  }

  /** Lista para el CRM: es la bandeja de soporte de mejoras de plan. */
  async listAdmin(params: { status?: unknown; limit?: unknown }) {
    const raw = String(params.status ?? '').trim().toUpperCase();
    const status = Object.values(LicensePlanRequestStatus).includes(
      raw as LicensePlanRequestStatus,
    )
      ? (raw as LicensePlanRequestStatus)
      : null;
    const limit = Math.min(
      Math.max(Number.parseInt(String(params.limit ?? '50'), 10) || 50, 1),
      200,
    );
    const rows = await this.prisma.licensePlanRequest.findMany({
      where: status ? { status } : {},
      orderBy: { createdAt: 'desc' },
      take: limit,
      include: {
        company: {
          select: { id: true, name: true, slug: true, planCode: true },
        },
      },
    });
    return {
      requests: rows.map((row) => ({
        ...toView(row),
        companyName: row.company?.name ?? null,
        companySlug: row.company?.slug ?? null,
        companyPlanCode: row.company?.planCode ?? null,
      })),
    };
  }

  async setStatus(input: {
    requestId: string;
    status: LicensePlanRequestStatus;
    actor?: string | null;
  }) {
    const request = await this.prisma.licensePlanRequest.findUnique({
      where: { id: input.requestId },
      select: { id: true, companyId: true, reference: true, status: true },
    });
    if (!request) {
      throw new NotFoundException({
        code: 'PLAN_REQUEST_NOT_FOUND',
        message: 'No encontramos esa solicitud.',
      });
    }
    const updated = await this.prisma.licensePlanRequest.update({
      where: { id: request.id },
      data: { status: input.status },
    });
    await this.prisma.companyLicenseAuditLog.create({
      data: {
        companyId: request.companyId,
        actorEmail: input.actor ?? null,
        action: 'license.plan_upgrade_status',
        reason: request.reference,
        before: { status: request.status } satisfies Prisma.InputJsonValue,
        after: { status: updated.status } satisfies Prisma.InputJsonValue,
      },
    });
    return { ok: true, request: toView(updated) };
  }

  private async nextReference(tx: Prisma.TransactionClient) {
    const year = new Date().getUTCFullYear();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const reference = `SOL-${year}-${String(randomInt(0, 1_000_000)).padStart(6, '0')}`;
      const exists = await tx.licensePlanRequest.findUnique({
        where: { reference },
        select: { id: true },
      });
      if (!exists) return reference;
    }
    return `SOL-${year}-${Date.now().toString().slice(-6)}`;
  }
}

function toView(row: {
  id: string;
  reference: string;
  status: LicensePlanRequestStatus;
  currentPlanCode: string | null;
  requestedPlanCode: string | null;
  message: string | null;
  createdAt: Date;
}): PlanRequestView {
  return {
    id: row.id,
    reference: row.reference,
    status: row.status,
    currentPlanCode: row.currentPlanCode,
    requestedPlanCode: row.requestedPlanCode,
    message: row.message,
    createdAt: row.createdAt,
  };
}
