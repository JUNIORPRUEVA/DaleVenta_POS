import { Injectable } from "@nestjs/common";
import { type ProductItemType } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { dec, money } from "../fiscal-core/ecf-money";
import { fingerprint } from "../documents/ecf-document-idempotency.service";
import { effectiveLineClassification } from "../documents/ecf-line-classification.policy";
import type { EcfSaleSnapshot, EcfSaleSnapshotLine } from "./ecf-sale-adapter";
import {
  assertBuyerForDocumentType,
  assertIssuerComplete,
  assertSaleEligible,
  fiscalFailure,
  goodServiceFor,
  reconcileSaleTotals,
  taxCategoryFor,
  toCents,
  type EcfFiscalResult,
} from "./ecf-sale-fiscal.policy";

export type EcfSaleFiscalSnapshot = {
  saleId: string;
  companyId: string;
  documentType: "E31" | "E32";
  snapshot: EcfSaleSnapshot;
  /** Evidencia de la validación, para auditar qué se leyó y cuándo. */
  evidence: {
    saleId: string;
    companyId: string;
    itemCount: number;
    currency: string;
    resolvedAt: string;
    snapshotFingerprint: string;
    totals: EcfSaleSnapshot["totals"];
  };
};

const SUPPORTED_TYPES = ["E31", "E32"] as const;

/**
 * Adaptador autoritativo venta → snapshot fiscal electrónico.
 *
 * Lee la venta desde PostgreSQL (fuente única de verdad) y la traduce usando
 * EXCLUSIVAMENTE datos persistidos:
 *
 * - dosificación de impuestos: `SaleItem.taxRate` / `taxExempt`;
 * - bien o servicio: `Product.itemType` (única fuente declarada);
 * - totales: los de la venta, verificados contra la suma de partidas;
 * - emisor y receptor: las instantáneas guardadas en la venta.
 *
 * Nunca modifica la venta, nunca recalcula impuestos y nunca inventa una
 * clasificación: si falta un dato obligatorio devuelve un error estructurado y
 * la preparación queda bloqueada.
 */
@Injectable()
export class EcfSaleFiscalAdapter {
  constructor(private readonly prisma: PrismaService) {}

