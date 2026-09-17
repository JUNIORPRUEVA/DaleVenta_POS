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
      products,
      movements,
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
          where: {
            companyId,
            itemType: ProductItemType.PRODUCT,
            trackInventory: true,
          },
          select: {
            id: true,
            nombre: true,
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
        }),
        this.prisma.cashMovement.findMany({
          where: {
            createdAt: range,
            companyId,
            ...(canSeeAll ? {} : { userId: user.id }),
          },
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
        }),
        companyPromise,
      ]);
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

    const creditPaymentWhere: Prisma.SaleCreditPaymentWhereInput = {
      companyId,
      paidAt: range,
      // Semántica de filtro por usuario MANTENIDA (SELLER): el reporte atribuye
      // el dinero cobrado al vendedor de la venta, igual que antes de este fix.
      // El cobrador (`SaleCreditPayment.userId`) se conserva para auditoría.
      ...(canSeeAll ? {} : { sale: { userId: user.id } }),
    };
    const creditPaymentsInRange = await this.prisma.saleCreditPayment.findMany({
      where: creditPaymentWhere,
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
    let creditPaymentsCashInPeriod = 0;
    let creditPaymentsTransferInPeriod = 0;
    let creditPaymentsCashOperations = 0;
    let creditPaymentsTransferOperations = 0;
    for (const payment of creditPaymentsInRange) {
      const allocation = this.paymentCategoryAllocation(payment, selectedCategory);
      if (allocation <= 0) continue;
      const cash = this.toNumber(payment.cashAmount) * allocation;
      const transfer = this.toNumber(payment.transferAmount) * allocation;
      if (cash > 0) creditPaymentsCashOperations += 1;
      if (transfer > 0) creditPaymentsTransferOperations += 1;
      creditPaymentsCashInPeriod += cash;
      creditPaymentsTransferInPeriod += transfer;
      totals.cash += cash;
      totals.transfer += transfer;
    }

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
        this.addInventoryQuantityToBuckets(acc.unitsByUnit, product);
        acc.costValue += stock * cost;
        acc.saleValue += stock * price;
        if (inventoryEnabled && stock <= 0) acc.outOfStock += 1;
        if (inventoryEnabled && stock > 0 && stock <= 3) acc.lowStock += 1;
        if (cost <= 0) acc.productsWithoutCost += 1;
        return acc;
      },
      {
        products: 0,
        units: 0,
        unitsByUnit: new Map<string, QuantityBucket>(),
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
        count: initialCashOperations + creditPaymentsCashOperations,
      },
      {
        method: "Transferencia",
        amount: totals.transfer,
        count: initialTransferOperations + creditPaymentsTransferOperations,
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
        // Efectivo/transferencia cobrados por abonos de crédito DENTRO del
        // período (fecha real `paidAt`), separados del pago inicial.
        creditPaymentsCash: creditPaymentsCashInPeriod,
        creditPaymentsTransfer: creditPaymentsTransferInPeriod,
        creditPaymentsCount: creditPaymentsInRange.length,
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
      categoryProfits: [...categoryMap.values()]
        .map((row) => ({
          ...row,
          quantityBuckets: [...row.quantityBuckets.values()],
        }))
        .sort((a, b) => b.totalProfit - a.totalProfit),
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
        cashMovementRows: movements.length,
        creditPaymentRows: creditPaymentsInRange.length,
        paymentBreakdownViolations,
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
