import { BadRequestException, Injectable } from "@nestjs/common";
import { Prisma, ProductItemType, Role } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import {
  creditPaymentTotalsBySaleId,
  deriveSalePaymentBreakdown,
} from "../common/utils/sale-credit-payment.util";

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
type QuantityBucket = {
  unitCode: string;
  unitName: string;
  unitSymbol: string;
  unitPrecision: number;
  quantity: number;
  label: string;
};
type CashMovementSummary = {
  cashIn: number;
  cashOut: number;
  expenses: number;
  rowCount: number;
};
type ProductCatalogSummary = {
  categories: string[];
  inventory: {
    products: number;
    units: number;
    unitsByUnit: Map<string, QuantityBucket>;
    costValue: number;
    saleValue: number;
    outOfStock: number;
    lowStock: number;
    productsWithoutCost: number;
  };
};
type CreditPaymentPeriodSummary = {
  cash: number;
  transfer: number;
  cashOperations: number;
  transferOperations: number;
  rowCount: number;
};
type TopClientSummary = {
  clientName: string;
  totalSpent: number;
  purchaseCount: number;
};
type TopProductSummary = {
  productName: string;
  totalSales: number;
  totalQty: number;
  unitCode: string;
  unitName: string;
  unitSymbol: string;
  unitPrecision: number;
  totalQtyLabel: string;
  totalProfit: number;
};
type SalesSeriesSummary = {
  salesSeries: Array<{ label: string; value: number }>;
  profitSeries: Array<{ label: string; value: number }>;
};
type CategoryProfitSummary = {
  category: string;
  totalSales: number;
  totalCost: number;
  totalProfit: number;
  totalQty: number;
  quantityBuckets: QuantityBucket[];
  totalQtyLabel: string;
  salesCount: number;
};
type SalesOverviewFinancialSummary = {
  totalSales: number;
  saleItemRows: number;
  totalSold: number;
  totalCost: number;
  totalProfit: number;
  totalCommission: number;
  taxableBase: number;
  taxAmount: number;
  exemptAmount: number;
  discountAmount: number;
  initialCash: number;
  initialTransfer: number;
  initialCashOperations: number;
  initialTransferOperations: number;
  paymentBreakdownViolations: number;
  zeroCostItems: number;
  zeroCostSoldAmount: number;
  returnCount: number;
  returnedAmount: number;
  returnedCost: number;
  returnedProfit: number;
  refundDocumentRows: number;
};

