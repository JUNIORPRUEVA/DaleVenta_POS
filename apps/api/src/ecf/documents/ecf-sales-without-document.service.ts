import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import {
  ECF_WITHOUT_DOCUMENT_ERRORS,
  canRegisterSaleWithoutDocument,
  normalizeExpectedDocumentType,
  validateWithoutDocumentReason,
} from "./ecf-sales-without-document.policy";

export type RegisterSaleWithoutDocumentInput = {
  saleId: string;
  reason: string;
  expectedDocumentType?: string | null;
};

/**
 * Registro de ventas hechas SIN comprobante electrónico.
 *
 * Es la contraparte obligatoria de la opción «Normal» del POS: la empresa la
 * habilita y solo entonces se acepta el registro, pero cada uso queda como
 * evidencia (venta, motivo, usuario, fecha). Sin este registro, «Normal» sería un
 * botón; con él, es una excepción declarada y auditable.
 *
 * Reglas que NO se relajan:
 *  - `companyId` sale del contexto autenticado y la venta se busca siempre con
 *    `{ companyId, id }`, así que un id ajeno se comporta como inexistente.
 *  - Una venta que YA tiene comprobante fiscal (NCF legado o e-CF) no se registra
 *    como «sin comprobante»: sería un registro falso.
 *  - Una fila por venta; repetir la petición devuelve la existente en lugar de
 *    duplicar la evidencia.
 */
@Injectable()
export class EcfSalesWithoutDocumentService {
  constructor(private readonly prisma: PrismaService) {}

  async register(user: TenantUser, input: RegisterSaleWithoutDocumentInput) {
    const companyId = requireTenant(user);

    const config = await this.prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
      select: { enabled: true, allowSalesWithoutEcf: true },
    });
    const allowed = canRegisterSaleWithoutDocument(config);
    if (!allowed.ok) {
      throw new ConflictException(`${allowed.code}: ${allowed.message}`);
    }

    const validatedReason = validateWithoutDocumentReason(input.reason);
    if (!validatedReason.ok) {
      throw new BadRequestException(
        `${validatedReason.code}: ${validatedReason.message}`,
      );
    }

    const expected = normalizeExpectedDocumentType(input.expectedDocumentType);
    if (!expected.ok) throw new BadRequestException(expected.code);

    const sale = await this.prisma.sale.findFirst({
      where: { companyId, id: input.saleId },
      select: { id: true, fiscalVoucherType: true },
    });
    if (!sale) {
      throw new NotFoundException(
        `${ECF_WITHOUT_DOCUMENT_ERRORS.saleNotFound}: La venta no existe para esta empresa.`,
      );
    }
    if (sale.fiscalVoucherType) {
      throw new ConflictException(
        `${ECF_WITHOUT_DOCUMENT_ERRORS.saleHasDocument}: La venta ya tiene el ` +
          `comprobante ${sale.fiscalVoucherType}; no se registra como venta sin comprobante.`,
      );
    }

    const existingDocument = await this.prisma.ecfElectronicDocument.findFirst({
      where: { companyId, sourceType: "SALE", sourceId: sale.id },
      select: { documentType: true },
    });
    if (existingDocument) {
      throw new ConflictException(
        `${ECF_WITHOUT_DOCUMENT_ERRORS.saleHasDocument}: La venta ya tiene un ` +
          `comprobante ${existingDocument.documentType} preparado.`,
      );
    }

    try {
      const created = await this.prisma.ecfSaleWithoutDocument.create({
        data: {
          companyId,
          saleId: sale.id,
          reason: validatedReason.reason,
          expectedDocumentType: expected.value,
          registeredByUserId: user.id ?? null,
        },
      });
      return this.toView(created);
    } catch (error) {
      // Reintento de la misma operación: se devuelve la evidencia ya guardada en
      // lugar de duplicarla o de fallar por una carrera con el mismo vendedor.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const existing = await this.prisma.ecfSaleWithoutDocument.findUnique({
          where: { companyId_saleId: { companyId, saleId: sale.id } },
        });
        if (existing) return this.toView(existing);
      }
      throw error;
    }
  }

  /** Últimas excepciones registradas por la empresa, más recientes primero. */
  async list(user: TenantUser, limit = 100) {
    const companyId = requireTenant(user);
    const take = Number.isInteger(limit) ? Math.min(Math.max(limit, 1), 200) : 100;
    const rows = await this.prisma.ecfSaleWithoutDocument.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take,
    });
    return { items: rows.map((row) => this.toView(row)) };
  }

  private toView(row: {
    id: string;
    saleId: string;
    reason: string;
    expectedDocumentType: string | null;
    registeredByUserId: string | null;
    createdAt: Date;
  }) {
    return {
      id: row.id,
      saleId: row.saleId,
      reason: row.reason,
      expectedDocumentType: row.expectedDocumentType,
      registeredByUserId: row.registeredByUserId,
      createdAt: row.createdAt,
    };
  }
}
