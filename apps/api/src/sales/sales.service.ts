import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  Optional,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { InventoryMovementType, Prisma, ProductSource, Role } from "@prisma/client";
import crypto from "node:crypto";
import * as fs from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import * as path from "node:path";
import { PrismaService } from "../prisma/prisma.service";
import { CatalogRealtimeRelayService } from "../products/catalog-realtime-relay.service";
import { TaxService } from "../tax/tax.service";
import {
  DEFAULT_UNIT_OF_MEASURE,
  unitSnapshotFields,
  validateQuantityForUnit,
  type UnitOfMeasureSnapshot,
} from "../products/unit-of-measure.util";
import { NcfService } from "../tax/ncf.service";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import {
  CreateSaleDto,
  CreateSaleItemDto,
  CreateSaleReturnDto,
} from "./dto/create-sale.dto";
import { CreateSalePdfShareLinkDto } from "./dto/create-sale-pdf-share-link.dto";
import { deriveCashTenderChange } from "./cash-change.util";
import { InventoryMutationService } from "../inventory/inventory-mutation.service";
import {
  TerminalResolutionService,
  type OperationalTerminalContext,
} from "../terminals/terminal-resolution.service";

type NormalizedSaleItem = {
  productId: string | null;
  productSource: ProductSource | null;
  sourceProductId: string | null;
  productNameSnapshot: string;
  productImageSnapshot: string | null;
  qty: Prisma.Decimal;
  unitCodeSnapshot: string;
  unitNameSnapshot: string;
  unitSymbolSnapshot: string;
  unitPrecisionSnapshot: number;
  priceSoldUnit: Prisma.Decimal;
  originalUnitPriceSnapshot?: Prisma.Decimal;
  costUnitSnapshot: Prisma.Decimal;
  subtotalSold: Prisma.Decimal;
  subtotalCost: Prisma.Decimal;
  profit: Prisma.Decimal;
  taxTreatment: "INHERIT" | "TAXABLE" | "EXEMPT";
  taxRate: Prisma.Decimal | null;
  taxPriceMode: "NO_TAX" | "TAX_ADDED" | "TAX_INCLUDED" | null;
  grossAmount?: Prisma.Decimal;
  lineDiscountAmount?: Prisma.Decimal;
  taxableBase?: Prisma.Decimal;
  taxAmount?: Prisma.Decimal;
  exemptAmount?: Prisma.Decimal;
  taxIncluded?: boolean;
  taxExempt?: boolean;
  lineTotal?: Prisma.Decimal;
};

type ResolvedSaleWarehouse = {
  id: string;
  name: string;
  code: string;
};

const SALE_TRANSACTION_OPTIONS = { maxWait: 10000, timeout: 20000 } as const;
const SALE_RETURN_TRANSACTION_OPTIONS = {
  maxWait: 10000,
  timeout: 30000,
} as const;

