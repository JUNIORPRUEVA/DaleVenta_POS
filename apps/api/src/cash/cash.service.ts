import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CloseCashSessionDto, CreateCashMovementDto, OpenCashSessionDto } from './dto/cash.dto';

type RequestUser = { id: string; role: Role };

@Injectable()
export class CashService {
  constructor(private readonly prisma: PrismaService) {}

  private businessDate(date = new Date()) {
    return date.toISOString().slice(0, 10);
  }

  private toNumber(value: Prisma.Decimal | number | null | undefined) {
    if (value == null) return 0;
    if (typeof value === 'number') return value;
    return value.toNumber();
  }

  private async currentUserName(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { nombreCompleto: true, email: true, blocked: true },
    });
    if (!user || user.blocked) {
      throw new ForbiddenException('No se pudo confirmar el usuario actual.');
    }
    return user.nombreCompleto || user.email || 'Usuario';
  }

  async gateState(user: RequestUser) {
    const businessDate = this.businessDate();
    const [cashboxToday, userOpenShift] = await Promise.all([
      this.prisma.cashboxDaily.findUnique({ where: { businessDate } }),
      this.prisma.cashSession.findFirst({
        where: { openedByUserId: user.id, status: 'OPEN', closedAt: null },
        orderBy: { openedAt: 'desc' },
      }),
    ]);

    return {
      businessDate,
      cashboxToday,
      userOpenShift,
      activeSession: userOpenShift
        ? this.mapActiveSession(userOpenShift)
        : null,
      canOperate: userOpenShift?.status === 'OPEN',
    };
  }

  async startSession(user: RequestUser, dto: OpenCashSessionDto) {
    const userName = await this.currentUserName(user.id);
    const businessDate = this.businessDate();
    const openingAmount = new Prisma.Decimal(dto.openingAmount);

    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.cashSession.findFirst({
        where: { openedByUserId: user.id, status: 'OPEN', closedAt: null },
        orderBy: { openedAt: 'desc' },
      });
      if (existing) return this.mapActiveSession(existing);

      const cashbox = await tx.cashboxDaily.upsert({
        where: { businessDate },
        create: {
          businessDate,
          openedByUserId: user.id,
          initialAmount: openingAmount,
          currentAmount: openingAmount,
          note: dto.note,
        },
        update: {
          status: 'OPEN',
          closedAt: null,
          closedByUserId: null,
        },
      });

      const session = await tx.cashSession.create({
        data: {
          openedByUserId: user.id,
          userName,
          initialAmount: openingAmount,
          cashboxDailyId: cashbox.id,
          businessDate,
          note: dto.note,
        },
      });

      return this.mapActiveSession(session);
    });
  }

  async addMovement(user: RequestUser, dto: CreateCashMovementDto) {
    const session = await this.requireOpenSession(user.id);
    const amount = new Prisma.Decimal(dto.amount);
    if (dto.type === 'OUT') {
      const summary = await this.buildSummaryForSession(session.id);
      if (summary.expectedCash < dto.amount) {
        throw new BadRequestException('No hay efectivo suficiente en caja para este retiro.');
      }
    }

    const movementType = dto.movementType ?? 'expense';
    const affectsProfit =
      dto.affectsProfit ?? (dto.type === 'OUT' && movementType === 'expense');

    return this.prisma.cashMovement.create({
      data: {
        sessionId: session.id,
        type: dto.type,
        amount,
        reason: dto.reason,
        movementType,
        affectsProfit,
        userId: user.id,
      },
    });
  }

  async closeSession(user: RequestUser, dto: CloseCashSessionDto) {
    const session = await this.requireOpenSession(user.id);
    const summary = await this.buildSummaryForSession(session.id);
    const closingAmount = new Prisma.Decimal(dto.closingAmount);
    const expectedAmount = new Prisma.Decimal(summary.expectedCash);
    const difference = closingAmount.minus(expectedAmount);

    return this.prisma.$transaction(async (tx) => {
      const closed = await tx.cashSession.update({
        where: { id: session.id },
        data: {
          status: 'CLOSED',
          closingAmount,
          expectedAmount,
          difference,
          closedAt: new Date(),
          closedByUserId: user.id,
          note: dto.note ?? session.note,
        },
      });

      const otherOpen = await tx.cashSession.findFirst({
        where: {
          cashboxDailyId: session.cashboxDailyId,
          status: 'OPEN',
          closedAt: null,
          id: { not: session.id },
        },
        select: { id: true },
      });

      if (!otherOpen && session.cashboxDailyId) {
        await tx.cashboxDaily.update({
          where: { id: session.cashboxDailyId },
          data: {
            status: 'CLOSED',
            closedAt: new Date(),
            closedByUserId: user.id,
            currentAmount: closingAmount,
          },
        });
      }

      return { session: closed, summary, difference: this.toNumber(difference) };
    });
  }

  async summary(user: RequestUser) {
    const session = await this.requireOpenSession(user.id);
    return this.buildSummaryForSession(session.id);
  }

  async movements(user: RequestUser) {
    const session = await this.requireOpenSession(user.id);
    return this.prisma.cashMovement.findMany({
      where: { sessionId: session.id },
      orderBy: { createdAt: 'desc' },
    });
  }

  async closedSessions(user: RequestUser) {
    return this.prisma.cashSession.findMany({
      where:
        user.role === Role.ADMIN || user.role === Role.ASISTENTE
          ? { status: 'CLOSED' }
          : { status: 'CLOSED', openedByUserId: user.id },
      orderBy: { closedAt: 'desc' },
      take: 60,
    });
  }

  async requireOpenSession(userId: string) {
    const session = await this.prisma.cashSession.findFirst({
      where: { openedByUserId: userId, status: 'OPEN', closedAt: null },
      orderBy: { openedAt: 'desc' },
    });
    if (!session) {
      throw new NotFoundException('No encontramos un turno abierto para operar.');
    }
    return session;
  }

  async buildSummaryForSession(sessionId: string) {
    const session = await this.prisma.cashSession.findUnique({
      where: { id: sessionId },
    });
    if (!session) {
      throw new NotFoundException('No encontramos el turno solicitado.');
    }

    const [sales, movements] = await Promise.all([
      this.prisma.sale.findMany({
        where: { cashSessionId: sessionId },
        select: {
          totalSold: true,
          paymentMethod: true,
          paymentCashAmount: true,
          paymentTransferAmount: true,
          isDeleted: true,
          kind: true,
        },
      }),
      this.prisma.cashMovement.findMany({ where: { sessionId } }),
    ]);

    let salesCashTotal = 0;
    let salesTransferTotal = 0;
    let totalSales = 0;
    let refundsCash = 0;
    let totalTickets = 0;
    let totalRefunds = 0;

    for (const sale of sales) {
      const cash = this.toNumber(sale.paymentCashAmount);
      const transfer = this.toNumber(sale.paymentTransferAmount);
      if (sale.isDeleted || sale.kind === 'return') {
        refundsCash += cash;
        totalRefunds += 1;
        continue;
      }
      totalTickets += 1;
      totalSales += this.toNumber(sale.totalSold);
      salesCashTotal += cash;
      salesTransferTotal += transfer;
    }

    let cashInManual = 0;
    let cashOutManual = 0;
    let totalExpenses = 0;
    let totalWithdrawals = 0;
    for (const movement of movements) {
      const amount = this.toNumber(movement.amount);
      if (movement.type === 'IN') cashInManual += amount;
      if (movement.type === 'OUT') {
        cashOutManual += amount;
        if (movement.movementType === 'expense' && movement.affectsProfit) {
          totalExpenses += amount;
        } else {
          totalWithdrawals += amount;
        }
      }
    }

    const openingAmount = this.toNumber(session.initialAmount);
    const expectedCash =
      openingAmount + salesCashTotal - refundsCash + cashInManual - cashOutManual;

    return {
      sessionId,
      openingAmount,
      totalSales,
      totalExpenses,
      totalWithdrawals,
      cashInManual,
      cashOutManual,
      creditAbonos: 0,
      layawayAbonos: 0,
      salesCashTotal,
      salesCardTotal: 0,
      salesTransferTotal,
      salesCreditTotal: 0,
      refundsCash,
      expectedCash,
      totalTickets,
      totalRefunds,
    };
  }

  private mapActiveSession(session: {
    id: string;
    openedByUserId: string;
    cashboxDailyId: string | null;
    openedAt: Date;
    status: string;
    userName: string | null;
    businessDate: string | null;
  }) {
    return {
      userId: session.openedByUserId,
      cashId: session.cashboxDailyId,
      shiftId: session.id,
      openedAt: session.openedAt,
      status: session.status,
      userName: session.userName ?? 'Usuario',
      businessDate: session.businessDate ?? this.businessDate(),
    };
  }
}
