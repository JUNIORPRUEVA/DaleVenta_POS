import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import type { CreateSaleAttemptDeclarationDto } from "./dto/sale-attempt-declaration.dto";

/**
 * Señal interna: alguien sin rol administrativo intentó cambiar el importe.
 *
 * Se usa un error propio (y no `ForbiddenException` directamente) porque la
 * comprobación ocurre DENTRO de la transacción: al lanzarla, la transacción se
 * revierte y el rechazo se escribe después, en una transacción nueva, para que
 * la evidencia no se pierda con el rollback.
 */
class RectificationRejectedError extends Error {
  constructor(
    readonly obligationId: string,
    readonly previousTotal: string,
  ) {
    super("RECTIFICATION_REQUIRES_ADMIN");
    this.name = "RectificationRejectedError";
  }
}

/**
 * Obligaciones de conciliación por cobros declarados sin venta confirmada.
 *
 * Contexto: cuando el backend no confirma el resultado de un cobro, el encargado
 * puede declarar «sí recibí el dinero» en el Centro de recuperación. Esa
 * declaración es una AFIRMACIÓN HUMANA, no una venta.
 *
 * Reglas que este servicio garantiza:
 *  - NO crea ventas, pagos, movimientos de caja, cuentas por cobrar ni
 *    inventario. Solo registra la obligación de conciliar.
 *  - UNA sola obligación ACTIVA por operación (`companyId + clientRequestId`).
 *    Varias personas o dispositivos declarando lo mismo NO duplican el importe
 *    pendiente: se registran como eventos auditables sobre la misma obligación.
 *  - Cambiar el importe es una RECTIFICACIÓN y exige rol administrativo; queda
 *    registrada con el importe anterior, el nuevo, el actor y la nota. Un rol no
 *    administrativo recibe 403 y no altera nada.
 *  - Idempotente: la misma declaración (misma huella) devuelve la obligación
 *    existente y no escribe un evento nuevo.
 *  - Aislada por empresa: la empresa sale SIEMPRE del token, nunca del cuerpo.
 *  - Append-only: ni la obligación ni sus eventos se borran; se resuelven con
 *    estado explícito y rastro.
 */