@Injectable()
export class SalesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly taxes: TaxService,
    private readonly ncf: NcfService,
    @Optional()
    private readonly inventoryMutations?: InventoryMutationService,
    @Optional()
    private readonly terminalResolution?: TerminalResolutionService,
  ) {}

  private saleInclude() {
    return {
      customer: {
        select: {
          id: true,
          nombre: true,
          telefono: true,
          taxId: true,
          businessName: true,
          taxIdType: true,
        },
      },
      user: {
        select: {
          id: true,
          nombreCompleto: true,
          email: true,
        },
      },
      items: {
        include: {
          product: {
            select: {
              categoria: true,
              taxTreatment: true,
              taxRate: true,
              taxPriceMode: true,
              unitOfMeasure: {
                select: {
                  code: true,
                  name: true,
                  symbol: true,
                  allowDecimals: true,
                  precision: true,
                },
              },
            },
          },
        },
      },
      creditPayments: {
        orderBy: { paidAt: "desc" },
      },
    } satisfies Prisma.SaleInclude;
  }

  private compatibleSaleListSelect() {
    return {
      id: true,
      userId: true,
      customerId: true,
      saleDate: true,
      note: true,
      totalSold: true,
      totalCost: true,
      totalProfit: true,
      commissionAmount: true,
      paymentMethod: true,
      paymentCashAmount: true,
      paymentTransferAmount: true,
      creditAmount: true,
      creditPaidAmount: true,
      creditBalance: true,
      creditStatus: true,
      isDeleted: true,
      deletedAt: true,
    } satisfies Prisma.SaleSelect;
  }

  private async findManySalesWithFallback(
    where: Prisma.SaleWhereInput,
    include: Prisma.SaleInclude,
    limit?: number,
  ) {
    const take = limit && limit > 0 ? limit : undefined;
    try {
      return await this.prisma.sale.findMany({
        where,
        orderBy: { saleDate: "desc" },
        take,
        include,
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      return this.prisma.sale.findMany({
        where,
        orderBy: { saleDate: "desc" },
        take,
        select: this.compatibleSaleListSelect(),
      });
    }
  }

  private isSchemaMismatch(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === "P2021" || error.code === "P2022";
    }

    if (typeof error === "object" && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === "string" ? value.code : "";
      const message = typeof value.message === "string" ? value.message : "";
      return (
        code === "P2021" ||
        code === "P2022" ||
        message.includes("does not exist in the current database") ||
        message.toLowerCase().includes("column")
      );
    }

    return false;
  }

  private inventoryMutationService() {
    return this.inventoryMutations ?? new InventoryMutationService(this.prisma);
  }

  private terminalResolutionService() {
    return this.terminalResolution ?? new TerminalResolutionService(this.prisma);
  }

  private async resolveLegacyCancellationWarehouse(
    tx: Prisma.TransactionClient,
    companyId: string,
  ): Promise<ResolvedSaleWarehouse> {
    const zeroConfigState = await tx.inventoryZeroConfigState.findUnique({
      where: { companyId },
      select: { status: true, warehouseId: true },
    });
    if (zeroConfigState?.status !== "completed") {
      throw new BadRequestException(
        "La venta historica no tiene almacen y la compania no tiene backfill W3 completado.",
      );
    }

    const warehouse = zeroConfigState.warehouseId
      ? await tx.warehouse.findFirst({
          where: { id: zeroConfigState.warehouseId, companyId, isActive: true },
          select: { id: true, name: true, code: true },
        })
      : (
          await this.terminalResolutionService().resolveForSale(tx, {
            companyId,
          })
        ).warehouse;
    if (!warehouse) {
      throw new BadRequestException(
        "No se encontro el almacen legacy W3 para restaurar la venta.",
      );
    }
    return warehouse;
  }

  private async returnQuantityMaps(
    tx: Prisma.TransactionClient,
    companyId: string,
    saleId: string,
    originalSaleItemIds: string[],
  ) {
    const zero = () => new Prisma.Decimal(0);
    const financialReturned = new Map<string, Prisma.Decimal>();
    const inventoryReturned = new Map<string, Prisma.Decimal>();
    if (originalSaleItemIds.length === 0) {
      return { financialReturned, inventoryReturned };
    }

    const financialRows = await tx.saleItem.groupBy({
      by: ["refundedSaleItemId"],
      where: {
        refundedSaleItemId: { in: originalSaleItemIds },
        sale: {
          companyId,
          refundedSaleId: saleId,
          kind: "refund",
          isDeleted: false,
        },
      },
      _sum: { qty: true },
    });
    for (const row of financialRows) {
      if (!row.refundedSaleItemId) continue;
      financialReturned.set(
        row.refundedSaleItemId,
        new Prisma.Decimal(row._sum.qty ?? 0),
      );
    }

    const refundItems = await tx.saleItem.findMany({
      where: {
        refundedSaleItemId: { in: originalSaleItemIds },
        sale: {
          companyId,
          refundedSaleId: saleId,
          kind: "refund",
          isDeleted: false,
        },
      },
      select: { id: true, refundedSaleItemId: true },
    });
    const refundItemToOriginal = new Map(
      refundItems
        .filter((item) => item.refundedSaleItemId)
        .map((item) => [item.id, item.refundedSaleItemId!]),
    );

    if (refundItemToOriginal.size > 0) {
      const movementRows = await tx.inventoryMovement.groupBy({
        by: ["sourceItemId"],
        where: {
          companyId,
          type: InventoryMovementType.RETURN,
          sourceItemId: { in: [...refundItemToOriginal.keys()] },
        },
        _sum: { quantityDelta: true },
      });
      for (const row of movementRows) {
        if (!row.sourceItemId) continue;
        const originalItemId = refundItemToOriginal.get(row.sourceItemId);
        if (!originalItemId) continue;
        inventoryReturned.set(
          originalItemId,
          (inventoryReturned.get(originalItemId) ?? zero()).plus(
            row._sum.quantityDelta ?? 0,
          ),
        );
      }
    }

    const legacyMovementRows = await tx.inventoryMovement.groupBy({
      by: ["sourceItemId"],
      where: {
        companyId,
        type: InventoryMovementType.RETURN,
        sourceType: "SALE_RETURN",
        sourceId: saleId,
        sourceItemId: { in: originalSaleItemIds },
      },
      _sum: { quantityDelta: true },
    });
    for (const row of legacyMovementRows) {
      if (!row.sourceItemId) continue;
      inventoryReturned.set(
        row.sourceItemId,
        (inventoryReturned.get(row.sourceItemId) ?? zero()).plus(
          row._sum.quantityDelta ?? 0,
        ),
      );
    }

    return { financialReturned, inventoryReturned };
  }

  private async lockReturnableSale(
    tx: Prisma.TransactionClient,
    companyId: string,
    saleId: string,
  ) {
    const executeRawUnsafe = (tx as unknown as {
      $executeRawUnsafe?: (query: string, ...values: unknown[]) => Promise<unknown>;
    }).$executeRawUnsafe;
    if (!executeRawUnsafe) return;
    await executeRawUnsafe.call(
      tx,
      "SELECT pg_advisory_xact_lock(hashtext($1))",
      `${companyId}:${saleId}`,
    );
  }

  private resolveUploadDir() {
    const fromEnv = (this.config.get<string>("UPLOAD_DIR") ?? "").trim();
    const volumeDir = "/uploads";
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv) {
      if ((fromEnv === "./uploads" || fromEnv === "uploads") && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    return volumeExists ? volumeDir : path.join(process.cwd(), "uploads");
  }

  private publicBaseUrl(requestBaseUrl?: string) {
    const raw =
      (this.config.get<string>("PUBLIC_BASE_URL") ?? "").trim() ||
      (this.config.get<string>("API_BASE_URL") ?? "").trim() ||
      (process.env.PUBLIC_BASE_URL ?? "").trim() ||
      (process.env.API_BASE_URL ?? "").trim() ||
      (requestBaseUrl ?? "").trim();

    return raw.replace(/\/+$/, "");
  }

  private sanitizePdfFileName(value: string, fallback: string) {
    const source = (value || fallback).trim() || fallback;
    const base = path
      .basename(source)
      .replace(/[^a-zA-Z0-9._-]+/g, "_")
      .replace(/^_+|_+$/g, "");
    const withExt = base.toLowerCase().endsWith(".pdf") ? base : `${base}.pdf`;
    return withExt || fallback;
  }

  private parsePdfBase64(value: string) {
    const trimmed = (value ?? "").trim();
    if (!trimmed) {
      throw new BadRequestException("Debes enviar el PDF de la factura.");
    }

    const base64 = trimmed.startsWith("data:")
      ? trimmed.slice(trimmed.indexOf(",") + 1)
      : trimmed;

    const bytes = Buffer.from(base64, "base64");
    if (!bytes.length) {
      throw new BadRequestException("El PDF de la factura llegó vacío.");
    }

    const maxPdfBytes = 8 * 1024 * 1024;
    if (bytes.length > maxPdfBytes) {
      throw new BadRequestException(
        "El PDF de la factura supera el límite de 8 MB.",
      );
    }

    return bytes;
  }

  async resolvePublicInvoicePdfDownload(saleId: string, fileName: string) {
    const safeSaleId = (saleId ?? "").trim();
    const safeFileName = this.sanitizePdfFileName(
      fileName ?? "",
      "factura.pdf",
    );
    if (!safeSaleId || safeSaleId.includes("/") || safeSaleId.includes("\\")) {
      throw new NotFoundException("PDF de factura no encontrado.");
    }

    const absolutePath = path.join(
      this.resolveUploadDir(),
      "facturas",
      safeSaleId,
      safeFileName,
    );

    if (!fs.existsSync(absolutePath)) {
      throw new NotFoundException("PDF de factura no encontrado.");
    }

    return {
      absolutePath,
      fileName: safeFileName,
    };
  }

  async listMine(
    user: TenantUser,
    from?: string,
    to?: string,
    customerId?: string,
    includeDeleted = false,
    limit?: number,
  ) {
    const companyId = requireTenant(user);
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      companyId,
      ...(includeDeleted ? {} : { isDeleted: false }),
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    const include = this.saleInclude();
    return this.findManySalesWithFallback(
      where,
      {
        customer: include.customer,
        user: include.user,
        items: include.items,
      },
      limit,
    );
  }

  async listInvoices(
    user: TenantUser,
    from?: string,
    to?: string,
    customerId?: string,
    includeDeleted = false,
    limit?: number,
  ) {
    const companyId = requireTenant(user);
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      companyId,
      ...(includeDeleted ? {} : { isDeleted: false }),
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    return this.findManySalesWithFallback(where, this.saleInclude(), limit);
  }

  async listByUser(
    user: TenantUser,
    userId: string,
    from?: string,
    to?: string,
    customerId?: string,
    includeDeleted = false,
  ) {
    const companyId = requireTenant(user);
    const normalizedUserId = userId?.trim();
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      companyId,
      ...(normalizedUserId ? { userId: normalizedUserId } : {}),
      ...(includeDeleted ? {} : { isDeleted: false }),
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    return this.prisma.sale.findMany({
      where,
      orderBy: { saleDate: "desc" },
      include: this.saleInclude(),
    });
  }

  async summaryMine(
    user: TenantUser,
    from?: string,
    to?: string,
    customerId?: string,
  ) {
    const companyId = requireTenant(user);
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      companyId,
      isDeleted: false,
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    let aggregate: {
      _sum: {
        totalSold: Prisma.Decimal | null;
        totalCost: Prisma.Decimal | null;
        totalProfit: Prisma.Decimal | null;
        commissionAmount: Prisma.Decimal | null;
      };
    } = {
      _sum: {
        totalSold: null,
        totalCost: null,
        totalProfit: null,
        commissionAmount: null,
      },
    };
    let totalSales = 0;

    try {
      [aggregate, totalSales] = await Promise.all([
        this.prisma.sale.aggregate({
          where,
          _sum: {
            totalSold: true,
            totalCost: true,
            totalProfit: true,
            commissionAmount: true,
          },
        }),
        this.prisma.sale.count({ where }),
      ]);
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
    }

    return {
      totalSales,
      totalSold: this.toNumber(aggregate._sum.totalSold),
      totalCost: this.toNumber(aggregate._sum.totalCost),
      totalProfit: this.toNumber(aggregate._sum.totalProfit),
      totalCommission: this.toNumber(aggregate._sum.commissionAmount),
      commissionRate: 0.1,
    };
  }

  async summaryByUser(
    user: TenantUser,
    from?: string,
    to?: string,
    userId?: string,
  ) {
    const companyId = requireTenant(user);
    const where: Prisma.SaleWhereInput = {
      companyId,
      isDeleted: false,
      ...(userId ? { userId } : {}),
      ...this.buildDateRange(from, to),
    };

    let grouped: Array<{
      userId: string;
      _sum: {
        totalSold: Prisma.Decimal | null;
        totalProfit: Prisma.Decimal | null;
        commissionAmount: Prisma.Decimal | null;
      };
      _count: { _all: number };
    }> = [];

    try {
      const groupedResult = await this.prisma.sale.groupBy({
        by: ["userId"],
        where,
        _sum: {
          totalSold: true,
          totalProfit: true,
          commissionAmount: true,
        },
        _count: {
          _all: true,
        },
      });
      grouped = groupedResult as typeof grouped;
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      grouped = [];
    }

    const userIds = grouped.map((group) => group.userId);
    let users: Array<{ id: string; email: string; nombreCompleto: string }> =
      [];
    if (userIds.length) {
      try {
        users = await this.prisma.user.findMany({
          where: { id: { in: userIds } },
          select: { id: true, email: true, nombreCompleto: true },
        });
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        users = [];
      }
    }

    const userMap = new Map(users.map((user) => [user.id, user]));

    const items = grouped.map((group) => {
      const user = userMap.get(group.userId);
      return {
        userId: group.userId,
        userName: user?.nombreCompleto ?? "Usuario",
        userEmail: user?.email ?? "",
        totalSales: group._count._all,
        totalSold: this.toNumber(group._sum.totalSold),
        totalProfit: this.toNumber(group._sum.totalProfit),
        totalCommission: this.toNumber(group._sum.commissionAmount),
      };
    });

    const totals = items.reduce(
      (acc, row) => {
        acc.totalSales += row.totalSales;
        acc.totalSold += row.totalSold;
        acc.totalProfit += row.totalProfit;
        acc.totalCommission += row.totalCommission;
        return acc;
      },
      { totalSales: 0, totalSold: 0, totalProfit: 0, totalCommission: 0 },
    );

    return { items, totals, commissionRate: 0.1 };
  }

  async create(user: TenantUser, dto: CreateSaleDto) {
    const companyId = requireTenant(user);
    if (!dto.items.length) {
      throw new BadRequestException("La venta requiere al menos 1 item");
    }

    const sourceQuotationId = dto.sourceQuotationId?.trim() || null;
    const sourceQuotation = sourceQuotationId
      ? await this.prisma.cotizacion.findFirst({
          where: { id: sourceQuotationId, companyId },
          include: { items: { orderBy: { createdAt: "asc" } } },
        })
      : null;
    if (sourceQuotationId && !sourceQuotation) {
      throw new BadRequestException("Cotización inválida para esta empresa.");
    }

    if (sourceQuotationId) {
      const existingFromQuotation = await this.prisma.sale.findFirst({
        where: {
          companyId,
          sourceQuotationId,
          kind: "invoice",
          isDeleted: false,
        },
        include: this.saleInclude(),
      });
      if (existingFromQuotation) return existingFromQuotation;
    }

    const customerId =
      dto.customerId?.trim() || sourceQuotation?.customerId || null;
    const clientRequestId = dto.clientRequestId?.trim() || null;
    const saleOccurredAt = this.resolveSaleOccurredAt(dto.saleOccurredAt);

    if (clientRequestId) {
      const existing = await this.prisma.sale.findFirst({
        where: { companyId, clientRequestId },
        include: this.saleInclude(),
      });
      if (existing) return existing;
    }

    let customerFiscalSnapshot: {
      nombre: string;
      telefono: string;
      taxId: string | null;
      businessName: string | null;
      direccion: string | null;
    } | null = null;
    if (customerId) {
      try {
        const customer = await this.prisma.client.findFirst({
          where: { id: customerId, companyId, isDeleted: false },
          select: {
            nombre: true,
            telefono: true,
            taxId: true,
            businessName: true,
            direccion: true,
          },
        });
        if (!customer) {
          throw new BadRequestException("Cliente inválido");
        }
        customerFiscalSnapshot = customer;
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
      }
    }

    const [companySnapshot, appConfigSnapshot] = await Promise.all([
      this.prisma.company.findFirst({
        where: { id: companyId },
        select: { name: true },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: {
          companyName: true,
          rnc: true,
          address: true,
          phone: true,
        },
      }),
    ]);
    const issuerNameSnapshot =
      appConfigSnapshot?.companyName?.trim() ||
      companySnapshot?.name?.trim() ||
      null;
    const issuerTaxIdSnapshot = appConfigSnapshot?.rnc?.trim() || null;
    const issuerAddressSnapshot = appConfigSnapshot?.address?.trim() || null;
    const issuerPhoneSnapshot = appConfigSnapshot?.phone?.trim() || null;
    const issuerEmailSnapshot = null;

    const productIds = Array.from(
      new Set(
        (sourceQuotation
          ? sourceQuotation.items.map((item) => item.productId)
          : dto.items.map((item) => item.productId)
        ).filter((id): id is string => Boolean(id)),
      ),
    );

    let products: Array<{
      id: string;
      nombre: string;
      imagen: string | null;
      costo: Prisma.Decimal;
      stock: Prisma.Decimal;
      taxTreatment: "INHERIT" | "TAXABLE" | "EXEMPT";
      taxRate: Prisma.Decimal | null;
      taxPriceMode: "NO_TAX" | "TAX_ADDED" | "TAX_INCLUDED" | null;
      unitOfMeasure: UnitOfMeasureSnapshot | null;
    }> = [];
    if (productIds.length) {
      try {
        products = await this.prisma.product.findMany({
          where: { id: { in: productIds }, companyId, archivedAt: null },
          select: {
            id: true,
            nombre: true,
            imagen: true,
            costo: true,
            stock: true,
            taxTreatment: true,
            taxRate: true,
            taxPriceMode: true,
            unitOfMeasure: {
              select: {
                code: true,
                name: true,
                symbol: true,
                allowDecimals: true,
                precision: true,
              },
            },
          },
        });
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        products = [];
      }
    }

    const productMap = new Map(
      products.map((product) => [product.id, product]),
    );

    let normalizedItems: NormalizedSaleItem[] = sourceQuotation
      ? sourceQuotation.items.map((item) => {
          const qty = new Prisma.Decimal(item.qty);
          const priceSoldUnit = new Prisma.Decimal(item.unitPrice);
          const costUnitSnapshot = new Prisma.Decimal(
            item.costUnitSnapshot ?? 0,
          );
          const subtotalCost = item.subtotalCost ?? qty.mul(costUnitSnapshot);
          const lineTotal = new Prisma.Decimal(item.lineTotal);
          return {
            productId: item.productId,
            productSource: item.productSource,
            sourceProductId: item.sourceProductId,
            productNameSnapshot: item.productNameSnapshot,
            productImageSnapshot: item.productImageSnapshot,
            qty,
            unitCodeSnapshot: item.unitCodeSnapshot,
            unitNameSnapshot: item.unitNameSnapshot,
            unitSymbolSnapshot: item.unitSymbolSnapshot,
            unitPrecisionSnapshot: item.unitPrecisionSnapshot,
            priceSoldUnit,
            costUnitSnapshot,
            subtotalSold: lineTotal,
            subtotalCost,
            profit: lineTotal.minus(subtotalCost),
            taxTreatment: item.taxTreatment,
            taxRate: item.taxRate,
            taxPriceMode: item.taxPriceMode,
            grossAmount: item.grossAmount,
            lineDiscountAmount: item.lineDiscountAmount,
            taxableBase: item.taxableBase,
            taxAmount: item.taxAmount,
            exemptAmount: item.exemptAmount,
            taxIncluded: item.taxIncluded,
            taxExempt: item.taxExempt,
            lineTotal,
          };
        })
      : dto.items.map((item, index) =>
          this.normalizeItem(item, index, productMap),
        );

    this.assertNoUnsupportedExternalStockMutation(normalizedItems);

    const fiscalSettings = await this.taxes.getCompanyFiscalSettings(companyId);
    const defaultPriceMode = this.taxes.resolvePriceMode(fiscalSettings);
    const taxCalculation = sourceQuotation
      ? (() => {
          const totalRealLineDiscount = normalizedItems.reduce(
            (sum, item) =>
              sum.plus(new Prisma.Decimal(item.lineDiscountAmount ?? 0)),
            new Prisma.Decimal(0),
          );
          const generalDiscount = new Prisma.Decimal(
            sourceQuotation.globalDiscountAmount ?? 0,
          );
          return {
            total: new Prisma.Decimal(sourceQuotation.total),
            taxableBase: new Prisma.Decimal(sourceQuotation.taxableBase),
            taxAmount: new Prisma.Decimal(sourceQuotation.taxAmount),
            exemptAmount: new Prisma.Decimal(sourceQuotation.exemptAmount),
            discountAmount: totalRealLineDiscount.plus(generalDiscount),
            lines: normalizedItems.map((item, index) => ({
              index,
              grossAmount: new Prisma.Decimal(item.grossAmount ?? 0),
              discountAmount: new Prisma.Decimal(item.lineDiscountAmount ?? 0),
              taxableBase: new Prisma.Decimal(item.taxableBase ?? 0),
              taxRate: new Prisma.Decimal(item.taxRate ?? 0),
              taxAmount: new Prisma.Decimal(item.taxAmount ?? 0),
              exemptAmount: new Prisma.Decimal(item.exemptAmount ?? 0),
              taxIncluded: item.taxIncluded ?? false,
              taxExempt: item.taxExempt ?? false,
              lineTotal: new Prisma.Decimal(
                item.lineTotal ?? item.subtotalSold,
              ),
            })),
          };
        })()
      : this.taxes.calculatorService.calculate({
          taxEnabled: fiscalSettings.taxEnabled,
          defaultTaxRate: fiscalSettings.defaultTaxRate,
          defaultPriceMode,
          globalDiscountAmount: dto.globalDiscountAmount ?? 0,
          lines: normalizedItems.map((item) => ({
            description: item.productNameSnapshot,
            quantity: item.qty,
            unitPrice: item.priceSoldUnit,
            taxTreatment: item.taxTreatment,
            taxRate: item.taxRate ?? fiscalSettings.defaultTaxRate,
            priceMode: item.taxPriceMode ?? defaultPriceMode,
          })),
        });

    // Descuento COMERCIAL real por línea (ventas directas). Se separa del
    // prorrateo fiscal del descuento general (que calculate() guardaba en
    // lineDiscountAmount): el PDF solo muestra el descuento comercial.
    const directCommercialLineValues = sourceQuotation
      ? []
      : normalizedItems.map((item) => {
          const originalPrice =
            item.originalUnitPriceSnapshot ?? item.priceSoldUnit;
          const realGross = item.qty.mul(originalPrice);
          const realLineDiscount = Prisma.Decimal.max(
            new Prisma.Decimal(0),
            realGross.minus(item.qty.mul(item.priceSoldUnit)),
          );
          return { realGross, realLineDiscount };
        });
    const totalDirectCommercialLineDiscount = directCommercialLineValues.reduce(
      (sum, value) => sum.plus(value.realLineDiscount),
      new Prisma.Decimal(0),
    );

    let totalSold = sourceQuotation
      ? new Prisma.Decimal(sourceQuotation.total)
      : fiscalSettings.taxEnabled
        ? taxCalculation.total
        : new Prisma.Decimal(taxCalculation.discountAmount);
    let totalCost = new Prisma.Decimal(0);
    let totalProfit = new Prisma.Decimal(0);

    for (const item of normalizedItems) {
      if (!sourceQuotation && !fiscalSettings.taxEnabled) {
        totalSold = totalSold.plus(item.subtotalSold);
      }
      totalCost = totalCost.plus(item.subtotalCost);
    }
    totalProfit = totalSold.minus(totalCost);

    const expectedTotalSold =
      dto.expectedTotalSold === undefined || dto.expectedTotalSold === null
        ? null
        : new Prisma.Decimal(dto.expectedTotalSold).toDecimalPlaces(2);

    if (
      expectedTotalSold &&
      expectedTotalSold.greaterThanOrEqualTo(0) &&
      totalSold.greaterThan(0) &&
      !sourceQuotation &&
      !fiscalSettings.taxEnabled &&
      totalSold.minus(expectedTotalSold).abs().greaterThan(0.009)
    ) {
      let remainingSold = expectedTotalSold;
      normalizedItems = normalizedItems.map((item, index) => {
        const isLast = index === normalizedItems.length - 1;
        const nextSubtotalSold = isLast
          ? remainingSold
          : item.subtotalSold
              .div(totalSold)
              .mul(expectedTotalSold)
              .toDecimalPlaces(2);
        remainingSold = remainingSold.minus(nextSubtotalSold);
        const nextPriceSoldUnit = nextSubtotalSold
          .div(item.qty)
          .toDecimalPlaces(6);
        return {
          ...item,
          priceSoldUnit: nextPriceSoldUnit,
          subtotalSold: nextSubtotalSold,
          profit: nextSubtotalSold.minus(item.subtotalCost),
        };
      });

      totalSold = new Prisma.Decimal(0);
      totalCost = new Prisma.Decimal(0);
      totalProfit = new Prisma.Decimal(0);
      for (const item of normalizedItems) {
        totalSold = totalSold.plus(item.subtotalSold);
        totalCost = totalCost.plus(item.subtotalCost);
        totalProfit = totalProfit.plus(item.profit);
      }
    }
    if (
      sourceQuotation &&
      expectedTotalSold &&
      totalSold.minus(expectedTotalSold).abs().greaterThan(0.009)
    ) {
      throw new BadRequestException(
        "El total esperado no coincide con la cotización fiscal guardada.",
      );
    }

    totalSold = totalSold.toDecimalPlaces(2);
    totalCost = totalCost.toDecimalPlaces(2);
    const netTaxRevenue = taxCalculation.taxableBase.plus(
      taxCalculation.exemptAmount,
    );
    totalProfit = (
      sourceQuotation || fiscalSettings.taxEnabled
        ? netTaxRevenue.minus(totalCost)
        : totalProfit
    ).toDecimalPlaces(2);
    const commercialProfit = totalProfit;
    const netTaxProfit = totalProfit;
    const commercialMargin = totalSold.gt(0)
      ? commercialProfit.div(totalSold).toDecimalPlaces(4)
      : new Prisma.Decimal(0);
    const netTaxMargin = netTaxRevenue.gt(0)
      ? netTaxProfit.div(netTaxRevenue).toDecimalPlaces(4)
      : new Prisma.Decimal(0);

    const commissionRate = new Prisma.Decimal(0.1);
    const commissionAmount = totalProfit.greaterThan(0)
      ? totalProfit.mul(commissionRate)
      : new Prisma.Decimal(0);
    const activeSession = await this.prisma.cashSession.findFirst({
      where: {
        openedByUserId: user.id,
        companyId,
        status: "OPEN",
        closedAt: null,
      },
      orderBy: { openedAt: "desc" },
    });
    if (!activeSession) {
      throw new BadRequestException("Debes abrir caja antes de facturar.");
    }

    const requestedVoucherType = dto.fiscalVoucherType?.trim()
      ? this.ncf.normalizeType(dto.fiscalVoucherType)
      : null;
    const customerSnapshotTaxId = customerFiscalSnapshot?.taxId?.trim() || null;
    const customerSnapshotName =
      customerFiscalSnapshot?.nombre?.trim() ||
      customerFiscalSnapshot?.businessName?.trim() ||
      null;

    if (
      requestedVoucherType === "B01" &&
      (!customerId || !customerFiscalSnapshot)
    ) {
      throw new BadRequestException(
        "Para emitir un comprobante B01 debes seleccionar un cliente con RNC/Cédula y nombre.",
      );
    }

    const fiscalCustomerTaxId =
      customerSnapshotTaxId ||
      (requestedVoucherType === "B01"
        ? null
        : dto.fiscalCustomerTaxId?.trim()) ||
      null;
    const fiscalCustomerName =
      customerSnapshotName ||
      (requestedVoucherType === "B01"
        ? null
        : dto.fiscalCustomerName?.trim()) ||
      null;

    if (requestedVoucherType && !fiscalSettings.ncfEnabled) {
      throw new BadRequestException(
        "Los comprobantes fiscales no están activados para esta empresa.",
      );
    }

    if (fiscalSettings.ncfEnabled && requestedVoucherType) {
      this.taxes.calculatorService.validateFiscalCustomer({
        voucherType: requestedVoucherType,
        customerTaxId: fiscalCustomerTaxId,
        customerBusinessName: fiscalCustomerName,
      });
      if (
        requestedVoucherType === "B01" &&
        (!fiscalCustomerTaxId || !fiscalCustomerName)
      ) {
        throw new BadRequestException(
          "Para emitir un comprobante B01 debes seleccionar un cliente con RNC/Cédula y nombre.",
        );
      }
      if (requestedVoucherType === "B02") {
        // B02 is allowed for final consumers; customer fiscal data is optional.
      }
    }

    const payment = this.normalizeSalePayment(dto, totalSold);
    const {
      paymentMethod,
      paymentCashAmount,
      paymentTransferAmount,
      cashReceived,
      changeAmount,
      paidAmount,
      creditAmount,
      creditBalance,
    } = payment;

    try {
      const sale = await this.prisma.$transaction(async (tx) => {
        const operationalContext: OperationalTerminalContext | null =
          normalizedItems.some(
          (item) => item.productId,
        )
          ? await this.terminalResolutionService().resolveForSale(tx, {
              companyId,
              terminalId: dto.terminalId,
              deviceFingerprint: dto.deviceFingerprint,
              requestedWarehouseId: dto.warehouseId,
            })
          : null;

        const reservedNcf = requestedVoucherType
          ? await this.ncf.reserveNextNcf(tx, {
              companyId,
              userId: user.id,
              voucherType: requestedVoucherType,
            })
          : null;

        const sale = await tx.sale.create({
          data: {
            userId: user.id,
            companyId,
            clientRequestId,
            sourceQuotationId,
            customerId,
            cashSessionId: activeSession.id,
            terminalId: operationalContext?.terminal.id ?? null,
            terminalNameSnapshot: operationalContext?.terminal.name ?? null,
            terminalCodeSnapshot: operationalContext?.terminal.code ?? null,
            saleDate: saleOccurredAt,
            note: dto.note,
            paymentMethod,
            paymentCashAmount,
            paymentTransferAmount,
            cashReceived,
            changeAmount,
            creditAmount,
            creditPaidAmount: paidAmount,
            creditBalance,
            kind: "invoice",
            status:
              paymentMethod === "credit" && creditBalance.greaterThan(0)
                ? "CREDIT"
                : "PAID",
            creditStatus:
              paymentMethod === "credit"
                ? creditBalance.greaterThan(0)
                  ? "open"
                  : "paid"
                : "none",
            totalSold,
            fiscalTaxEnabled: sourceQuotation
              ? sourceQuotation.fiscalTaxEnabled
              : fiscalSettings.taxEnabled,
            fiscalPriceMode: sourceQuotation
              ? sourceQuotation.fiscalPriceMode
              : defaultPriceMode,
            taxableBase: taxCalculation.taxableBase,
            taxAmount: taxCalculation.taxAmount,
            exemptAmount: taxCalculation.exemptAmount,
            discountAmount: sourceQuotation
              ? taxCalculation.discountAmount
              : totalDirectCommercialLineDiscount.plus(
                  new Prisma.Decimal(taxCalculation.discountAmount),
                ),
            fiscalVoucherType: requestedVoucherType,
            ncf: reservedNcf?.ncf ?? null,
            ncfExpirationDate: reservedNcf?.validUntil ?? null,
            issuerNameSnapshot,
            issuerTaxIdSnapshot,
            issuerAddressSnapshot,
            issuerPhoneSnapshot,
            issuerEmailSnapshot,
            fiscalCustomerTaxId,
            fiscalCustomerName,
            customerAddressSnapshot:
              customerFiscalSnapshot?.direccion?.trim() || null,
            customerPhoneSnapshot:
              customerFiscalSnapshot?.telefono?.trim() || null,
            totalCost,
            totalProfit,
            commercialProfit,
            netTaxProfit,
            commercialMargin,
            netTaxMargin,
            commissionRate,
            commissionAmount,
          },
        });

        for (let index = 0; index < normalizedItems.length; index += 1) {
          const item = normalizedItems[index];
          const warehouseSnapshot = item.productId
            ? operationalContext?.warehouse
            : null;
          const saleItem = await tx.saleItem.create({
            data: {
              saleId: sale.id,
                ...(() => {
                  const taxLine = taxCalculation.lines[index];
                  const lineTotal = taxLine?.lineTotal ?? item.subtotalSold;
                  const itemNetTaxProfit = (
                    sourceQuotation || fiscalSettings.taxEnabled
                      ? (taxLine?.taxableBase ?? new Prisma.Decimal(0)).plus(
                          taxLine?.exemptAmount ?? new Prisma.Decimal(0),
                        )
                      : lineTotal
                  ).minus(item.subtotalCost);
                  const itemCommercialProfit = itemNetTaxProfit;
                  return {
                    grossAmount: sourceQuotation
                      ? (taxLine?.grossAmount ?? item.subtotalSold)
                      : directCommercialLineValues[index].realGross,
                    lineDiscountAmount: sourceQuotation
                      ? (taxLine?.discountAmount ?? new Prisma.Decimal(0))
                      : directCommercialLineValues[index].realLineDiscount,
                    taxableBase: taxLine?.taxableBase ?? new Prisma.Decimal(0),
                    taxRate: taxLine?.taxRate ?? new Prisma.Decimal(0),
                    taxAmount: taxLine?.taxAmount ?? new Prisma.Decimal(0),
                    exemptAmount: taxLine?.exemptAmount ?? item.subtotalSold,
                    taxIncluded: taxLine?.taxIncluded ?? false,
                    taxExempt: taxLine?.taxExempt ?? true,
                    subtotalSold: lineTotal,
                    profit: itemCommercialProfit,
                    commercialProfit: itemCommercialProfit,
                    netTaxProfit: itemNetTaxProfit,
                  };
                })(),
                productId: item.productId,
                productSource: item.productSource,
                sourceProductId: item.sourceProductId,
                warehouseId: warehouseSnapshot?.id ?? null,
                warehouseNameSnapshot: warehouseSnapshot?.name ?? null,
                warehouseCodeSnapshot: warehouseSnapshot?.code ?? null,
                productNameSnapshot: item.productNameSnapshot,
                productImageSnapshot: item.productImageSnapshot,
                qty: item.qty,
                unitCodeSnapshot: item.unitCodeSnapshot,
                unitNameSnapshot: item.unitNameSnapshot,
                unitSymbolSnapshot: item.unitSymbolSnapshot,
                unitPrecisionSnapshot: item.unitPrecisionSnapshot,
                priceSoldUnit: item.priceSoldUnit,
                costUnitSnapshot: item.costUnitSnapshot,
                subtotalCost: item.subtotalCost,
            },
          });

          if (item.productId && operationalContext) {
            await this.inventoryMutationService().decreaseStockInTransaction(tx, {
              companyId,
              productId: item.productId,
              warehouseId: operationalContext.warehouse.id,
              quantity: item.qty,
              type: InventoryMovementType.SALE,
              sourceType: "SALE",
              sourceId: sale.id,
              sourceItemId: saleItem.id,
              reason: "SALE",
              createdByUserId: user.id,
            });
          }
        }

        const createdSale = await tx.sale.findUniqueOrThrow({
          where: { id: sale.id },
          include: this.saleInclude(),
        });

        if (customerId) {
          await tx.client.update({
            where: { id: customerId },
            data: { lastActivityAt: createdSale.saleDate },
          });
        }

        if (reservedNcf) {
          await this.ncf.markIssued(tx, {
            companyId,
            sequenceId: reservedNcf.sequenceId,
            saleId: createdSale.id,
            userId: user.id,
            ncf: reservedNcf.ncf,
            type: reservedNcf.type,
          });
        }

        return createdSale;
      }, SALE_TRANSACTION_OPTIONS);
      this.emitSaleEvent(companyId, "sale.created", sale.id, {
        userId: user.id,
        cashSessionId: sale.cashSessionId,
        saleDate: sale.saleDate,
      });
      return sale;
    } catch (error) {
      this.logOfflineSyncConflictIfSafe(error, {
        companyId,
        clientRequestId,
        terminalId: dto.terminalId,
        warehouseId: dto.warehouseId,
      });
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002" &&
        clientRequestId
      ) {
        const existing = await this.prisma.sale.findFirst({
          where: { companyId, clientRequestId },
          include: this.saleInclude(),
        });
        if (existing) return existing;
        throw new BadRequestException(
          "No se pudo registrar la venta porque ya existe una solicitud fiscal con el mismo identificador.",
        );
      }
      if (!this.isSchemaMismatch(error)) throw error;
      throw new BadRequestException(
        "El módulo de ventas no está sincronizado con la base de datos.",
      );
    }
  }
  async calculate(user: TenantUser, dto: CreateSaleDto) {
    const companyId = requireTenant(user);
    if (!dto.items.length) {
      throw new BadRequestException("La venta requiere al menos 1 item");
    }

    const productIds = Array.from(
      new Set(
        dto.items
          .map((item) => item.productId)
          .filter((id): id is string => Boolean(id)),
      ),
    );
    const products = productIds.length
      ? await this.prisma.product.findMany({
          where: { id: { in: productIds }, companyId, archivedAt: null },
          select: {
            id: true,
            nombre: true,
            imagen: true,
            costo: true,
            stock: true,
            taxTreatment: true,
            taxRate: true,
            taxPriceMode: true,
            unitOfMeasure: {
              select: {
                code: true,
                name: true,
                symbol: true,
                allowDecimals: true,
                precision: true,
              },
            },
          },
        })
      : [];
    const productMap = new Map(
      products.map((product) => [product.id, product]),
    );
    const normalizedItems = dto.items.map((item, index) =>
      this.normalizeItem(item, index, productMap),
    );
    const fiscalSettings = await this.taxes.getCompanyFiscalSettings(companyId);
    const defaultPriceMode = this.taxes.resolvePriceMode(fiscalSettings);
    const calculation = this.taxes.calculatorService.calculate({
      taxEnabled: fiscalSettings.taxEnabled,
      defaultTaxRate: fiscalSettings.defaultTaxRate,
      defaultPriceMode,
      globalDiscountAmount: dto.globalDiscountAmount ?? 0,
      lines: normalizedItems.map((item) => ({
        description: item.productNameSnapshot,
        quantity: item.qty,
        unitPrice: item.priceSoldUnit,
        taxTreatment: item.taxTreatment,
        taxRate: item.taxRate ?? fiscalSettings.defaultTaxRate,
        priceMode: item.taxPriceMode ?? defaultPriceMode,
      })),
    });
    return {
      taxEnabled: fiscalSettings.taxEnabled,
      priceMode: defaultPriceMode,
      subtotal: this.toNumber(calculation.subtotal),
      taxableBase: this.toNumber(calculation.taxableBase),
      exemptAmount: this.toNumber(calculation.exemptAmount),
      taxAmount: this.toNumber(calculation.taxAmount),
      discountTotal: this.toNumber(calculation.discountAmount),
      grandTotal: this.toNumber(calculation.total),
      lines: calculation.lines.map((line) => ({
        index: line.index,
        description: line.description,
        quantity: this.toNumber(line.quantity),
        unitPrice: this.toNumber(line.unitPrice),
        grossAmount: this.toNumber(line.grossAmount),
        discount: this.toNumber(line.discountAmount),
        taxableBase: this.toNumber(line.taxableBase),
        taxRate: this.toNumber(line.taxRate),
        tax: this.toNumber(line.taxAmount),
        exemptAmount: this.toNumber(line.exemptAmount),
        total: this.toNumber(line.lineTotal),
        taxIncluded: line.taxIncluded,
        taxExempt: line.taxExempt,
      })),
    };
  }

  async createInvoicePdfShareLink(
    user: TenantUser,
    dto: CreateSalePdfShareLinkDto,
    requestBaseUrl?: string,
  ) {
    const companyId = requireTenant(user);
    const saleId = dto.saleId.trim();
    const sale = await this.prisma.sale.findFirst({
      where: { id: saleId, companyId },
      select: {
        id: true,
        userId: true,
        isDeleted: true,
      },
    });

    if (!sale || sale.isDeleted) {
      throw new NotFoundException("Venta no encontrada.");
    }

    const canShare =
      sale.userId === user.id ||
      user.role === Role.ADMIN ||
      user.role === Role.ASISTENTE;
    if (!canShare) {
      throw new ForbiddenException(
        "No tienes permiso para compartir esta factura.",
      );
    }

    const bytes = this.parsePdfBase64(dto.pdfBase64);
    const fileName = this.sanitizePdfFileName(
      dto.fileName ?? "",
      `factura_${saleId.slice(0, 8)}.pdf`,
    );
    const uploadDir = this.resolveUploadDir();
    const saleDir = path.join(uploadDir, "facturas", saleId);
    await mkdir(saleDir, { recursive: true });
    await writeFile(path.join(saleDir, fileName), bytes);

    const relativeUrl = `/sales/public/invoice-pdf/${encodeURIComponent(saleId)}/${encodeURIComponent(fileName)}`;
    const baseUrl = this.publicBaseUrl(requestBaseUrl);
    if (!baseUrl) {
      throw new BadRequestException(
        "No se pudo construir el enlace público del PDF. Configura PUBLIC_BASE_URL o API_BASE_URL.",
      );
    }

    return {
      ok: true,
      saleId,
      fileName,
      pdfUrl: `${baseUrl}${relativeUrl}`,
      expiresIn: null,
      createdAt: new Date().toISOString(),
    };
  }

  async remove(requestUser: TenantUser, saleId: string) {
    const companyId = requireTenant(requestUser);
    let sale: {
      id: string;
      isDeleted: boolean;
      userId: string;
      kind: string;
      inventoryRestoredAt: Date | null;
    } | null = null;
    try {
      sale = await this.prisma.sale.findFirst({
        where: { id: saleId, companyId },
        select: {
          id: true,
          isDeleted: true,
          userId: true,
          kind: true,
          inventoryRestoredAt: true,
        },
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException("Venta no encontrada");
    }
    if (!sale || sale.isDeleted) {
      throw new NotFoundException("Venta no encontrada");
    }

    const isAdmin = isAdminLike(requestUser);
    if (!isAdmin && sale.userId !== requestUser.id) {
      throw new ForbiddenException("No puedes eliminar esta venta");
    }

    if (sale.kind === "invoice") {
      return this.cancelSaleInventory(requestUser, saleId, {
        reason: "DELETE_ROUTE_SAFE_CANCELLATION",
        markDeleted: true,
      });
    }

    try {
      await this.prisma.sale.update({
        where: { id: saleId },
        data: {
          isDeleted: true,
          deletedAt: new Date(),
          deletedById: requestUser.id,
        },
      });
      this.emitSaleEvent(companyId, "sale.deleted", saleId, {
        userId: requestUser.id,
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException("Venta no encontrada");
    }

    return { ok: true };
  }

  private async cancelSaleInventory(
    requestUser: TenantUser,
    saleId: string,
    options: { reason?: string; markDeleted?: boolean } = {},
  ) {
    const companyId = requireTenant(requestUser);
    const now = new Date();

    const result = await this.prisma.$transaction(async (tx) => {
      const sale = await tx.sale.findFirst({
        where: { id: saleId, companyId },
        include: { items: true },
      });
      if (!sale || sale.isDeleted || sale.kind !== "invoice") {
        throw new NotFoundException("Venta no encontrada");
      }

      const refundCount = await tx.sale.count({
        where: {
          companyId,
          refundedSaleId: saleId,
          kind: "refund",
          isDeleted: false,
        },
      });
      if (refundCount > 0) {
        throw new BadRequestException(
          "No se puede cancelar una venta con devoluciones registradas.",
        );
      }

      const claim = await tx.sale.updateMany({
        where: { id: saleId, companyId, inventoryRestoredAt: null },
        data: {
          cancelledAt: now,
          cancelledById: requestUser.id,
          cancellationReason: options.reason ?? null,
          inventoryRestoredAt: now,
          ...(options.markDeleted
            ? {
                isDeleted: true,
                deletedAt: now,
                deletedById: requestUser.id,
              }
            : {}),
        },
      });
      if (claim.count !== 1) {
        return { ok: true, alreadyCancelled: true };
      }

      let legacyWarehouse: ResolvedSaleWarehouse | null = null;
      for (const item of sale.items) {
        if (!item.productId) continue;
        if (item.productSource && item.productSource !== ProductSource.LOCAL) {
          continue;
        }

        let warehouseId = item.warehouseId;
        let reason = options.reason ?? "SALE_CANCELLATION";
        if (!warehouseId) {
          legacyWarehouse ??= await this.resolveLegacyCancellationWarehouse(
            tx,
            companyId,
          );
          warehouseId = legacyWarehouse.id;
          reason = "LEGACY_MAIN_WAREHOUSE_FALLBACK";
        }

        await this.inventoryMutationService().increaseStockInTransaction(tx, {
          companyId,
          productId: item.productId,
          warehouseId,
          quantity: item.qty,
          type: InventoryMovementType.SALE_CANCELLATION,
          sourceType: "SALE",
          sourceId: sale.id,
          sourceItemId: item.id,
          reason,
          createdByUserId: requestUser.id,
        });
      }

      return { ok: true, alreadyCancelled: false };
    }, SALE_TRANSACTION_OPTIONS);

    this.emitSaleEvent(companyId, "sale.deleted", saleId, {
      userId: requestUser.id,
      safeCancellation: true,
      alreadyCancelled: result.alreadyCancelled,
    });
    return { ok: true };
  }

  async returnSale(
    requestUser: TenantUser,
    saleId: string,
    dto: CreateSaleReturnDto = {},
  ) {
    const companyId = requireTenant(requestUser);
    const canReturn =
      requestUser.role === Role.ADMIN ||
      requestUser.adminAuthorized === true ||
      requestUser.authorizedPermissions?.includes("refundSales") === true;
    if (!canReturn) {
      throw new ForbiddenException(
        "Solo un administrador puede devolver ventas",
      );
    }

    try {
      const clientRequestId = dto.clientRequestId?.trim() || undefined;
      if (clientRequestId) {
        const existing = await this.prisma.sale.findFirst({
          where: { companyId, clientRequestId, kind: "refund" },
          include: this.saleInclude(),
        });
        if (existing) return existing;
      }

      const activeSession = await this.prisma.cashSession.findFirst({
        where: {
          openedByUserId: requestUser.id,
          companyId,
          status: "OPEN",
          closedAt: null,
        },
        orderBy: { openedAt: "desc" },
      });
      if (!activeSession) {
        throw new BadRequestException(
          "Debes abrir caja antes de registrar una devolución.",
        );
      }

      const returned = await this.prisma.$transaction(async (tx) => {
        await this.lockReturnableSale(tx, companyId, saleId);
        const sale = await tx.sale.findFirst({
          where: { id: saleId, companyId },
          include: { items: true },
        });
        if (!sale || sale.isDeleted || sale.kind !== "invoice") {
          throw new NotFoundException("Venta no encontrada");
        }
        if (sale.cancelledAt || sale.inventoryRestoredAt) {
          throw new BadRequestException(
            "No se puede devolver una venta cuyo inventario ya fue restaurado por cancelacion.",
          );
        }
        if (clientRequestId) {
          const existing = await tx.sale.findFirst({
            where: { companyId, clientRequestId, kind: "refund" },
            include: this.saleInclude(),
          });
          if (existing) return existing;
        }

        const originalItems = new Map(
          sale.items.map((item) => [item.id, item]),
        );
        const requestedInput =
          dto.items && dto.items.length
            ? dto.items.map((item) => ({
                saleItemId: item.saleItemId,
                qty: new Prisma.Decimal(item.qty),
              }))
            : sale.items.map((item) => ({
                saleItemId: item.id,
                qty: new Prisma.Decimal(item.qty),
              }));

        const requestedByItem = new Map<string, Prisma.Decimal>();
        for (const item of requestedInput) {
          requestedByItem.set(
            item.saleItemId,
            (requestedByItem.get(item.saleItemId) ?? new Prisma.Decimal(0)).plus(
              item.qty,
            ),
          );
        }
        const requestedItems = [...requestedByItem.entries()].map(
          ([saleItemId, qty]) => ({ saleItemId, qty }),
        );
        const restoreInventory = dto.restoreInventory !== false;
        const { financialReturned, inventoryReturned } =
          await this.returnQuantityMaps(
            tx,
            companyId,
            saleId,
            sale.items.map((item) => item.id),
          );

        const refundItems = requestedItems.map((request, index) => {
          const original = originalItems.get(request.saleItemId);
          if (!original) {
            throw new BadRequestException(
              `Item inválido en devolución #${index + 1}`,
            );
          }
          if (request.qty.lte(0)) {
            throw new BadRequestException(
              `Cantidad inválida en devolución #${index + 1}`,
            );
          }
          validateQuantityForUnit({
            quantity: request.qty,
            unit: {
              code: original.unitCodeSnapshot,
              name: original.unitNameSnapshot,
              symbol: original.unitSymbolSnapshot,
              precision: original.unitPrecisionSnapshot,
              allowDecimals: original.unitPrecisionSnapshot > 0,
            },
            label: `devolución #${index + 1}`,
          });
          const alreadyFinancialReturned =
            financialReturned.get(original.id) ?? new Prisma.Decimal(0);
          const remainingFinancialQty = original.qty.minus(
            alreadyFinancialReturned,
          );
          if (request.qty.greaterThan(remainingFinancialQty)) {
            throw new BadRequestException(
              `La devolución de ${original.productNameSnapshot} supera la cantidad disponible.`,
            );
          }
          if (restoreInventory) {
            const alreadyInventoryReturned =
              inventoryReturned.get(original.id) ?? new Prisma.Decimal(0);
            const remainingInventoryQty = original.qty.minus(
              alreadyInventoryReturned,
            );
            if (request.qty.greaterThan(remainingInventoryQty)) {
              throw new BadRequestException(
                `La devolución de ${original.productNameSnapshot} supera la cantidad disponible para restaurar inventario.`,
              );
            }
          }
          const ratio = request.qty.div(original.qty);
          const subtotalCost = original.subtotalCost
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const lineTotal = original.subtotalSold
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const taxableBase = original.taxableBase
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const taxAmount = original.taxAmount
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const exemptAmount = original.exemptAmount
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const lineDiscountAmount = original.lineDiscountAmount
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const grossAmount = original.grossAmount
            .mul(ratio)
            .toDecimalPlaces(2)
            .neg();
          const commercialProfit = lineTotal.minus(subtotalCost);
          const netTaxProfit = taxableBase
            .plus(exemptAmount)
            .minus(subtotalCost);
          return {
            original,
            data: {
              refundedSaleItemId: original.id,
              productId: original.productId,
              productSource: original.productSource,
              sourceProductId: original.sourceProductId,
              warehouseId: original.warehouseId,
              warehouseNameSnapshot: original.warehouseNameSnapshot,
              warehouseCodeSnapshot: original.warehouseCodeSnapshot,
              productNameSnapshot: original.productNameSnapshot,
              productImageSnapshot: original.productImageSnapshot,
              qty: request.qty,
              unitCodeSnapshot: original.unitCodeSnapshot,
              unitNameSnapshot: original.unitNameSnapshot,
              unitSymbolSnapshot: original.unitSymbolSnapshot,
              unitPrecisionSnapshot: original.unitPrecisionSnapshot,
              priceSoldUnit: original.priceSoldUnit,
              grossAmount,
              lineDiscountAmount,
              taxableBase,
              taxRate: original.taxRate,
              taxAmount,
              exemptAmount,
              taxIncluded: original.taxIncluded,
              taxExempt: original.taxExempt,
              costUnitSnapshot: original.costUnitSnapshot,
              subtotalSold: lineTotal,
              subtotalCost,
              profit: commercialProfit,
              commercialProfit,
              netTaxProfit,
            },
          };
        });

        let legacyWarehouse: ResolvedSaleWarehouse | null = null;
        for (const item of refundItems) {
          if (!restoreInventory) continue;
          if (
            item.original.productSource &&
            item.original.productSource !== "LOCAL"
          ) {
            throw new BadRequestException(
              "Las devoluciones de productos FULLPOS requieren integración writable validada.",
            );
          }
          if (!item.original.productId || item.original.warehouseId) continue;
          {
            legacyWarehouse ??= await this.resolveLegacyCancellationWarehouse(
              tx,
              companyId,
            );
            item.data.warehouseId = legacyWarehouse.id;
            item.data.warehouseNameSnapshot = legacyWarehouse.name;
            item.data.warehouseCodeSnapshot = legacyWarehouse.code;
          }
        }

        const totalSold = refundItems
          .reduce(
            (sum, item) => sum.plus(item.data.subtotalSold),
            new Prisma.Decimal(0),
          )
          .toDecimalPlaces(2);
        const totalCost = refundItems
          .reduce(
            (sum, item) => sum.plus(item.data.subtotalCost),
            new Prisma.Decimal(0),
          )
          .toDecimalPlaces(2);
        const taxableBase = refundItems
          .reduce(
            (sum, item) => sum.plus(item.data.taxableBase),
            new Prisma.Decimal(0),
          )
          .toDecimalPlaces(2);
        const taxAmount = refundItems
          .reduce(
            (sum, item) => sum.plus(item.data.taxAmount),
            new Prisma.Decimal(0),
          )
          .toDecimalPlaces(2);
        const exemptAmount = refundItems
          .reduce(
            (sum, item) => sum.plus(item.data.exemptAmount),
            new Prisma.Decimal(0),
          )
          .toDecimalPlaces(2);
        const discountAmount = refundItems
          .reduce(
            (sum, item) => sum.plus(item.data.lineDiscountAmount),
            new Prisma.Decimal(0),
          )
          .toDecimalPlaces(2);
        const totalProfit = totalSold.minus(totalCost).toDecimalPlaces(2);
        const netTaxRevenue = taxableBase.plus(exemptAmount);
        const netTaxProfit = netTaxRevenue.minus(totalCost).toDecimalPlaces(2);
        const commercialMargin = totalSold.abs().gt(0)
          ? totalProfit.div(totalSold.abs()).toDecimalPlaces(4)
          : new Prisma.Decimal(0);
        const netTaxMargin = netTaxRevenue.abs().gt(0)
          ? netTaxProfit.div(netTaxRevenue.abs()).toDecimalPlaces(4)
          : new Prisma.Decimal(0);

        const returned = await tx.sale.create({
          data: {
            userId: requestUser.id,
            companyId,
            clientRequestId,
            refundedSaleId: saleId,
            customerId: sale.customerId,
            cashSessionId: activeSession.id,
            saleDate: new Date(),
            note:
              dto.reason?.trim() ||
              (restoreInventory
                ? "DEVOLUCION: venta devuelta desde historial."
                : "REEMBOLSO FINANCIERO: no restaura inventario."),
            paymentMethod: "refund",
            paymentCashAmount: totalSold,
            paymentTransferAmount: new Prisma.Decimal(0),
            creditAmount: new Prisma.Decimal(0),
            creditPaidAmount: new Prisma.Decimal(0),
            creditBalance: new Prisma.Decimal(0),
            creditStatus: "none",
            kind: "refund",
            status: "RETURNED",
            totalSold,
            fiscalTaxEnabled: sale.fiscalTaxEnabled,
            fiscalPriceMode: sale.fiscalPriceMode,
            taxableBase,
            taxAmount,
            exemptAmount,
            discountAmount,
            fiscalVoucherType: sale.fiscalVoucherType,
            issuerNameSnapshot: sale.issuerNameSnapshot,
            issuerTaxIdSnapshot: sale.issuerTaxIdSnapshot,
            issuerAddressSnapshot: sale.issuerAddressSnapshot,
            issuerPhoneSnapshot: sale.issuerPhoneSnapshot,
            issuerEmailSnapshot: sale.issuerEmailSnapshot,
            fiscalCustomerTaxId: sale.fiscalCustomerTaxId,
            fiscalCustomerName: sale.fiscalCustomerName,
            customerAddressSnapshot: sale.customerAddressSnapshot,
            customerPhoneSnapshot: sale.customerPhoneSnapshot,
            totalCost,
            totalProfit,
            commercialProfit: totalProfit,
            netTaxProfit,
            commercialMargin,
            netTaxMargin,
            commissionRate: new Prisma.Decimal(0),
            commissionAmount: new Prisma.Decimal(0),
            items: {
              create: refundItems.map((item) => item.data),
            },
          },
          include: this.saleInclude(),
        });

        if (restoreInventory) {
          for (const refundItem of returned.items) {
            const item = refundItems.find(
              (candidate) =>
                candidate.original.id === refundItem.refundedSaleItemId,
            );
            if (!item || !item.original.productId) continue;
            const warehouseId = item.original.warehouseId ?? item.data.warehouseId;
            if (!warehouseId) {
              throw new BadRequestException(
                "No se pudo resolver el almacen original de la devolucion.",
              );
            }
            const reason =
              !item.original.warehouseId && item.data.warehouseId
                ? "LEGACY_MAIN_WAREHOUSE_FALLBACK"
                : dto.reason?.trim() || "SALE_RETURN";

            await this.inventoryMutationService().increaseStockInTransaction(
              tx,
              {
                companyId,
                productId: item.original.productId,
                warehouseId,
                quantity: refundItem.qty,
                type: InventoryMovementType.RETURN,
                sourceType: "SALE_RETURN",
                sourceId: returned.id,
                sourceItemId: refundItem.id,
                reason,
                createdByUserId: requestUser.id,
              },
            );
          }
        }

        return tx.sale.findUniqueOrThrow({
          where: { id: returned.id },
          include: this.saleInclude(),
        });
      }, SALE_RETURN_TRANSACTION_OPTIONS);
      this.emitSaleEvent(companyId, "sale.returned", saleId, {
        userId: requestUser.id,
        cashSessionId: returned.cashSessionId,
        saleDate: returned.saleDate,
      });
      return returned;
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002" &&
        dto.clientRequestId
      ) {
        const existing = await this.prisma.sale.findFirst({
          where: {
            companyId,
            clientRequestId: dto.clientRequestId.trim(),
            kind: "refund",
          },
          include: this.saleInclude(),
        });
        if (existing) return existing;
      }
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException("Venta no encontrada");
    }
  }

  async listCredits(user: TenantUser, includePaid = false) {
    const companyId = requireTenant(user);
    const where: Prisma.SaleWhereInput = {
      companyId,
      isDeleted: false,
      creditStatus: includePaid ? { in: ["open", "paid"] } : "open",
    };

    return this.findManySalesWithFallback(where, this.saleInclude());
  }

  async addCreditPayment(
    user: TenantUser,
    saleId: string,
    dto: { cashAmount?: number; transferAmount?: number; note?: string },
  ) {
    const companyId = requireTenant(user);
    const sale = await this.prisma.sale.findFirst({
      where: { id: saleId, companyId },
      include: { customer: true },
    });
    if (!sale || sale.isDeleted || sale.creditStatus === "none") {
      throw new NotFoundException("Crédito no encontrado");
    }

    const activeSession = await this.prisma.cashSession.findFirst({
      where: {
        openedByUserId: user.id,
        companyId,
        status: "OPEN",
        closedAt: null,
      },
      orderBy: { openedAt: "desc" },
    });
    if (!activeSession) {
      throw new BadRequestException(
        "Debes abrir caja antes de registrar un abono.",
      );
    }

    const cashAmount = new Prisma.Decimal(dto.cashAmount ?? 0);
    const transferAmount = new Prisma.Decimal(dto.transferAmount ?? 0);
    const amount = cashAmount.plus(transferAmount);
    if (amount.lte(0)) {
      throw new BadRequestException("El abono debe ser mayor que cero.");
    }
    if (amount.greaterThan(sale.creditBalance)) {
      throw new BadRequestException(
        "El abono no puede superar el saldo pendiente.",
      );
    }

    const result = await this.prisma.$transaction(async (tx) => {
      const payment = await tx.saleCreditPayment.create({
        data: {
          saleId,
          companyId,
          userId: user.id,
          cashSessionId: activeSession.id,
          amount,
          cashAmount,
          transferAmount,
          note: dto.note?.trim() || null,
        },
      });
      const nextPaid = sale.creditPaidAmount.plus(amount);
      const nextBalance = sale.creditBalance.minus(amount);
      const nextStatus = nextBalance.lte(0) ? "paid" : "open";
      const updatedSale = await tx.sale.update({
        where: { id: saleId },
        data: {
          paymentCashAmount: sale.paymentCashAmount.plus(cashAmount),
          paymentTransferAmount:
            sale.paymentTransferAmount.plus(transferAmount),
          creditPaidAmount: nextPaid,
          creditBalance: nextBalance,
          creditStatus: nextStatus,
          status: nextStatus === "paid" ? "PAID" : "CREDIT",
        },
        include: this.saleInclude(),
      });
      return { payment, sale: updatedSale };
    });
    this.emitSaleEvent(companyId, "sale.credit_payment.created", saleId, {
      userId: user.id,
      cashSessionId: activeSession.id,
      saleDate: result.sale.saleDate,
    });
    return result;
  }

  async purgeAllForDebug(user: TenantUser) {
    if (!isAdminLike(user)) {
      throw new ForbiddenException(
        "Solo un administrador puede limpiar ventas.",
      );
    }

    const companyId = requireTenant(user);
    const deleted = await this.prisma.sale.deleteMany({ where: { companyId } });
    return {
      ok: true,
      deletedSales: deleted.count,
    };
  }

  private normalizeItem(
    item: CreateSaleItemDto,
    index: number,
    productMap: Map<
      string,
      {
        id: string;
        nombre: string;
        imagen: string | null;
        costo: Prisma.Decimal;
        stock: Prisma.Decimal;
        taxTreatment: "INHERIT" | "TAXABLE" | "EXEMPT";
        taxRate: Prisma.Decimal | null;
        taxPriceMode: "NO_TAX" | "TAX_ADDED" | "TAX_INCLUDED" | null;
        unitOfMeasure: UnitOfMeasureSnapshot | null;
      }
    >,
  ): NormalizedSaleItem {
    const qty = new Prisma.Decimal(item.qty);
    const priceSoldUnit = new Prisma.Decimal(item.priceSoldUnit);

    if (qty.lte(0)) {
      throw new BadRequestException(`Cantidad inválida en item #${index + 1}`);
    }

    if (priceSoldUnit.lt(0)) {
      throw new BadRequestException(`Precio inválido en item #${index + 1}`);
    }

    if (item.productId) {
      const product = productMap.get(item.productId);
      if (!product) {
        throw new BadRequestException(
          `Producto inválido en item #${index + 1}`,
        );
      }
      validateQuantityForUnit({
        quantity: qty,
        unit: product.unitOfMeasure,
        label: `item #${index + 1}`,
      });

      const costUnitSnapshot = new Prisma.Decimal(product.costo);
      const subtotalSold = qty.mul(priceSoldUnit);
      const subtotalCost = qty.mul(costUnitSnapshot);
      const profit = subtotalSold.minus(subtotalCost);

      return {
        productId: product.id,
        productSource: ProductSource.LOCAL,
        sourceProductId: product.id,
        productNameSnapshot: product.nombre,
        productImageSnapshot: product.imagen,
        qty,
        ...unitSnapshotFields(product.unitOfMeasure),
        priceSoldUnit,
        originalUnitPriceSnapshot:
          item.originalUnitPriceSnapshot === undefined
            ? undefined
            : new Prisma.Decimal(item.originalUnitPriceSnapshot),
        costUnitSnapshot,
        subtotalSold,
        subtotalCost,
        profit,
        taxTreatment: product.taxTreatment,
        taxRate: product.taxRate,
        taxPriceMode: product.taxPriceMode,
      };
    }

    const productName = item.productName?.trim();
    if (!productName) {
      throw new BadRequestException(
        `Nombre requerido para item fuera de inventario #${index + 1}`,
      );
    }

    if (item.costUnitSnapshot === undefined || item.costUnitSnapshot === null) {
      throw new BadRequestException(
        `Costo unitario requerido en item fuera de inventario #${index + 1}`,
      );
    }

    const costUnitSnapshot = new Prisma.Decimal(item.costUnitSnapshot);
    if (costUnitSnapshot.lt(0)) {
      throw new BadRequestException(`Costo inválido en item #${index + 1}`);
    }
    const externalUnit = this.externalUnitSnapshot(item);
    if (this.hasExternalUnitSnapshot(item)) {
      validateQuantityForUnit({
        quantity: qty,
        unit: externalUnit,
        label: `item #${index + 1}`,
      });
    }

    const subtotalSold = qty.mul(priceSoldUnit);
    const subtotalCost = qty.mul(costUnitSnapshot);
    const profit = subtotalSold.minus(subtotalCost);

    return {
      productId: null,
      productSource: this.externalProductSource(item),
      sourceProductId: this.cleanSourceProductId(item.sourceProductId),
      productNameSnapshot: productName,
      productImageSnapshot: null,
      qty,
      ...unitSnapshotFields(externalUnit),
      priceSoldUnit,
      originalUnitPriceSnapshot:
        item.originalUnitPriceSnapshot === undefined
          ? undefined
          : new Prisma.Decimal(item.originalUnitPriceSnapshot),
      costUnitSnapshot,
      subtotalSold,
      subtotalCost,
      profit,
      taxTreatment: "INHERIT" as const,
      taxRate: null,
      taxPriceMode: null,
    };
  }

  private assertNoUnsupportedExternalStockMutation(items: NormalizedSaleItem[]) {
    const external = items.find(
      (item) => item.productSource && item.productSource !== ProductSource.LOCAL,
    );
    if (!external) return;
    throw new BadRequestException(
      "Ventas de productos FULLPOS requieren stock writable validado e idempotente antes de registrarse.",
    );
  }

  private externalUnitSnapshot(item: CreateSaleItemDto): UnitOfMeasureSnapshot {
    const code = item.unitCodeSnapshot?.trim() || DEFAULT_UNIT_OF_MEASURE.code;
    const precision = Number(item.unitPrecisionSnapshot ?? 0);
    return {
      code,
      name: item.unitNameSnapshot?.trim() || DEFAULT_UNIT_OF_MEASURE.name,
      symbol:
        item.unitSymbolSnapshot?.trim() || DEFAULT_UNIT_OF_MEASURE.symbol,
      precision,
      allowDecimals: precision > 0,
    };
  }

  private hasExternalUnitSnapshot(item: CreateSaleItemDto): boolean {
    return (
      item.unitCodeSnapshot !== undefined ||
      item.unitNameSnapshot !== undefined ||
      item.unitSymbolSnapshot !== undefined ||
      item.unitPrecisionSnapshot !== undefined
    );
  }

  private externalProductSource(item: CreateSaleItemDto): ProductSource | null {
    if (!item.productSource) return null;
    if (item.productSource === "LOCAL") return ProductSource.LOCAL;
    return item.productSource as ProductSource;
  }

  private cleanSourceProductId(value: unknown) {
    const text = String(value ?? "").trim();
    return text.length > 0 ? text : null;
  }

  private resolveSaleOccurredAt(value?: string | null) {
    const text = value?.trim();
    if (!text) return new Date();
    const parsed = new Date(text);
    if (Number.isNaN(parsed.getTime())) return new Date();
    const now = Date.now();
    if (parsed.getTime() > now + 5 * 60 * 1000) return new Date();
    return parsed;
  }

  private logOfflineSyncConflictIfSafe(
    error: unknown,
    context: {
      companyId: string;
      clientRequestId: string | null;
      terminalId?: string | null;
      warehouseId?: string | null;
    },
  ) {
    const response =
      typeof (error as { getResponse?: unknown }).getResponse === "function"
        ? (error as { getResponse: () => unknown }).getResponse()
        : null;
    const body =
      response && typeof response === "object"
        ? (response as Record<string, unknown>)
        : null;
    const code = String(body?.errorCode ?? body?.code ?? "").trim();
    if (!code.includes("STOCK") && !code.includes("WAREHOUSE") && !code.includes("TERMINAL")) {
      return;
    }
    const details =
      body?.details && typeof body.details === "object"
        ? (body.details as Record<string, unknown>)
        : {};
    // eslint-disable-next-line no-console
    console.warn("[offline-sync-conflict]", {
      companyId: context.companyId,
      clientRequestId: context.clientRequestId,
      conflictType: code,
      productId: details.productId,
      warehouseId: details.warehouseId ?? context.warehouseId,
      terminalId: context.terminalId,
    });
  }

  private toNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === "number") return value;
    return Number(value);
  }

  private normalizeSalePayment(dto: CreateSaleDto, totalSold: Prisma.Decimal) {
    const allowed = new Set(["cash", "transfer", "mixed", "credit"]);
    const requestedMethod = (dto.paymentMethod ?? "cash").trim();
    const paymentMethod = allowed.has(requestedMethod)
      ? (requestedMethod as "cash" | "transfer" | "mixed" | "credit")
      : "cash";
    const cashWasProvided = dto.paymentCashAmount !== undefined;
    const transferWasProvided = dto.paymentTransferAmount !== undefined;
    const total = totalSold.toDecimalPlaces(2);

    let paymentCashAmount = new Prisma.Decimal(
      dto.paymentCashAmount ??
        (paymentMethod === "cash" ? total.toNumber() : 0),
    ).toDecimalPlaces(2);
    let paymentTransferAmount = new Prisma.Decimal(
      dto.paymentTransferAmount ??
        (paymentMethod === "transfer" ? total.toNumber() : 0),
    ).toDecimalPlaces(2);

    if (paymentCashAmount.lt(0) || paymentTransferAmount.lt(0)) {
      throw new BadRequestException(
        "Los montos de pago no pueden ser negativos.",
      );
    }

    if (paymentMethod === "cash") {
      paymentCashAmount = total;
      paymentTransferAmount = new Prisma.Decimal(0);
    }

    if (paymentMethod === "transfer") {
      paymentCashAmount = new Prisma.Decimal(0);
      paymentTransferAmount = total;
    }

    const paidAmount = paymentCashAmount.plus(paymentTransferAmount);

    if (paymentMethod === "mixed") {
      if (!cashWasProvided || !transferWasProvided) {
        throw new BadRequestException(
          "El pago mixto requiere monto en efectivo y monto por transferencia.",
        );
      }
      if (paymentCashAmount.lte(0) || paymentTransferAmount.lte(0)) {
        throw new BadRequestException(
          "El pago mixto debe tener efectivo y transferencia mayores que cero.",
        );
      }
      if (paidAmount.minus(total).abs().greaterThan(0.009)) {
        throw new BadRequestException(
          "En pago mixto, efectivo + transferencia debe coincidir con el total.",
        );
      }
    }

    const requestedCreditAmount = new Prisma.Decimal(
      dto.creditAmount ?? 0,
    ).toDecimalPlaces(2);
    const computedCreditAmount = total.minus(paidAmount);
    const creditAmount =
      paymentMethod === "credit"
        ? requestedCreditAmount.greaterThan(computedCreditAmount)
          ? requestedCreditAmount
          : computedCreditAmount
        : new Prisma.Decimal(0);
    const creditBalance =
      paymentMethod === "credit" ? creditAmount : new Prisma.Decimal(0);

    if (
      paymentMethod !== "credit" &&
      paidAmount.minus(total).abs().greaterThan(0.009)
    ) {
      throw new BadRequestException(
        "El monto pagado debe coincidir con el total de la factura.",
      );
    }
    if (paymentMethod === "credit" && paidAmount.greaterThan(total)) {
      throw new BadRequestException(
        "El abono inicial no puede superar el total de la factura.",
      );
    }

    // Tender (efectivo recibido) y devuelta. Son OPCIONALES: cuando el cliente
    // (versión legada) no los envía se conservan NULL para no fabricar un
    // tender histórico inexistente. paymentCashAmount permanece como el
    // efectivo NETO retenido por la venta.
    const tender = deriveCashTenderChange({
      cashReceived: dto.cashReceived,
      changeAmount: dto.changeAmount,
      paymentCashAmount,
    });

    return {
      paymentMethod,
      paymentCashAmount,
      paymentTransferAmount,
      cashReceived: tender.cashReceived,
      changeAmount: tender.changeAmount,
      paidAmount,
      creditAmount,
      creditBalance,
    };
  }

  private buildDateRange(
    from?: string,
    to?: string,
  ): { saleDate?: Prisma.DateTimeFilter } {
    const saleDate: Prisma.DateTimeFilter = {};

    if (from) {
      const fromDate = this.parseDateBoundary(from, true);
      if (Number.isNaN(fromDate.getTime())) {
        throw new BadRequestException("Parámetro from inválido");
      }
      saleDate.gte = fromDate;
    }

    if (to) {
      const toDate = this.parseDateBoundary(to, false);
      if (Number.isNaN(toDate.getTime())) {
        throw new BadRequestException("Parámetro to inválido");
      }
      saleDate.lt = toDate;
    }

    return Object.keys(saleDate).length ? { saleDate } : {};
  }

  private parseDateBoundary(value: string, isStart: boolean): Date {
    const trimmed = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      const date = new Date(`${trimmed}T00:00:00.000-04:00`);
      if (isStart) return date;
      return new Date(date.getTime() + 24 * 60 * 60 * 1000);
    }
    return new Date(trimmed);
  }

  private emitSaleEvent(
    companyId: string,
    type: string,
    saleId: string,
    extra: Record<string, unknown> = {},
  ) {
    this.realtime.emitCompany(companyId, "sales.event", {
      eventId: crypto.randomUUID(),
      type,
      saleId,
      companyId,
      emittedAt: new Date().toISOString(),
      ...extra,
    });
  }
}
