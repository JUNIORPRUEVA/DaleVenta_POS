import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { EcfAuditAction, Prisma, type ProductItemType } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import type { ConfirmEcfLineClassificationDto } from "../dto/ecf-documents.dto";
import { ECF_LINE_CLASSIFICATION_MESSAGES } from "./ecf-line-classification.messages";
import {
  effectiveLineClassification,
  isFiscallyFrozen,
  lineClassificationRefusal,
} from "./ecf-line-classification.policy";

/**
 * Clasificación fiscal SUPERVISADA de partidas (F1).
 *
 * Resuelve un caso concreto: una partida fuera de inventario no tiene producto
 * del que heredar si es bien o servicio, así que la venta queda imposible de
 * facturar electrónicamente. Aquí un usuario AUTORIZADO deja constancia de la
 * clasificación, con motivo, autor y fecha.
 *
 * Lo que este servicio NO hace, por diseño:
 *
 *  - **No modifica la venta ni la partida.** La decisión es un hecho nuevo y
 *    fechado; el `SaleItem` histórico se queda como está.
 *  - **No adivina.** Solo acepta `PRODUCT` o `SERVICE` explícitos.
 *  - **No reclasifica algo que ya salió.** Si el comprobante ya se envió o está
 *    en revisión humana, se rechaza.
 *  - **No autoriza nada ante la DGII.** Es una decisión interna de la empresa.
 *
 * Cada consulta y cada escritura está acotada al `companyId` del contexto
 * autenticado: una partida de otra empresa se comporta como inexistente.
 */
@Injectable()
export class EcfLineClassificationService {
  constructor(private readonly prisma: PrismaService) {}

  /** Partidas de una venta con su estado de clasificación. */
  async listPending(user: TenantUser, saleId: string) {
    const companyId = requireTenant(user);
    const sale = await this.prisma.sale.findFirst({
      where: { id: saleId, companyId },
      include: { items: { orderBy: { createdAt: "asc" } } },
    });
    if (!sale) {
      throw new NotFoundException(ECF_LINE_CLASSIFICATION_MESSAGES.saleNotFound);
    }

    const documentStatuses = await this.documentStatuses(companyId, saleId);
    const fiscallyFrozen = isFiscallyFrozen(documentStatuses);
    const supervised = await this.latestByItem(
      companyId,
      sale.items.map((item) => item.id),
    );

    return {
      saleId,
      fiscallyFrozen,
      documentStatuses,
      lines: sale.items.map((item) => {
        const latest = supervised.get(item.id) ?? null;
        const effective = effectiveLineClassification({
          frozenSnapshot: item.itemTypeSnapshot,
          supervised: latest?.classification ?? null,
        });
        return {
          saleItemId: item.id,
          name: item.productNameSnapshot,
          quantity: item.qty.toString(),
          unitPrice: item.priceSoldUnit.toString(),
          frozenClassification: item.itemTypeSnapshot,
          supervisedClassification: latest?.classification ?? null,
          supervisedReason: latest?.reason ?? null,
          supervisedAt: latest?.decidedAt ?? null,
          effectiveClassification: effective,
          /** `true` mientras no haya forma de saber si es bien o servicio. */
          needsClassification: effective === null,
          /** Solo se puede confirmar lo que aún no salió del equipo. */
          canConfirm: !fiscallyFrozen && effective === null,
        };
      }),
    };
  }

