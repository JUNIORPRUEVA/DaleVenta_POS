import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
} from "@nestjs/common";
import { Prisma, Role } from "@prisma/client";
import crypto from "node:crypto";
import { PrismaService } from "../prisma/prisma.service";
import { CatalogRealtimeRelayService } from "../products/catalog-realtime-relay.service";
import { isAdminLike, requireTenant, type TenantUser } from "../auth/tenant-context";
import {
  CloseCashSessionDto,
  CreateCashMovementDto,
  OpenCashSessionDto,
} from "./dto/cash.dto";
import { TerminalResolutionService } from "../terminals/terminal-resolution.service";

type RequestUser = TenantUser;

@Injectable()
export class CashService {
  private readonly logger = new Logger(CashService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
    @Optional()
    private readonly terminalResolution?: TerminalResolutionService,
  ) {}

  private terminalResolutionService() {
    return this.terminalResolution ?? new TerminalResolutionService(this.prisma);
  }

  private businessDate(date = new Date()) {
    return date.toISOString().slice(0, 10);
  }

  private toNumber(value: Prisma.Decimal | number | null | undefined) {
    if (value == null) return 0;
    if (typeof value === "number") return value;
    return value.toNumber();
  }

  private async currentUserName(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { nombreCompleto: true, email: true, blocked: true },
    });
    if (!user || user.blocked) {
      throw new ForbiddenException("No se pudo confirmar el usuario actual.");
    }
    return user.nombreCompleto || user.email || "Usuario";
  }

  async gateState(user: RequestUser) {
    const companyId = requireTenant(user);
    const businessDate = this.businessDate();
    const [cashboxToday, userOpenShift] = await Promise.all([
      this.prisma.cashboxDaily.findFirst({ where: { companyId, businessDate } }),
      this.prisma.cashSession.findFirst({
        where: { openedByUserId: user.id, companyId, status: "OPEN", closedAt: null },
        orderBy: { openedAt: "desc" },
      }),
    ]);

    return {
      businessDate,
      cashboxToday,
      userOpenShift,
      activeSession: userOpenShift
        ? this.mapActiveSession(userOpenShift)
        : null,
      canOperate: userOpenShift?.status === "OPEN",
    };
  }

  async startSession(user: RequestUser, dto: OpenCashSessionDto) {
    const companyId = requireTenant(user);
    const userName = await this.currentUserName(user.id);
    const businessDate = this.businessDate();
    const openingAmount = new Prisma.Decimal(dto.openingAmount);

    // Invariante multi-dispositivo: solo puede existir UN turno abierto por
    // (usuario + empresa). Dos dispositivos pueden pulsar "Abrir caja" casi al
    // mismo tiempo; con aislamiento por defecto (READ COMMITTED) ambos podrían
    // ver "no existe turno" y crear dos turnos abiertos. Con SERIALIZABLE el
    // segundo intento aborta (P2034) y se reintenta: en el reintento ya verá el
    // turno creado y lo devolverá, en lugar de crear un segundo.
    const session = await this.retryOnWriteConflict(() =>
      this.prisma.$transaction(
        async (tx) => {
          const terminalContext =
            dto.terminalId || dto.deviceFingerprint
              ? await this.terminalResolutionService().resolveForSale(tx, {
                  companyId,
                  terminalId: dto.terminalId,
                  deviceFingerprint: dto.deviceFingerprint,
                })
              : null;
          const existing = await tx.cashSession.findFirst({
            where: {
              openedByUserId: user.id,
              companyId,
              status: "OPEN",
              closedAt: null,
            },
            orderBy: { openedAt: "desc" },
          });
          if (existing) return this.mapActiveSession(existing);

          let cashbox = await tx.cashboxDaily.findFirst({
            where: { companyId, businessDate },
          });
          if (!cashbox) {
            cashbox = await tx.cashboxDaily.create({
              data: {
                companyId,
                businessDate,
                openedByUserId: user.id,
                initialAmount: openingAmount,
                currentAmount: openingAmount,
                note: dto.note,
              },
            });
          } else {
            cashbox = await tx.cashboxDaily.update({
              where: { id: cashbox.id },
              data: {
                status: "OPEN",
                closedAt: null,
                closedByUserId: null,
              },
            });
          }

          const session = await tx.cashSession.create({
            data: {
              companyId,
              openedByUserId: user.id,
              terminalId: terminalContext?.terminal.id ?? null,
              terminalNameSnapshot: terminalContext?.terminal.name ?? null,
              terminalCodeSnapshot: terminalContext?.terminal.code ?? null,
              userName,
              initialAmount: openingAmount,
              cashboxDailyId: cashbox.id,
              businessDate,
              note: dto.note,
            },
          });

          return this.mapActiveSession(session);
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      ),
    );
    this.emitCashEvent(companyId, "cash.session.opened", session.shiftId, {
      userId: user.id,
      businessDate: session.businessDate,
    });
    return session;
  }

  /**
   * Reintenta una transacción que falló por conflicto de escritura/deadlock
   * (P2034, típico de aislamiento SERIALIZABLE bajo concurrencia real). El
   * reintento es seguro: la transacción es idempotente (si el turno ya existe
   * se devuelve el existente).
   */
  private async retryOnWriteConflict<T>(
    task: () => Promise<T>,
    attempts = 3,
  ): Promise<T> {
    for (let attempt = 1; ; attempt++) {
      try {
        return await task();
      } catch (error) {
        const isConflict =
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2034";
        if (!isConflict || attempt >= attempts) throw error;
      }
    }
  }

  async addMovement(user: RequestUser, dto: CreateCashMovementDto) {
    const companyId = requireTenant(user);
    const session = await this.requireOpenSession(user.id, companyId);
    const amount = new Prisma.Decimal(dto.amount);
    if (dto.type === "OUT") {
      const summary = await this.buildSummaryForSession(session.id, companyId);
      if (summary.expectedCash < dto.amount) {
        throw new BadRequestException(
          "No hay efectivo suficiente en caja para este retiro.",
        );
      }
    }

    const movementType = dto.movementType ?? "expense";
    const affectsProfit =
      dto.affectsProfit ?? (dto.type === "OUT" && movementType === "expense");

    const movement = await this.prisma.cashMovement.create({
      data: {
        sessionId: session.id,
        companyId,
        type: dto.type,
        amount,
        reason: dto.reason,
        movementType,
        affectsProfit,
        userId: user.id,
      },
    });
    this.emitCashEvent(companyId, "cash.movement.created", session.id, {
      userId: user.id,
      movementId: movement.id,
      businessDate: session.businessDate,
    });
    return movement;
  }

  async closeSession(user: RequestUser, dto: CloseCashSessionDto) {
    const companyId = requireTenant(user);
    const session = await this.requireOpenSession(user.id, companyId);
    const summary = await this.buildSummaryForSession(session.id, companyId);
    const closingAmount = new Prisma.Decimal(dto.closingAmount);
    const expectedAmount = new Prisma.Decimal(summary.expectedCash);
    const difference = closingAmount.minus(expectedAmount);

    const result = await this.prisma.$transaction(async (tx) => {
      const closeResult = await tx.cashSession.updateMany({
        where: {
          id: session.id,
          companyId,
          openedByUserId: user.id,
          status: "OPEN",
          closedAt: null,
        },
        data: {
          status: "CLOSED",
          closingAmount,
          expectedAmount,
          difference,
          closedAt: new Date(),
          closedByUserId: user.id,
          note: dto.note ?? session.note,
        },
      });
      if (closeResult.count !== 1) {
        throw new ConflictException("Este turno ya fue cerrado.");
      }

      const closed = await tx.cashSession.findFirst({
        where: { id: session.id, companyId },
      });
      if (!closed) {
        throw new NotFoundException("No encontramos el turno cerrado.");
      }

      const otherOpen = await tx.cashSession.findFirst({
        where: {
          cashboxDailyId: session.cashboxDailyId,
          companyId,
          status: "OPEN",
          closedAt: null,
          id: { not: session.id },
        },
        select: { id: true },
      });

      if (!otherOpen && session.cashboxDailyId) {
        await tx.cashboxDaily.update({
          where: { id: session.cashboxDailyId },
          data: {
            status: "CLOSED",
            closedAt: new Date(),
            closedByUserId: user.id,
            currentAmount: closingAmount,
          },
        });
      }

      return {
        session: closed,
        summary,
        difference: this.toNumber(difference),
      };
    });
    this.emitCashEvent(companyId, "cash.session.closed", session.id, {
      userId: user.id,
      businessDate: session.businessDate,
    });
    return result;
  }

  async summary(user: RequestUser) {
    const companyId = requireTenant(user);
    const session = await this.requireOpenSession(user.id, companyId);
    return this.buildSummaryForSession(session.id, companyId);
  }

  async movements(user: RequestUser) {
    const companyId = requireTenant(user);
    const session = await this.requireOpenSession(user.id, companyId);
    return this.prisma.cashMovement.findMany({
      where: { sessionId: session.id, companyId },
      orderBy: { createdAt: "desc" },
    });
  }

  async movementHistory(user: RequestUser, query: Record<string, string> = {}) {
    const companyId = requireTenant(user);
    const takeParam = Number(query.take ?? 160);
    const take = Number.isFinite(takeParam)
      ? Math.min(Math.max(takeParam, 1), 250)
      : 160;
    const type = ["IN", "OUT"].includes(query.type ?? "")
      ? query.type
      : undefined;
    const movementType = ["expense", "owner_draw", "transfer"].includes(
      query.movementType ?? "",
    )
      ? query.movementType
      : undefined;

    const where: Prisma.CashMovementWhereInput = {
      ...(type ? { type } : {}),
      ...(movementType ? { movementType } : {}),
      companyId,
      ...this.movementDateRange(query.from, query.to),
    };

    const rows = await this.prisma.cashMovement.findMany({
      where,
      include: {
        session: {
          select: {
            userName: true,
            businessDate: true,
            status: true,
            openedAt: true,
            closedAt: true,
          },
        },
      },
      orderBy: { createdAt: "desc" },
      take,
    });

    return rows.map(({ session, ...movement }) => ({
      ...movement,
      userName: session.userName ?? "Usuario",
      businessDate: session.businessDate,
      sessionStatus: session.status,
      sessionOpenedAt: session.openedAt,
      sessionClosedAt: session.closedAt,
    }));
  }

  private movementDateRange(
    from?: string,
    to?: string,
  ): Prisma.CashMovementWhereInput {
    if (!from && !to) return {};
    const createdAt: Prisma.DateTimeFilter = {};
    if (from) {
      const start = this.parseDominicanDate(from, true);
      if (Number.isNaN(start.getTime())) {
        throw new BadRequestException("Parámetro from inválido.");
      }
      createdAt.gte = start;
    }
    if (to) {
      const end = this.parseDominicanDate(to, false);
      if (Number.isNaN(end.getTime())) {
        throw new BadRequestException("Parámetro to inválido.");
      }
      createdAt.lte = end;
    }
    return { createdAt };
  }

  private parseDominicanDate(value: string, startOfDay: boolean) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim().slice(0, 10));
    if (!match) return new Date(Number.NaN);
    const year = Number(match[1]);
    const month = Number(match[2]) - 1;
    const day = Number(match[3]);
    if (startOfDay) return new Date(Date.UTC(year, month, day, 4, 0, 0, 0));
    return new Date(Date.UTC(year, month, day + 1, 3, 59, 59, 999));
  }

  async closedSessions(user: RequestUser) {
    const companyId = requireTenant(user);
    return this.prisma.cashSession.findMany({
      where:
        isAdminLike(user)
          ? { companyId, status: "CLOSED" }
          : { companyId, status: "CLOSED", openedByUserId: user.id },
      orderBy: { closedAt: "desc" },
      take: 60,
    });
  }

  async sessionDetail(user: RequestUser, sessionId: string) {
    const companyId = requireTenant(user);
    const session = await this.prisma.cashSession.findFirst({
      where: {
        id: sessionId,
        companyId,
        ...(isAdminLike(user) ? {} : { openedByUserId: user.id }),
      },
    });
    if (!session) {
      throw new NotFoundException("No encontramos el turno solicitado.");
    }
    const [summary, movements] = await Promise.all([
      this.buildSummaryForSession(sessionId, companyId),
      this.prisma.cashMovement.findMany({
        where: { sessionId, companyId },
        orderBy: { createdAt: "asc" },
      }),
    ]);
    return {
      id: session.id,
      userName: session.userName ?? "Usuario",
      businessDate: session.businessDate,
      openedAt: session.openedAt,
      closedAt: session.closedAt,
      status: session.status,
      terminalId: session.terminalId,
      terminalName: session.terminalNameSnapshot,
      terminalCode: session.terminalCodeSnapshot,
      initialAmount: this.toNumber(session.initialAmount),
      closingAmount: this.toNumber(session.closingAmount),
      expectedAmount: this.toNumber(session.expectedAmount),
      difference: this.toNumber(session.difference),
      note: session.note,
      summary,
      movements,
    };
  }

  async requireOpenSession(userId: string, companyId: string) {
    const session = await this.prisma.cashSession.findFirst({
      where: { openedByUserId: userId, companyId, status: "OPEN", closedAt: null },
      orderBy: { openedAt: "desc" },
    });
    if (!session) {
      throw new NotFoundException(
        "No encontramos un turno abierto para operar.",
      );
    }
    return session;
  }

  async buildSummaryForSession(sessionId: string, companyId: string) {
    const session = await this.prisma.cashSession.findFirst({
      where: { id: sessionId, companyId },
    });
    if (!session) {
      throw new NotFoundException("No encontramos el turno solicitado.");
    }

    const [sales, movements, creditPayments] = await Promise.all([
      this.prisma.sale.findMany({
        where: { cashSessionId: sessionId, companyId },
        select: {
          totalSold: true,
          totalProfit: true,
          paymentMethod: true,
          paymentCashAmount: true,
          paymentTransferAmount: true,
          creditAmount: true,
          creditBalance: true,
          isDeleted: true,
          kind: true,
          items: {
            select: {
              subtotalSold: true,
              profit: true,
              productNameSnapshot: true,
              product: {
                select: { categoria: true },
              },
            },
          },
        },
      }),
      this.prisma.cashMovement.findMany({ where: { sessionId, companyId } }),
      this.prisma.saleCreditPayment.findMany({
        where: { cashSessionId: sessionId, companyId },
      }),
    ]);

    let salesCashTotal = 0;
    let salesTransferTotal = 0;
    let totalSales = 0;
    let refundsCash = 0;
    let totalTickets = 0;
    let totalRefunds = 0;
    let creditAbonos = 0;
    let creditSalesTotal = 0;
    let creditInitialCash = 0;
    let creditInitialTransfer = 0;
    let creditBalanceTotal = 0;
    let creditPaymentCash = 0;
    let creditPaymentTransfer = 0;
    const categories = new Map<
      string,
      {
        category: string;
        totalSold: number;
        totalProfit: number;
        items: number;
      }
    >();

    for (const sale of sales) {
      const cash = this.toNumber(sale.paymentCashAmount);
      const transfer = this.toNumber(sale.paymentTransferAmount);
      if (sale.isDeleted || sale.kind === "return") {
        refundsCash += cash;
        totalRefunds += 1;
        continue;
      }
      totalTickets += 1;
      totalSales += this.toNumber(sale.totalSold);
      salesCashTotal += cash;
      salesTransferTotal += transfer;
      if (sale.paymentMethod === "credit") {
        creditSalesTotal += this.toNumber(sale.totalSold);
        creditInitialCash += cash;
        creditInitialTransfer += transfer;
        creditBalanceTotal += this.toNumber(sale.creditBalance);
      }
      for (const item of sale.items) {
        const category = item.product?.categoria?.trim() || "Sin categoria";
        const current = categories.get(category) ?? {
          category,
          totalSold: 0,
          totalProfit: 0,
          items: 0,
        };
        current.totalSold += this.toNumber(item.subtotalSold);
        current.totalProfit += this.toNumber(item.profit);
        current.items += 1;
        categories.set(category, current);
      }
    }

    for (const payment of creditPayments) {
      const cash = this.toNumber(payment.cashAmount);
      const transfer = this.toNumber(payment.transferAmount);
      const amount = this.toNumber(payment.amount);
      creditAbonos += amount;
      creditPaymentCash += cash;
      creditPaymentTransfer += transfer;
      salesCashTotal += cash;
      salesTransferTotal += transfer;
    }

    let cashInManual = 0;
    let cashOutManual = 0;
    let totalExpenses = 0;
    let totalWithdrawals = 0;
    for (const movement of movements) {
      const amount = this.toNumber(movement.amount);
      if (movement.type === "IN") cashInManual += amount;
      if (movement.type === "OUT") {
        cashOutManual += amount;
        if (movement.movementType === "expense" && movement.affectsProfit) {
          totalExpenses += amount;
        } else {
          totalWithdrawals += amount;
        }
      }
    }

    const openingAmount = this.toNumber(session.initialAmount);
    const expectedCash =
      openingAmount +
      salesCashTotal -
      refundsCash +
      cashInManual -
      cashOutManual;

    return {
      sessionId,
      openingAmount,
      totalSales,
      totalExpenses,
      totalWithdrawals,
      cashInManual,
      cashOutManual,
      creditAbonos,
      creditSalesTotal,
      creditInitialCash,
      creditInitialTransfer,
      creditBalanceTotal,
      creditPaymentCash,
      creditPaymentTransfer,
      layawayAbonos: 0,
      salesCashTotal,
      salesCardTotal: 0,
      salesTransferTotal,
      salesCreditTotal: sales
        .filter((sale) => !sale.isDeleted && sale.paymentMethod === "credit")
        .reduce(
          (sum, sale) =>
            sum +
            Math.max(
              0,
              this.toNumber(sale.totalSold) -
                this.toNumber(sale.paymentCashAmount) -
                this.toNumber(sale.paymentTransferAmount),
            ),
          0,
        ),
      refundsCash,
      expectedCash,
      totalTickets,
      totalRefunds,
      categorySummary: Array.from(categories.values()).sort(
        (a, b) => b.totalSold - a.totalSold,
      ),
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
    terminalId?: string | null;
    terminalNameSnapshot?: string | null;
    terminalCodeSnapshot?: string | null;
  }) {
    return {
      userId: session.openedByUserId,
      cashId: session.cashboxDailyId,
      shiftId: session.id,
      openedAt: session.openedAt,
      status: session.status,
      userName: session.userName ?? "Usuario",
      businessDate: session.businessDate ?? this.businessDate(),
      terminalId: session.terminalId ?? null,
      terminalName: session.terminalNameSnapshot ?? null,
      terminalCode: session.terminalCodeSnapshot ?? null,
    };
  }

  private emitCashEvent(
    companyId: string,
    type: string,
    sessionId?: string | null,
    extra: Record<string, unknown> = {},
  ) {
    const payload = {
      eventId: crypto.randomUUID(),
      type,
      sessionId,
      companyId,
      emittedAt: new Date().toISOString(),
      ...extra,
    };
    this.logger.log(
      `cash.realtime.emit room=company:${companyId} event=cash.event type=${type} ` +
        `sessionId=${sessionId ?? ""} userId=${(extra.userId as string) ?? ""}`,
    );
    try {
      this.realtime.emitCompany(companyId, "cash.event", payload);
    } catch (error) {
      this.logger.error(
        `cash.realtime.emit.failed type=${type} room=company:${companyId}`,
        error instanceof Error ? (error.stack ?? error.message) : String(error),
      );
    }
  }
}