@Injectable()
export class SaleReconciliationObligationService {
  private readonly logger = new Logger(SaleReconciliationObligationService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Huella estable de la declaración. Incluye identidad, operación, importe y
   * la hora declarada: dos declaraciones distintas del mismo intento con
   * importes u horas diferentes NO colisionan, y el reenvío exacto SÍ.
   */
  static declarationHash(input: {
    companyId: string;
    clientRequestId: string;
    totalDeclared: string;
    declaredAtUtc: string;
    declaredByUserId?: string | null;
    note?: string | null;
  }): string {
    const note = (input.note ?? "").trim().toLowerCase();
    const actor = (input.declaredByUserId ?? "").trim().toLowerCase();
    const payload = [
      input.companyId.toLowerCase(),
      input.clientRequestId,
      input.totalDeclared,
      input.declaredAtUtc,
      actor,
      note,
    ].join("|");
    return createHash("sha256").update(payload, "utf8").digest("hex");
  }

  async recordDeclaration(
    user: TenantUser,
    clientRequestId: string,
    dto: CreateSaleAttemptDeclarationDto,
  ) {
    const companyId = requireTenant(user);
    const requestId = clientRequestId.trim();
    if (!requestId) {
      throw new BadRequestException("clientRequestId es obligatorio");
    }

    const totalDeclared = new Prisma.Decimal(dto.totalDeclared).toFixed(2);
    const actorUserId = dto.declaredByUserId ?? user.id;
    const actorRole = dto.declaredByRole ?? null;
    const note = dto.note?.trim() || null;
    const declaredAt = new Date(dto.declaredAtUtc);
    const declarationHash = SaleReconciliationObligationService.declarationHash({
      companyId,
      clientRequestId: requestId,
      totalDeclared,
      declaredAtUtc: dto.declaredAtUtc,
      declaredByUserId: actorUserId,
      note,
    });

    const outcome = await this.applyWithRetry({
      companyId,
      requestId,
      actorUserId,
      actorRole,
      note,
      totalDeclared,
      declaredAt,
      declarationHash,
      paymentMethod: dto.paymentMethod ?? "cash",
      operationFingerprint: dto.operationFingerprint?.trim() || null,
      attemptPayload: (dto.attemptPayload ?? undefined) as
        | Prisma.InputJsonValue
        | undefined,
      isAdmin: isAdminLike(user),
    });

    return {
      obligation: this.toDto(outcome.obligation as never),
      duplicate: outcome.kind === "DUPLICATE",
      amendment: outcome.kind,
    };
  }

  /**
   * Varias declaraciones simultáneas de la misma operación compiten por el
   * índice único. En PostgreSQL, un choque de unicidad ABORTA la transacción
   * entera, así que no se puede "seguir" dentro de ella: se reintenta la
   * transacción completa. En el reintento la obligación activa ya existe y la
   * declaración se aplica como AMENDED (o DUPLICATE), sin duplicar el saldo.
   *
   * Una rectificación sin permiso se señaliza con un error propio para poder
   * escribir el rechazo en una transacción NUEVA (si se escribiera dentro, el
   * rollback lo borraría y se perdería la evidencia).
   */
  private async applyWithRetry(
    input: Parameters<SaleReconciliationObligationService["applyDeclaration"]>[0],
  ) {
    const maxAttempts = 5;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await this.applyDeclaration(input);
      } catch (error) {
        if (error instanceof RectificationRejectedError) {
          await this.recordRejectedRectification(input, error);
          throw new ForbiddenException({
            code: "RECTIFICATION_REQUIRES_ADMIN",
            message:
              "Cambiar el importe declarado exige un usuario administrativo. Pide autorización al encargado; la declaración original no se modificó.",
          });
        }
        if (this.isUniqueViolation(error) && attempt < maxAttempts) {
          // Pequeña espera con jitter para no reintentar en el mismo instante
          // que la otra declaración.
          await new Promise((resolve) =>
            setTimeout(resolve, 5 * attempt + Math.floor(Math.random() * 10)),
          );
          continue;
        }
        throw error;
      }
    }
    throw new BadRequestException(
      "No se pudo registrar la declaración por una condición de carrera. Reintenta.",
    );
  }

  private async recordRejectedRectification(
    input: Parameters<SaleReconciliationObligationService["applyDeclaration"]>[0],
    error: RectificationRejectedError,
  ) {
    try {
      await this.writeEvent(this.prisma as never, {
        companyId: input.companyId,
        obligationId: error.obligationId,
        requestId: input.requestId,
        declarationHash: input.declarationHash,
        kind: "RECTIFICATION_REJECTED",
        totalDeclared: input.totalDeclared,
        previousTotal: error.previousTotal,
        actorUserId: input.actorUserId,
        actorRole: input.actorRole,
        note: input.note,
        declaredAt: input.declaredAt,
      });
      this.logger.warn(
        `sale_reconciliation_rectification_rejected id=${error.obligationId} company=${input.companyId} actor=${input.actorUserId} role=${input.actorRole}`,
      );
    } catch (writeError) {
      this.logger.error(
        `sale_reconciliation_rejection_audit_failed id=${error.obligationId} ${writeError}`,
      );
    }
  }

  private async applyDeclaration(input: {
    companyId: string;
    requestId: string;
    actorUserId: string;
    actorRole: string | null;
    note: string | null;
    totalDeclared: string;
    declaredAt: Date;
    declarationHash: string;
    paymentMethod: string;
    operationFingerprint: string | null;
    attemptPayload: Prisma.InputJsonValue | undefined;
    isAdmin: boolean;
  }) {
    // La transacción serializa declaraciones simultáneas de la misma operación
    // (el índice parcial único es la última red de seguridad).
    return this.prisma.$transaction(async (tx) => {
      const active = await tx.saleReconciliationObligation.findFirst({
        where: {
          companyId: input.companyId,
          clientRequestId: input.requestId,
          status: "PENDING",
        },
      });

      if (!active) {
        const created = await tx.saleReconciliationObligation.create({
          data: {
            companyId: input.companyId,
            clientRequestId: input.requestId,
            declarationHash: input.declarationHash,
            totalDeclared: new Prisma.Decimal(input.totalDeclared),
            paymentMethod: input.paymentMethod,
            declaredAtUtc: input.declaredAt,
            declaredByUserId: input.actorUserId,
            declaredByRole: input.actorRole,
            note: input.note,
            operationFingerprint: input.operationFingerprint,
            attemptPayload: input.attemptPayload,
            status: "PENDING",
            declarationCount: 1,
            version: 1,
            lastDeclaredAtUtc: input.declaredAt,
          },
        });
        await this.writeEvent(tx, {
          companyId: input.companyId,
          obligationId: created.id,
          requestId: input.requestId,
          declarationHash: input.declarationHash,
          kind: "CREATED",
          totalDeclared: input.totalDeclared,
          previousTotal: null,
          actorUserId: input.actorUserId,
          actorRole: input.actorRole,
          note: input.note,
          declaredAt: input.declaredAt,
        });
        this.logger.log(
          `sale_reconciliation_obligation_created id=${created.id} company=${input.companyId} request=${input.requestId} total=${input.totalDeclared}`,
        );
        return { obligation: created, kind: "CREATED" as const };
      }

      return this.applyOnExisting(tx, active, input);
    });
  }

  private async applyOnExisting(
    tx: Prisma.TransactionClient,
    active: {
      id: string;
      declarationHash: string;
      totalDeclared: Prisma.Decimal;
    },
    input: {
      companyId: string;
      requestId: string;
      actorUserId: string;
      actorRole: string | null;
      note: string | null;
      totalDeclared: string;
      declaredAt: Date;
      declarationHash: string;
      isAdmin: boolean;
    },
  ) {
    // 1) Reenvío exacto: nada que hacer.
    if (active.declarationHash === input.declarationHash) {
      this.logger.log(
        `sale_reconciliation_obligation_duplicate id=${active.id} company=${input.companyId} request=${input.requestId}`,
      );
      return { obligation: active, kind: "DUPLICATE" as const };
    }

    const currentTotal = active.totalDeclared.toFixed(2);
    const changesAmount = currentTotal !== input.totalDeclared;

    // 2) Cambiar el importe sin autorización: se señaliza para que el rechazo
    //    se registre en una transacción aparte (si se escribiera aquí, el
    //    rollback borraría la evidencia).
    if (changesAmount && !input.isAdmin) {
      throw new RectificationRejectedError(active.id, currentTotal);
    }

    const updated = await tx.saleReconciliationObligation.update({
      where: { id: active.id },
      data: {
        // El importe solo cambia en una rectificación autorizada.
        ...(changesAmount
          ? {
              totalDeclared: new Prisma.Decimal(input.totalDeclared),
              version: { increment: 1 },
              declarationHash: input.declarationHash,
            }
          : {}),
        declarationCount: { increment: 1 },
        lastDeclaredAtUtc: input.declaredAt,
        // La nota y el actor vigentes reflejan la última declaración auditada.
        note: input.note ?? undefined,
        declaredByUserId: input.actorUserId,
        declaredByRole: input.actorRole ?? undefined,
        updatedAt: new Date(),
      },
    });

    await this.writeEvent(tx, {
      companyId: input.companyId,
      obligationId: active.id,
      requestId: input.requestId,
      declarationHash: input.declarationHash,
      kind: changesAmount ? "RECTIFIED" : "AMENDED",
      totalDeclared: input.totalDeclared,
      previousTotal: changesAmount ? currentTotal : null,
      actorUserId: input.actorUserId,
      actorRole: input.actorRole,
      note: input.note,
      declaredAt: input.declaredAt,
    });

    this.logger.log(
      `sale_reconciliation_obligation_${changesAmount ? "rectified" : "amended"} id=${active.id} company=${input.companyId} ` +
        `from=${currentTotal} to=${input.totalDeclared} actor=${input.actorUserId}`,
    );
    return {
      obligation: updated,
      kind: (changesAmount ? "RECTIFIED" : "AMENDED") as
        | "RECTIFIED"
        | "AMENDED",
    };
  }

  private writeEvent(
    tx: Prisma.TransactionClient,
    input: {
      companyId: string;
      obligationId: string;
      requestId: string;
      declarationHash: string;
      kind: string;
      totalDeclared: string;
      previousTotal: string | null;
      actorUserId: string;
      actorRole: string | null;
      note: string | null;
      declaredAt: Date;
    },
  ) {
    return tx.saleReconciliationDeclarationEvent.create({
      data: {
        companyId: input.companyId,
        obligationId: input.obligationId,
        clientRequestId: input.requestId,
        declarationHash: input.declarationHash,
        kind: input.kind,
        totalDeclared: new Prisma.Decimal(input.totalDeclared),
        previousTotal:
          input.previousTotal == null
            ? null
            : new Prisma.Decimal(input.previousTotal),
        actorUserId: input.actorUserId,
        actorRole: input.actorRole,
        note: input.note,
        declaredAtUtc: input.declaredAt,
      },
    });
  }

  private isUniqueViolation(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    );
  }

  async list(user: TenantUser, status?: string) {
    const companyId = requireTenant(user);
    const rows = await this.prisma.saleReconciliationObligation.findMany({
      where: {
        companyId,
        ...(status ? { status: status.trim().toUpperCase() } : {}),
      },
      orderBy: [{ createdAt: "desc" }],
      take: 200,
    });
    return rows.map((row) => this.toDto(row));
  }

  /** Historial de declaraciones de UNA obligación (solo lectura, por empresa). */
  async listEvents(user: TenantUser, obligationId: string) {
    const companyId = requireTenant(user);
    const obligation = await this.prisma.saleReconciliationObligation.findFirst({
      where: { id: obligationId, companyId },
      select: { id: true },
    });
    if (!obligation) {
      throw new ForbiddenException({
        code: "OBLIGATION_NOT_FOUND",
        message: "La obligación no existe en esta empresa.",
      });
    }
    const events =
      await this.prisma.saleReconciliationDeclarationEvent.findMany({
        where: { companyId, obligationId },
        orderBy: [{ createdAt: "asc" }],
        take: 200,
      });
    return events.map((event) => ({
      id: event.id,
      kind: event.kind,
      totalDeclared: Number(event.totalDeclared),
      previousTotal:
        event.previousTotal == null ? null : Number(event.previousTotal),
      actorUserId: event.actorUserId,
      actorRole: event.actorRole,
      note: event.note,
      declaredAtUtc: event.declaredAtUtc.toISOString(),
      createdAt: event.createdAt.toISOString(),
    }));
  }

  private toDto(row: {
    id: string;
    clientRequestId: string;
    totalDeclared: Prisma.Decimal;
    paymentMethod: string;
    declaredAtUtc: Date;
    declaredByUserId: string | null;
    declaredByRole: string | null;
    note: string | null;
    operationFingerprint: string | null;
    status: string;
    createdAt: Date;
    resolvedAt: Date | null;
    resolvedByUserId: string | null;
    resolutionNote: string | null;
    declarationCount: number;
    version: number;
    lastDeclaredAtUtc: Date | null;
  }) {
    return {
      id: row.id,
      clientRequestId: row.clientRequestId,
      totalDeclared: Number(row.totalDeclared),
      paymentMethod: row.paymentMethod,
      declaredAtUtc: row.declaredAtUtc.toISOString(),
      declaredByUserId: row.declaredByUserId,
      declaredByRole: row.declaredByRole,
      note: row.note,
      operationFingerprint: row.operationFingerprint,
      status: row.status,
      createdAt: row.createdAt.toISOString(),
      resolvedAt: row.resolvedAt?.toISOString() ?? null,
      resolvedByUserId: row.resolvedByUserId,
      resolutionNote: row.resolutionNote,
      // Una operación = una obligación activa; estos campos dicen cuántas
      // declaraciones la respaldan y si el importe fue rectificado.
      declarationCount: row.declarationCount,
      version: row.version,
      lastDeclaredAtUtc: row.lastDeclaredAtUtc?.toISOString() ?? null,
      // Nunca se habilita repetir el cobro desde aquí.
      retryAllowed: false,
      assertsPaymentReceived: false,
    };
  }
}
