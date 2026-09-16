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
import {
  businessDateRange,
  formatBusinessDay,
} from "../common/utils/business-time.util";

type RequestUser = TenantUser;

type MoneyLike = Prisma.Decimal | number | string | null | undefined;
type PerformanceSaleItem = {
  id: string;
  qty: MoneyLike;
  subtotalSold: MoneyLike;
  subtotalCost: MoneyLike;
  profit: MoneyLike;
  lineDiscountAmount?: MoneyLike;
  taxableBase?: MoneyLike;
  taxAmount?: MoneyLike;
  exemptAmount?: MoneyLike;
  costUnitSnapshot?: MoneyLike;
  product?: { categoria: string | null } | null;
  productId?: string | null;
  productSource?: string | null;
  sourceProductId?: string | null;
  productNameSnapshot?: string;
  unitCodeSnapshot?: string | null;
  unitNameSnapshot?: string | null;
  unitSymbolSnapshot?: string | null;
  unitPrecisionSnapshot?: number | null;
};
/**
 * Campos mínimos que necesita el cálculo de desempeño. Permite reutilizar la
 * MISMA proyección en la ruta completa (reporte) y en la ruta liviana
 * (`summaryOnly`) sin duplicar fórmulas.
 */
type PerformanceSale = {
  id: string;
  saleDate: Date;
  totalSold: MoneyLike;
  discountAmount?: MoneyLike;
  commissionAmount?: MoneyLike;
  paymentMethod?: string | null;
  paymentCashAmount?: MoneyLike;
  paymentTransferAmount?: MoneyLike;
  customerId?: string | null;
  customer?: { id: string; nombre: string | null } | null;
  items: PerformanceSaleItem[];
};
type RemanentAmounts = {
  qty: number;
  returnedQty: number;
  remainingQty: number;
  ratio: number;
  subtotalSold: number;
  subtotalCost: number;
  profit: number;
  taxableBase: number;
  taxAmount: number;
  exemptAmount: number;
  lineDiscountAmount: number;
};
type ProjectedSale = {
  sale: PerformanceSale;
  items: Array<{ item: PerformanceSaleItem; remanent: RemanentAmounts }>;
  grossSold: number;
  grossCost: number;
  grossProfit: number;
  netSold: number;
  netCost: number;
  netProfit: number;
  taxableBase: number;
  taxAmount: number;
  exemptAmount: number;
  lineDiscount: number;
  generalDiscount: number;
  generalDiscountShare: number;
  hasReturnedItems: boolean;
};
/**
 * Máximo de ids de línea por consulta de devoluciones. Evita un `IN` gigante
 * en períodos con miles de líneas sin caer en N+1 (una consulta por lote).
 */
