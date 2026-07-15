import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateSaleDto, CreateSaleItemDto } from './dto/create-sale.dto';

@Injectable()
export class SalesService {
  constructor(private readonly prisma: PrismaService) {}

  private isSchemaMismatch(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021' || error.code === 'P2022';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return (
        code === 'P2021' ||
        code === 'P2022' ||
        message.includes('does not exist in the current database') ||
        message.toLowerCase().includes('column')
      );
    }

    return false;
  }

  async listMine(userId: string, from?: string, to?: string, customerId?: string, includeDeleted = false) {
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      userId,
      ...(includeDeleted ? {} : { isDeleted: false }),
      ...(normalizedCustomerId ? { customerId: normalizedCustomerId } : {}),
      ...this.buildDateRange(from, to),
    };

    try {
      return await this.prisma.sale.findMany({
        where,
        orderBy: { saleDate: 'desc' },
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
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      return [];
    }
  }

  async listByUser(userId: string, from?: string, to?: string, customerId?: string, includeDeleted = false) {
    return this.listMine(userId, from, to, customerId, includeDeleted);
  }

  async summaryMine(userId: string, from?: string, to?: string, customerId?: string) {
    const normalizedCustomerId = customerId?.trim();
    const where: Prisma.SaleWhereInput = {
      userId,
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
      _sum: { totalSold: null, totalCost: null, totalProfit: null, commissionAmount: null },
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

  async summaryByUser(from?: string, to?: string, userId?: string) {
    const where: Prisma.SaleWhereInput = {
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
        by: ['userId'],
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
    let users: Array<{ id: string; email: string; nombreCompleto: string }> = [];
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
        userName: user?.nombreCompleto ?? 'Usuario',
        userEmail: user?.email ?? '',
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

  async create(userId: string, dto: CreateSaleDto) {
    if (!dto.items.length) {
      throw new BadRequestException('La venta requiere al menos 1 item');
    }

    if (!dto.customerId?.trim()) {
      throw new BadRequestException('Debes seleccionar un cliente');
    }

    try {
      const customer = await this.prisma.client.findFirst({
        where: { id: dto.customerId, isDeleted: false },
      });
      if (!customer) {
        throw new BadRequestException('Cliente inválido');
      }
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
    }

    const productIds = Array.from(
      new Set(dto.items.map((item) => item.productId).filter((id): id is string => Boolean(id))),
    );

    let products: Array<{ id: string; nombre: string; imagen: string | null; costo: Prisma.Decimal; stock: Prisma.Decimal }> = [];
    if (productIds.length) {
      try {
        products = await this.prisma.product.findMany({
          where: { id: { in: productIds } },
          select: {
            id: true,
            nombre: true,
            imagen: true,
            costo: true,
            stock: true,
          },
        });
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        products = [];
      }
    }

    const productMap = new Map(products.map((product) => [product.id, product]));

    const normalizedItems = dto.items.map((item, index) =>
      this.normalizeItem(item, index, productMap),
    );

    let totalSold = new Prisma.Decimal(0);
    let totalCost = new Prisma.Decimal(0);
    let totalProfit = new Prisma.Decimal(0);

    for (const item of normalizedItems) {
      totalSold = totalSold.plus(item.subtotalSold);
      totalCost = totalCost.plus(item.subtotalCost);
      totalProfit = totalProfit.plus(item.profit);
    }

    const commissionRate = new Prisma.Decimal(0.1);
    const commissionAmount = totalProfit.greaterThan(0)
      ? totalProfit.mul(commissionRate)
      : new Prisma.Decimal(0);

    try {
      return await this.prisma.$transaction(async (tx) => {
        for (const item of normalizedItems) {
          if (!item.productId) continue;
          const updated = await tx.product.updateMany({
            where: {
              id: item.productId,
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

        const sale = await tx.sale.create({
          data: {
            userId,
            customerId: dto.customerId,
            saleDate: new Date(),
            note: dto.note,
            totalSold,
            totalCost,
            totalProfit,
            commissionRate,
            commissionAmount,
            items: {
              create: normalizedItems.map((item) => ({
                productId: item.productId,
                productNameSnapshot: item.productNameSnapshot,
                productImageSnapshot: item.productImageSnapshot,
                qty: item.qty,
                priceSoldUnit: item.priceSoldUnit,
                costUnitSnapshot: item.costUnitSnapshot,
                subtotalSold: item.subtotalSold,
                subtotalCost: item.subtotalCost,
                profit: item.profit,
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

        await tx.client.update({
          where: { id: dto.customerId },
          data: { lastActivityAt: sale.saleDate },
        });

        return sale;
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new BadRequestException('El módulo de ventas no está sincronizado con la base de datos.');
    }
  }

  async remove(requestUserId: string, saleId: string) {
    let sale: { id: string; isDeleted: boolean; userId: string } | null = null;
    try {
      sale = await this.prisma.sale.findUnique({ where: { id: saleId } });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException('Venta no encontrada');
    }
    if (!sale || sale.isDeleted) {
      throw new NotFoundException('Venta no encontrada');
    }

    if (sale.userId !== requestUserId) {
      throw new ForbiddenException('No puedes eliminar esta venta');
    }

    try {
      await this.prisma.sale.update({
        where: { id: saleId },
        data: {
          isDeleted: true,
          deletedAt: new Date(),
          deletedById: requestUserId,
        },
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException('Venta no encontrada');
    }

    return { ok: true };
  }

  async returnSale(requestUserId: string, saleId: string) {
    let sale:
      | (Prisma.SaleGetPayload<{
          include: { items: true };
        }>)
      | null = null;

    try {
      sale = await this.prisma.sale.findUnique({
        where: { id: saleId },
        include: { items: true },
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException('Venta no encontrada');
    }

    if (!sale || sale.isDeleted) {
      throw new NotFoundException('Venta no encontrada');
    }

    if (sale.userId !== requestUserId) {
      throw new ForbiddenException('No puedes devolver esta venta');
    }

    try {
      return await this.prisma.$transaction(async (tx) => {
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
            deletedById: requestUserId,
            note: sale!.note?.trim()
              ? `${sale!.note}\nDEVOLUCION: venta devuelta desde historial.`
              : 'DEVOLUCION: venta devuelta desde historial.',
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
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new NotFoundException('Venta no encontrada');
    }
  }

  async purgeAllForDebug(user: { id: string; role: string }) {
    if (`${user.role}`.trim().toUpperCase() !== 'ADMIN') {
      throw new ForbiddenException('Solo un administrador puede limpiar ventas.');
    }

    const deleted = await this.prisma.sale.deleteMany();
    return {
      ok: true,
      deletedSales: deleted.count,
    };
  }

  private normalizeItem(
    item: CreateSaleItemDto,
    index: number,
    productMap: Map<string, { id: string; nombre: string; imagen: string | null; costo: Prisma.Decimal; stock: Prisma.Decimal }>,
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
        throw new BadRequestException(`Producto inválido en item #${index + 1}`);
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
      };
    }

    const productName = item.productName?.trim();
    if (!productName) {
      throw new BadRequestException(`Nombre requerido para item fuera de inventario #${index + 1}`);
    }

    if (item.costUnitSnapshot === undefined || item.costUnitSnapshot === null) {
      throw new BadRequestException(`Costo unitario requerido en item fuera de inventario #${index + 1}`);
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
    };
  }

  private toNumber(value: Prisma.Decimal | number | string | null | undefined): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === 'number') return value;
    return Number(value);
  }

  private buildDateRange(from?: string, to?: string): { saleDate?: Prisma.DateTimeFilter } {
    const saleDate: Prisma.DateTimeFilter = {};

    if (from) {
      const fromDate = this.parseDateBoundary(from, true);
      if (Number.isNaN(fromDate.getTime())) {
        throw new BadRequestException('Parámetro from inválido');
      }
      saleDate.gte = fromDate;
    }

    if (to) {
      const toDate = this.parseDateBoundary(to, false);
      if (Number.isNaN(toDate.getTime())) {
        throw new BadRequestException('Parámetro to inválido');
      }
      saleDate.lt = toDate;
    }

    return Object.keys(saleDate).length ? { saleDate } : {};
  }

  private parseDateBoundary(value: string, isStart: boolean): Date {
    const trimmed = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      const date = new Date(`${trimmed}T00:00:00.000Z`);
      if (isStart) return date;
      return new Date(date.getTime() + 24 * 60 * 60 * 1000);
    }
    return new Date(trimmed);
  }
}
