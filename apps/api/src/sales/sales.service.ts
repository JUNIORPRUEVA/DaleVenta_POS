import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma, Role } from "@prisma/client";
import crypto from "node:crypto";
import * as fs from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import * as path from "node:path";
import { PrismaService } from "../prisma/prisma.service";
import { CatalogRealtimeRelayService } from "../products/catalog-realtime-relay.service";
import { TaxService } from "../tax/tax.service";
import { NcfService } from "../tax/ncf.service";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import { CreateSaleDto, CreateSaleItemDto } from "./dto/create-sale.dto";
import { CreateSalePdfShareLinkDto } from "./dto/create-sale-pdf-share-link.dto";

@Injectable()
export class SalesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly taxes: TaxService,
    private readonly ncf: NcfService,
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
            },
          },
        },
      },
      creditPayments: {
        orderBy: { paidAt: "desc" },
      },
    } satisfies Prisma.SaleInclude;
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
  ) {
    const companyId = requireTenant(user);
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      companyId,
      ...(includeDeleted ? {} : { isDeleted: false }),
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    try {
      return await this.prisma.sale.findMany({
        where,
        orderBy: { saleDate: "desc" },
        include: {
          customer: this.saleInclude().customer,
          user: this.saleInclude().user,
          items: this.saleInclude().items,
        },
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      return [];
    }
  }

  async listInvoices(
    user: TenantUser,
    from?: string,
    to?: string,
    customerId?: string,
    includeDeleted = false,
  ) {
    const companyId = requireTenant(user);
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      companyId,
      ...(includeDeleted ? {} : { isDeleted: false }),
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    try {
      return await this.prisma.sale.findMany({
        where,
        orderBy: { saleDate: "desc" },
        include: this.saleInclude(),
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      return [];
    }
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

    const customerId = dto.customerId?.trim() || null;
    const clientRequestId = dto.clientRequestId?.trim() || null;

    if (clientRequestId) {
      const existing = await this.prisma.sale.findFirst({
        where: { companyId, clientRequestId },
        include: this.saleInclude(),
      });
      if (existing) return existing;
    }

    let customerFiscalSnapshot: {
      nombre: string;
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

    const productIds = Array.from(
      new Set(
        dto.items
          .map((item) => item.productId)
          .filter((id): id is string => Boolean(id)),
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
    }> = [];
    if (productIds.length) {
      try {
        products = await this.prisma.product.findMany({
          where: { id: { in: productIds }, companyId },
          select: {
            id: true,
            nombre: true,
            imagen: true,
            costo: true,
            stock: true,
            taxTreatment: true,
            taxRate: true,
            taxPriceMode: true,
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

    let normalizedItems = dto.items.map((item, index) =>
      this.normalizeItem(item, index, productMap),
    );

    const fiscalSettings = await this.taxes.getCompanyFiscalSettings(companyId);
    const defaultPriceMode = this.taxes.resolvePriceMode(fiscalSettings);
    const taxCalculation = this.taxes.calculatorService.calculate({
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

    let totalSold = fiscalSettings.taxEnabled
      ? taxCalculation.total
      : new Prisma.Decimal(0);
    let totalCost = new Prisma.Decimal(0);
    let totalProfit = new Prisma.Decimal(0);

    for (const item of normalizedItems) {
      if (!fiscalSettings.taxEnabled) {
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

    totalSold = totalSold.toDecimalPlaces(2);
    totalCost = totalCost.toDecimalPlaces(2);
    totalProfit = totalSold.minus(totalCost).toDecimalPlaces(2);

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
    const fiscalCustomerTaxId =
      dto.fiscalCustomerTaxId?.trim() ||
      customerFiscalSnapshot?.taxId?.trim() ||
      null;
    const fiscalCustomerName =
      dto.fiscalCustomerName?.trim() ||
      customerFiscalSnapshot?.businessName?.trim() ||
      customerFiscalSnapshot?.nombre?.trim() ||
      null;

    if (requestedVoucherType && !fiscalSettings.ncfEnabled) {
      throw new BadRequestException("Los comprobantes fiscales no están activados para esta empresa.");
    }

    if (fiscalSettings.ncfEnabled && requestedVoucherType) {
      this.taxes.calculatorService.validateFiscalCustomer({
        voucherType: requestedVoucherType,
        customerTaxId: fiscalCustomerTaxId,
        customerBusinessName: fiscalCustomerName,
      });
      if (requestedVoucherType === "B02") {
        // B02 is allowed for final consumers; customer fiscal data is optional.
      }
    }

    const payment = this.normalizeSalePayment(dto, totalSold);
    const {
      paymentMethod,
      paymentCashAmount,
      paymentTransferAmount,
      paidAmount,
      creditAmount,
      creditBalance,
    } = payment;

    try {
      const sale = await this.prisma.$transaction(async (tx) => {
        for (const item of normalizedItems) {
          if (!item.productId) continue;
          const updated = await tx.product.updateMany({
            where: {
              id: item.productId,
              companyId,
              stock: { gte: item.qty },
            },
            data: {
              stock: { decrement: item.qty },
            },
          });
          if (updated.count !== 1) {
            throw new BadRequestException(
              `Stock insuficiente para ${item.productNameSnapshot}`,
            );
          }
        }

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
            customerId,
            cashSessionId: activeSession.id,
            saleDate: new Date(),
            note: dto.note,
            paymentMethod,
            paymentCashAmount,
            paymentTransferAmount,
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
            fiscalTaxEnabled: fiscalSettings.taxEnabled,
            fiscalPriceMode: defaultPriceMode,
            taxableBase: taxCalculation.taxableBase,
            taxAmount: taxCalculation.taxAmount,
            exemptAmount: taxCalculation.exemptAmount,
            discountAmount: taxCalculation.discountAmount,
            fiscalVoucherType: requestedVoucherType,
            ncf: reservedNcf?.ncf ?? null,
            fiscalCustomerTaxId,
            fiscalCustomerName,
            totalCost,
            totalProfit,
            commissionRate,
            commissionAmount,
            items: {
              create: normalizedItems.map((item, index) => ({
                ...(() => {
                  const taxLine = taxCalculation.lines[index];
                  return {
                    grossAmount: taxLine?.grossAmount ?? item.subtotalSold,
                    lineDiscountAmount: taxLine?.discountAmount ?? new Prisma.Decimal(0),
                    taxableBase: taxLine?.taxableBase ?? new Prisma.Decimal(0),
                    taxRate: taxLine?.taxRate ?? new Prisma.Decimal(0),
                    taxAmount: taxLine?.taxAmount ?? new Prisma.Decimal(0),
                    exemptAmount: taxLine?.exemptAmount ?? item.subtotalSold,
                    taxIncluded: taxLine?.taxIncluded ?? false,
                    taxExempt: taxLine?.taxExempt ?? true,
                    subtotalSold: taxLine?.lineTotal ?? item.subtotalSold,
                    profit: (taxLine?.lineTotal ?? item.subtotalSold).minus(item.subtotalCost),
                  };
                })(),
                productId: item.productId,
                productNameSnapshot: item.productNameSnapshot,
                productImageSnapshot: item.productImageSnapshot,
                qty: item.qty,
                priceSoldUnit: item.priceSoldUnit,
                costUnitSnapshot: item.costUnitSnapshot,
                subtotalCost: item.subtotalCost,
              })),
            },
          },
          include: {
            customer: {
              select: {
                id: true,
                nombre: true,
                telefono: true,
              },
            },
            items: true,
          },
        });

        if (customerId) {
          await tx.client.update({
            where: { id: customerId },
            data: { lastActivityAt: sale.saleDate },
          });
        }

        if (reservedNcf) {
          await this.ncf.markIssued(tx, {
            companyId,
            sequenceId: reservedNcf.sequenceId,
            saleId: sale.id,
            userId: user.id,
            ncf: reservedNcf.ncf,
            type: reservedNcf.type,
          });
        }

        return sale;
      });
      this.emitSaleEvent(companyId, "sale.created", sale.id, {
        userId: user.id,
        cashSessionId: sale.cashSessionId,
        saleDate: sale.saleDate,
      });
      return sale;
    } catch (error) {
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
          where: { id: { in: productIds }, companyId },
          select: {
            id: true,
            nombre: true,
            imagen: true,
            costo: true,
            stock: true,
            taxTreatment: true,
            taxRate: true,
            taxPriceMode: true,
          },
        })
      : [];
    const productMap = new Map(products.map((product) => [product.id, product]));
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
    let sale: { id: string; isDeleted: boolean; userId: string } | null = null;
    try {
      sale = await this.prisma.sale.findFirst({
        where: { id: saleId, companyId },
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

  async returnSale(requestUser: TenantUser, saleId: string) {
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

    let sale: Prisma.SaleGetPayload<{
      include: { items: true };
    }> | null = null;

    try {
      sale = await this.prisma.sale.findFirst({
        where: { id: saleId, companyId },
        include: { items: true },
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException("Venta no encontrada");
    }

    if (!sale || sale.isDeleted) {
      throw new NotFoundException("Venta no encontrada");
    }

    try {
      const returned = await this.prisma.$transaction(async (tx) => {
        for (const item of sale!.items) {
          if (!item.productId) continue;
          await tx.product.update({
            where: { id: item.productId },
            data: { stock: { increment: item.qty } },
          });
        }

        return tx.sale.update({
          where: { id: saleId },
          data: {
            isDeleted: true,
            deletedAt: new Date(),
            deletedById: requestUser.id,
            note: sale!.note?.trim()
              ? `${sale!.note}\nDEVOLUCION: venta devuelta desde historial.`
              : "DEVOLUCION: venta devuelta desde historial.",
          },
          include: this.saleInclude(),
        });
      });
      this.emitSaleEvent(companyId, "sale.returned", saleId, {
        userId: requestUser.id,
        cashSessionId: returned.cashSessionId,
        saleDate: returned.saleDate,
      });
      return returned;
    } catch (error) {
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

    try {
      return await this.prisma.sale.findMany({
        where,
        orderBy: { saleDate: "desc" },
        include: this.saleInclude(),
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      return [];
    }
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
      }
    >,
  ) {
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

      const costUnitSnapshot = new Prisma.Decimal(product.costo);
      const subtotalSold = qty.mul(priceSoldUnit);
      const subtotalCost = qty.mul(costUnitSnapshot);
      const profit = subtotalSold.minus(subtotalCost);

      return {
        productId: product.id,
        productNameSnapshot: product.nombre,
        productImageSnapshot: product.imagen,
        qty,
        priceSoldUnit,
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

    const subtotalSold = qty.mul(priceSoldUnit);
    const subtotalCost = qty.mul(costUnitSnapshot);
    const profit = subtotalSold.minus(subtotalCost);

    return {
      productId: null,
      productNameSnapshot: productName,
      productImageSnapshot: null,
      qty,
      priceSoldUnit,
      costUnitSnapshot,
      subtotalSold,
      subtotalCost,
      profit,
      taxTreatment: "INHERIT" as const,
      taxRate: null,
      taxPriceMode: null,
    };
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

    return {
      paymentMethod,
      paymentCashAmount,
      paymentTransferAmount,
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