  async build(
    user: TenantUser,
    input: {
      saleId: string;
      documentType: "E31" | "E32";
      currency?: "DOP" | "USD" | "EUR";
    },
  ): Promise<EcfFiscalResult<EcfSaleFiscalSnapshot>> {
    const companyId = requireTenant(user);
    if (!SUPPORTED_TYPES.includes(input.documentType)) {
      return fiscalFailure(
        "ECF_DOCUMENT_TYPE_UNSUPPORTED",
        "Solo E31 y E32 se preparan desde una venta; E34 se prepara como nota de crédito.",
      );
    }

    // El filtro por companyId es lo que impide leer una venta de otra empresa:
    // un identificador ajeno se comporta igual que uno inexistente.
    const sale = await this.prisma.sale.findFirst({
      where: { id: input.saleId, companyId },
      include: {
        items: {
          orderBy: { createdAt: "asc" },
        },
        customer: {
          select: {
            taxId: true,
            businessName: true,
            nombre: true,
            direccion: true,
            telefono: true,
            email: true,
          },
        },
      },
    });
    if (!sale) {
      return fiscalFailure(
        "ECF_SALE_NOT_FOUND",
        "La venta no existe para esta empresa.",
      );
    }

    const eligible = assertSaleEligible({
      isDeleted: sale.isDeleted,
      cancelledAt: sale.cancelledAt,
      refundedSaleId: sale.refundedSaleId,
      itemCount: sale.items.length,
    });
    if (!eligible.ok) return eligible;

    const issuer = assertIssuerComplete({
      legalName: sale.issuerNameSnapshot,
      taxId: sale.issuerTaxIdSnapshot,
      address: sale.issuerAddressSnapshot,
    });
    if (!issuer.ok) return issuer;

    const buyer = {
      taxId: sale.fiscalCustomerTaxId ?? sale.customer?.taxId ?? null,
      legalName:
        sale.fiscalCustomerName ??
        sale.customer?.businessName ??
        sale.customer?.nombre ??
        null,
      address: sale.customerAddressSnapshot ?? sale.customer?.direccion ?? null,
      phone: sale.customerPhoneSnapshot ?? sale.customer?.telefono ?? null,
      email: sale.customer?.email ?? null,
    };
    const buyerCheck = assertBuyerForDocumentType(input.documentType, buyer);
    if (!buyerCheck.ok) return buyerCheck;

    const reconciliation = reconcileSaleTotals({
      lines: sale.items.map((item) => ({
        grossAmount: item.grossAmount.toString(),
        lineDiscountAmount: item.lineDiscountAmount.toString(),
        taxableBase: item.taxableBase.toString(),
        exemptAmount: item.exemptAmount.toString(),
        taxAmount: item.taxAmount.toString(),
      })),
      totals: {
        taxableBase: sale.taxableBase.toString(),
        exemptAmount: sale.exemptAmount.toString(),
        discountAmount: sale.discountAmount.toString(),
        taxAmount: sale.taxAmount.toString(),
        total: sale.totalSold.toString(),
      },
    });
    if (!reconciliation.ok) return reconciliation;

    const lines: EcfSaleSnapshotLine[] = [];
    // Clasificaciones supervisadas de las partidas que no tienen producto, en
    // UNA sola consulta y sin tocar la venta. Solo aplican cuando la venta no
    // congeló una clasificación propia.
    const supervised = await this.supervisedClassifications(
      companyId,
      sale.items
        .filter((item) => item.itemTypeSnapshot === null)
        .map((item) => item.id),
    );
    for (const item of sale.items) {
      // La clasificación CONGELADA en la venta manda siempre. Si falta, se usa
      // la supervisada (una decisión humana, fechada y auditada). Leer el
      // producto actual NO es evidencia histórica de cómo se emitió la venta.
      const effective = effectiveLineClassification({
        frozenSnapshot: item.itemTypeSnapshot,
        supervised: supervised.get(item.id) ?? null,
      });
      if (effective === null) {
        return fiscalFailure(
          "ECF_LINE_CLASSIFICATION_UNCONFIRMED",
          "Una partida no tiene clasificación fiscal (bien o servicio) y no se adivina. Un usuario autorizado debe confirmarla antes de preparar el comprobante.",
        );
      }
      const classification = goodServiceFor(effective);
      if (!classification.ok) return classification;
      const category = taxCategoryFor({
        taxExempt: item.taxExempt,
        taxRate: item.taxRate.toString(),
      });
      if (!category.ok) return category;

      // El contrato fiscal exige precio unitario SIN impuesto y descuento
      // aparte: `cantidad * unitPrice - descuento` debe reproducir la base neta
      // persistida de la partida. Se DERIVA de lo guardado (base + descuento);
      // el impuesto no se recalcula aquí. Si la división no reproduce el
      // importe exactamente al céntimo, se bloquea en vez de emitir un
      // comprobante incoherente.
      const netCents =
        toCents(item.taxableBase.toString()) + toCents(item.exemptAmount.toString());
      const quantity = dec(item.qty);
      if (quantity.isZero() || quantity.isNegative()) {
        return fiscalFailure(
          "ECF_LINE_QUANTITY_INVALID",
          "Una partida tiene cantidad cero o negativa.",
        );
      }
      const unitPrice = dec(netCents + toCents(item.lineDiscountAmount.toString()))
        .div(100)
        .div(quantity);
      const reproduced = money(
        quantity.mul(unitPrice).minus(item.lineDiscountAmount.toString()),
      );
      const expectedNet = money(dec(netCents).div(100));
      if (!reproduced.eq(expectedNet)) {
        return fiscalFailure(
          "ECF_LINE_AMOUNT_NOT_REPRESENTABLE",
          "Una partida no admite un precio unitario y un descuento coherentes con su base persistida.",
        );
      }

      lines.push({
        name: item.productNameSnapshot,
        quantity: item.qty.toString(),
        unitPrice: unitPrice.toFixed(10),
        discountAmount: item.lineDiscountAmount.toString(),
        taxCategory: category.value,
        goodServiceIndicator: classification.value,
      });
    }

    const issueDate = sale.saleDate.toISOString().slice(0, 10);
    // Sistema de una sola moneda. `Sale` no persiste moneda y el resto del
    // esquema fija DOP (p. ej. `PurchaseInvoice.currency @default("DOP")`).
    const currency = input.currency ?? "DOP";
    const snapshot: EcfSaleSnapshot = {
      type: input.documentType,
      issueDate,
      currency,
      seller: {
        legalName: sale.issuerNameSnapshot ?? "",
        taxId: sale.issuerTaxIdSnapshot ?? "",
        address: sale.issuerAddressSnapshot ?? undefined,
        phone: sale.issuerPhoneSnapshot ?? undefined,
        email: sale.issuerEmailSnapshot ?? undefined,
      },
      buyer: {
        legalName: buyer.legalName ?? undefined,
        taxId: buyer.taxId ?? undefined,
        address: buyer.address ?? undefined,
        phone: buyer.phone ?? undefined,
        email: buyer.email ?? undefined,
      },
      lines,
      totals: reconciliation.value.totals,
    };

    return {
      ok: true,
      value: {
        saleId: sale.id,
        companyId,
        documentType: input.documentType,
        snapshot,
        evidence: {
          saleId: sale.id,
          companyId,
          itemCount: lines.length,
          currency,
          resolvedAt: new Date().toISOString(),
          snapshotFingerprint: fingerprint(snapshot),
          totals: snapshot.totals,
        },
      },
    };
  }

  /**
   * Última clasificación supervisada de cada partida, si existe.
   *
   * La tabla es APPEND-ONLY —corregir es añadir otro registro—, así que se
   * recorre en orden ascendente y el último valor leído es el vigente. Se
   * desempata por `id` para que el resultado sea determinista aunque dos
   * registros compartan marca de tiempo.
   */
  private async supervisedClassifications(
    companyId: string,
    saleItemIds: string[],
  ): Promise<Map<string, ProductItemType>> {
    if (saleItemIds.length === 0) return new Map();
    const rows = await this.prisma.ecfLineClassification.findMany({
      where: { companyId, saleItemId: { in: saleItemIds } },
      orderBy: [{ decidedAt: "asc" }, { id: "asc" }],
      select: { saleItemId: true, classification: true },
    });
    const latest = new Map<string, ProductItemType>();
    for (const row of rows) latest.set(row.saleItemId, row.classification);
    return latest;
  }
}