  /**
   * Confirma la clasificación de una partida sin producto.
   *
   * Es APPEND-ONLY: cada confirmación es un registro nuevo. Corregir consiste en
   * añadir otro; el valor anterior queda como `previousClassification`, y el más
   * reciente manda.
   */
  async confirm(user: TenantUser, dto: ConfirmEcfLineClassificationDto) {
    const companyId = requireTenant(user);
    const sale = await this.prisma.sale.findFirst({
      where: { id: dto.saleId, companyId },
      include: { items: { where: { id: dto.saleItemId } } },
    });
    if (!sale) {
      throw new NotFoundException(ECF_LINE_CLASSIFICATION_MESSAGES.saleNotFound);
    }
    const item = sale.items[0];
    if (!item) {
      throw new NotFoundException(ECF_LINE_CLASSIFICATION_MESSAGES.itemNotFound);
    }

    // Si la venta ya congeló la clasificación, esa es la evidencia histórica y
    // no se toca: reclasificar sería reescribir cómo se emitió la venta.
    if (item.itemTypeSnapshot !== null) {
      throw new ConflictException({
        code: "ECF_LINE_CLASSIFICATION_ALREADY_FROZEN",
        message: ECF_LINE_CLASSIFICATION_MESSAGES.alreadyClassified,
      });
    }

    const documentStatuses = await this.documentStatuses(companyId, dto.saleId);
    const current = await this.prisma.ecfLineClassification.findFirst({
      where: { companyId, saleItemId: item.id },
      orderBy: [{ decidedAt: "desc" }, { id: "desc" }],
      select: { classification: true },
    });

    const refusal = lineClassificationRefusal({
      classification: dto.classification,
      reason: dto.reason,
      documentStatuses,
      currentClassification: current?.classification ?? null,
    });
    if (refusal) {
      throw new ConflictException({ code: refusal.code, message: refusal.message });
    }

    const created = await this.prisma.$transaction(async (tx) => {
      const row = await tx.ecfLineClassification.create({
        data: {
          companyId,
          saleId: dto.saleId,
          saleItemId: item.id,
          classification: dto.classification,
          previousClassification: current?.classification ?? null,
          reason: dto.reason.trim(),
          decidedByUserId: user.id,
        },
      });
      await tx.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id,
          action: EcfAuditAction.LINE_CLASSIFICATION_CONFIRMED,
          targetType: "EcfLineClassification",
          targetId: row.id,
          // Se omiten los nulos en vez de escribirlos: un JSON `null` explícito
          // se confundiría con «no había valor anterior» cuando lo que no hay es
          // un estado previo que registrar.
          ...(current
            ? { before: { classification: current.classification } as Prisma.InputJsonValue }
            : {}),
          after: {
            classification: row.classification,
            saleId: dto.saleId,
            saleItemId: item.id,
            reason: row.reason,
          } as Prisma.InputJsonValue,
        },
      });
      return row;
    });

    const view = await this.listPending(user, dto.saleId);
    return {
      classification: {
        id: created.id,
        saleItemId: created.saleItemId,
        classification: created.classification,
        previousClassification: created.previousClassification,
        reason: created.reason,
        decidedAt: created.decidedAt,
        decidedByUserId: created.decidedByUserId,
      },
      sale: view,
    };
  }

  /** Estados de los comprobantes de la venta, para decidir si ya salió. */
  private async documentStatuses(companyId: string, saleId: string) {
    const rows = await this.prisma.ecfElectronicDocument.findMany({
      where: { companyId, sourceId: saleId },
      select: { status: true },
    });
    return rows.map((row) => row.status as string);
  }

  /** Última clasificación supervisada por partida (append-only: gana la última). */
  private async latestByItem(
    companyId: string,
    saleItemIds: string[],
  ): Promise<
    Map<
      string,
      { classification: ProductItemType; reason: string; decidedAt: Date }
    >
  > {
    if (saleItemIds.length === 0) return new Map();
    const rows = await this.prisma.ecfLineClassification.findMany({
      where: { companyId, saleItemId: { in: saleItemIds } },
      orderBy: [{ decidedAt: "asc" }, { id: "asc" }],
      select: {
        saleItemId: true,
        classification: true,
        reason: true,
        decidedAt: true,
      },
    });
    // Recorriendo en orden ascendente, el último valor escrito es el vigente.
    const latest = new Map<
      string,
      { classification: ProductItemType; reason: string; decidedAt: Date }
    >();
    for (const row of rows) {
      latest.set(row.saleItemId, {
        classification: row.classification,
        reason: row.reason,
        decidedAt: row.decidedAt,
      });
    }
    return latest;
  }
}
