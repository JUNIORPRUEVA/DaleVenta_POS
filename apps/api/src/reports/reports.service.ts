import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type RequestUser = { id: string; role: Role };

type MoneyLike = Prisma.Decimal | number | string | null | undefined;

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async salesOverview(user: RequestUser, query: Record<string, string>) {
    const range = this.buildDateRange(query.from, query.to);
    const canSeeAll = user.role === Role.ADMIN || user.role === Role.ASISTENTE;
    const userFilter = canSeeAll ? {} : { userId: user.id };

    const saleWhere: Prisma.SaleWhereInput = {
      ...userFilter,
      kind: 'invoice',
      isDeleted: false,
      saleDate: range,
    };
    const returnedWhere: Prisma.SaleWhereInput = {
      ...userFilter,
      kind: 'invoice',
      isDeleted: true,
      deletedAt: range,
    };

    const [sales, returnedSales, products, movements] = await Promise.all([
      this.prisma.sale.findMany({
        where: saleWhere,
        include: {
          customer: { select: { id: true, nombre: true } },
          items: true,
        },
        orderBy: { saleDate: 'asc' },
      }),
      this.prisma.sale.findMany({
        where: returnedWhere,
        include: { items: true },
        orderBy: { deletedAt: 'asc' },
      }),
      this.prisma.product.findMany({
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
          ...(canSeeAll ? {} : { userId: user.id }),
        },
      }),
    ]);

    const totals = sales.reduce(
      (acc, sale) => {
        acc.totalSold += this.toNumber(sale.totalSold);
        acc.totalCost += this.toNumber(sale.totalCost);
        acc.totalProfit += this.toNumber(sale.totalProfit);
        acc.totalCommission += this.toNumber(sale.commissionAmount);
        acc.cash += this.toNumber(sale.paymentCashAmount);
        acc.transfer += this.toNumber(sale.paymentTransferAmount);
        return acc;
      },
      {
        totalSold: 0,
        totalCost: 0,
        totalProfit: 0,
        totalCommission: 0,
        cash: 0,
        transfer: 0,
      },
    );

    const returns = returnedSales.reduce(
      (acc, sale) => {
        acc.count += 1;
        acc.amount += this.toNumber(sale.totalSold);
        acc.cost += this.toNumber(sale.totalCost);
        acc.profit += this.toNumber(sale.totalProfit);
        return acc;
      },
      { count: 0, amount: 0, cost: 0, profit: 0 },
    );

    const expenses = movements.reduce(
      (acc, movement) => {
        const amount = this.toNumber(movement.amount);
        if (movement.type === 'IN') acc.cashIn += amount;
        if (movement.type === 'OUT') {
          acc.cashOut += amount;
          if (movement.movementType === 'expense' && movement.affectsProfit) {
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
      { productName: string; totalSales: number; totalQty: number; totalProfit: number }
    >();
    const clientMap = new Map<string, { clientName: string; totalSpent: number; purchaseCount: number }>();
    let zeroCostItems = 0;
    let zeroCostSoldAmount = 0;

    for (const sale of sales) {
      const day = this.formatDominicanDay(sale.saleDate);
      salesSeries.set(day, (salesSeries.get(day) ?? 0) + this.toNumber(sale.totalSold));
      profitSeries.set(day, (profitSeries.get(day) ?? 0) + this.toNumber(sale.totalProfit));

      const clientKey = sale.customerId ?? 'general';
      const clientName = sale.customer?.nombre?.trim() || 'Consumidor final';
      const client = clientMap.get(clientKey) ?? {
        clientName,
        totalSpent: 0,
        purchaseCount: 0,
      };
      client.totalSpent += this.toNumber(sale.totalSold);
      client.purchaseCount += 1;
      clientMap.set(clientKey, client);

      for (const item of sale.items) {
        const productKey = item.productId ?? item.productNameSnapshot;
        const product = productMap.get(productKey) ?? {
          productName: item.productNameSnapshot || 'Producto sin nombre',
          totalSales: 0,
          totalQty: 0,
          totalProfit: 0,
        };
        product.totalSales += this.toNumber(item.subtotalSold);
        product.totalQty += this.toNumber(item.qty);
        product.totalProfit += this.toNumber(item.profit);
        productMap.set(productKey, product);

        if (this.toNumber(item.costUnitSnapshot) <= 0) {
          zeroCostItems += 1;
          zeroCostSoldAmount += this.toNumber(item.subtotalSold);
        }
      }
    }

    const inventory = products.reduce(
      (acc, product) => {
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
      { method: 'Efectivo', amount: totals.cash, count: sales.filter((sale) => this.toNumber(sale.paymentCashAmount) > 0).length },
      { method: 'Transferencia', amount: totals.transfer, count: sales.filter((sale) => this.toNumber(sale.paymentTransferAmount) > 0).length },
    ].filter((row) => row.amount > 0 || row.count > 0);

    const netProfit = totals.totalProfit - expenses.expenses;
    const warnings = [
      ...(returns.count > 0
        ? [
            {
              code: 'returns_soft_deleted',
              severity: 'warning',
              message:
                'Las devoluciones actuales restauran stock y marcan la factura como devuelta, pero no generan un comprobante financiero separado.',
            },
          ]
        : []),
      ...(zeroCostItems > 0
        ? [
            {
              code: 'items_without_cost',
              severity: 'warning',
              message: `${zeroCostItems} lineas vendidas tienen costo cero. La utilidad puede estar sobreestimada.`,
            },
          ]
        : []),
      ...(inventory.productsWithoutCost > 0
        ? [
            {
              code: 'products_without_cost',
              severity: 'warning',
              message: `${inventory.productsWithoutCost} productos del catalogo no tienen costo configurado.`,
            },
          ]
        : []),
    ];

    return {
      range: {
        from: range.gte,
        to: range.lte,
        timezone: 'America/Santo_Domingo',
      },
      kpis: {
        totalSales: sales.length,
        grossSales: totals.totalSold + returns.amount,
        returnedSales: returns.amount,
        netSales: totals.totalSold,
        totalSold: totals.totalSold,
        totalCost: totals.totalCost,
        totalProfit: totals.totalProfit,
        netProfit,
        totalCommission: totals.totalCommission,
        avgTicket: sales.length === 0 ? 0 : totals.totalSold / sales.length,
        totalReturns: returns.count,
        totalExpenses: expenses.expenses,
        cashIncome: totals.cash + expenses.cashIn,
        cashExpense: expenses.cashOut,
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
      inventory,
      audit: {
        source: 'database',
        saleRows: sales.length,
        saleItemRows: sales.reduce((sum, sale) => sum + sale.items.length, 0),
        returnedRows: returns.count,
        cashMovementRows: movements.length,
        warnings,
      },
    };
  }

  private buildDateRange(from?: string, to?: string): Prisma.DateTimeFilter {
    const start = this.parseDominicanDate(from, true);
    const end = this.parseDominicanDate(to, false);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      throw new BadRequestException('Rango de fechas invalido');
    }
    if (start.getTime() > end.getTime()) {
      throw new BadRequestException('La fecha inicial no puede ser mayor que la final');
    }
    return { gte: start, lte: end };
  }

  private parseDominicanDate(value: string | undefined, startOfDay: boolean) {
    const now = new Date();
    const fallback = `${now.getUTCFullYear()}-${`${now.getUTCMonth() + 1}`.padStart(2, '0')}-${`${now.getUTCDate()}`.padStart(2, '0')}`;
    const text = (value?.trim() || fallback).slice(0, 10);
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
    if (!match) return new Date(Number.NaN);
    const year = Number(match[1]);
    const month = Number(match[2]) - 1;
    const day = Number(match[3]);
    if (startOfDay) return new Date(Date.UTC(year, month, day, 4, 0, 0, 0));
    return new Date(Date.UTC(year, month, day + 1, 3, 59, 59, 999));
  }

  private formatDominicanDay(date: Date) {
    const dominicanTime = new Date(date.getTime() - 4 * 60 * 60 * 1000);
    return `${dominicanTime.getUTCFullYear()}-${`${dominicanTime.getUTCMonth() + 1}`.padStart(2, '0')}-${`${dominicanTime.getUTCDate()}`.padStart(2, '0')}`;
  }

  private seriesFromMap(map: Map<string, number>) {
    return [...map.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([label, value]) => ({ label, value }));
  }

  private toNumber(value: MoneyLike) {
    if (value === null || value === undefined) return 0;
    if (typeof value === 'number') return value;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    return Number(value) || 0;
  }
}
