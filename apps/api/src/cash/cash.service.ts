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
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import {
  cashCloseLegacyCompatEnabled,
  classifyFinancialContract,
  financialLegacyCompatEnabled,
  legacyCompatRejected,
  legacyFinancialLogPayload,
  partialFinancialContractRejected,
  type FinancialClientMetadata,
} from "../common/financial-legacy-compat";
import {
  normalizePagePagination,
  toPageResult,
} from "../common/pagination/page-pagination";
import {
  CloseCashSessionDto,
  CreateCashMovementDto,
  OpenCashSessionDto,
} from "./dto/cash.dto";
import { TerminalResolutionService } from "../terminals/terminal-resolution.service";
import { UsageTelemetryService } from "../usage-telemetry/usage-telemetry.service";
import {
  creditPaymentTotalsBySaleId,
  deriveSalePaymentBreakdown,
} from "../common/utils/sale-credit-payment.util";
import {
  currentBusinessDay,
  businessDateRange,
} from "../common/utils/business-time.util";
import {
  evaluateShiftOperationWindow,
  shiftWindowRejected,
} from "./cash-operation-window";

type RequestUser = TenantUser;

const CURRENT_CASH_MOVEMENTS_LIMIT = 500;

@Injectable()
export class CashService {
  private readonly logger = new Logger(CashService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
    @Optional()
    private readonly terminalResolution?: TerminalResolutionService,
    @Optional()
    private readonly telemetry?: UsageTelemetryService,
  ) {}

  private terminalResolutionService() {
    return (
      this.terminalResolution ?? new TerminalResolutionService(this.prisma)
    );
  }