const SALES_OVERVIEW_MAX_ROWS = 5000;

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async salesOverview(user: RequestUser, query: Record<string, string>) {
    const companyId = requireTenant(user);
    const range = this.buildDateRange(query.from, query.to);
    const selectedCategory = this.normalizeCategoryFilter(query.category);
    const canSeeAll = isAdminLike(user);
    const userFilter = canSeeAll ? {} : { userId: user.id };

    if (!selectedCategory && this.canUseRawAggregates()) {
      return this.salesOverviewNoCategoryAggregated({
        user,
        query,
        companyId,
        range,
        canSeeAll,
      });
    }

    const saleWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "invoice",
      saleDate: range,
    };
    const returnedWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "invoice",
      isDeleted: true,
      deletedAt: range,
    };
    const refundWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "refund",
      isDeleted: false,
      saleDate: range,
    };

    const companyPromise =
      (this.prisma as any).company?.findUnique?.({
        where: { id: companyId },
        select: { inventoryEnabled: true },
      }) ?? Promise.resolve(null);
    const [
      sales,
      returnedSales,
      refundSales,
      productCatalog,
      cashMovementSummary,
      cancelledInRangeSales,
      company,
    ] = await Promise.all([
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
          take: SALES_OVERVIEW_MAX_ROWS + 1,
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
          take: SALES_OVERVIEW_MAX_ROWS + 1,
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
          take: SALES_OVERVIEW_MAX_ROWS + 1,
        }),
        this.buildProductCatalogSummary(companyId, selectedCategory),
        this.buildCashMovementSummary({
          createdAt: range,
          companyId,
          ...(canSeeAll ? {} : { userId: user.id }),
        }),
        this.prisma.sale.findMany({
          where: {
            companyId,
            ...userFilter,
            kind: "invoice",
            isDeleted: true,
            deletedAt: range,
          },
          select: { id: true },
          take: SALES_OVERVIEW_MAX_ROWS + 1,
        }),
        companyPromise,
      ]);
    this.assertReportRowBudget("ventas", sales);
    this.assertReportRowBudget("ventas anuladas", returnedSales);
    this.assertReportRowBudget("devoluciones", refundSales);
    this.assertReportRowBudget(
      "ventas canceladas del rango",
      cancelledInRangeSales,
    );
    const inventoryEnabled = company?.inventoryEnabled !== false;

    const visibleSales = selectedCategory
      ? sales.filter(
          (sale) =>
            this.saleItemsForCategory(sale, selectedCategory).length > 0,
        )
      : sales;
    // Refunds of a cancelled sale are already covered by that sale's reversal
    // (returnedWhere for prior periods, or never counted at all when the sale
    // was created and cancelled inside this same period). Counting them again
    // as returns would discount the returned portion twice (600 + 200 = 800).
    const cancelledInRangeIds = new Set(
      cancelledInRangeSales.map((row) => row.id),
    );
    const visibleByCategory = (rows: typeof sales) =>
      selectedCategory
        ? rows.filter(
            (sale) =>
              this.saleItemsForCategory(sale, selectedCategory).length > 0,
          )
        : rows;
    const visibleCancelledSales = visibleByCategory(returnedSales);
    const visibleRefundSales = visibleByCategory(refundSales).filter(
      (refund) =>
        !refund.refundedSaleId ||
        !cancelledInRangeIds.has(refund.refundedSaleId),
    );
    const visibleReturnedSales = [
      ...visibleCancelledSales,
      ...visibleRefundSales,
    ];

    // ---------------------------------------------------------------------
    // DINERO DEVENGADO vs DINERO COBRADO.
    //
    // `Sale.paymentCashAmount/paymentTransferAmount` son ACUMULADOS: pago
    // inicial + todos los abonos posteriores. Usarlos directamente atribuía un
    // abono del 10/09 al reporte del 01/09. La composición correcta es:
    //   A) pago inicial (acumulado menos ledger lifetime de esa venta) de las
    //      ventas cuya `saleDate` cae en el período;
    //   B) abonos (`SaleCreditPayment`) cuyo `paidAt` real cae en el período.
    // Ambas lecturas son batched (sin N+1) y filtradas por `companyId`.
    // ---------------------------------------------------------------------
    const creditPaymentLedger = await creditPaymentTotalsBySaleId(this.prisma, {
      companyId,
      saleIds: visibleSales
        .filter((sale) => sale.paymentMethod === "credit")
        .map((sale) => sale.id),
    });

    // Semántica de filtro por usuario MANTENIDA (SELLER): el reporte atribuye
    // el dinero cobrado al vendedor de la venta, igual que antes de este fix.
    // El cobrador (`SaleCreditPayment.userId`) se conserva para auditoría.
    const creditPaymentPeriodSummary =
      await this.buildCreditPaymentPeriodSummary({
        companyId,
        range,
        sellerUserId: canSeeAll ? null : user.id,
        selectedCategory,
      });

    let paymentBreakdownViolations = 0;
    const initialPaymentBySaleId = new Map<
      string,
      { cash: number; transfer: number }
    >();
    for (const sale of visibleSales) {
      const ledger = creditPaymentLedger.get(sale.id);
      const breakdown = deriveSalePaymentBreakdown({
        cumulativeCash: sale.paymentCashAmount,
        cumulativeTransfer: sale.paymentTransferAmount,
        creditPaymentsCash: ledger?.cash,
        creditPaymentsTransfer: ledger?.transfer,
      });
      if (breakdown.invariantViolation) paymentBreakdownViolations += 1;
      initialPaymentBySaleId.set(sale.id, {
        cash: this.toNumber(breakdown.initialCash),
        transfer: this.toNumber(breakdown.initialTransfer),
      });
    }

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
        // Descuento general REAL del documento (comercial). lineDiscountAmount
        // ahora es solo el descuento comercial de línea; el general se asigna
        // proporcionalmente por categoría para no perderlo en el reporte.
        const saleLineDiscountTotal = sale.items.reduce(
          (sum, item) => sum + this.toNumber(item.lineDiscountAmount),
          0,
        );
        const generalDiscount = Math.max(
          0,
          this.toNumber(sale.discountAmount) - saleLineDiscountTotal,
        );
        const saleSold = this.toNumber(sale.totalSold);
        const allocation = saleSold > 0 ? itemSold / saleSold : 0;
        const initialPayment = initialPaymentBySaleId.get(sale.id) ?? {
          cash: 0,
          transfer: 0,
        };
        acc.totalSold += itemSold;
        acc.totalCost += itemCost;
        acc.totalProfit += itemProfit;
        acc.taxableBase += itemTaxableBase;
        acc.taxAmount += itemTaxAmount;
        acc.exemptAmount += itemExemptAmount;
        acc.discountAmount += itemDiscountAmount + generalDiscount * allocation;
        acc.totalCommission +=
          this.toNumber(sale.commissionAmount) * allocation;
        // Pago recibido AL CREAR la venta (atribuido a `saleDate`).
        acc.cash += initialPayment.cash * allocation;
        acc.transfer += initialPayment.transfer * allocation;
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

    // Abonos con fecha real (`paidAt`) dentro del período. Se prorratean por
    // categoría con el MISMO criterio ya usado para el pago inicial
    // (participación de la categoría en el total de la venta): no se inventa un
    // contrato de reparto nuevo.
    const creditPaymentsCashInPeriod = creditPaymentPeriodSummary.cash;
    const creditPaymentsTransferInPeriod = creditPaymentPeriodSummary.transfer;
    const creditPaymentsCashOperations =
      creditPaymentPeriodSummary.cashOperations;
    const creditPaymentsTransferOperations =
      creditPaymentPeriodSummary.transferOperations;
    totals.cash += creditPaymentsCashInPeriod;
    totals.transfer += creditPaymentsTransferInPeriod;

    const initialCashOperations = visibleSales.filter(
      (sale) => (initialPaymentBySaleId.get(sale.id)?.cash ?? 0) > 0,
    ).length;
    const initialTransferOperations = visibleSales.filter(
      (sale) => (initialPaymentBySaleId.get(sale.id)?.transfer ?? 0) > 0,
    ).length;

    const returns = visibleReturnedSales.reduce(
      (acc, sale) => {
        const categoryItems = this.saleItemsForCategory(sale, selectedCategory);
        acc.count += 1;
        acc.amount += Math.abs(
          categoryItems.reduce(
            (sum, item) => sum + this.toNumber(item.subtotalSold),
            0,
          ),
        );
        acc.cost += Math.abs(
          categoryItems.reduce(
            (sum, item) => sum + this.toNumber(item.subtotalCost),
            0,
          ),
        );
        acc.profit += Math.abs(
          categoryItems.reduce(
            (sum, item) => sum + this.toNumber(item.profit),
            0,
          ),
        );
        return acc;
      },
      { count: 0, amount: 0, cost: 0, profit: 0 },
    );

    const expenses = cashMovementSummary;

    const salesSeries = new Map<string, number>();
    const profitSeries = new Map<string, number>();
    const productMap = new Map<
      string,
      {
        productName: string;
        totalSales: number;
        totalQty: number;
        unitCode: string;
        unitName: string;
        unitSymbol: string;
        unitPrecision: number;
        totalQtyLabel: string;
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
        quantityBuckets: Map<string, QuantityBucket>;
        totalQtyLabel: string;
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
        const itemUnit = this.itemUnit(item);
        const productIdentity =
          item.productSource && item.sourceProductId
            ? `${item.productSource}:${item.sourceProductId}`
            : (item.productId ?? item.productNameSnapshot);
        const productKey = `${productIdentity}:${itemUnit.unitCode}`;
        const product = productMap.get(productKey) ?? {
          productName: item.productNameSnapshot || "Producto sin nombre",
          totalSales: 0,
          totalQty: 0,
          unitCode: itemUnit.unitCode,
          unitName: itemUnit.unitName,
          unitSymbol: itemUnit.unitSymbol,
          unitPrecision: itemUnit.unitPrecision,
          totalQtyLabel: "0",
          totalProfit: 0,
        };
        product.totalSales += this.toNumber(item.subtotalSold);
        product.totalQty += this.toNumber(item.qty);
        product.totalQtyLabel = this.quantityLabel(
          product.totalQty,
          product.unitSymbol,
          product.unitPrecision,
          product.unitCode,
        );
        product.totalProfit += this.toNumber(item.profit);
        productMap.set(productKey, product);

        const category = categoryMap.get(itemCategory) ?? {
          category: itemCategory,
          totalSales: 0,
          totalCost: 0,
          totalProfit: 0,
          totalQty: 0,
          quantityBuckets: new Map<string, QuantityBucket>(),
          totalQtyLabel: "0",
          salesCount: 0,
        };
        category.totalSales += this.toNumber(item.subtotalSold);
        category.totalCost += this.toNumber(item.subtotalCost);
        category.totalProfit += this.toNumber(item.profit);
        category.totalQty += this.toNumber(item.qty);
        this.addQuantityToBuckets(category.quantityBuckets, item);
        category.totalQtyLabel = this.quantityBucketsLabel(
          category.quantityBuckets,
        );
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

    const inventory = {
      ...productCatalog.inventory,
      outOfStock: inventoryEnabled ? productCatalog.inventory.outOfStock : 0,
      lowStock: inventoryEnabled ? productCatalog.inventory.lowStock : 0,
    };

    const paymentMethods = [
      {
        method: "Efectivo",
        amount: totals.cash,
        count: initialCashOperations + creditPaymentsCashOperations,
      },
      {
        method: "Transferencia",
        amount: totals.transfer,
        count: initialTransferOperations + creditPaymentsTransferOperations,
      },
    ].filter((row) => row.amount > 0 || row.count > 0);
    const legacyTopClients = () =>
      [...clientMap.values()]
        .sort((a, b) => b.totalSpent - a.totalSpent)
        .slice(0, 10);
    const topClients = selectedCategory
      ? legacyTopClients()
      : ((await this.buildTopClientsSummary({
          companyId,
          range,
          sellerUserId: canSeeAll ? null : user.id,
        })) ?? legacyTopClients());
    const legacyTopProducts = () =>
      [...productMap.values()]
        .sort((a, b) => b.totalSales - a.totalSales)
        .slice(0, 10);
    const topProducts = selectedCategory
      ? legacyTopProducts()
      : ((await this.buildTopProductsSummary({
          companyId,
          range,
          sellerUserId: canSeeAll ? null : user.id,
        })) ?? legacyTopProducts());
    const legacySeries = (): SalesSeriesSummary => ({
      salesSeries: this.seriesFromMap(salesSeries),
      profitSeries: this.seriesFromMap(profitSeries),
    });
    const series = selectedCategory
      ? legacySeries()
      : ((await this.buildSalesSeriesSummary({
          companyId,
          range,
          sellerUserId: canSeeAll ? null : user.id,
        })) ?? legacySeries());
    const legacyCategoryProfits = (): CategoryProfitSummary[] =>
      [...categoryMap.values()]
        .map((row) => ({
          ...row,
          quantityBuckets: [...row.quantityBuckets.values()],
        }))
        .sort((a, b) => b.totalProfit - a.totalProfit);
    const categoryProfits = selectedCategory
      ? legacyCategoryProfits()
      : ((await this.buildCategoryProfitsSummary({
          companyId,
          range,
          sellerUserId: canSeeAll ? null : user.id,
        })) ?? legacyCategoryProfits());

    const profitExpenses = selectedCategory ? 0 : expenses.expenses;
    const cashIncome = selectedCategory
      ? totals.cash
      : totals.cash + expenses.cashIn;
    const cashExpense = selectedCategory ? 0 : expenses.cashOut;
    const netSales = totals.totalSold - returns.amount;
    const netProfit = totals.totalProfit - returns.profit - profitExpenses;
    const warnings = [
      ...(paymentBreakdownViolations > 0
        ? [
            {
              code: "payment_breakdown_invariant_violation",
              severity: "warning",
              message:
                `${paymentBreakdownViolations} ventas tienen abonos registrados por encima del efectivo/transferencia acumulado de la venta. El efectivo se expone sin recortar para que la inconsistencia sea auditable.`,
            },
          ]
        : []),
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
      categories: productCatalog.categories,
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
        // Efectivo/transferencia cobrados por abonos de crédito DENTRO del
        // período (fecha real `paidAt`), separados del pago inicial.
        creditPaymentsCash: creditPaymentsCashInPeriod,
        creditPaymentsTransfer: creditPaymentsTransferInPeriod,
        creditPaymentsCount: creditPaymentPeriodSummary.rowCount,
        zeroCostItems,
        zeroCostSoldAmount,
      },
      salesSeries: series.salesSeries,
      profitSeries: series.profitSeries,
      paymentMethods,
      topProducts,
      topClients,
      categoryProfits,
      inventory: {
        ...inventory,
        unitsByUnit: [...inventory.unitsByUnit.values()],
        unitsLabel: this.quantityBucketsLabel(inventory.unitsByUnit),
      },
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
        cashMovementRows: cashMovementSummary.rowCount,
        creditPaymentRows: creditPaymentPeriodSummary.rowCount,
        paymentBreakdownViolations,
        categoryFiltered: selectedCategory !== null,
        warnings,
      },
    };
  }

  private canUseRawAggregates() {
    const queryRaw = (this.prisma as unknown as { $queryRaw?: unknown }).$queryRaw;
    return typeof queryRaw === "function" && !(queryRaw as any)._isMockFunction;
  }

  private async salesOverviewNoCategoryAggregated(params: {
    user: RequestUser;
    query: Record<string, string>;
    companyId: string;
    range: Prisma.DateTimeFilter;
    canSeeAll: boolean;
  }) {
    const sellerUserId = params.canSeeAll ? null : params.user.id;
    const [
      company,
      financial,
      productCatalog,
      cashMovementSummary,
      creditPaymentPeriodSummary,
      topClients,
      topProducts,
      series,
      categoryProfits,
    ] = await Promise.all([
      (this.prisma as any).company?.findUnique?.({
        where: { id: params.companyId },
        select: { inventoryEnabled: true },
      }) ?? Promise.resolve(null),
      this.buildSalesOverviewFinancialSummary({
        companyId: params.companyId,
        range: params.range,
        sellerUserId,
      }),
      this.buildProductCatalogSummary(params.companyId, null),
      this.buildCashMovementSummary({
        createdAt: params.range,
        companyId: params.companyId,
        ...(sellerUserId ? { userId: sellerUserId } : {}),
      }),
      this.buildCreditPaymentPeriodSummary({
        companyId: params.companyId,
        range: params.range,
        sellerUserId,
        selectedCategory: null,
      }),
      this.buildTopClientsSummary({
        companyId: params.companyId,
        range: params.range,
        sellerUserId,
      }),
      this.buildTopProductsSummary({
        companyId: params.companyId,
        range: params.range,
        sellerUserId,
      }),
      this.buildSalesSeriesSummary({
        companyId: params.companyId,
        range: params.range,
        sellerUserId,
      }),
      this.buildCategoryProfitsSummary({
        companyId: params.companyId,
        range: params.range,
        sellerUserId,
      }),
    ]);

    const inventoryEnabled = company?.inventoryEnabled !== false;
    const inventory = {
      ...productCatalog.inventory,
      outOfStock: inventoryEnabled ? productCatalog.inventory.outOfStock : 0,
      lowStock: inventoryEnabled ? productCatalog.inventory.lowStock : 0,
    };
    const totalsCash =
      financial.initialCash + creditPaymentPeriodSummary.cash;
    const totalsTransfer =
      financial.initialTransfer + creditPaymentPeriodSummary.transfer;
    const initialCashOperations = financial.initialCashOperations;
    const initialTransferOperations = financial.initialTransferOperations;
    const paymentMethods = [
      {
        method: "Efectivo",
        amount: totalsCash,
        count: initialCashOperations + creditPaymentPeriodSummary.cashOperations,
      },
      {
        method: "Transferencia",
        amount: totalsTransfer,
        count:
          initialTransferOperations +
          creditPaymentPeriodSummary.transferOperations,
      },
    ].filter((row) => row.amount > 0 || row.count > 0);
    const netSales = financial.totalSold - financial.returnedAmount;
    const netProfit =
      financial.totalProfit -
      financial.returnedProfit -
      cashMovementSummary.expenses;
    const warnings = [
      ...(financial.paymentBreakdownViolations > 0
        ? [
            {
              code: "payment_breakdown_invariant_violation",
              severity: "warning",
              message:
                `${financial.paymentBreakdownViolations} ventas tienen abonos registrados por encima del efectivo/transferencia acumulado de la venta. El efectivo se expone sin recortar para que la inconsistencia sea auditable.`,
            },
          ]
        : []),
      ...(financial.returnCount > 0
        ? [
            {
              code: "returns_present",
              severity: "info",
              message:
                "El reporte distingue ventas brutas, devoluciones y ventas netas usando snapshots historicos.",
            },
          ]
        : []),
      ...(financial.zeroCostItems > 0
        ? [
            {
              code: "items_without_cost",
              severity: "warning",
              message: `${financial.zeroCostItems} lineas vendidas tienen costo cero. La utilidad puede estar sobreestimada.`,
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
        from: params.range.gte,
        to: params.range.lt,
        timezone: "America/Santo_Domingo",
      },
      filters: { category: null },
      categories: productCatalog.categories,
      kpis: {
        totalSales: financial.totalSales,
        grossSales: financial.totalSold,
        returnedSales: financial.returnedAmount,
        netSales,
        totalSold: netSales,
        totalCost: financial.totalCost,
        totalProfit: financial.totalProfit,
        commercialProfit: financial.totalProfit,
        netTaxProfit:
          financial.taxableBase + financial.exemptAmount > 0
            ? financial.taxableBase +
              financial.exemptAmount -
              financial.totalCost
            : financial.totalProfit,
        netProfit,
        totalCommission: financial.totalCommission,
        taxableBase: financial.taxableBase,
        taxAmount: financial.taxAmount,
        exemptAmount: financial.exemptAmount,
        discountAmount: financial.discountAmount,
        avgTicket:
          financial.totalSales === 0
            ? 0
            : financial.totalSold / financial.totalSales,
        totalReturns: financial.returnCount,
        totalExpenses: cashMovementSummary.expenses,
        cashIncome: totalsCash + cashMovementSummary.cashIn,
        cashExpense: cashMovementSummary.cashOut,
        creditPaymentsCash: creditPaymentPeriodSummary.cash,
        creditPaymentsTransfer: creditPaymentPeriodSummary.transfer,
        creditPaymentsCount: creditPaymentPeriodSummary.rowCount,
        zeroCostItems: financial.zeroCostItems,
        zeroCostSoldAmount: financial.zeroCostSoldAmount,
      },
      salesSeries: series?.salesSeries ?? [],
      profitSeries: series?.profitSeries ?? [],
      paymentMethods,
      topProducts: topProducts ?? [],
      topClients: topClients ?? [],
      categoryProfits: categoryProfits ?? [],
      inventory: {
        ...inventory,
        unitsByUnit: [...inventory.unitsByUnit.values()],
        unitsLabel: this.quantityBucketsLabel(inventory.unitsByUnit),
      },
      audit: {
        source: "database",
        saleRows: financial.totalSales,
        saleItemRows: financial.saleItemRows,
        returnedRows: financial.returnCount,
        refundDocumentRows: financial.refundDocumentRows,
        cashMovementRows: cashMovementSummary.rowCount,
        creditPaymentRows: creditPaymentPeriodSummary.rowCount,
        paymentBreakdownViolations: financial.paymentBreakdownViolations,
        categoryFiltered: false,
        warnings,
      },
    };
  }

  private async buildSalesOverviewFinancialSummary(params: {
    companyId: string;
    range: Prisma.DateTimeFilter;
    sellerUserId: string | null;
  }): Promise<SalesOverviewFinancialSummary> {
    const sellerFilter = params.sellerUserId
      ? Prisma.sql`AND s."userId" = ${params.sellerUserId}`
      : Prisma.empty;
    const rows = await (this.prisma as unknown as {
      $queryRaw: <T = unknown>(query: Prisma.Sql) => Promise<T>;
    }).$queryRaw<
      Array<{
        totalSales: bigint | number | string | null;
        saleItemRows: bigint | number | string | null;
        totalSold: MoneyLike;
        totalCost: MoneyLike;
        totalProfit: MoneyLike;
        totalCommission: MoneyLike;
        taxableBase: MoneyLike;
        taxAmount: MoneyLike;
        exemptAmount: MoneyLike;
        discountAmount: MoneyLike;
        initialCash: MoneyLike;
        initialTransfer: MoneyLike;
        initialCashOperations: bigint | number | string | null;
        initialTransferOperations: bigint | number | string | null;
        paymentBreakdownViolations: bigint | number | string | null;
        zeroCostItems: bigint | number | string | null;
        zeroCostSoldAmount: MoneyLike;
        returnCount: bigint | number | string | null;
        returnedAmount: MoneyLike;
        returnedCost: MoneyLike;
        returnedProfit: MoneyLike;
        refundDocumentRows: bigint | number | string | null;
      }>
    >(Prisma.sql`
      WITH invoice_sales AS (
        SELECT s.*
        FROM "Sale" s
        WHERE s."company_id" = ${params.companyId}
          AND s."kind" = 'invoice'
          AND s."saleDate" >= ${params.range.gte as Date}
          AND s."saleDate" < ${params.range.lt as Date}
          ${sellerFilter}
      ),
      item_totals AS (
        SELECT
          si."saleId",
          COUNT(*) AS "itemRows",
          COALESCE(SUM(si."subtotalSold"), 0) AS "totalSold",
          COALESCE(SUM(si."subtotalCost"), 0) AS "totalCost",
          COALESCE(SUM(si."profit"), 0) AS "totalProfit",
          COALESCE(SUM(si."taxable_base"), 0) AS "taxableBase",
          COALESCE(SUM(si."tax_amount"), 0) AS "taxAmount",
          COALESCE(SUM(si."exempt_amount"), 0) AS "exemptAmount",
          COALESCE(SUM(si."line_discount_amount"), 0) AS "lineDiscount",
          SUM(CASE WHEN si."costUnitSnapshot" <= 0 THEN 1 ELSE 0 END) AS "zeroCostItems",
          COALESCE(SUM(CASE WHEN si."costUnitSnapshot" <= 0 THEN si."subtotalSold" ELSE 0 END), 0) AS "zeroCostSoldAmount"
        FROM "SaleItem" si
        INNER JOIN invoice_sales s ON s."id" = si."saleId"
        GROUP BY si."saleId"
      ),
      credit_lifetime AS (
        SELECT
          cp."saleId",
          COALESCE(SUM(cp."cashAmount"), 0) AS "creditCash",
          COALESCE(SUM(cp."transferAmount"), 0) AS "creditTransfer"
        FROM "sale_credit_payments" cp
        WHERE cp."company_id" = ${params.companyId}
        GROUP BY cp."saleId"
      ),
      per_sale AS (
        SELECT
          s."id",
          COALESCE(it."itemRows", 0) AS "itemRows",
          COALESCE(it."totalSold", 0) AS "totalSold",
          COALESCE(it."totalCost", 0) AS "totalCost",
          COALESCE(it."totalProfit", 0) AS "totalProfit",
          COALESCE(s."commissionAmount", 0) AS "commissionAmount",
          COALESCE(it."taxableBase", 0) AS "taxableBase",
          COALESCE(it."taxAmount", 0) AS "taxAmount",
          COALESCE(it."exemptAmount", 0) AS "exemptAmount",
          COALESCE(it."lineDiscount", 0) AS "lineDiscount",
          GREATEST(0, COALESCE(s."discount_amount", 0) - COALESCE(it."lineDiscount", 0)) AS "generalDiscount",
          COALESCE(s."paymentCashAmount", 0) - COALESCE(cl."creditCash", 0) AS "initialCash",
          COALESCE(s."paymentTransferAmount", 0) - COALESCE(cl."creditTransfer", 0) AS "initialTransfer",
          CASE WHEN COALESCE(cl."creditCash", 0) - COALESCE(s."paymentCashAmount", 0) > 0.005
             OR COALESCE(cl."creditTransfer", 0) - COALESCE(s."paymentTransferAmount", 0) > 0.005
            THEN 1 ELSE 0 END AS "breakdownViolation",
          COALESCE(it."zeroCostItems", 0) AS "zeroCostItems",
          COALESCE(it."zeroCostSoldAmount", 0) AS "zeroCostSoldAmount"
        FROM invoice_sales s
        LEFT JOIN item_totals it ON it."saleId" = s."id"
        LEFT JOIN credit_lifetime cl ON cl."saleId" = s."id"
      ),
      cancelled_in_range AS (
        SELECT s."id"
        FROM "Sale" s
        WHERE s."company_id" = ${params.companyId}
          AND s."kind" = 'invoice'
          AND s."isDeleted" = true
          AND s."deletedAt" >= ${params.range.gte as Date}
          AND s."deletedAt" < ${params.range.lt as Date}
          ${sellerFilter}
      ),
      refund_documents_all AS (
        SELECT s."id", s."refunded_sale_id"
        FROM "Sale" s
        WHERE s."company_id" = ${params.companyId}
          AND s."kind" = 'refund'
          AND s."isDeleted" = false
          AND s."saleDate" >= ${params.range.gte as Date}
          AND s."saleDate" < ${params.range.lt as Date}
          ${sellerFilter}
      ),
      return_documents AS (
        SELECT ci."id"
        FROM cancelled_in_range ci
        UNION ALL
        SELECT r."id"
        FROM refund_documents_all r
        WHERE r."refunded_sale_id" IS NULL
          OR NOT EXISTS (
            SELECT 1 FROM cancelled_in_range ci WHERE ci."id" = r."refunded_sale_id"
          )
      ),
      return_item_totals AS (
        SELECT
          rd."id",
          COALESCE(SUM(si."subtotalSold"), 0) AS "returnedAmount",
          COALESCE(SUM(si."subtotalCost"), 0) AS "returnedCost",
          COALESCE(SUM(si."profit"), 0) AS "returnedProfit"
        FROM return_documents rd
        LEFT JOIN "SaleItem" si ON si."saleId" = rd."id"
        GROUP BY rd."id"
      )
      SELECT
        (SELECT COUNT(*) FROM per_sale) AS "totalSales",
        (SELECT COALESCE(SUM("itemRows"), 0) FROM per_sale) AS "saleItemRows",
        (SELECT COALESCE(SUM("totalSold"), 0) FROM per_sale) AS "totalSold",
        (SELECT COALESCE(SUM("totalCost"), 0) FROM per_sale) AS "totalCost",
        (SELECT COALESCE(SUM("totalProfit"), 0) FROM per_sale) AS "totalProfit",
        (SELECT COALESCE(SUM("commissionAmount"), 0) FROM per_sale) AS "totalCommission",
        (SELECT COALESCE(SUM("taxableBase"), 0) FROM per_sale) AS "taxableBase",
        (SELECT COALESCE(SUM("taxAmount"), 0) FROM per_sale) AS "taxAmount",
        (SELECT COALESCE(SUM("exemptAmount"), 0) FROM per_sale) AS "exemptAmount",
        (SELECT COALESCE(SUM("lineDiscount" + "generalDiscount"), 0) FROM per_sale) AS "discountAmount",
        (SELECT COALESCE(SUM("initialCash"), 0) FROM per_sale) AS "initialCash",
        (SELECT COALESCE(SUM("initialTransfer"), 0) FROM per_sale) AS "initialTransfer",
        (SELECT COUNT(*) FROM per_sale WHERE "initialCash" > 0) AS "initialCashOperations",
        (SELECT COUNT(*) FROM per_sale WHERE "initialTransfer" > 0) AS "initialTransferOperations",
        (SELECT COALESCE(SUM("breakdownViolation"), 0) FROM per_sale) AS "paymentBreakdownViolations",
        (SELECT COALESCE(SUM("zeroCostItems"), 0) FROM per_sale) AS "zeroCostItems",
        (SELECT COALESCE(SUM("zeroCostSoldAmount"), 0) FROM per_sale) AS "zeroCostSoldAmount",
        (SELECT COUNT(*) FROM return_documents) AS "returnCount",
        (SELECT COALESCE(SUM(ABS("returnedAmount")), 0) FROM return_item_totals) AS "returnedAmount",
        (SELECT COALESCE(SUM(ABS("returnedCost")), 0) FROM return_item_totals) AS "returnedCost",
        (SELECT COALESCE(SUM(ABS("returnedProfit")), 0) FROM return_item_totals) AS "returnedProfit",
        (SELECT COUNT(*) FROM refund_documents_all) AS "refundDocumentRows"
    `);
    const row = rows[0] ?? {};
    return {
      totalSales: Number(row.totalSales ?? 0),
      saleItemRows: Number(row.saleItemRows ?? 0),
      totalSold: this.toNumber(row.totalSold),
      totalCost: this.toNumber(row.totalCost),
      totalProfit: this.toNumber(row.totalProfit),
      totalCommission: this.toNumber(row.totalCommission),
      taxableBase: this.toNumber(row.taxableBase),
      taxAmount: this.toNumber(row.taxAmount),
      exemptAmount: this.toNumber(row.exemptAmount),
      discountAmount: this.toNumber(row.discountAmount),
      initialCash: this.toNumber(row.initialCash),
      initialTransfer: this.toNumber(row.initialTransfer),
      initialCashOperations: Number(row.initialCashOperations ?? 0),
      initialTransferOperations: Number(row.initialTransferOperations ?? 0),
      paymentBreakdownViolations: Number(row.paymentBreakdownViolations ?? 0),
      zeroCostItems: Number(row.zeroCostItems ?? 0),
      zeroCostSoldAmount: this.toNumber(row.zeroCostSoldAmount),
      returnCount: Number(row.returnCount ?? 0),
      returnedAmount: this.toNumber(row.returnedAmount),
      returnedCost: this.toNumber(row.returnedCost),
      returnedProfit: this.toNumber(row.returnedProfit),
      refundDocumentRows: Number(row.refundDocumentRows ?? 0),
    };
  }

  private async buildCashMovementSummary(
    where: Prisma.CashMovementWhereInput,
  ): Promise<CashMovementSummary> {
    const delegate = this.prisma.cashMovement as unknown as {
      groupBy?: (args: unknown) => Promise<
        Array<{
          type: string | null;
          movementType: string | null;
          affectsProfit: boolean | null;
          _sum: { amount: MoneyLike };
          _count: { _all: number };
        }>
      >;
      findMany: (args: unknown) => Promise<
        Array<{
          type: string;
          movementType: string;
          affectsProfit: boolean;
          amount: MoneyLike;
        }>
      >;
    };

    if (typeof delegate.groupBy === "function") {
      const rows = await delegate.groupBy({
        by: ["type", "movementType", "affectsProfit"],
        where,
        _sum: { amount: true },
        _count: { _all: true },
      });
      return rows.reduce<CashMovementSummary>(
        (acc, row) => {
          const amount = this.toNumber(row._sum.amount);
          acc.rowCount += row._count._all;
          if (row.type === "IN") acc.cashIn += amount;
          if (row.type === "OUT") {
            acc.cashOut += amount;
            if (row.movementType === "expense" && row.affectsProfit) {
              acc.expenses += amount;
            }
          }
          return acc;
        },
        { cashIn: 0, cashOut: 0, expenses: 0, rowCount: 0 },
      );
    }

    const rows = await delegate.findMany({
      where,
      take: SALES_OVERVIEW_MAX_ROWS + 1,
    });
    this.assertReportRowBudget("movimientos de caja", rows);
    return rows.reduce<CashMovementSummary>(
      (acc, movement) => {
        const amount = this.toNumber(movement.amount);
        acc.rowCount += 1;
        if (movement.type === "IN") acc.cashIn += amount;
        if (movement.type === "OUT") {
          acc.cashOut += amount;
          if (movement.movementType === "expense" && movement.affectsProfit) {
            acc.expenses += amount;
          }
        }
        return acc;
      },
      { cashIn: 0, cashOut: 0, expenses: 0, rowCount: 0 },
    );
  }

  private async buildProductCatalogSummary(
    companyId: string,
    selectedCategory: string | null,
  ): Promise<ProductCatalogSummary> {
    const delegate = this.prisma as unknown as {
      $queryRaw?: <T = unknown>(query: TemplateStringsArray | Prisma.Sql) => Promise<T>;
      product: {
        findMany: (args: unknown) => Promise<
          Array<{
            categoria: string | null;
            costo: MoneyLike;
            precio: MoneyLike;
            stock: MoneyLike;
            unitOfMeasure?: {
              code: string;
              name: string;
              symbol: string;
              precision: number;
            } | null;
          }>
        >;
      };
    };

    if (typeof delegate.$queryRaw === "function") {
      const normalizedCategorySql = Prisma.sql`lower(regexp_replace(btrim(COALESCE(p."categoria", '')), '\s+', ' ', 'g'))`;
      const categoryFilter = selectedCategory
        ? Prisma.sql`AND ${normalizedCategorySql} = ${selectedCategory}`
        : Prisma.empty;
      const rows = await delegate.$queryRaw<
        Array<{
          category: string | null;
          unitCode: string | null;
          unitName: string | null;
          unitSymbol: string | null;
          unitPrecision: number | null;
          products: bigint | number | string | null;
          units: MoneyLike;
          costValue: MoneyLike;
          saleValue: MoneyLike;
          outOfStock: bigint | number | string | null;
          lowStock: bigint | number | string | null;
          productsWithoutCost: bigint | number | string | null;
        }>
      >(Prisma.sql`
        SELECT
          COALESCE(NULLIF(btrim(p."categoria"), ''), 'Sin categoria') AS "category",
          COALESCE(u."code", 'UNIT') AS "unitCode",
          COALESCE(u."name", 'Unidad') AS "unitName",
          COALESCE(u."symbol", 'u') AS "unitSymbol",
          COALESCE(u."precision", 0) AS "unitPrecision",
          COUNT(*) AS "products",
          COALESCE(SUM(p."stock"), 0) AS "units",
          COALESCE(SUM(p."stock" * p."costo"), 0) AS "costValue",
          COALESCE(SUM(p."stock" * p."precio"), 0) AS "saleValue",
          SUM(CASE WHEN p."stock" <= 0 THEN 1 ELSE 0 END) AS "outOfStock",
          SUM(CASE WHEN p."stock" > 0 AND p."stock" <= 3 THEN 1 ELSE 0 END) AS "lowStock",
          SUM(CASE WHEN p."costo" <= 0 THEN 1 ELSE 0 END) AS "productsWithoutCost"
        FROM "Product" p
        LEFT JOIN "unit_of_measures" u ON u."id" = p."unit_of_measure_id"
        WHERE p."company_id" = ${companyId}
          AND p."item_type" = CAST(${ProductItemType.PRODUCT} AS "product_item_type")
          AND p."track_inventory" = true
          ${categoryFilter}
        GROUP BY
          COALESCE(NULLIF(btrim(p."categoria"), ''), 'Sin categoria'),
          COALESCE(u."code", 'UNIT'),
          COALESCE(u."name", 'Unidad'),
          COALESCE(u."symbol", 'u'),
          COALESCE(u."precision", 0)
      `);

      const categories = selectedCategory
        ? rows.map((row) => row.category?.trim() || "Sin categoria")
        : await this.productCategoriesFromDatabase(companyId);
      return this.productCatalogSummaryFromRows(categories, rows);
    }

    return this.buildProductCatalogSummaryLegacy(companyId, selectedCategory);
  }

  private async buildCreditPaymentPeriodSummary(params: {
    companyId: string;
    range: Prisma.DateTimeFilter;
    sellerUserId: string | null;
    selectedCategory: string | null;
  }): Promise<CreditPaymentPeriodSummary> {
    const delegate = this.prisma as unknown as {
      $queryRaw?: <T = unknown>(query: Prisma.Sql) => Promise<T>;
      saleCreditPayment: {
        findMany: (args: unknown) => Promise<
          Array<{
            cashAmount: MoneyLike;
            transferAmount: MoneyLike;
            amount: MoneyLike;
            sale: {
              items: Array<{
                subtotalSold: MoneyLike;
                product: { categoria: string | null } | null;
              }>;
            };
          }>
        >;
      };
    };

    if (!params.selectedCategory && typeof delegate.$queryRaw === "function") {
      const sellerFilter = params.sellerUserId
        ? Prisma.sql`AND s."userId" = ${params.sellerUserId}`
        : Prisma.empty;
      const rows = await delegate.$queryRaw<
        Array<{
          cash: MoneyLike;
          transfer: MoneyLike;
          cashOperations: bigint | number | string | null;
          transferOperations: bigint | number | string | null;
          rowCount: bigint | number | string | null;
        }>
      >(Prisma.sql`
        SELECT
          COALESCE(SUM(cp."cashAmount"), 0) AS "cash",
          COALESCE(SUM(cp."transferAmount"), 0) AS "transfer",
          SUM(CASE WHEN cp."cashAmount" > 0 THEN 1 ELSE 0 END) AS "cashOperations",
          SUM(CASE WHEN cp."transferAmount" > 0 THEN 1 ELSE 0 END) AS "transferOperations",
          COUNT(*) AS "rowCount"
        FROM "sale_credit_payments" cp
        INNER JOIN "Sale" s ON s."id" = cp."saleId"
        WHERE cp."company_id" = ${params.companyId}
          AND cp."paidAt" >= ${params.range.gte as Date}
          AND cp."paidAt" < ${params.range.lt as Date}
          ${sellerFilter}
      `);
      const row = rows[0] ?? {
        cash: 0,
        transfer: 0,
        cashOperations: 0,
        transferOperations: 0,
        rowCount: 0,
      };
      return {
        cash: this.toNumber(row.cash),
        transfer: this.toNumber(row.transfer),
        cashOperations: Number(row.cashOperations ?? 0),
        transferOperations: Number(row.transferOperations ?? 0),
        rowCount: Number(row.rowCount ?? 0),
      };
    }

    const rows = await delegate.saleCreditPayment.findMany({
      where: {
        companyId: params.companyId,
        paidAt: params.range,
        ...(params.sellerUserId ? { sale: { userId: params.sellerUserId } } : {}),
      },
      select: {
        saleId: true,
        cashAmount: true,
        transferAmount: true,
        amount: true,
        sale: {
          select: {
            items: {
              select: {
                subtotalSold: true,
                product: { select: { categoria: true } },
              },
            },
          },
        },
      },
      take: SALES_OVERVIEW_MAX_ROWS + 1,
    });
    this.assertReportRowBudget("abonos de credito", rows);
    return rows.reduce<CreditPaymentPeriodSummary>(
      (acc, payment) => {
        const allocation = this.paymentCategoryAllocation(
          payment,
          params.selectedCategory,
        );
        if (allocation <= 0) return acc;
        const cash = this.toNumber(payment.cashAmount) * allocation;
        const transfer = this.toNumber(payment.transferAmount) * allocation;
        if (cash > 0) acc.cashOperations += 1;
        if (transfer > 0) acc.transferOperations += 1;
        acc.cash += cash;
        acc.transfer += transfer;
        acc.rowCount += 1;
        return acc;
      },
      {
        cash: 0,
        transfer: 0,
        cashOperations: 0,
        transferOperations: 0,
        rowCount: 0,
      },
    );
  }

  private async buildTopClientsSummary(params: {
    companyId: string;
    range: Prisma.DateTimeFilter;
    sellerUserId: string | null;
  }): Promise<TopClientSummary[] | null> {
    const delegate = this.prisma as unknown as {
      $queryRaw?: <T = unknown>(query: Prisma.Sql) => Promise<T>;
    };
    if (typeof delegate.$queryRaw !== "function") return null;
    const sellerFilter = params.sellerUserId
      ? Prisma.sql`AND s."userId" = ${params.sellerUserId}`
      : Prisma.empty;
    const rows = await delegate.$queryRaw<
      Array<{
        clientName: string | null;
        totalSpent: MoneyLike;
        purchaseCount: bigint | number | string | null;
      }>
    >(Prisma.sql`
      SELECT
        COALESCE(NULLIF(btrim(c."nombre"), ''), 'Consumidor final') AS "clientName",
        COALESCE(SUM(per_sale."saleTotal"), 0) AS "totalSpent",
        COUNT(*) AS "purchaseCount"
      FROM (
        SELECT
          s."id",
          s."customerId",
          COALESCE(SUM(si."subtotalSold"), 0) AS "saleTotal"
        FROM "Sale" s
        LEFT JOIN "SaleItem" si ON si."saleId" = s."id"
        WHERE s."company_id" = ${params.companyId}
          AND s."kind" = 'invoice'
          AND s."saleDate" >= ${params.range.gte as Date}
          AND s."saleDate" < ${params.range.lt as Date}
          ${sellerFilter}
        GROUP BY s."id", s."customerId"
      ) per_sale
      LEFT JOIN "Client" c ON c."id" = per_sale."customerId"
      GROUP BY COALESCE(NULLIF(btrim(c."nombre"), ''), 'Consumidor final')
      ORDER BY "totalSpent" DESC, "clientName" ASC
      LIMIT 10
    `);
    return rows.map((row) => ({
      clientName: row.clientName?.trim() || "Consumidor final",
      totalSpent: this.toNumber(row.totalSpent),
      purchaseCount: Number(row.purchaseCount ?? 0),
    }));
  }

  private async buildTopProductsSummary(params: {
    companyId: string;
    range: Prisma.DateTimeFilter;
    sellerUserId: string | null;
  }): Promise<TopProductSummary[] | null> {
    const delegate = this.prisma as unknown as {
      $queryRaw?: <T = unknown>(query: Prisma.Sql) => Promise<T>;
    };
    if (typeof delegate.$queryRaw !== "function") return null;
    const sellerFilter = params.sellerUserId
      ? Prisma.sql`AND s."userId" = ${params.sellerUserId}`
      : Prisma.empty;
    const rows = await delegate.$queryRaw<
      Array<{
        productName: string | null;
        totalSales: MoneyLike;
        totalQty: MoneyLike;
        unitCode: string | null;
        unitName: string | null;
        unitSymbol: string | null;
        unitPrecision: number | null;
        totalProfit: MoneyLike;
      }>
    >(Prisma.sql`
      SELECT
        MIN(NULLIF(btrim(si."productNameSnapshot"), '')) AS "productName",
        COALESCE(SUM(si."subtotalSold"), 0) AS "totalSales",
        COALESCE(SUM(si."qty"), 0) AS "totalQty",
        COALESCE(NULLIF(btrim(si."unit_code_snapshot"), ''), 'UNIT') AS "unitCode",
        COALESCE(NULLIF(btrim(si."unit_name_snapshot"), ''), 'Unidad') AS "unitName",
        COALESCE(NULLIF(btrim(si."unit_symbol_snapshot"), ''), 'u') AS "unitSymbol",
        COALESCE(si."unit_precision_snapshot", 0) AS "unitPrecision",
        COALESCE(SUM(si."profit"), 0) AS "totalProfit"
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s."id" = si."saleId"
      WHERE s."company_id" = ${params.companyId}
        AND s."kind" = 'invoice'
        AND s."saleDate" >= ${params.range.gte as Date}
        AND s."saleDate" < ${params.range.lt as Date}
        ${sellerFilter}
      GROUP BY
        COALESCE(
          CASE
            WHEN si."product_source" IS NOT NULL AND si."source_product_id" IS NOT NULL
            THEN CONCAT(si."product_source"::text, ':', si."source_product_id"::text)
            ELSE NULL
          END,
          si."productId"::text,
          si."productNameSnapshot"
        ),
        COALESCE(NULLIF(btrim(si."unit_code_snapshot"), ''), 'UNIT'),
        COALESCE(NULLIF(btrim(si."unit_name_snapshot"), ''), 'Unidad'),
        COALESCE(NULLIF(btrim(si."unit_symbol_snapshot"), ''), 'u'),
        COALESCE(si."unit_precision_snapshot", 0)
      ORDER BY "totalSales" DESC, "productName" ASC
      LIMIT 10
    `);
    return rows.map((row) => {
      const unitCode = row.unitCode ?? "UNIT";
      const unitSymbol = row.unitSymbol ?? "u";
      const unitPrecision = row.unitPrecision ?? 0;
      const totalQty = this.toNumber(row.totalQty);
      return {
        productName: row.productName?.trim() || "Producto sin nombre",
        totalSales: this.toNumber(row.totalSales),
        totalQty,
        unitCode,
        unitName: row.unitName ?? "Unidad",
        unitSymbol,
        unitPrecision,
        totalQtyLabel: this.quantityLabel(
          totalQty,
          unitSymbol,
          unitPrecision,
          unitCode,
        ),
        totalProfit: this.toNumber(row.totalProfit),
      };
    });
  }

  private async buildSalesSeriesSummary(params: {
    companyId: string;
    range: Prisma.DateTimeFilter;
    sellerUserId: string | null;
  }): Promise<SalesSeriesSummary | null> {
    const delegate = this.prisma as unknown as {
      $queryRaw?: <T = unknown>(query: Prisma.Sql) => Promise<T>;
    };
    if (typeof delegate.$queryRaw !== "function") return null;
    const sellerFilter = params.sellerUserId
      ? Prisma.sql`AND s."userId" = ${params.sellerUserId}`
      : Prisma.empty;
    const rows = await delegate.$queryRaw<
      Array<{
        label: string;
        sales: MoneyLike;
        profit: MoneyLike;
      }>
    >(Prisma.sql`
      SELECT
        to_char(s."saleDate" - interval '4 hours', 'YYYY-MM-DD') AS "label",
        COALESCE(SUM(si."subtotalSold"), 0) AS "sales",
        COALESCE(SUM(si."profit"), 0) AS "profit"
      FROM "Sale" s
      LEFT JOIN "SaleItem" si ON si."saleId" = s."id"
      WHERE s."company_id" = ${params.companyId}
        AND s."kind" = 'invoice'
        AND s."saleDate" >= ${params.range.gte as Date}
        AND s."saleDate" < ${params.range.lt as Date}
        ${sellerFilter}
      GROUP BY to_char(s."saleDate" - interval '4 hours', 'YYYY-MM-DD')
      ORDER BY "label" ASC
    `);
    return {
      salesSeries: rows.map((row) => ({
        label: row.label,
        value: this.toNumber(row.sales),
      })),
      profitSeries: rows.map((row) => ({
        label: row.label,
        value: this.toNumber(row.profit),
      })),
    };
  }

  private async buildCategoryProfitsSummary(params: {
    companyId: string;
    range: Prisma.DateTimeFilter;
    sellerUserId: string | null;
  }): Promise<CategoryProfitSummary[] | null> {
    const delegate = this.prisma as unknown as {
      $queryRaw?: <T = unknown>(query: Prisma.Sql) => Promise<T>;
    };
    if (typeof delegate.$queryRaw !== "function") return null;
    const sellerFilter = params.sellerUserId
      ? Prisma.sql`AND s."userId" = ${params.sellerUserId}`
      : Prisma.empty;
    const rows = await delegate.$queryRaw<
      Array<{
        category: string | null;
        totalSales: MoneyLike;
        totalCost: MoneyLike;
        totalProfit: MoneyLike;
        totalQty: MoneyLike;
        salesCount: bigint | number | string | null;
        unitCode: string | null;
        unitName: string | null;
        unitSymbol: string | null;
        unitPrecision: number | null;
        unitQuantity: MoneyLike;
      }>
    >(Prisma.sql`
      WITH item_rows AS (
        SELECT
          COALESCE(NULLIF(btrim(p."categoria"), ''), 'Sin categoria') AS category,
          s."id" AS "saleId",
          si."subtotalSold",
          si."subtotalCost",
          si."profit",
          si."qty",
          COALESCE(NULLIF(btrim(si."unit_code_snapshot"), ''), 'UNIT') AS "unitCode",
          COALESCE(NULLIF(btrim(si."unit_name_snapshot"), ''), 'Unidad') AS "unitName",
          COALESCE(NULLIF(btrim(si."unit_symbol_snapshot"), ''), 'u') AS "unitSymbol",
          COALESCE(si."unit_precision_snapshot", 0) AS "unitPrecision"
        FROM "SaleItem" si
        INNER JOIN "Sale" s ON s."id" = si."saleId"
        LEFT JOIN "Product" p ON p."id" = si."productId"
        WHERE s."company_id" = ${params.companyId}
          AND s."kind" = 'invoice'
          AND s."saleDate" >= ${params.range.gte as Date}
          AND s."saleDate" < ${params.range.lt as Date}
          ${sellerFilter}
      ),
      category_totals AS (
        SELECT
          category,
          COALESCE(SUM("subtotalSold"), 0) AS "totalSales",
          COALESCE(SUM("subtotalCost"), 0) AS "totalCost",
          COALESCE(SUM("profit"), 0) AS "totalProfit",
          COALESCE(SUM("qty"), 0) AS "totalQty",
          COUNT(DISTINCT "saleId") AS "salesCount"
        FROM item_rows
        GROUP BY category
      ),
      unit_totals AS (
        SELECT
          category,
          "unitCode",
          "unitName",
          "unitSymbol",
          "unitPrecision",
          COALESCE(SUM("qty"), 0) AS "unitQuantity"
        FROM item_rows
        GROUP BY category, "unitCode", "unitName", "unitSymbol", "unitPrecision"
      )
      SELECT
        ct.category,
        ct."totalSales",
        ct."totalCost",
        ct."totalProfit",
        ct."totalQty",
        ct."salesCount",
        ut."unitCode",
        ut."unitName",
        ut."unitSymbol",
        ut."unitPrecision",
        ut."unitQuantity"
      FROM category_totals ct
      INNER JOIN unit_totals ut ON ut.category = ct.category
      ORDER BY ct."totalProfit" DESC, ct.category ASC, ut."unitCode" ASC
    `);
    const byCategory = new Map<string, CategoryProfitSummary>();
    for (const row of rows) {
      const categoryName = row.category?.trim() || "Sin categoria";
      const current = byCategory.get(categoryName) ?? {
        category: categoryName,
        totalSales: this.toNumber(row.totalSales),
        totalCost: this.toNumber(row.totalCost),
        totalProfit: this.toNumber(row.totalProfit),
        totalQty: this.toNumber(row.totalQty),
        quantityBuckets: [],
        totalQtyLabel: "0",
        salesCount: Number(row.salesCount ?? 0),
      };
      const unitCode = row.unitCode ?? "UNIT";
      const unitName = row.unitName ?? "Unidad";
      const unitSymbol = row.unitSymbol ?? "u";
      const unitPrecision = row.unitPrecision ?? 0;
      const quantity = this.toNumber(row.unitQuantity);
      current.quantityBuckets.push({
        unitCode,
        unitName,
        unitSymbol,
        unitPrecision,
        quantity,
        label: this.quantityLabel(
          quantity,
          unitSymbol,
          unitPrecision,
          unitCode,
        ),
      });
      current.totalQtyLabel = current.quantityBuckets
        .map((bucket) => bucket.label)
        .join(" + ");
      byCategory.set(categoryName, current);
    }
    return [...byCategory.values()].sort((a, b) => b.totalProfit - a.totalProfit);
  }

  private async productCategoriesFromDatabase(companyId: string) {
    const rows = await (this.prisma as unknown as {
      $queryRaw: <T = unknown>(query: Prisma.Sql) => Promise<T>;
    }).$queryRaw<Array<{ category: string | null }>>(Prisma.sql`
      SELECT DISTINCT COALESCE(NULLIF(btrim("categoria"), ''), 'Sin categoria') AS "category"
      FROM "Product"
      WHERE "company_id" = ${companyId}
        AND "item_type" = CAST(${ProductItemType.PRODUCT} AS "product_item_type")
        AND "track_inventory" = true
      ORDER BY "category" ASC
    `);
    return rows
      .map((row) => row.category?.trim() || "Sin categoria")
      .sort((a, b) => a.localeCompare(b, "es-DO"));
  }

  private productCatalogSummaryFromRows(
    categories: string[],
    rows: Array<{
      unitCode: string | null;
      unitName: string | null;
      unitSymbol: string | null;
      unitPrecision: number | null;
      products: bigint | number | string | null;
      units: MoneyLike;
      costValue: MoneyLike;
      saleValue: MoneyLike;
      outOfStock: bigint | number | string | null;
      lowStock: bigint | number | string | null;
      productsWithoutCost: bigint | number | string | null;
    }>,
  ): ProductCatalogSummary {
    const inventory: ProductCatalogSummary["inventory"] = {
      products: 0,
      units: 0,
      unitsByUnit: new Map<string, QuantityBucket>(),
      costValue: 0,
      saleValue: 0,
      outOfStock: 0,
      lowStock: 0,
      productsWithoutCost: 0,
    };
    for (const row of rows) {
      const units = this.toNumber(row.units);
      inventory.products += Number(row.products ?? 0);
      inventory.units += units;
      inventory.costValue += this.toNumber(row.costValue);
      inventory.saleValue += this.toNumber(row.saleValue);
      inventory.outOfStock += Number(row.outOfStock ?? 0);
      inventory.lowStock += Number(row.lowStock ?? 0);
      inventory.productsWithoutCost += Number(row.productsWithoutCost ?? 0);
      this.addQuantityBucket(
        inventory.unitsByUnit,
        row.unitCode ?? "UNIT",
        row.unitName ?? "Unidad",
        row.unitSymbol ?? "u",
        row.unitPrecision ?? 0,
        units,
      );
    }
    return { categories, inventory };
  }

  private async buildProductCatalogSummaryLegacy(
    companyId: string,
    selectedCategory: string | null,
  ): Promise<ProductCatalogSummary> {
    const products = await this.prisma.product.findMany({
      where: {
        companyId,
        itemType: ProductItemType.PRODUCT,
        trackInventory: true,
      },
      select: {
        categoria: true,
        costo: true,
        precio: true,
        stock: true,
        unitOfMeasure: {
          select: {
            code: true,
            name: true,
            symbol: true,
            precision: true,
          },
        },
      },
      take: SALES_OVERVIEW_MAX_ROWS + 1,
    });
    this.assertReportRowBudget("productos", products);

    const inventory: ProductCatalogSummary["inventory"] = {
      products: 0,
      units: 0,
      unitsByUnit: new Map<string, QuantityBucket>(),
      costValue: 0,
      saleValue: 0,
      outOfStock: 0,
      lowStock: 0,
      productsWithoutCost: 0,
    };
    for (const product of products) {
      const category = (product.categoria ?? "").trim() || "Sin categoria";
      if (
        selectedCategory &&
        this.normalizeCategoryKey(category) !== selectedCategory
      ) {
        continue;
      }
      const stock = this.toNumber(product.stock);
      const cost = this.toNumber(product.costo);
      const price = this.toNumber(product.precio);
      inventory.products += 1;
      inventory.units += stock;
      this.addInventoryQuantityToBuckets(inventory.unitsByUnit, product);
      inventory.costValue += stock * cost;
      inventory.saleValue += stock * price;
      if (stock <= 0) inventory.outOfStock += 1;
      if (stock > 0 && stock <= 3) inventory.lowStock += 1;
      if (cost <= 0) inventory.productsWithoutCost += 1;
    }
    return {
      categories: this.availableCategories(products),
      inventory,
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

  private assertReportRowBudget(label: string, rows: unknown[]) {
    if (rows.length <= SALES_OVERVIEW_MAX_ROWS) return;
    throw new BadRequestException(
      `El reporte contiene demasiados registros de ${label}. Reduce el rango de fechas o usa una exportacion/agregacion dedicada.`,
    );
  }

  private normalizeCategoryKey(value: string) {
    return value.trim().replace(/\s+/g, " ").toLocaleLowerCase("es-DO");
  }

  /**
   * Participación de la categoría filtrada dentro del total de la venta dueña
   * del abono. Sin filtro de categoría la participación es 1 (el abono se cuenta
   * completo); con filtro, un abono de una venta sin esa categoría aporta 0.
   * Mismo criterio que el pago inicial para no introducir un contrato nuevo.
   */
  private paymentCategoryAllocation(
    payment: {
      sale: {
        items: Array<{
          subtotalSold: MoneyLike;
          product: { categoria: string | null } | null;
        }>;
      };
    },
    selectedCategory: string | null,
  ) {
    if (!selectedCategory) return 1;
    const saleTotal = payment.sale.items.reduce(
      (sum, item) => sum + this.toNumber(item.subtotalSold),
      0,
    );
    if (saleTotal <= 0) return 0;
    const categoryTotal = payment.sale.items.reduce(
      (sum, item) =>
        this.normalizeCategoryKey(this.itemCategoryFromParts(item)) ===
        selectedCategory
          ? sum + this.toNumber(item.subtotalSold)
          : sum,
      0,
    );
    return categoryTotal / saleTotal;
  }

  private itemCategoryFromParts(item: {
    product: { categoria: string | null } | null;
  }) {
    return item.product?.categoria?.trim() || "Sin categoria";
  }

  private itemCategory(item: SaleOverviewItem) {
    return item.product?.categoria?.trim() || "Sin categoria";
  }

  private itemUnit(item: SaleOverviewItem) {
    const unitCode =
      (item as any).unitCodeSnapshot?.toString().trim() || "UNIT";
    const unitName =
      (item as any).unitNameSnapshot?.toString().trim() || "Unidad";
    const unitSymbol =
      (item as any).unitSymbolSnapshot?.toString().trim() ||
      (unitCode === "UNIT" ? "u" : unitCode.toLowerCase());
    const unitPrecision = Math.max(
      0,
      Number((item as any).unitPrecisionSnapshot ?? 0) || 0,
    );
    return { unitCode, unitName, unitSymbol, unitPrecision };
  }

  private addQuantityToBuckets(
    buckets: Map<string, QuantityBucket>,
    item: SaleOverviewItem,
  ) {
    const unit = this.itemUnit(item);
    this.addQuantityBucket(
      buckets,
      unit.unitCode,
      unit.unitName,
      unit.unitSymbol,
      unit.unitPrecision,
      this.toNumber(item.qty),
    );
  }

  private addInventoryQuantityToBuckets(
    buckets: Map<string, QuantityBucket>,
    product: {
      stock: MoneyLike;
      unitOfMeasure?: {
        code: string;
        name: string;
        symbol: string;
        precision: number;
      } | null;
    },
  ) {
    const unit = product.unitOfMeasure;
    this.addQuantityBucket(
      buckets,
      unit?.code ?? "UNIT",
      unit?.name ?? "Unidad",
      unit?.symbol ?? "u",
      unit?.precision ?? 0,
      this.toNumber(product.stock),
    );
  }

  private addQuantityBucket(
    buckets: Map<string, QuantityBucket>,
    unitCode: string,
    unitName: string,
    unitSymbol: string,
    unitPrecision: number,
    quantity: number,
  ) {
    const key = unitCode || "UNIT";
    const current = buckets.get(key) ?? {
      unitCode: key,
      unitName,
      unitSymbol,
      unitPrecision,
      quantity: 0,
      label: "0",
    };
    current.quantity += quantity;
    current.label = this.quantityLabel(
      current.quantity,
      current.unitSymbol,
      current.unitPrecision,
      current.unitCode,
    );
    buckets.set(key, current);
  }

  private quantityBucketsLabel(buckets: Map<string, QuantityBucket>) {
    const values = [...buckets.values()];
    if (!values.length) return "0";
    return values.map((bucket) => bucket.label).join(" + ");
  }

  private quantityLabel(
    quantity: number,
    symbol: string,
    precision: number,
    code: string,
  ) {
    const decimals = code === "UNIT" || precision <= 0 ? 0 : precision;
    const value = quantity.toLocaleString("es-DO", {
      minimumFractionDigits: 0,
      maximumFractionDigits: decimals,
    });
    return `${value} ${symbol || (code === "UNIT" ? "u" : code.toLowerCase())}`;
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