const RETURNED_QUANTITY_BATCH_SIZE = 2000;
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

    // Modo liviano para las comparativas de la pantalla de Reportes: devuelve
    // SOLO los KPIs de desempeño calculados con la MISMA proyección canónica
    // (sin productos, caja, crédito ni inventario). Evita que la misma métrica
    // se lea de otro endpoint y muestre un número distinto al del header.
    if (this.isSummaryOnlyQuery(query)) {
      return this.salesPerformanceSummary(companyId, userFilter, range);
    }

    // ---------------------------------------------------------------------
    // SEMÁNTICA CANÓNICA: DESEMPEÑO NETO DE VENTAS (STATE-AWARE).
    //
    // Reportes/Ventas NO es flujo de caja. Cada venta aporta únicamente su
    // CONTRIBUCIÓN ECONÓMICA REMANENTE dentro de su propio período (saleDate):
    //
    //   venta bruta del período  - parte devuelta  = ventas netas
    //   costo snapshot bruto     - costo devuelto  = costo neto
    //
    // Los documentos `kind=refund` NUNCA se suman como una "venta negativa":
    // eso producía que una devolución fechada en otro período generara ventas
    // negativas artificiales. Las ventas canceladas (isDeleted) aportan 0 por
    // estado, sin reversión fechada adicional.
    // ---------------------------------------------------------------------
    const saleWhere: Prisma.SaleWhereInput = {
      companyId,
      ...userFilter,
      kind: "invoice",
      isDeleted: false,
      saleDate: range,
    };

    const companyPromise =
      (this.prisma as any).company?.findUnique?.({
        where: { id: companyId },
        select: { inventoryEnabled: true },
      }) ?? Promise.resolve(null);
    const [sales, products, movements, company] = await Promise.all([
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
        companyPromise,
      ]);
    const inventoryEnabled = company?.inventoryEnabled !== false;

    // Cantidad DEVUELTA por línea original. Se lee de los documentos de
    // devolución sin filtrar por fecha (el reporte es state-aware): una
    // devolución descuenta SIEMPRE la venta a la que pertenece. Una sola
    // consulta batched por rango de ids, acotada por companyId.
    const returnedQtyByItemId = await this.returnedQuantityByItemId(
      companyId,
      sales.flatMap((sale) => sale.items.map((item) => item.id)),
    );

    // Proyección única: todo el reporte (KPIs, series, categorías, top) se
    // deriva de estas filas remanentes.
    const projectedSales = sales
      .map((sale) =>
        this.projectSalePerformance(
          sale,
          selectedCategory,
          returnedQtyByItemId,
        ),
      )
      .filter((row) => row.items.length > 0);
    // Ticket activo = venta con al menos una línea con contribución remanente.
    // Totalmente devuelta / cancelada / eliminada => 0 tickets.
    const ticketSales = projectedSales.filter((row) =>
      row.items.some((entry) => entry.remanent.ratio > 0),
    );

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
      saleIds: projectedSales
        .filter((row) => row.sale.paymentMethod === "credit")
        .map((row) => row.sale.id),
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
    for (const row of projectedSales) {
      const sale = row.sale;
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

    // Totales del período desde la MISMA proyección remanente. No hay
    // "ventas negativas": una venta devuelta aporta 0, no -monto.
    const totals = projectedSales.reduce(
      (acc, row) => {
        acc.totalSold += row.netSold;
        acc.totalCost += row.netCost;
        acc.totalProfit += row.netProfit;
        acc.taxableBase += row.taxableBase;
        acc.taxAmount += row.taxAmount;
        acc.exemptAmount += row.exemptAmount;
        // Descuento comercial de línea (parte remanente) + descuento general
        // del documento prorrateado por la participación remanente. Una venta
        // devuelta no queda contada al 100% en descuentos.
        acc.discountAmount +=
          row.lineDiscount + row.generalDiscount * row.generalDiscountShare;
        // La participación de la categoría para comisión y dinero cobrado se
        // mantiene BRUTA: no se altera el contrato de caja ni el hardening de
        // crédito (pago inicial por `saleDate`, abonos por `paidAt`).
        const saleSold = this.toNumber(row.sale.totalSold);
        const allocation = saleSold > 0 ? row.grossSold / saleSold : 0;
        acc.totalCommission +=
          this.toNumber(row.sale.commissionAmount) * allocation;
        const initialPayment = initialPaymentBySaleId.get(row.sale.id) ?? {
          cash: 0,
          transfer: 0,
        };
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

    const initialCashOperations = projectedSales.filter(
      (row) => (initialPaymentBySaleId.get(row.sale.id)?.cash ?? 0) > 0,
    ).length;
    const initialTransferOperations = projectedSales.filter(
      (row) => (initialPaymentBySaleId.get(row.sale.id)?.transfer ?? 0) > 0,
    ).length;

    // Devoluciones del período = porción NO remanente de las ventas del
    // período, derivada de la MISMA proyección:
    //   grossSales - returnedSales = netSales
    // El documento de devolución no se cuenta nunca como una venta negativa.
    const grossSales = projectedSales.reduce(
      (sum, row) => sum + row.grossSold,
      0,
    );
    const returns = projectedSales.reduce(
      (acc, row) => {
        acc.amount += row.grossSold - row.netSold;
        acc.cost += row.grossCost - row.netCost;
        acc.profit += row.grossProfit - row.netProfit;
        if (row.hasReturnedItems) acc.count += 1;
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

    // Series, categorías y rankings se alimentan de la MISMA proyección
    // remanente: así el gráfico, el donut de categorías y los KPIs nunca
    // muestran números distintos para el mismo filtro.
    for (const row of projectedSales) {
      const sale = row.sale;
      const day = this.formatDominicanDay(sale.saleDate);
      salesSeries.set(day, (salesSeries.get(day) ?? 0) + row.netSold);
      profitSeries.set(day, (profitSeries.get(day) ?? 0) + row.netProfit);

      const activeEntries = row.items.filter(
        (entry) => entry.remanent.ratio > 0,
      );
      if (activeEntries.length > 0) {
        const clientKey = sale.customerId ?? "general";
        const clientName = sale.customer?.nombre?.trim() || "Consumidor final";
        const client = clientMap.get(clientKey) ?? {
          clientName,
          totalSpent: 0,
          purchaseCount: 0,
        };
        client.totalSpent += row.netSold;
        client.purchaseCount += 1;
        clientMap.set(clientKey, client);
      }

      const countedCategories = new Set<string>();
      for (const entry of activeEntries) {
        const item = entry.item;
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
        product.totalSales += entry.remanent.subtotalSold;
        product.totalQty += entry.remanent.remainingQty;
        product.totalQtyLabel = this.quantityLabel(
          product.totalQty,
          product.unitSymbol,
          product.unitPrecision,
          product.unitCode,
        );
        product.totalProfit += entry.remanent.profit;
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
        category.totalSales += entry.remanent.subtotalSold;
        category.totalCost += entry.remanent.subtotalCost;
        category.totalProfit += entry.remanent.profit;
        category.totalQty += entry.remanent.remainingQty;
        this.addQuantityToBuckets(
          category.quantityBuckets,
          item,
          entry.remanent.remainingQty,
        );
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
          zeroCostSoldAmount += entry.remanent.subtotalSold;
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
    // UNA SOLA FUENTE DE VERDAD:
    //   netSales    = contribución remanente (state-aware)
    //   grossProfit = netSales - costo neto
    //   netProfit   = grossProfit - gastos que afectan utilidad
    const netSales = totals.totalSold;
    const grossProfit = totals.totalProfit;
    const netProfit = grossProfit - profitExpenses;
    const ticketCount = ticketSales.length;
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
                "El reporte descuenta las devoluciones sobre la venta original (state-aware): una venta devuelta aporta 0, nunca una venta negativa.",
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
        // Tickets con contribución remanente > 0 (ACTIVE y PARTIALLY_RETURNED
        // cuentan 1; FULLY_RETURNED, CANCELLED, DELETED y el documento de
        // devolución cuentan 0).
        totalSales: ticketCount,
        grossSales,
        returnedSales: returns.amount,
        netSales,
        totalSold: netSales,
        totalCost: totals.totalCost,
        grossProfit,
        // Alias histórico: `totalProfit` SIEMPRE fue la utilidad antes de
        // gastos = utilidad bruta. Se mantiene para no romper consumidores.
        totalProfit: grossProfit,
        commercialProfit: grossProfit,
        netTaxProfit:
          totals.taxableBase + totals.exemptAmount > 0
            ? totals.taxableBase + totals.exemptAmount - totals.totalCost
            : grossProfit,
        netProfit,
        returnedCost: returns.cost,
        returnedProfit: returns.profit,
        totalCommission: totals.totalCommission,
        taxableBase: totals.taxableBase,
        taxAmount: totals.taxAmount,
        exemptAmount: totals.exemptAmount,
        discountAmount: totals.discountAmount,
        // Ticket promedio sobre los tickets con contribución remanente
        // (respeta el filtro de categoría); evita dividir por ventas que ya no
        // aportan desempeño.
        avgTicket: ticketCount === 0 ? 0 : netSales / ticketCount,
        totalReturns: returns.count,
        returnedSalesCount: returns.count,
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
      // Breakdown de dinero COBRADO (no de ventas devengadas): se mantiene el
      // contrato de caja/crédito. La UI lo etiqueta como cobros.
      paymentMethodsSource: "collected_cash",
      topProducts: [...productMap.values()]
        .sort((a, b) => b.totalSales - a.totalSales)
        .slice(0, 10),
      topClients: [...clientMap.values()]
        .sort((a, b) => b.totalSpent - a.totalSpent)
        .slice(0, 10),
      categoryProfits: [...categoryMap.values()]
        // Una categoría totalmente devuelta no aporta desempeño: se omite para
        // no mostrar filas en cero que no cuadran con nada.
        .filter(
          (row) =>
            row.salesCount > 0 ||
            row.totalSales !== 0 ||
            row.totalCost !== 0 ||
            row.totalProfit !== 0,
        )
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
        // Filas de desempeño del período: ventas emitidas (no canceladas) que
        // tienen líneas del filtro aplicado.
        performanceRows: projectedSales.length,
        activeTicketRows: ticketCount,
        saleRows: projectedSales.length,
        saleItemRows: projectedSales.reduce(
          (sum, row) => sum + row.items.length,
          0,
        ),
        returnedRows: returns.count,
        cashMovementRows: movements.length,
        creditPaymentRows: creditPaymentsInRange.length,
        paymentBreakdownViolations,
        categoryFiltered: selectedCategory !== null,
        warnings,
      },
    };
  }

  /**
   * KPIs de desempeño de ventas para un rango con la MISMA semántica
   * state-aware de `salesOverview`. Alimenta las comparativas de la pantalla de
   * Reportes: la métrica "Ventas" sale siempre de la misma fórmula, sin
   * importar la sección que la muestre.
   */
  private async salesPerformanceSummary(
    companyId: string,
    userFilter: Prisma.SaleWhereInput,
    range: Prisma.DateTimeFilter,
  ) {
    const sales = await this.prisma.sale.findMany({
      where: {
        companyId,
        ...userFilter,
        kind: "invoice",
        isDeleted: false,
        saleDate: range,
      },
      select: {
        id: true,
        saleDate: true,
        totalSold: true,
        discountAmount: true,
        commissionAmount: true,
        paymentMethod: true,
        items: {
          select: {
            id: true,
            qty: true,
            subtotalSold: true,
            subtotalCost: true,
            profit: true,
            lineDiscountAmount: true,
            taxableBase: true,
            taxAmount: true,
            exemptAmount: true,
          },
        },
      },
    });

    const returnedQtyByItemId = await this.returnedQuantityByItemId(
      companyId,
      sales.flatMap((sale) => sale.items.map((item) => item.id)),
    );

    let grossSales = 0;
    let netSales = 0;
    let totalCost = 0;
    let grossProfit = 0;
    let ticketCount = 0;
    for (const sale of sales) {
      const row = this.projectSalePerformance(sale, null, returnedQtyByItemId);
      grossSales += row.grossSold;
      netSales += row.netSold;
      totalCost += row.netCost;
      grossProfit += row.netProfit;
      if (row.items.some((entry) => entry.remanent.ratio > 0)) ticketCount += 1;
    }

    return {
      range: {
        from: range.gte,
        to: range.lt,
        timezone: "America/Santo_Domingo",
      },
      summaryOnly: true,
      kpis: {
        totalSales: ticketCount,
        grossSales,
        returnedSales: grossSales - netSales,
        netSales,
        totalSold: netSales,
        totalCost,
        grossProfit,
        // Alias histórico de utilidad bruta.
        totalProfit: grossProfit,
        avgTicket: ticketCount === 0 ? 0 : netSales / ticketCount,
      },
    };
  }

  private isSummaryOnlyQuery(query: Record<string, string>) {
    const raw = (query.summaryOnly ?? "").trim().toLowerCase();
    return raw === "1" || raw === "true" || raw === "yes";
  }

  /**
   * Cantidad devuelta por línea original, sumando TODOS los documentos de
   * devolución de la empresa (SIN filtro de fecha: el reporte es state-aware y
   * la devolución pertenece a la venta a la que apunta). Se resuelve en una
   * consulta batched por lote sobre el índice de `refundedSaleItemId`; nunca una
   * consulta por venta ni por línea.
   */
  private async returnedQuantityByItemId(
    companyId: string,
    saleItemIds: string[],
  ) {
    const returned = new Map<string, number>();
    const uniqueIds = [...new Set(saleItemIds)];
    if (uniqueIds.length === 0) return returned;

    for (
      let offset = 0;
      offset < uniqueIds.length;
      offset += RETURNED_QUANTITY_BATCH_SIZE
    ) {
      const batch = uniqueIds.slice(
        offset,
        offset + RETURNED_QUANTITY_BATCH_SIZE,
      );
      const rows = await this.prisma.saleItem.groupBy({
        by: ["refundedSaleItemId"],
        where: {
          refundedSaleItemId: { in: batch },
          sale: { companyId, kind: "refund", isDeleted: false },
        },
        _sum: { qty: true },
      });
      for (const row of rows) {
        if (!row.refundedSaleItemId) continue;
        returned.set(
          row.refundedSaleItemId,
          (returned.get(row.refundedSaleItemId) ?? 0) +
            this.toNumber(row._sum.qty),
        );
      }
    }
    return returned;
  }

  /**
   * Importes REMANENTES de una línea: snapshot histórico × (1 - devuelto/qty).
   * Nunca usa el costo ACTUAL del producto y nunca produce importes negativos.
   * Una línea totalmente devuelta aporta exactamente 0.
   */
  private remanentAmounts(
    item: PerformanceSaleItem,
    returnedQtyByItemId: Map<string, number>,
  ): RemanentAmounts {
    const qty = this.toNumber(item.qty);
    const requested = Math.max(0, returnedQtyByItemId.get(item.id) ?? 0);
    // Nunca más que lo vendido: protege ante datos legacy o devoluciones
    // huérfanas que dejarían ratios negativos.
    const returnedQty = qty > 0 ? Math.min(requested, qty) : 0;
    const ratio = qty > 0 ? (qty - returnedQty) / qty : 1;
    const scale = (value: MoneyLike) => this.toNumber(value) * ratio;
    return {
      qty,
      returnedQty,
      remainingQty: qty - returnedQty,
      ratio,
      subtotalSold: scale(item.subtotalSold),
      subtotalCost: scale(item.subtotalCost),
      profit: scale(item.profit),
      taxableBase: scale(item.taxableBase),
      taxAmount: scale(item.taxAmount),
      exemptAmount: scale(item.exemptAmount),
      lineDiscountAmount: scale(item.lineDiscountAmount),
    };
  }

  /**
   * Proyección canónica de una venta a desempeño remanente. Es la ÚNICA
   * fórmula de dinero del reporte: KPIs, series, categorías y rankings salen de
   * aquí, por lo que header, cards, gráfico y tabla de categorías reconcilian.
   */
  private projectSalePerformance(
    sale: PerformanceSale,
    categoryKey: string | null,
    returnedQtyByItemId: Map<string, number>,
  ): ProjectedSale {
    const allEntries = sale.items.map((item) => ({
      item,
      remanent: this.remanentAmounts(item, returnedQtyByItemId),
    }));
    const entries =
      categoryKey === null
        ? allEntries
        : allEntries.filter(
            (entry) =>
              this.normalizeCategoryKey(this.itemCategoryFromParts(entry.item)) ===
              categoryKey,
          );

    const sumOf = (
      rows: Array<{ item: PerformanceSaleItem; remanent: RemanentAmounts }>,
      pick: (row: {
        item: PerformanceSaleItem;
        remanent: RemanentAmounts;
      }) => number,
    ) => rows.reduce((sum, row) => sum + pick(row), 0);

    const allItemsGrossSold = sumOf(allEntries, (entry) =>
      this.toNumber(entry.item.subtotalSold),
    );
    const allItemsLineDiscount = sumOf(allEntries, (entry) =>
      this.toNumber(entry.item.lineDiscountAmount),
    );
    const netSold = sumOf(entries, (entry) => entry.remanent.subtotalSold);
    const netCost = sumOf(entries, (entry) => entry.remanent.subtotalCost);

    return {
      sale,
      items: entries,
      grossSold: sumOf(entries, (entry) =>
        this.toNumber(entry.item.subtotalSold),
      ),
      grossCost: sumOf(entries, (entry) =>
        this.toNumber(entry.item.subtotalCost),
      ),
      grossProfit: sumOf(entries, (entry) => this.toNumber(entry.item.profit)),
      netSold,
      netCost,
      netProfit: sumOf(entries, (entry) => entry.remanent.profit),
      taxableBase: sumOf(entries, (entry) => entry.remanent.taxableBase),
      taxAmount: sumOf(entries, (entry) => entry.remanent.taxAmount),
      exemptAmount: sumOf(entries, (entry) => entry.remanent.exemptAmount),
      lineDiscount: sumOf(entries, (entry) => entry.remanent.lineDiscountAmount),
      // Descuento general REAL del documento (comercial): lo que no está
      // repartido como descuento de línea.
      generalDiscount: Math.max(
        0,
        this.toNumber(sale.discountAmount) - allItemsLineDiscount,
      ),
      // Participación remanente del documento. El descuento general se
      // prorratea con el mismo criterio: una venta devuelta no descuenta el
      // 100% del descuento general.
      generalDiscountShare:
        allItemsGrossSold > 0 ? netSold / allItemsGrossSold : 0,
      hasReturnedItems: entries.some((entry) => entry.remanent.returnedQty > 0),
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
    product?: { categoria: string | null } | null;
  }) {
    return item.product?.categoria?.trim() || "Sin categoria";
  }

  private itemCategory(item: PerformanceSaleItem) {
    return item.product?.categoria?.trim() || "Sin categoria";
  }

  private itemUnit(item: PerformanceSaleItem) {
    const unitCode = item.unitCodeSnapshot?.toString().trim() || "UNIT";
    const unitName = item.unitNameSnapshot?.toString().trim() || "Unidad";
    const unitSymbol =
      item.unitSymbolSnapshot?.toString().trim() ||
      (unitCode === "UNIT" ? "u" : unitCode.toLowerCase());
    const unitPrecision = Math.max(
      0,
      Number(item.unitPrecisionSnapshot ?? 0) || 0,
    );
    return { unitCode, unitName, unitSymbol, unitPrecision };
  }

  private addQuantityToBuckets(
    buckets: Map<string, QuantityBucket>,
    item: PerformanceSaleItem,
    quantity: number,
  ) {
    const unit = this.itemUnit(item);
    this.addQuantityBucket(
      buckets,
      unit.unitCode,
      unit.unitName,
      unit.unitSymbol,
      unit.unitPrecision,
      quantity,
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

  private availableCategories(products: Array<{ categoria: string }>) {
    return Array.from(
      new Set(
        products.map((product) => product.categoria?.trim() || "Sin categoria"),
      ),
    ).sort((a, b) => a.localeCompare(b, "es-DO"));
  }

  private buildDateRange(from?: string, to?: string): Prisma.DateTimeFilter {
    const { gte, lt } = businessDateRange(from, to);
    // Semántica de rango exclusivo: fecha >= inicio AND fecha < fin.
    // Evita la ventana de precisión de 23:59:59.999 que podría dejar fuera o
    // contar mal ventas cercanas a la medianoche (mismo criterio que /sales).
    return { gte, lt };
  }

  private formatDominicanDay(date: Date) {
    return formatBusinessDay(date);
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
