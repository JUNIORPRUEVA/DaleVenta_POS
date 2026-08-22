import { BadRequestException, Injectable } from "@nestjs/common";
import { Prisma, Role } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";

type RequestUser = TenantUser;

type MoneyLike = Prisma.Decimal | number | string | null | undefined;
type SaleOverviewRow = Prisma.SaleGetPayload<{
  include: {
    customer: { select: { id: true; nombre: true } };
    items: {
      include: {
        product: { select: { categoria: true } };
      };
    };
  };
}>;
type SaleOverviewItem = SaleOverviewRow["items"][number];

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async salesOverview(user: RequestUser, query: Record<string, string>) {
    const companyId = requireTenant(user);
    const range = this.buildDateRange(query.from, query.to);
    const selectedCategory = this.normalizeCategoryFilter(query.category);
    const canSeeAll = isAdminLike(user);
    const userFilter = canSeeAll ? {} : { userId: user.id };

    const saleWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "invoice",
      isDeleted: false,
      saleDate: range,
    };
    const returnedWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "invoice",
      isDeleted: true,
      deletedAt: range,
      // Reversión contable segura: solo restamos ventas anuladas que se
      // contabilizaron en un período ANTERIOR (saleDate < inicio del rango).
      // Una venta creada y anulada dentro del mismo período nunca entró al
      // "gross" (filtro isDeleted:false) y restarla aquí la descontaría dos
      // veces, produciendo un neto negativo incorrecto.
      saleDate: { lt: range.gte },
    };
    const refundWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "refund",
      isDeleted: false,
      saleDate: range,
    };

    const [sales, returnedSales, refundSales, products, movements] = await Promise.all([
      this.prisma.sale.findMany({
        where: saleWhere,
        include: {
          customer: { select: { id: true, nombre: true } },
          items: {
            include: {
              product: { select: { categoria: true } },
            },
          },
        },
        orderBy: { saleDate: "asc" },
      }),
      this.prisma.sale.findMany({
        where: returnedWhere,
        include: {
          customer: { select: { id: true, nombre: true } },
          items: {
            include: {
              product: { select: { categoria: true } },
            },
          },
        },
        orderBy: { deletedAt: "asc" },
      }),
      this.prisma.sale.findMany({
        where: refundWhere,
        include: {
          customer: { select: { id: true, nombre: true } },
          items: {
            include: {
              product: { select: { categoria: true } },
            },
          },
        },
        orderBy: { saleDate: "asc" },
      }),
      this.prisma.product.findMany({
        where: { companyId },
        select: {
          id: true,
          nombre: true,
          categoria: true,
          costo: true,
          precio: true,
          stock: true,
        },
      }),
      this.prisma.cashMovement.findMany({
        where: {
          createdAt: range,
          companyId,
          ...(canSeeAll ? {} : { userId: user.id }),
        },
      }),
    ]);

    const visibleSales = selectedCategory
      ? sales.filter(
          (sale) =>
            this.saleItemsForCategory(sale, selectedCategory).length > 0,
        )
      : sales;
    const returnedAndRefundedSales = [...returnedSales, ...refundSales];
    const visibleReturnedSales = selectedCategory
      ? returnedAndRefundedSales.filter(
          (sale) =>
            this.saleItemsForCategory(sale, selectedCategory).length > 0,
        )
      : returnedAndRefundedSales;

    const totals = visibleSales.reduce(
      (acc, sale) => {
        const categoryItems = this.saleItemsForCategory(sale, selectedCategory);
        const itemSold = categoryItems.reduce(
          (sum, item) => sum + this.toNumber(item.subtotalSold),
          0,
        );
        const itemCost = categoryItems.reduce(
          (sum, item) => sum + this.toNumber(item.subtotalCost),
          0,
        );
        const itemProfit = categoryItems.reduce(
          (sum, item) => sum + this.toNumber(item.profit),
          0,
        );
        const itemTaxableBase = categoryItems.reduce(
          (sum, item) => sum + this.toNumber((item as any).taxableBase),
          0,
        );
        const itemTaxAmount = categoryItems.reduce(
          (sum, item) => sum + this.toNumber((item as any).taxAmount),
          0,
        );
        const itemExemptAmount = categoryItems.reduce(
          (sum, item) => sum + this.toNumber((item as any).exemptAmount),
          0,
        );
        const itemDiscountAmount = categoryItems.reduce(
          (sum, item) => sum + this.toNumber((item as any).lineDiscountAmount),
          0,
        );
        const saleSold = this.toNumber(sale.totalSold);
        const allocation = saleSold > 0 ? itemSold / saleSold : 0;
        acc.totalSold += itemSold;
        acc.totalCost += itemCost;
        acc.totalProfit += itemProfit;
        acc.taxableBase += itemTaxableBase;
        acc.taxAmount += itemTaxAmount;
        acc.exemptAmount += itemExemptAmount;
        acc.discountAmount += itemDiscountAmount;
        acc.totalCommission +=
          this.toNumber(sale.commissionAmount) * allocation;
        acc.cash += this.toNumber(sale.paymentCashAmount) * allocation;
        acc.transfer += this.toNumber(sale.paymentTransferAmount) * allocation;
        return acc;
      },
      {
        totalSold: 0,
        totalCost: 0,
        totalProfit: 0,
        totalCommission: 0,
        cash: 0,
        transfer: 0,
        taxableBase: 0,
        taxAmount: 0,
        exemptAmount: 0,
        discountAmount: 0,
      },
    );

    const returns = visibleReturnedSales.reduce(
      (acc, sale) => {
        const categoryItems = this.saleItemsForCategory(sale, selectedCategory);
        acc.count += 1;
        acc.amount += Math.abs(categoryItems.reduce(
          (sum, item) => sum + this.toNumber(item.subtotalSold),
          0,
        ));
        acc.cost += Math.abs(categoryItems.reduce(
          (sum, item) => sum + this.toNumber(item.subtotalCost),
          0,
        ));
        acc.profit += Math.abs(categoryItems.reduce(
          (sum, item) => sum + this.toNumber(item.profit),
          0,
        ));
        return acc;
      },
      { count: 0, amount: 0, cost: 0, profit: 0 },
    );

    const expenses = movements.reduce(
      (acc, movement) => {
        const amount = this.toNumber(movement.amount);
        if (movement.type === "IN") acc.cashIn += amount;
        if (movement.type === "OUT") {
          acc.cashOut += amount;
          if (movement.movementType === "expense" && movement.affectsProfit) {
            acc.expenses += amount;
          }
        }
        return acc;
      },
      { cashIn: 0, cashOut: 0, expenses: 0 },
    );

    const salesSeries = new Map<string, number>();
    const profitSeries = new Map<string, number>();
    const productMap = new Map<
      string,
      {
        productName: string;
        totalSales: number;
        totalQty: number;
        totalProfit: number;
      }
    >();
    const clientMap = new Map<
      string,
      { clientName: string; totalSpent: number; purchaseCount: number }
    >();
    const categoryMap = new Map<
      string,
      {
        category: string;
        totalSales: number;
        totalCost: number;
        totalProfit: number;
        totalQty: number;
        salesCount: number;
      }
    >();
    let zeroCostItems = 0;
    let zeroCostSoldAmount = 0;

    for (const sale of visibleSales) {
      const categoryItems = this.saleItemsForCategory(sale, selectedCategory);
      const saleSold = categoryItems.reduce(
        (sum, item) => sum + this.toNumber(item.subtotalSold),
        0,
      );
      const saleProfit = categoryItems.reduce(
        (sum, item) => sum + this.toNumber(item.profit),
        0,
      );
      const day = this.formatDominicanDay(sale.saleDate);
      salesSeries.set(day, (salesSeries.get(day) ?? 0) + saleSold);
      profitSeries.set(day, (profitSeries.get(day) ?? 0) + saleProfit);

      const clientKey = sale.customerId ?? "general";
      const clientName = sale.customer?.nombre?.trim() || "Consumidor final";
      const client = clientMap.get(clientKey) ?? {
        clientName,
        totalSpent: 0,
        purchaseCount: 0,
      };
      client.totalSpent += saleSold;
      client.purchaseCount += 1;
      clientMap.set(clientKey, client);

      const countedCategories = new Set<string>();
      for (const item of categoryItems) {
        const itemCategory = this.itemCategory(item);
        const productKey = item.productId ?? item.productNameSnapshot;
        const product = productMap.get(productKey) ?? {
          productName: item.productNameSnapshot || "Producto sin nombre",
          totalSales: 0,
          totalQty: 0,
          totalProfit: 0,
        };
        product.totalSales += this.toNumber(item.subtotalSold);
        product.totalQty += this.toNumber(item.qty);
        product.totalProfit += this.toNumber(item.profit);
        productMap.set(productKey, product);

        const category = categoryMap.get(itemCategory) ?? {
          category: itemCategory,
          totalSales: 0,
          totalCost: 0,
          totalProfit: 0,
          totalQty: 0,
          salesCount: 0,
        };
        category.totalSales += this.toNumber(item.subtotalSold);
        category.totalCost += this.toNumber(item.subtotalCost);
        category.totalProfit += this.toNumber(item.profit);
        category.totalQty += this.toNumber(item.qty);
        if (!countedCategories.has(itemCategory)) {
          category.salesCount += 1;
          countedCategories.add(itemCategory);
        }
        categoryMap.set(itemCategory, category);

        if (this.toNumber(item.costUnitSnapshot) <= 0) {
          zeroCostItems += 1;
          zeroCostSoldAmount += this.toNumber(item.subtotalSold);
        }
      }
    }

    const inventory = products.reduce(
      (acc, product) => {
        const category = (product.categoria ?? "").trim() || "Sin categoria";
        if (
          selectedCategory &&
          this.normalizeCategoryKey(category) !== selectedCategory
        ) {
          return acc;
        }
        const stock = this.toNumber(product.stock);
        const cost = this.toNumber(product.costo);
        const price = this.toNumber(product.precio);
        acc.products += 1;
        acc.units += stock;
        acc.costValue += stock * cost;
        acc.saleValue += stock * price;
        if (stock <= 0) acc.outOfStock += 1;
        if (stock > 0 && stock <= 3) acc.lowStock += 1;
        if (cost <= 0) acc.productsWithoutCost += 1;
        return acc;
      },
      {
        products: 0,
        units: 0,
        costValue: 0,
        saleValue: 0,
        outOfStock: 0,
        lowStock: 0,
        productsWithoutCost: 0,
      },
    );

    const paymentMethods = [
      {
        method: "Efectivo",
        amount: totals.cash,
        count: visibleSales.filter(
          (sale) => this.toNumber(sale.paymentCashAmount) > 0,
        ).length,
      },
      {
        method: "Transferencia",
        amount: totals.transfer,
        count: visibleSales.filter(
          (sale) => this.toNumber(sale.paymentTransferAmount) > 0,
        ).length,
      },
    ].filter((row) => row.amount > 0 || row.count > 0);

    const profitExpenses = selectedCategory ? 0 : expenses.expenses;
    const cashIncome = selectedCategory
      ? totals.cash
      : totals.cash + expenses.cashIn;
    const cashExpense = selectedCategory ? 0 : expenses.cashOut;
    const netSales = totals.totalSold - returns.amount;
    const netProfit = totals.totalProfit - returns.profit - profitExpenses;
    const warnings = [
      ...(returns.count > 0
        ? [
            {
              code: "returns_present",
              severity: "info",
              message:
                "El reporte distingue ventas brutas, devoluciones y ventas netas usando snapshots historicos.",
            },
          ]
        : []),
      ...(zeroCostItems > 0
        ? [
            {
              code: "items_without_cost",
              severity: "warning",
              message: `${zeroCostItems} lineas vendidas tienen costo cero. La utilidad puede estar sobreestimada.`,
            },
          ]
        : []),
      ...(inventory.productsWithoutCost > 0
        ? [
            {
              code: "products_without_cost",
              severity: "warning",
              message: `${inventory.productsWithoutCost} productos del catalogo no tienen costo configurado.`,
            },
          ]
        : []),
    ];

    return {
      range: {
        from: range.gte,
        to: range.lt,
        timezone: "America/Santo_Domingo",
      },
      filters: {
        category: selectedCategory
          ? ([...categoryMap.keys()].find(
              (category) =>
                this.normalizeCategoryKey(category) === selectedCategory,
            ) ?? query.category)
          : null,
      },
      categories: this.availableCategories(products),
      kpis: {
        totalSales: visibleSales.length,
        grossSales: totals.totalSold,
        returnedSales: returns.amount,
        netSales,
        totalSold: netSales,
        totalCost: totals.totalCost,
        totalProfit: totals.totalProfit,
        commercialProfit: totals.totalProfit,
        netTaxProfit:
          totals.taxableBase + totals.exemptAmount > 0
            ? totals.taxableBase + totals.exemptAmount - totals.totalCost
            : totals.totalProfit,
        netProfit,
        totalCommission: totals.totalCommission,
        taxableBase: totals.taxableBase,
        taxAmount: totals.taxAmount,
        exemptAmount: totals.exemptAmount,
        discountAmount: totals.discountAmount,
        // Ticket promedio sobre el conteo de órdenes realmente visibles (respeta
        // el filtro de categoría); evita dividir por todas las ventas del rango.
        avgTicket:
          visibleSales.length === 0
            ? 0
            : totals.totalSold / visibleSales.length,
        totalReturns: returns.count,
        totalExpenses: profitExpenses,
        cashIncome,
        cashExpense,
        zeroCostItems,
        zeroCostSoldAmount,
      },
      salesSeries: this.seriesFromMap(salesSeries),
      profitSeries: this.seriesFromMap(profitSeries),
      paymentMethods,
      topProducts: [...productMap.values()]
        .sort((a, b) => b.totalSales - a.totalSales)
        .slice(0, 10),
      topClients: [...clientMap.values()]
        .sort((a, b) => b.totalSpent - a.totalSpent)
        .slice(0, 10),
      categoryProfits: [...categoryMap.values()].sort(
        (a, b) => b.totalProfit - a.totalProfit,
      ),
      inventory,
      audit: {
        source: "database",
        saleRows: visibleSales.length,
        saleItemRows: visibleSales.reduce(
          (sum, sale) =>
            sum + this.saleItemsForCategory(sale, selectedCategory).length,
          0,
        ),
        returnedRows: returns.count,
        refundDocumentRows: refundSales.length,
        cashMovementRows: movements.length,
        categoryFiltered: selectedCategory !== null,
        warnings,
      },
    };
  }

  private normalizeCategoryFilter(value: string | undefined) {
    const raw = (value ?? "").trim();
    if (!raw || raw.toLowerCase() === "all" || raw.toLowerCase() === "todas") {
      return null;
    }
    if (raw.length > 80) {
      throw new BadRequestException("Categoria invalida");
    }
    return this.normalizeCategoryKey(raw);
  }

  private normalizeCategoryKey(value: string) {
    return value.trim().replace(/\s+/g, " ").toLocaleLowerCase("es-DO");
  }

  private itemCategory(item: SaleOverviewItem) {
    return item.product?.categoria?.trim() || "Sin categoria";
  }

  private saleItemsForCategory(
    sale: SaleOverviewRow,
    categoryKey: string | null,
  ) {
    if (!categoryKey) return sale.items;
    return sale.items.filter(
      (item) =>
        this.normalizeCategoryKey(this.itemCategory(item)) === categoryKey,
    );
  }

  private availableCategories(products: Array<{ categoria: string }>) {
    return Array.from(
      new Set(
        products.map((product) => product.categoria?.trim() || "Sin categoria"),
      ),
    ).sort((a, b) => a.localeCompare(b, "es-DO"));
  }

  private buildDateRange(from?: string, to?: string): Prisma.DateTimeFilter {
    const start = this.parseDominicanDate(from, true);
    const end = this.parseDominicanDate(to, false);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      throw new BadRequestException("Rango de fechas invalido");
    }
    if (start.getTime() >= end.getTime()) {
      throw new BadRequestException(
        "La fecha inicial no puede ser mayor que la final",
      );
    }
    // Semántica de rango exclusivo: fecha >= inicio AND fecha < fin.
    // Evita la ventana de precisión de 23:59:59.999 que podría dejar fuera o
    // contar mal ventas cercanas a la medianoche (mismo criterio que /sales).
    return { gte: start, lt: end };
  }

  private parseDominicanDate(value: string | undefined, startOfDay: boolean) {
    const now = new Date();
    const fallback = `${now.getUTCFullYear()}-${`${now.getUTCMonth() + 1}`.padStart(2, "0")}-${`${now.getUTCDate()}`.padStart(2, "0")}`;
    const text = (value?.trim() || fallback).slice(0, 10);
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
    if (!match) return new Date(Number.NaN);
    const year = Number(match[1]);
    const month = Number(match[2]) - 1;
    const day = Number(match[3]);
    // América/Santo_Domingo es UTC-4 (sin horario de verano):
    // inicio de día = 04:00 UTC; fin = 04:00 UTC del día siguiente (exclusivo).
    if (startOfDay) return new Date(Date.UTC(year, month, day, 4, 0, 0, 0));
    return new Date(Date.UTC(year, month, day + 1, 4, 0, 0, 0));
  }

  private formatDominicanDay(date: Date) {
    const dominicanTime = new Date(date.getTime() - 4 * 60 * 60 * 1000);
    return `${dominicanTime.getUTCFullYear()}-${`${dominicanTime.getUTCMonth() + 1}`.padStart(2, "0")}-${`${dominicanTime.getUTCDate()}`.padStart(2, "0")}`;
  }

  private seriesFromMap(map: Map<string, number>) {
    return [...map.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([label, value]) => ({ label, value }));
  }

  private toNumber(value: MoneyLike) {
    if (value === null || value === undefined) return 0;
    if (typeof value === "number") return value;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    return Number(value) || 0;
  }
}