  private businessDate(date = new Date()) {
    return currentBusinessDay(date);
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
    const [cashboxToday, openShifts] = await Promise.all([
      this.prisma.cashboxDaily.findFirst({
        where: { companyId, businessDate },
      }),
      this.prisma.cashSession.findMany({
        where: {
          openedByUserId: user.id,
          companyId,
          status: "OPEN",
          closedAt: null,
        },
        orderBy: { openedAt: "desc" },
        take: 2,
      }),
    ]);

    // Ambigüedad REAL: más de un turno abierto del mismo usuario. Sólo este
    // caso conserva el 409 histórico (código intacto para los clientes
    // 1.0.6+130/132) porque no hay una elección segura de turno.
    if (openShifts.length > 1) {
      this.logger.warn(
        `cash.state.ambiguous company=${companyId} userId=${user.id} open=${openShifts.length}`,
      );
      throw new ConflictException({
        code: "CASH_SESSION_REQUIRES_REVIEW",
        errorCode: "CASH_SESSION_REQUIRES_REVIEW",
        reason: "MULTIPLE_OPEN_SESSIONS",
        message:
          "Hay más de un turno abierto para tu usuario. Contacta a un administrador.",
      });
    }

    const userOpenShift = openShifts[0] ?? null;
    // Turno vencido = turno abierto de un día comercial anterior. Se devuelve
    // para que el usuario pueda CERRARLO (antes el 409 lo dejaba sin salida),
    // pero queda bloqueado para operar (`canOperate: false`).
    const staleBusinessDate = userOpenShift
      ? (userOpenShift.businessDate ?? businessDate) !== businessDate
      : false;
    if (userOpenShift && staleBusinessDate) {
      // Observabilidad: turno vencido detectado antes de que bloquee ventas.
      this.logger.warn(
        `cash.state.stale_shift company=${companyId} userId=${user.id} session=${userOpenShift.id} sessionBusinessDate=${userOpenShift.businessDate ?? "null"} currentBusinessDate=${businessDate}`,
      );
    }
    const cashboxTotals = await this.cashboxTotals(
      cashboxToday?.id ?? null,
      companyId,
    );

    return {
      businessDate,
      cashboxToday,
      cashboxTotals,
      userOpenShift,
      activeSession: userOpenShift
        ? this.mapActiveSession(userOpenShift)
        : null,
      canOperate: Boolean(userOpenShift) && !staleBusinessDate,
      staleBusinessDate,
      requiresClosure: staleBusinessDate,
      requiresReview: false,
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
          if (existing) {
            // Nunca se reutiliza en silencio un turno de otro día comercial:
            // eso permitía que ventas de días posteriores cayeran en el cierre
            // anterior. El cliente recibe la identidad del turno a cerrar.
            const existingStale =
              (existing.businessDate ?? businessDate) !== businessDate;
            if (existingStale) {
              this.logger.warn(
                `cash.open.rejected reason=previous_shift_open company=${companyId} userId=${user.id} session=${existing.id} sessionBusinessDate=${existing.businessDate ?? "null"} currentBusinessDate=${businessDate}`,
              );
              throw new ConflictException({
                code: "CASH_CLOSE_PREVIOUS_REQUIRED",
                errorCode: "CASH_CLOSE_PREVIOUS_REQUIRED",
                sessionId: existing.id,
                businessDate: existing.businessDate,
                message: `Tienes un turno abierto del ${
                  existing.businessDate ?? "día anterior"
                }. Ciérralo antes de abrir uno nuevo.`,
              });
            }
            return this.mapActiveSession(existing);
          }

          // Identidad de apertura provista por el cliente (turno abierto
          // offline). Hace la apertura idempotente: si el turno ya existe con
          // esa identidad y sigue abierto, se devuelve el mismo; si ya fue
          // cerrado, se rechaza de forma controlada sin crear otro turno.
          const clientSessionId = this.validUuidOrNull(dto.clientSessionId);
          if (clientSessionId) {
            const existingById = await tx.cashSession.findFirst({
              where: { id: clientSessionId, companyId },
            });
            if (existingById) {
              const isMineAndOpen =
                existingById.openedByUserId === user.id &&
                existingById.status === "OPEN" &&
                existingById.closedAt == null;
              if (isMineAndOpen) return this.mapActiveSession(existingById);
              this.logger.warn(
                `cash.open.rejected company=${companyId} clientSessionId=${clientSessionId} status=${existingById.status}`,
              );
              throw new ConflictException(
                "Ese turno ya no está disponible para operar.",
              );
            }
          }

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

          let session;
          try {
            session = await tx.cashSession.create({
              data: {
                ...(clientSessionId ? { id: clientSessionId } : {}),
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
          } catch (error) {
            // Colisión de identidad (mismo id en otra empresa): se responde de
            // forma controlada en lugar de propagar un error de Prisma.
            if (
              error instanceof Prisma.PrismaClientKnownRequestError &&
              error.code === "P2002"
            ) {
              this.logger.warn(
                `cash.open.rejected reason=client_session_id_conflict company=${companyId} clientSessionId=${clientSessionId}`,
              );
              throw new ConflictException(
                "Ese turno ya no está disponible para operar.",
              );
            }
            throw error;
          }

          await this.telemetry?.enqueueBusinessEvent(tx, {
            companyId,
            actorUserId: user.id,
            eventType: "CASH_SESSION_OPENED",
            entityType: "cash_session",
            entityId: session.id,
            feature: "CASH",
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
   *
   * Se reintenta con espera exponencial y jitter: varios empleados abriendo
   * turno en el mismo instante reintentaban sincronizados y volvían a chocar
   * hasta agotar los intentos (reproducido en UAT con 4 aperturas simultáneas).
   */
  private async retryOnWriteConflict<T>(
    task: () => Promise<T>,
    attempts = 5,
  ): Promise<T> {
    for (let attempt = 1; ; attempt++) {
      try {
        return await task();
      } catch (error) {
        const isConflict =
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2034";
        if (!isConflict || attempt >= attempts) throw error;
        const backoffMs =
          Math.min(50 * 2 ** (attempt - 1), 400) + Math.floor(Math.random() * 60);
        this.logger.warn(
          `cash.tx.retry reason=write_conflict attempt=${attempt}/${attempts} backoffMs=${backoffMs}`,
        );
        await new Promise((resolve) => setTimeout(resolve, backoffMs));
      }
    }
  }

  /**
   * Patrón de UUID (v4/v1/v7) para validar identificadores de turno antes de
   * tocar una columna `@db.Uuid`. Un valor malformado se responde como
   * "no existe" (404 controlado) en lugar de provocar un error de Prisma (P2023).
   */
  private static readonly UUID_PATTERN =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  private validUuidOrNull(value?: string | null): string | null {
    const text = (value ?? "").trim();
    return CashService.UUID_PATTERN.test(text) ? text : null;
  }

  async addMovement(
    user: RequestUser,
    dto: CreateCashMovementDto,
    requestMetadata?: FinancialClientMetadata,
  ) {
    const companyId = requireTenant(user);
    const movementPath = classifyFinancialContract(
      {
        sessionId: dto.sessionId,
        operationId: dto.operationId,
      },
      ["sessionId"],
      ["operationId"],
    );
    if (movementPath === "INVALID_PARTIAL_REQUEST") {
      throw partialFinancialContractRejected("cash.movement");
    }
    const operationId = (dto.operationId ?? "").trim() || null;
    if (operationId) {
      const existing = await this.prisma.cashMovement.findFirst({
        where: { companyId, operationId },
      });
      if (existing) return existing;
    }
    if (
      movementPath === "LEGACY_COMPAT_PATH" &&
      !financialLegacyCompatEnabled()
    ) {
      this.logger.warn(
        `OFFLINE_MOVEMENT_LEGACY_MISSING_SESSION company=${companyId} userId=${user.id}`,
      );
      throw legacyCompatRejected();
    }
    // Un movimiento encolado offline se aplica EXACTAMENTE al turno que lo
    // originó (dto.sessionId). Nunca a "el turno abierto actual". Si el turno
    // original ya no está abierto, se rechaza de forma controlada en lugar de
    // contaminar un turno posterior.
    const session = await this.requireOpenSession(
      user.id,
      companyId,
      movementPath === "SAFE_NEW_PATH" ? dto.sessionId : undefined,
      this.parseOccurredAt(dto.occurredAt),
    );
    if (movementPath === "LEGACY_COMPAT_PATH") {
      this.logger.warn(
        JSON.stringify(
          legacyFinancialLogPayload({
            operation: "cash.movement",
            companyId,
            userId: user.id,
            resolvedCashSessionId: session.id,
            ...requestMetadata,
          }),
        ),
      );
      this.logger.warn(
        `LEGACY_CASH_MOVEMENT company=${companyId} userId=${user.id} session=${session.id}`,
      );
    }
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

    let movement;
    try {
      movement = await this.prisma.cashMovement.create({
        data: {
          sessionId: session.id,
          companyId,
          operationId,
          type: dto.type,
          amount,
          reason: dto.reason,
          movementType,
          affectsProfit,
          userId: user.id,
        },
      });
    } catch (error) {
      if (
        operationId &&
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const existing = await this.prisma.cashMovement.findFirst({
          where: { companyId, operationId },
        });
        if (existing) return existing;
      }
      throw error;
    }
    this.emitCashEvent(companyId, "cash.movement.created", session.id, {
      userId: user.id,
      movementId: movement.id,
      businessDate: session.businessDate,
    });
    return movement;
  }

  /**
   * Cierra un turno. El cierre SIEMPRE queda ligado inequívocamente a la sesión
   * que lo originó:
   *
   * - Con `dto.sessionId`: se cierra EXACTAMENTE esa sesión (de la empresa y
   *   del usuario del JWT). Si no está abierta se responde 409 y nunca se toca
   *   otra sesión. Un replay offline de un cierre viejo no puede cerrar un
   *   turno posterior.
   * - Sin `dto.sessionId` (cliente legacy): se aplica la política controlada
   *   `CASH_CLOSE_LEGACY_COMPAT` (por defecto RECHAZO 409), porque sin identidad
   *   no hay forma segura de distinguir un cierre contemporáneo de un replay.
   */
  async closeSession(user: RequestUser, dto: CloseCashSessionDto) {
    const companyId = requireTenant(user);
    const requestedSessionId = (dto.sessionId ?? "").trim() || null;

    const session = requestedSessionId
      ? await this.resolveCloseTargetById(user, companyId, requestedSessionId)
      : await this.resolveCloseTargetLegacy(user, companyId);

    return this.performCloseSession(user, companyId, session, dto);
  }

  /**
   * Resuelve la sesión a cerrar por identidad explícita. No hay fallback a
   * "el turno abierto actual": si el id no corresponde a una sesión cerrable
   * del usuario/empresa, la operación se rechaza.
   */
  private async resolveCloseTargetById(
    user: RequestUser,
    companyId: string,
    sessionId: string,
  ) {
    if (!this.validUuidOrNull(sessionId)) {
      this.logger.warn(
        `cash.close.rejected reason=malformed_session_id company=${companyId} session=${sessionId}`,
      );
      throw new NotFoundException("El turno indicado no existe.");
    }

    const session = await this.prisma.cashSession.findFirst({
      where: { id: sessionId, companyId, openedByUserId: user.id },
    });
    if (!session) {
      // Cubre "no existe", "es de otra empresa" y "es de otro usuario" con la
      // misma respuesta: no se filtra la existencia de turnos ajenos.
      this.logger.warn(
        `cash.close.rejected reason=session_not_found company=${companyId} session=${sessionId}`,
      );
      throw new NotFoundException("El turno indicado no existe.");
    }

    if (session.status !== "OPEN" || session.closedAt != null) {
      // El cierre solicitado ya se aplicó (replay / doble request) o el turno
      // no es cerrable. Se registra si además hay OTRO turno abierto, que es la
      // firma exacta del incidente Asadero, y se rechaza sin tocarlo.
      const otherOpen = await this.prisma.cashSession.findFirst({
        where: {
          openedByUserId: user.id,
          companyId,
          status: "OPEN",
          closedAt: null,
          id: { not: sessionId },
        },
        select: { id: true },
      });
      this.logger.warn(
        `CLOSE_REPLAY_REJECTED_SESSION_MISMATCH company=${companyId} session=${sessionId} status=${session.status} otherOpen=${otherOpen?.id ?? "none"}`,
      );
      throw new ConflictException("Este turno ya fue cerrado.");
    }

    return session;
  }

  /**
   * Política de compatibilidad para cierres sin `sessionId`.
   *
   * Sin identidad no existe una forma inequívocamente segura de distinguir un
   * cierre contemporáneo (UI online) de un replay offline viejo, así que por
   * defecto se RECHAZA de forma controlada. `CASH_CLOSE_LEGACY_COMPAT=true`
   * sólo deja evidencia explícita de que existe un cliente demasiado antiguo;
   * no cierra "el turno abierto actual" porque eso reabre el riesgo Asadero.
   */
  private async resolveCloseTargetLegacy(
    user: RequestUser,
    companyId: string,
  ): Promise<never> {
    this.logger.warn(
      `CLOSE_LEGACY_REJECTED company=${companyId} userId=${user.id} compat=${cashCloseLegacyCompatEnabled()}`,
    );
    throw new ConflictException({
      code: "CASH_CLOSE_SESSION_ID_REQUIRED",
      message: "Necesitas actualizar Fullpos para cerrar el turno.",
    });
  }

  private async performCloseSession(
    user: RequestUser,
    companyId: string,
    session: {
      id: string;
      cashboxDailyId: string | null;
      note: string | null;
      businessDate: string | null;
    },
    dto: CloseCashSessionDto,
  ) {
    const summary = await this.buildSummaryForSession(session.id, companyId);
    const closingAmount = new Prisma.Decimal(dto.closingAmount);
    const expectedAmount = new Prisma.Decimal(summary.expectedCash);
    const difference = closingAmount.minus(expectedAmount);

    const result = await this.prisma.$transaction(async (tx) => {
      // Serializa los cierres de la MISMA caja diaria: el bloqueo de fila se
      // toma al principio y siempre en el mismo orden, así que no hay ciclos de
      // espera. Con el bloqueo, la comprobación de "quedan turnos abiertos" y
      // la suma de cierres se hacen sobre datos ya confirmados: el agregado no
      // puede perderse si el proceso muere (todo va en la MISMA transacción que
      // el cierre del turno) ni quedar por debajo del real por concurrencia.
      if (session.cashboxDailyId) {
        await this.lockCashboxDaily(tx, session.cashboxDailyId);
      }

      // Transición atómica OPEN -> CLOSED condicionada por identidad. Sólo UNA
      // solicitud (doble clic, dos dispositivos, replay + cierre manual) puede
      // efectuar la transición; el resto obtiene count 0.
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
        this.logger.warn(
          `cash.close.conflict company=${companyId} session=${session.id}`,
        );
        throw new ConflictException("Este turno ya fue cerrado.");
      }

      const closed = await tx.cashSession.findFirst({
        where: { id: session.id, companyId },
      });
      if (!closed) {
        throw new NotFoundException("No encontramos el turno cerrado.");
      }

      if (session.cashboxDailyId) {
        await this.refreshDailyCashbox(
          tx,
          session.cashboxDailyId,
          companyId,
          user.id,
          session.id,
          closingAmount,
        );
      }

      await this.telemetry?.enqueueBusinessEvent(tx, {
        companyId,
        actorUserId: user.id,
        eventType: "CASH_SESSION_CLOSED",
        entityType: "cash_session",
        entityId: closed.id,
        feature: "CASH",
      });

      return {
        session: closed,
        summary,
        difference: this.toNumber(difference),
      };
    });

    this.logger.log(
      `cash.close.ok company=${companyId} session=${session.id} source=${
        (dto.sessionId ?? "").trim() ? "identified" : "legacy"
      } expected=${expectedAmount.toFixed(2)} closing=${closingAmount.toFixed(2)} difference=${difference.toFixed(2)} cashbox=${session.cashboxDailyId ?? "none"}`,
    );

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
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: CURRENT_CASH_MOVEMENTS_LIMIT,
    });
  }

  async movementHistory(user: RequestUser, query: Record<string, string> = {}) {
    const companyId = requireTenant(user);
    const pageParam = Number(query.page);
    const limitParam = Number(query.limit ?? query.take);
    const pagination = normalizePagePagination({
      page: Number.isFinite(pageParam) ? pageParam : undefined,
      limit: Number.isFinite(limitParam) ? limitParam : undefined,
      defaultLimit: 50,
    });
    const type = ["IN", "OUT"].includes(query.type ?? "")
      ? query.type
      : undefined;
    const movementType = ["expense", "owner_draw", "transfer"].includes(
      query.movementType ?? "",
    )
      ? query.movementType
      : undefined;
    const search = (query.search ?? query.q ?? "").trim();
    const searchWhere: Prisma.CashMovementWhereInput[] = search
      ? [
          { reason: { contains: search, mode: "insensitive" } },
          { type: { contains: search, mode: "insensitive" } },
          { movementType: { contains: search, mode: "insensitive" } },
          { session: { userName: { contains: search, mode: "insensitive" } } },
          {
            session: {
              businessDate: { contains: search, mode: "insensitive" },
            },
          },
        ]
      : [];

    const where: Prisma.CashMovementWhereInput = {
      ...(type ? { type } : {}),
      ...(movementType ? { movementType } : {}),
      companyId,
      ...this.movementDateRange(query.from, query.to),
      ...(searchWhere.length > 0 ? { OR: searchWhere } : {}),
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
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      skip: pagination.skip,
      take: pagination.take,
    });

    const items = rows.map(({ session, ...movement }) => ({
      ...movement,
      userName: session.userName ?? "Usuario",
      businessDate: session.businessDate,
      sessionStatus: session.status,
      sessionOpenedAt: session.openedAt,
      sessionClosedAt: session.closedAt,
    }));
    return toPageResult(items, pagination);
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
      createdAt.lt = end;
    }
    return { createdAt };
  }

  private parseDominicanDate(value: string, startOfDay: boolean) {
    const range = businessDateRange(value, value);
    return startOfDay ? range.gte : range.lt;
  }

  async closedSessions(user: RequestUser, query: Record<string, string> = {}) {
    const companyId = requireTenant(user);
    const pageParam = Number(query.page);
    const limitParam = Number(query.limit ?? query.take);
    const pagination = normalizePagePagination({
      page: Number.isFinite(pageParam) ? pageParam : undefined,
      limit: Number.isFinite(limitParam) ? limitParam : undefined,
      defaultLimit: 50,
    });
    const search = (query.search ?? query.q ?? "").trim();
    const rangeWhere = this.sessionBusinessDateRange(query.from, query.to);
    const searchWhere: Prisma.CashSessionWhereInput[] = search
      ? [
          { userName: { contains: search, mode: "insensitive" } },
          { businessDate: { contains: search, mode: "insensitive" } },
          { status: { contains: search, mode: "insensitive" } },
        ]
      : [];
    const baseWhere: Prisma.CashSessionWhereInput = {
      companyId,
      status: "CLOSED",
    };
    const rows = await this.prisma.cashSession.findMany({
      where: isAdminLike(user)
        ? {
            ...baseWhere,
            ...rangeWhere,
            ...(searchWhere.length > 0 ? { OR: searchWhere } : {}),
          }
        : {
            ...baseWhere,
            openedByUserId: user.id,
            ...rangeWhere,
            ...(searchWhere.length > 0 ? { OR: searchWhere } : {}),
          },
      orderBy: [{ closedAt: "desc" }, { id: "desc" }],
      skip: pagination.skip,
      take: pagination.take,
    });
    return toPageResult(rows, pagination);
  }

  private sessionBusinessDateRange(
    from?: string,
    to?: string,
  ): Prisma.CashSessionWhereInput {
    if (!from && !to) return {};
    const businessDate: Prisma.StringFilter = {};
    if (from) businessDate.gte = from;
    if (to) businessDate.lte = to;
    return { businessDate };
  }

  async sessionDetail(
    user: RequestUser,
    sessionId: string,
    query: Record<string, string> = {},
  ) {
    const companyId = requireTenant(user);
    const pageParam = Number(query.movementsPage ?? query.page);
    const limitParam = Number(
      query.movementsLimit ?? query.limit ?? query.take,
    );
    const pagination = normalizePagePagination({
      page: Number.isFinite(pageParam) ? pageParam : undefined,
      limit: Number.isFinite(limitParam) ? limitParam : undefined,
      defaultLimit: 50,
    });
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
        skip: pagination.skip,
        take: pagination.take,
      }),
    ]);
    const movementPage = toPageResult(movements, pagination);
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
      movements: movementPage.items,
      movementsPage: movementPage,
    };
  }

  async requireOpenSession(
    userId: string,
    companyId: string,
    sessionId?: string,
    occurredAt: Date = new Date(),
  ) {
    const requested = (sessionId ?? "").trim();
    // Con identidad explícita se exige ESA sesión abierta: un movimiento
    // encolado nunca cae sobre "el turno abierto actual". Sin identidad se
    // mantiene el comportamiento histórico (turno abierto del usuario).
    const scope = requested
      ? { id: this.validUuidOrNull(requested) ?? "__invalid__" }
      : {};
    const session = await this.prisma.cashSession.findFirst({
      where: {
        ...scope,
        openedByUserId: userId,
        companyId,
        status: "OPEN",
        closedAt: null,
      },
      orderBy: { openedAt: "desc" },
    });
    if (!session) {
      if (requested) {
        this.logger.warn(
          `cash.session.not_open company=${companyId} userId=${userId} session=${requested}`,
        );
      }
      throw new NotFoundException(
        "No encontramos un turno abierto para operar.",
      );
    }
    // Ventana operativa: la operación debe haber ocurrido dentro de la vida del
    // turno y dentro de su día comercial (o del siguiente, para turnos
    // nocturnos). Reemplaza al rechazo por "turno legacy ambiguo" en este
    // camino: es más preciso (mismo 409, motivo distinto) y cubre también el
    // caso de turno vencido sin turno más nuevo del día.
    const verdict = evaluateShiftOperationWindow({ occurredAt, session });
    if (!verdict.allowed) {
      this.logger.warn(
        `cash.operation.rejected code=${verdict.code} company=${companyId} userId=${userId} session=${session.id} sessionBusinessDate=${session.businessDate ?? "null"} occurredAt=${occurredAt.toISOString()}`,
      );
      throw new ConflictException(
        shiftWindowRejected(verdict.code, verdict.reason, session.id),
      );
    }
    return session;
  }

  private parseOccurredAt(value?: string | null): Date {
    const text = `${value ?? ""}`.trim();
    if (!text) return new Date();
    const parsed = new Date(text);
    if (Number.isNaN(parsed.getTime())) return new Date();
    return parsed;
  }

  /**
   * Totales DERIVADOS de la caja diaria compartida.
   *
   * `cashbox_daily` es única por (empresa, fecha) y la comparten todos los
   * empleados del día; sus columnas históricas no se reescriben. Estos totales
   * se calculan sobre las operaciones reales para que la UI no presente el
   * cierre del último empleado como si fuera el total del día.
   */
  private async cashboxTotals(
    cashboxDailyId: string | null,
    companyId: string,
  ) {
    if (!cashboxDailyId) {
      return {
        cashboxDailyId: null,
        sessions: 0,
        openSessions: 0,
        openedTotal: 0,
        closedTotal: 0,
      };
    }
    const [aggregate, openSessions] = await Promise.all([
      this.prisma.cashSession.aggregate({
        where: { cashboxDailyId, companyId },
        _count: { _all: true },
        _sum: { initialAmount: true, closingAmount: true },
      }),
      this.prisma.cashSession.count({
        where: {
          cashboxDailyId,
          companyId,
          status: "OPEN",
          closedAt: null,
        },
      }),
    ]);
    return {
      cashboxDailyId,
      sessions: aggregate._count?._all ?? 0,
      openSessions,
      openedTotal: this.toNumber(aggregate._sum?.initialAmount),
      closedTotal: this.toNumber(aggregate._sum?.closingAmount),
    };
  }

  private assertCompanyAdmin(user: RequestUser) {
    const role = (user as { role?: Role }).role;
    if (role !== Role.ADMIN) {
      throw new ForbiddenException(
        "Solo un administrador puede administrar los turnos de otros usuarios.",
      );
    }
  }

  /**
   * Turnos abiertos de días comerciales anteriores (sólo ADMIN).
   *
   * Da visibilidad antes de que el turno vencido bloquee al empleado. No
   * modifica nada.
   */
  async staleSessions(user: RequestUser) {
    const companyId = requireTenant(user);
    this.assertCompanyAdmin(user);
    const businessDate = this.businessDate();
    const rows = await this.prisma.cashSession.findMany({
      where: {
        companyId,
        status: "OPEN",
        closedAt: null,
        businessDate: { not: businessDate },
      },
      orderBy: { openedAt: "asc" },
    });
    return {
      businessDate,
      items: rows.map((session) => ({
        ...this.mapActiveSession(session),
        openedByUserId: session.openedByUserId,
        userName: session.userName ?? "Usuario",
        terminalName: session.terminalNameSnapshot ?? null,
        requiresClosure: true,
      })),
    };
  }

  /**
   * Cierre administrativo de un turno ajeno.
   *
   * Requisitos no negociables:
   * - ADMIN de la empresa (tenant del JWT).
   * - Motivo obligatorio y monto declarado: el cierre NO inventa efectivo
   *   contado; la diferencia contra el esperado queda registrada.
   * - Transición atómica OPEN -> CLOSED (una sola gana) y cierre de la caja
   *   diaria sólo si no quedan otros turnos abiertos de ese día.
   * - Auditoría: log estructurado + telemetría + nota con actor y motivo.
   */
  async adminCloseSession(
    user: RequestUser,
    sessionId: string,
    dto: { reason: string; closingAmount: number; note?: string },
  ) {
    const companyId = requireTenant(user);
    this.assertCompanyAdmin(user);
    const requested = this.validUuidOrNull(sessionId);
    if (!requested) {
      throw new NotFoundException("El turno indicado no existe.");
    }
    const session = await this.prisma.cashSession.findFirst({
      where: { id: requested, companyId },
    });
    if (!session) {
      throw new NotFoundException("El turno indicado no existe.");
    }
    if (session.status !== "OPEN" || session.closedAt != null) {
      throw new ConflictException("Este turno ya fue cerrado.");
    }

    const summary = await this.buildSummaryForSession(session.id, companyId);
    const closingAmount = new Prisma.Decimal(dto.closingAmount);
    const expectedAmount = new Prisma.Decimal(summary.expectedCash);
    const difference = closingAmount.minus(expectedAmount);
    const reason = dto.reason.trim();
    const note = `[CIERRE ADMINISTRATIVO] ${reason}${
      dto.note?.trim() ? ` — ${dto.note.trim()}` : ""
    }`;

    const result = await this.prisma.$transaction(async (tx) => {
      if (session.cashboxDailyId) {
        await this.lockCashboxDaily(tx, session.cashboxDailyId);
      }

      const closeResult = await tx.cashSession.updateMany({
        where: {
          id: session.id,
          companyId,
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
          note,
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

      if (session.cashboxDailyId) {
        await this.refreshDailyCashbox(
          tx,
          session.cashboxDailyId,
          companyId,
          user.id,
          session.id,
          closingAmount,
        );
      }

      await this.telemetry?.enqueueBusinessEvent(tx, {
        companyId,
        actorUserId: user.id,
        eventType: "CASH_SESSION_ADMIN_CLOSED",
        entityType: "cash_session",
        entityId: closed.id,
        feature: "CASH",
      });

      return closed;
    });

    this.logger.warn(
      `cash.admin_close.ok company=${companyId} session=${session.id} actor=${user.id} owner=${session.openedByUserId} expected=${expectedAmount.toFixed(2)} closing=${closingAmount.toFixed(2)} difference=${difference.toFixed(2)} reason=${reason.slice(0, 80)}`,
    );
    this.emitCashEvent(companyId, "cash.session.closed", session.id, {
      userId: user.id,
      adminClose: true,
      businessDate: session.businessDate,
    });

    return {
      session: result,
      summary,
      difference: this.toNumber(difference),
    };
  }

  /**
   * Toma el bloqueo de fila de la caja diaria dentro de la transacción actual.
   *
   * Cualquier cierre de turno de la misma caja pasa por aquí, así que los
   * cierres concurrentes se serializan en un orden único (la fila de la caja) y
   * la comprobación "¿quedan turnos abiertos?" + la suma de cierres se calculan
   * siempre sobre datos confirmados. Sin el bloqueo, dos cierres simultáneos
   * podían verse mutuamente como OPEN y ninguno actualizaba el agregado.
   *
   * Si el cliente Prisma no expone `$queryRaw` (mocks de prueba), se degrada
   * sin bloqueo: el resultado sigue siendo correcto en el caso de un solo turno.
   */
  private async lockCashboxDaily(
    tx: Prisma.TransactionClient,
    cashboxDailyId: string,
  ) {
    const raw = (tx as unknown as { $queryRaw?: unknown }).$queryRaw;
    if (typeof raw !== "function") return;
    await tx.$queryRaw`SELECT id FROM "cashbox_daily" WHERE id = ${cashboxDailyId}::uuid FOR UPDATE`;
  }

  /**
   * Recalcula el agregado de la caja diaria a partir de los cierres reales.
   *
   * - El importe SIEMPRE se deriva de `SUM(closingAmount)` de los turnos CLOSED
   *   de esa caja (nunca "el último cierre gana"), de modo que es idempotente:
   *   ejecutarlo dos veces da el mismo resultado.
   * - El estado pasa a CLOSED solo cuando ya no queda ningún turno abierto.
   * - Se ejecuta dentro de la MISMA transacción que el cierre del turno, así que
   *   o se confirman los dos cambios o ninguno: un fallo, reinicio o caída del
   *   proceso no puede dejar el agregado desactualizado de forma permanente.
   * - Nunca toca los cierres históricos: solo lee `cash_sessions` y escribe el
   *   importe/estado de la caja diaria.
   */
  private async refreshDailyCashbox(
    tx: Prisma.TransactionClient,
    cashboxDailyId: string,
    companyId: string,
    userId: string,
    excludeSessionId: string,
    fallbackAmount: Prisma.Decimal,
  ) {
    const dailyTotal = await this.sumDailyClosedAmounts(
      tx,
      cashboxDailyId,
      companyId,
    );

    const otherOpen = await tx.cashSession.findFirst({
      where: {
        cashboxDailyId,
        companyId,
        status: "OPEN",
        closedAt: null,
        id: { not: excludeSessionId },
      },
      select: { id: true },
    });

    const data: Record<string, unknown> = {
      currentAmount: dailyTotal ?? fallbackAmount,
    };
    if (!otherOpen) {
      data.status = "CLOSED";
      data.closedAt = new Date();
      data.closedByUserId = userId;
    }

    await tx.cashboxDaily.update({ where: { id: cashboxDailyId }, data });
  }

  private async closeDailyIfNoOpenSessions(
    tx: Prisma.TransactionClient,
    cashboxDailyId: string,
    companyId: string,
    userId: string,
    excludeSessionId: string,
  ) {
    await this.lockCashboxDaily(tx, cashboxDailyId);
    await this.refreshDailyCashbox(
      tx,
      cashboxDailyId,
      companyId,
      userId,
      excludeSessionId,
      new Prisma.Decimal(0),
    );
  }

  /**
   * Suma de los cierres del día (turnos CLOSED de la misma caja diaria).
   *
   * Devuelve `null` si el cliente Prisma no expone `aggregate` (mocks de prueba
   * o clientes desactualizados); en ese caso el llamador conserva el importe
   * del cierre actual, que es el comportamiento anterior.
   */
  private async sumDailyClosedAmounts(
    tx: Prisma.TransactionClient,
    cashboxDailyId: string,
    companyId: string,
  ): Promise<Prisma.Decimal | null> {
    const model = tx.cashSession as unknown as { aggregate?: unknown };
    if (typeof model.aggregate !== "function") return null;
    const totals = await tx.cashSession.aggregate({
      where: {
        cashboxDailyId,
        companyId,
        status: "CLOSED",
        closedAt: { not: null },
      },
      _sum: { closingAmount: true },
    });
    return totals._sum?.closingAmount ?? null;
  }

  async buildSummaryForSession(sessionId: string, companyId: string) {
    const session = await this.prisma.cashSession.findFirst({
      where: { id: sessionId, companyId },
    });
    if (!session) {
      throw new NotFoundException("No encontramos el turno solicitado.");
    }

    if (this.canUseAggregatedCashSummary()) {
      return this.buildSummaryForSessionAggregated(
        session,
        sessionId,
        companyId,
      );
    }

    return this.buildSummaryForSessionLegacy(session, sessionId, companyId);
  }

  private canUseAggregatedCashSummary() {
    return (
      typeof (this.prisma.sale as { groupBy?: unknown }).groupBy ===
        "function" &&
      typeof (this.prisma.saleCreditPayment as { aggregate?: unknown })
        .aggregate === "function" &&
      typeof (this.prisma.cashMovement as { groupBy?: unknown }).groupBy ===
        "function" &&
      typeof (this.prisma as { $queryRaw?: unknown }).$queryRaw === "function"
    );
  }

  private async buildSummaryForSessionAggregated(
    session: { initialAmount: Prisma.Decimal | number | null },
    sessionId: string,
    companyId: string,
  ) {
    const activeSaleWhere: Prisma.SaleWhereInput = {
      cashSessionId: sessionId,
      companyId,
      isDeleted: false,
      kind: { not: "refund" },
    };
    const creditSaleWhere: Prisma.SaleWhereInput = {
      ...activeSaleWhere,
      paymentMethod: "credit",
    };

    const [
      saleGroups,
      creditLedgerTotals,
      turnCreditPayments,
      movementGroups,
      categorySummary,
      paymentBreakdownViolations,
    ] = await Promise.all([
      this.prisma.sale.groupBy({
        by: ["isDeleted", "kind", "paymentMethod"],
        where: { cashSessionId: sessionId, companyId },
        _count: { id: true },
        _sum: {
          totalSold: true,
          paymentCashAmount: true,
          paymentTransferAmount: true,
          creditBalance: true,
        },
      }),
      this.prisma.saleCreditPayment.aggregate({
        where: {
          companyId,
          sale: { is: creditSaleWhere },
        },
        _sum: {
          cashAmount: true,
          transferAmount: true,
        },
      }),
      this.prisma.saleCreditPayment.aggregate({
        where: { cashSessionId: sessionId, companyId },
        _sum: {
          amount: true,
          cashAmount: true,
          transferAmount: true,
        },
      }),
      this.prisma.cashMovement.groupBy({
        by: ["type", "movementType", "affectsProfit"],
        where: { sessionId, companyId },
        _sum: { amount: true },
      }),
      this.cashSessionCategorySummary(sessionId, companyId),
      this.cashSessionPaymentBreakdownViolations(sessionId, companyId),
    ]);

    let salesCashTotal = 0;
    let salesTransferTotal = 0;
    let totalSales = 0;
    let refundsCash = 0;
    let totalTickets = 0;
    let totalRefunds = 0;
    let creditSalesTotal = 0;
    let creditInitialCash = 0;
    let creditInitialTransfer = 0;
    let creditBalanceTotal = 0;

    for (const group of saleGroups) {
      const cash = this.toNumber(group._sum.paymentCashAmount);
      const transfer = this.toNumber(group._sum.paymentTransferAmount);
      const sold = this.toNumber(group._sum.totalSold);
      const count = group._count.id;
      const isRefund = group.isDeleted || group.kind === "refund";
      if (isRefund) {
        refundsCash += Math.abs(cash);
        totalRefunds += count;
        continue;
      }

      totalTickets += count;
      totalSales += sold;
      salesCashTotal += cash;
      salesTransferTotal += transfer;
      if (group.paymentMethod === "credit") {
        creditSalesTotal += sold;
        creditInitialCash += cash;
        creditInitialTransfer += transfer;
        creditBalanceTotal += this.toNumber(group._sum.creditBalance);
      }
    }

    const creditLedgerCash = this.toNumber(creditLedgerTotals._sum.cashAmount);
    const creditLedgerTransfer = this.toNumber(
      creditLedgerTotals._sum.transferAmount,
    );
    salesCashTotal -= creditLedgerCash;
    salesTransferTotal -= creditLedgerTransfer;
    creditInitialCash -= creditLedgerCash;
    creditInitialTransfer -= creditLedgerTransfer;

    const creditAbonos = this.toNumber(turnCreditPayments._sum.amount);
    const creditPaymentCash = this.toNumber(turnCreditPayments._sum.cashAmount);
    const creditPaymentTransfer = this.toNumber(
      turnCreditPayments._sum.transferAmount,
    );
    const creditPaymentsCashTotal = creditPaymentCash;

    let cashInManual = 0;
    let cashOutManual = 0;
    let totalExpenses = 0;
    let totalWithdrawals = 0;
    for (const group of movementGroups) {
      const amount = this.toNumber(group._sum.amount);
      if (group.type === "IN") cashInManual += amount;
      if (group.type === "OUT") {
        cashOutManual += amount;
        if (group.movementType === "expense" && group.affectsProfit) {
          totalExpenses += amount;
        } else {
          totalWithdrawals += amount;
        }
      }
    }

    const openingAmount = this.toNumber(session.initialAmount);
    if (paymentBreakdownViolations > 0) {
      this.logger.warn(
        `cash.session.payment_breakdown_invariant_violation companyId=${companyId} ` +
          `sessionId=${sessionId} sales=${paymentBreakdownViolations}`,
      );
    }
    const expectedCash =
      openingAmount +
      salesCashTotal +
      creditPaymentsCashTotal -
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
      creditPaymentsCashTotal,
      paymentBreakdownViolations,
      layawayAbonos: 0,
      salesCashTotal,
      salesCardTotal: 0,
      salesTransferTotal,
      salesCreditTotal:
        creditSalesTotal - creditInitialCash - creditInitialTransfer,
      refundsCash,
      expectedCash,
      totalTickets,
      totalRefunds,
      categorySummary,
    };
  }

  private async cashSessionCategorySummary(
    sessionId: string,
    companyId: string,
  ) {
    const rows = await this.prisma.$queryRaw<
      Array<{
        category: string | null;
        totalSold: Prisma.Decimal | number | null;
        totalProfit: Prisma.Decimal | number | null;
        items: bigint | number | string;
      }>
    >(Prisma.sql`
      SELECT
        COALESCE(NULLIF(TRIM(p.categoria), ''), 'Sin categoria') AS "category",
        COALESCE(SUM(si."subtotalSold"), 0) AS "totalSold",
        COALESCE(SUM(si.profit), 0) AS "totalProfit",
        COUNT(*) AS "items"
      FROM "SaleItem" si
      INNER JOIN "Sale" s ON s.id = si."saleId"
      LEFT JOIN "Product" p ON p.id = si."productId"
      WHERE s."cashSessionId" = ${sessionId}::uuid
        AND s.company_id = ${companyId}::uuid
        AND s."isDeleted" = false
        AND s.kind <> 'refund'
      GROUP BY 1
      ORDER BY SUM(si."subtotalSold") DESC
    `);

    return rows.map((row) => ({
      category: row.category?.trim() || "Sin categoria",
      totalSold: this.toNumber(row.totalSold),
      totalProfit: this.toNumber(row.totalProfit),
      items: Number(row.items ?? 0),
    }));
  }

  private async cashSessionPaymentBreakdownViolations(
    sessionId: string,
    companyId: string,
  ) {
    const rows = await this.prisma.$queryRaw<
      Array<{ count: bigint | number | string }>
    >(
      Prisma.sql`
        SELECT COUNT(*) AS "count"
        FROM (
          SELECT
            s.id,
            s."paymentCashAmount",
            s."paymentTransferAmount",
            COALESCE(SUM(p."cashAmount"), 0) AS "ledgerCash",
            COALESCE(SUM(p."transferAmount"), 0) AS "ledgerTransfer"
          FROM "Sale" s
          LEFT JOIN sale_credit_payments p
            ON p."saleId" = s.id
           AND p.company_id = s.company_id
          WHERE s."cashSessionId" = ${sessionId}::uuid
            AND s.company_id = ${companyId}::uuid
            AND s."paymentMethod" = 'credit'
            AND s."isDeleted" = false
            AND s.kind <> 'refund'
          GROUP BY s.id, s."paymentCashAmount", s."paymentTransferAmount"
          HAVING
            COALESCE(SUM(p."cashAmount"), 0) - s."paymentCashAmount" > 0.005
            OR
            COALESCE(SUM(p."transferAmount"), 0) - s."paymentTransferAmount" > 0.005
        ) violations
      `,
    );
    return Number(rows[0]?.count ?? 0);
  }

  private async buildSummaryForSessionLegacy(
    session: { initialAmount: Prisma.Decimal | number | null },
    sessionId: string,
    companyId: string,
  ) {
    // Las ventas del turno se leen primero porque sus ids alimentan UNA query
    // batched del ledger de abonos (nunca una consulta por venta).
    const sales = await this.prisma.sale.findMany({
      where: { cashSessionId: sessionId, companyId },
      select: {
        id: true,
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
    });

    const [movements, creditPayments, creditPaymentLedger] = await Promise.all([
      this.prisma.cashMovement.findMany({ where: { sessionId, companyId } }),
      this.prisma.saleCreditPayment.findMany({
        where: { cashSessionId: sessionId, companyId },
      }),
      // Solo una venta a crédito puede tener filas en `sale_credit_payments`
      // (`addCreditPayment` exige `creditStatus !== 'none'`), así que el ledger
      // batched solo se consulta cuando el turno contiene ventas a crédito.
      creditPaymentTotalsBySaleId(this.prisma, {
        companyId,
        saleIds: sales
          .filter((sale) => sale.paymentMethod === "credit")
          .map((sale) => sale.id),
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
    // Abonos cobrados EN ESTE TURNO (efectivo físico). Se mantiene separado de
    // `salesCashTotal` para no contar dos veces el mismo peso: `salesCashTotal`
    // es solo el efectivo recibido AL CREAR las ventas del turno.
    let creditPaymentsCashTotal = 0;
    // Ventas cuyo ledger de abonos excede el acumulado de la venta (data
    // invariante rota). Se reporta, nunca se corrige con `max(0)`.
    let paymentBreakdownViolations = 0;
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
      if (sale.isDeleted || sale.kind === "refund") {
        // Política vigente de anulación/devolución: el efectivo que debe salir
        // del cajón con la reversión sigue siendo el acumulado del documento
        // (no se deriva el pago inicial). Ver reporte de hardening, FASE 19.
        refundsCash += Math.abs(cash);
        totalRefunds += 1;
        continue;
      }

      const ledger = creditPaymentLedger.get(sale.id);
      const breakdown = deriveSalePaymentBreakdown({
        cumulativeCash: cash,
        cumulativeTransfer: transfer,
        creditPaymentsCash: ledger?.cash,
        creditPaymentsTransfer: ledger?.transfer,
      });
      if (breakdown.invariantViolation) paymentBreakdownViolations += 1;

      const initialCash = this.toNumber(breakdown.initialCash);
      const initialTransfer = this.toNumber(breakdown.initialTransfer);

      totalTickets += 1;
      totalSales += this.toNumber(sale.totalSold);
      salesCashTotal += initialCash;
      salesTransferTotal += initialTransfer;
      if (sale.paymentMethod === "credit") {
        creditSalesTotal += this.toNumber(sale.totalSold);
        creditInitialCash += initialCash;
        creditInitialTransfer += initialTransfer;
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
      // Abonos cobrados en este turno: entran a `expectedCash` por su propio
      // carril. NUNCA se suman a `salesCashTotal` (que ya no contiene abonos).
      creditPaymentsCashTotal += cash;
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
    if (paymentBreakdownViolations > 0) {
      this.logger.warn(
        `cash.session.payment_breakdown_invariant_violation companyId=${companyId} ` +
          `sessionId=${sessionId} sales=${paymentBreakdownViolations}`,
      );
    }
    const expectedCash =
      openingAmount +
      salesCashTotal +
      creditPaymentsCashTotal -
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
      creditPaymentsCashTotal,
      paymentBreakdownViolations,
      layawayAbonos: 0,
      salesCashTotal,
      salesCardTotal: 0,
      salesTransferTotal,
      salesCreditTotal: sales
        .filter((sale) => !sale.isDeleted && sale.paymentMethod === "credit")
        .reduce((sum, sale) => {
          const ledger = creditPaymentLedger.get(sale.id);
          const breakdown = deriveSalePaymentBreakdown({
            cumulativeCash: sale.paymentCashAmount,
            cumulativeTransfer: sale.paymentTransferAmount,
            creditPaymentsCash: ledger?.cash,
            creditPaymentsTransfer: ledger?.transfer,
          });
          return (
            sum +
            this.toNumber(
              new Prisma.Decimal(sale.totalSold)
                .minus(breakdown.initialCash)
                .minus(breakdown.initialTransfer),
            )
          );
        }, 0),
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

  private async rejectAmbiguousLegacyOpenSession(
    userId: string,
    companyId: string,
    session: {
      id: string;
      openedAt: Date;
      businessDate: string | null;
    },
    context: string,
    client: Pick<Prisma.TransactionClient, "cashSession"> = this.prisma,
  ) {
    const businessDate = this.businessDate();
    if (session.businessDate === businessDate) return;

    const newerCurrentOpen = await client.cashSession.findFirst({
      where: {
        companyId,
        status: "OPEN",
        closedAt: null,
        businessDate,
        id: { not: session.id },
        openedAt: { gt: session.openedAt },
      },
      select: { id: true, openedByUserId: true, openedAt: true },
      orderBy: { openedAt: "desc" },
    });
    if (!newerCurrentOpen) return;

    this.logger.warn(
      `cash.session.legacy_open_requires_review company=${companyId} userId=${userId} ` +
        `session=${session.id} sessionBusinessDate=${session.businessDate ?? "null"} ` +
        `currentBusinessDate=${businessDate} newerOpen=${newerCurrentOpen.id} context=${context}`,
    );
    throw new ConflictException({
      code: "CASH_SESSION_REQUIRES_REVIEW",
      errorCode: "CASH_SESSION_REQUIRES_REVIEW",
      message:
        "Este turno abierto necesita revisión antes de operar. Contacta a un administrador.",
    });
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
