import { Injectable, Logger } from "@nestjs/common";
import { createHash } from "node:crypto";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import type { CreateSaleAttemptDeclarationDto } from "./dto/sale-attempt-declaration.dto";

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
 *  - Idempotente: la misma declaración (misma huella) enviada dos veces devuelve
 *    la obligación existente y no duplica nada.
 *  - Aislada por empresa: la empresa sale SIEMPRE del token, nunca del cuerpo.
 *  - Append-only en su intención: una obligación no se borra; se resuelve con
 *    estado explícito y rastro de quién y cuándo.
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
    const totalDeclared = new Prisma.Decimal(dto.totalDeclared).toFixed(2);
    const declarationHash = SaleReconciliationObligationService.declarationHash({
      companyId,
      clientRequestId: requestId,
      totalDeclared,
      declaredAtUtc: dto.declaredAtUtc,
      declaredByUserId: dto.declaredByUserId ?? user.id,
      note: dto.note,
    });

    const data = {
      companyId,
      clientRequestId: requestId,
      declarationHash,
      totalDeclared: new Prisma.Decimal(totalDeclared),
      paymentMethod: dto.paymentMethod ?? "cash",
      declaredAtUtc: new Date(dto.declaredAtUtc),
      declaredByUserId: dto.declaredByUserId ?? user.id,
      declaredByRole: dto.declaredByRole ?? null,
      note: dto.note?.trim() || null,
      operationFingerprint: dto.operationFingerprint?.trim() || null,
      attemptPayload: (dto.attemptPayload ?? undefined) as
        | Prisma.InputJsonValue
        | undefined,
      status: "PENDING" as const,
    };

    try {
      const created = await this.prisma.saleReconciliationObligation.create({
        data,
      });
      this.logger.log(
        `sale_reconciliation_obligation_created id=${created.id} company=${companyId} request=${requestId} total=${totalDeclared}`,
      );
      return { obligation: this.toDto(created), duplicate: false };
    } catch (error) {
      // Único por (company, requestId, hash): el reenvío es idempotente.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const existing = await this.prisma.saleReconciliationObligation.findFirst(
          {
            where: { companyId, clientRequestId: requestId, declarationHash },
          },
        );
        if (existing) {
          this.logger.log(
            `sale_reconciliation_obligation_duplicate id=${existing.id} company=${companyId} request=${requestId}`,
          );
          return { obligation: this.toDto(existing), duplicate: true };
        }
      }
      throw error;
    }
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
      // Nunca se habilita repetir el cobro desde aquí.
      retryAllowed: false,
      assertsPaymentReceived: false,
    };
  }
}
