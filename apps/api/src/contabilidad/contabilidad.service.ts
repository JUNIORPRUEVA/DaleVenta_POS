import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  CloseType,
  DepositOrderStatus,
  PayableFrequency,
  Prisma,
} from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import PDFDocument from 'pdfkit';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { R2Service } from '../storage/r2.service';
import {
  CloseFinancialSummaryQueryDto,
  CloseStatus,
  CloseTransferEntryDto,
  CreateCloseDto,
  UpdateCloseDto,
} from './close.dto';
import type { CloseExpenseDetailDto } from './close.dto';
import {
  CreateDepositOrderDto,
  DepositOrdersQueryDto,
  DepositOrderStatusDto,
  UpdateDepositOrderDto,
} from './deposit-order.dto';
import {
  CreateFiscalInvoiceDto,
  FiscalInvoicesQueryDto,
  UpdateFiscalInvoiceDto,
} from './fiscal-invoice.dto';
import {
  CreatePayableServiceDto,
  PayablePaymentsQueryDto,
  PayableServicesQueryDto,
  RegisterPayablePaymentDto,
  UpdatePayablePaymentDto,
  UpdatePayableServiceDto,
} from './payable.dto';

type Actor = { id?: string; role?: string };

type GetClosesQuery = {
  date?: string;
  from?: string;
  to?: string;
  type?: string;
};

type CloseAiEvidence = {
  label: string;
  source: 'pos' | 'transfer' | 'expense';
  fileName: string | null;
  mimeType: string | null;
  fileUrl: string | null;
  storageKey: string | null;
  imageUrl: string | null;
  includedInVision: boolean;
  note?: string;
};

@Injectable()
export class ContabilidadService {
  constructor(
    private prisma: PrismaService,
    private readonly r2: R2Service,
    private readonly notifications: NotificationsService,
    private readonly config: ConfigService,
  ) {}

  private toNullableTrimmed(value?: string | null) {
    const cleaned = (value ?? '').trim();
    return cleaned.length > 0 ? cleaned : null;
  }

  private addMonthsKeepingDay(input: Date, months: number) {
    const source = new Date(input);
    const targetYear = source.getFullYear();
    const targetMonth = source.getMonth() + months;
    const safe = new Date(targetYear, targetMonth + 1, 0);
    const safeDay = Math.min(source.getDate(), safe.getDate());

    return new Date(
      targetYear,
      targetMonth,
      safeDay,
      source.getHours(),
      source.getMinutes(),
      source.getSeconds(),
      source.getMilliseconds(),
    );
  }

  private addDays(input: Date, days: number) {
    const next = new Date(input);
    next.setDate(next.getDate() + days);
    return next;
  }

  private nextDueDateFrom(frequency: PayableFrequency, paidAt: Date) {
    switch (frequency) {
      case PayableFrequency.MONTHLY:
        return this.addMonthsKeepingDay(paidAt, 1);
      case PayableFrequency.BIWEEKLY:
        return this.addDays(paidAt, 15);
      case PayableFrequency.ONE_TIME:
      default:
        return paidAt;
    }
  }

  private readonly allowedTransferBanks = new Set([
    'POPULAR',
    'BANRESERVAS',
    'BHD',
    'OTRO',
  ]);

  private readonly allowedDailyCloseTypes = new Set<CloseType>([
    CloseType.TIENDA,
    CloseType.PHYTOEMAGRY,
  ]);

  private readonly allowedDepositBanks = [
    {
      label: 'Banco Popular',
      accounts: [
        {
          label: 'Yunior Lopez de la Rosa · 0820297174',
          accountNumber: '0820297174',
        },
        {
          label: 'FULLTECH SRL · 0841088008',
          accountNumber: '0841088008',
        },
      ],
    },
    {
      label: 'Banreservas',
      accounts: [
        {
          label: 'Yunior Lopez de la Rosa · 9600921403',
          accountNumber: '9600921403',
        },
      ],
    },
    {
      label: 'BHD',
      accounts: [
        {
          label: 'Yunior Lopez de la Rosa · 28726660019',
          accountNumber: '28726660019',
        },
      ],
    },
  ] as const;

  private readonly depositOrderLegacySelect: Prisma.DepositOrderSelect = {
    id: true,
    windowFrom: true,
    windowTo: true,
    bankName: true,
    bankAccount: true,
    collaboratorName: true,
    note: true,
    reserveAmount: true,
    totalAvailableCash: true,
    depositTotal: true,
    closesCountByType: true,
    depositByType: true,
    accountByType: true,
    status: true,
    voucherUrl: true,
    voucherFileName: true,
    voucherMimeType: true,
    createdById: true,
    createdByName: true,
    executedById: true,
    executedByName: true,
    executedAt: true,
    createdAt: true,
    updatedAt: true,
  };

  private readonly depositOrderMinimumSelect: Prisma.DepositOrderSelect = {
    id: true,
    windowFrom: true,
    windowTo: true,
    bankName: true,
    bankAccount: true,
    collaboratorName: true,
    note: true,
    reserveAmount: true,
    totalAvailableCash: true,
    depositTotal: true,
    closesCountByType: true,
    depositByType: true,
    accountByType: true,
    status: true,
    createdById: true,
    executedById: true,
    executedAt: true,
    createdAt: true,
    updatedAt: true,
  };

  private readonly depositOrderSelectFallbacks: Prisma.DepositOrderSelect[] = [
    this.depositOrderLegacySelect,
    this.depositOrderMinimumSelect,
  ];

  private isDepositOrderSchemaCompatibilityError(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021' || error.code === 'P2022';
    }

    if (typeof error !== 'object' || error === null) {
      return false;
    }

    const value = error as { code?: unknown; message?: unknown };
    const code = typeof value.code === 'string' ? value.code : '';
    const message = typeof value.message === 'string' ? value.message.toLowerCase() : '';

    if (code === 'P2021' || code === 'P2022') return true;
    return message.includes('does not exist') || message.includes('unknown column');
  }

  private async findManyDepositOrdersWithFallback(args: {
    where: Record<string, unknown>;
    orderBy: Array<{ createdAt: 'desc' | 'asc' }>;
  }) {
    let lastError: unknown;

    for (const select of this.depositOrderSelectFallbacks) {
      try {
        return await this.prisma.depositOrder.findMany({
          where: args.where,
          orderBy: args.orderBy,
          select,
        });
      } catch (error) {
        lastError = error;
        if (!this.isDepositOrderSchemaCompatibilityError(error)) {
          throw error;
        }
      }
    }

    throw lastError;
  }

  private enrichDepositOrderRow<T extends Record<string, unknown>>(row: T) {
    return {
      ...row,
      correctionOfDepositOrderId: null,
      correctionReason: null,
      deletedAt: null,
      deletedById: null,
      deletedByName: null,
      deletedReason: null,
    };
  }

  private normalizeRoleGuard(actor: Actor) {
    if (!actor.id) {
      throw new ForbiddenException('No autorizado para operar cierres');
    }
  }

  private ensureAdmin(actor: Actor) {
    this.normalizeRoleGuard(actor);
    if ((actor.role ?? '').toUpperCase() !== 'ADMIN') {
      throw new ForbiddenException(
        'Solo administración puede realizar esta acción.',
      );
    }
  }

  private ensureReviewer(actor: Actor) {
    this.normalizeRoleGuard(actor);
    const role = (actor.role ?? '').toUpperCase();
    if (role !== 'ADMIN') {
      throw new ForbiddenException(
        'Solo administración puede aprobar o rechazar cierres.',
      );
    }
  }

  private isReviewer(actor: Actor) {
    const role = (actor.role ?? '').toUpperCase();
    return role === 'ADMIN';
  }

  private canReadAllCloses(actor: Actor) {
    const role = (actor.role ?? '').toUpperCase();
    return role === 'ADMIN' || role === 'ASISTENTE';
  }

  private normalizeDepositKey(value?: string | null) {
    return (value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
  }

  private normalizeDepositAccountNumber(value?: string | null) {
    return (value ?? '').replace(/\D/g, '');
  }

  private findAllowedDepositBank(bankName?: string | null) {
    const normalized = this.normalizeDepositKey(bankName);
    return this.allowedDepositBanks.find(
      (item) => this.normalizeDepositKey(item.label) === normalized,
    );
  }

  private isAllowedDepositAccount(
    bank:
      | (typeof this.allowedDepositBanks)[number]
      | undefined,
    account: string,
  ) {
    if (!bank) return false;
    const normalized = this.normalizeDepositKey(account);
    const accountNumber = this.normalizeDepositAccountNumber(account);
    return bank.accounts.some(
      (item) =>
        this.normalizeDepositKey(item.label) === normalized ||
        item.accountNumber === accountNumber,
    );
  }

  private parseDepositDate(value: string | Date, fieldName: string) {
    const parsed = value instanceof Date ? new Date(value) : new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException(`La fecha ${fieldName} no es válida.`);
    }
    return parsed;
  }

  private normalizeDepositCountMap(value: unknown) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new BadRequestException('Debes indicar el detalle de cierres.');
    }
    const result: Record<string, number> = {};
    for (const [key, raw] of Object.entries(value)) {
      const cleanKey = key.trim();
      if (!cleanKey) continue;
      const parsed = Number(raw ?? 0);
      if (!Number.isFinite(parsed) || parsed < 0) {
        throw new BadRequestException(
          `La cantidad de cierres para ${cleanKey} no es válida.`,
        );
      }
      result[cleanKey] = Math.trunc(parsed);
    }
    return result;
  }

  private normalizeDepositMoneyMap(value: unknown, fieldName: string) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new BadRequestException(`Debes indicar ${fieldName}.`);
    }
    const result: Record<string, number> = {};
    for (const [key, raw] of Object.entries(value)) {
      const cleanKey = key.trim();
      if (!cleanKey) continue;
      const amount = this.roundMoney(this.decimal(raw));
      if (amount <= 0) {
        throw new BadRequestException(
          `El monto para ${cleanKey} en ${fieldName} debe ser mayor a cero.`,
        );
      }
      result[cleanKey] = amount;
    }
    if (Object.keys(result).length === 0) {
      throw new BadRequestException(`Debes indicar ${fieldName}.`);
    }
    return result;
  }

  private normalizeDepositStringMap(value: unknown, fieldName: string) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new BadRequestException(`Debes indicar ${fieldName}.`);
    }
    const result: Record<string, string> = {};
    for (const [key, raw] of Object.entries(value)) {
      const cleanKey = key.trim();
      const cleanValue = this.toNullableTrimmed(String(raw ?? ''));
      if (!cleanKey || !cleanValue) continue;
      result[cleanKey] = cleanValue;
    }
    if (Object.keys(result).length === 0) {
      throw new BadRequestException(`Debes indicar ${fieldName}.`);
    }
    return result;
  }

  private async validateDepositCollaborator(collaboratorName?: string | null) {
    const cleaned = this.toNullableTrimmed(collaboratorName);
    if (!cleaned) return null;

    const collaborator = await this.prisma.user.findFirst({
      where: {
        nombreCompleto: {
          equals: cleaned,
          mode: 'insensitive',
        },
      },
      select: { id: true, nombreCompleto: true },
    });
    if (!collaborator) {
      throw new BadRequestException(
        'El colaborador indicado no existe en el sistema.',
      );
    }
    return collaborator.nombreCompleto.trim();
  }

  private async normalizeDepositPayload(params: {
    windowFrom: string | Date;
    windowTo: string | Date;
    bankName: string;
    bankAccount?: string | null;
    collaboratorName?: string | null;
    note?: string | null;
    reserveAmount: unknown;
    totalAvailableCash: unknown;
    depositTotal: unknown;
    closesCountByType: unknown;
    depositByType: unknown;
    accountByType: unknown;
  }) {
    const windowFrom = this.parseDepositDate(params.windowFrom, 'desde');
    const windowTo = this.parseDepositDate(params.windowTo, 'hasta');
    if (windowFrom.getTime() > windowTo.getTime()) {
      throw new BadRequestException(
        'La fecha inicial del depósito no puede ser mayor que la final.',
      );
    }

    const bankName = this.toNullableTrimmed(params.bankName);
    if (!bankName) {
      throw new BadRequestException('Debes indicar el banco del depósito.');
    }
    const bank = this.findAllowedDepositBank(bankName);
    if (!bank) {
      throw new BadRequestException('El banco seleccionado no es válido.');
    }

    const bankAccount = this.toNullableTrimmed(params.bankAccount);
    if (!bankAccount) {
      throw new BadRequestException('Debes indicar la cuenta del depósito.');
    }
    if (!this.isAllowedDepositAccount(bank, bankAccount)) {
      throw new BadRequestException(
        'La cuenta seleccionada no corresponde al banco indicado.',
      );
    }

    const collaboratorName = await this.validateDepositCollaborator(
      params.collaboratorName,
    );
    const reserveAmount = this.roundMoney(this.decimal(params.reserveAmount));
    const totalAvailableCash = this.roundMoney(
      this.decimal(params.totalAvailableCash),
    );
    const depositTotal = this.roundMoney(this.decimal(params.depositTotal));
    if (depositTotal <= 0) {
      throw new BadRequestException(
        'El monto total del depósito debe ser mayor a cero.',
      );
    }

    const closesCountByType = this.normalizeDepositCountMap(
      params.closesCountByType,
    );
    const depositByType = this.normalizeDepositMoneyMap(
      params.depositByType,
      'los montos por tipo',
    );
    const accountByType = this.normalizeDepositStringMap(
      params.accountByType,
      'las cuentas por tipo',
    );

    const summedDeposit = this.roundMoney(
      Object.values(depositByType).reduce((sum, item) => sum + item, 0),
    );
    if (Math.abs(summedDeposit - depositTotal) > 0.009) {
      throw new BadRequestException(
        'El monto total del depósito no coincide con la suma por tipo.',
      );
    }

    for (const [type, account] of Object.entries(accountByType)) {
      if (!depositByType[type]) {
        throw new BadRequestException(
          `La cuenta ${type} no tiene un monto asociado en el depósito.`,
        );
      }
      if (!this.isAllowedDepositAccount(bank, account)) {
        throw new BadRequestException(
          `La cuenta de ${type} no corresponde al banco indicado.`,
        );
      }
    }

    for (const type of Object.keys(depositByType)) {
      if (!accountByType[type]) {
        throw new BadRequestException(
          `Debes indicar la cuenta asociada al tipo ${type}.`,
        );
      }
    }

    return {
      windowFrom,
      windowTo,
      bankName,
      bankAccount,
      collaboratorName,
      note: this.toNullableTrimmed(params.note),
      reserveAmount,
      totalAvailableCash,
      depositTotal,
      closesCountByType,
      depositByType,
      accountByType,
    };
  }

  private async resolveDepositCorrection(
    dto: {
      correctionOfDepositOrderId?: string | null;
      correctionReason?: string | null;
    },
    actor: Actor,
  ) {
    const correctionOfDepositOrderId = this.toNullableTrimmed(
      dto.correctionOfDepositOrderId,
    );
    if (!correctionOfDepositOrderId) {
      return { correctionOfDepositOrderId: null, correctionReason: null };
    }

    const correctionReason = this.toNullableTrimmed(dto.correctionReason);
    if (!correctionReason) {
      throw new BadRequestException(
        'Debes indicar el motivo de la corrección del depósito.',
      );
    }

    const original = await this.prisma.depositOrder.findUnique({
      where: { id: correctionOfDepositOrderId },
      select: { id: true, createdById: true },
    });
    if (!original) {
      throw new NotFoundException('El depósito original de la corrección no existe.');
    }
    if (!this.isReviewer(actor) && original.createdById !== actor.id) {
      throw new ForbiddenException(
        'Solo puedes crear correcciones sobre depósitos propios.',
      );
    }

    return { correctionOfDepositOrderId, correctionReason };
  }

  private accountingDay(input: Date) {
    const value = new Date(input);
    value.setHours(0, 0, 0, 0);
    return value;
  }

  private parseType(value?: string): CloseType | undefined {
    if (!value) return undefined;
    const normalized = value.trim().toUpperCase();
    if (normalized === 'CAPSULAS') return CloseType.CAPSULAS;
    if (normalized === 'POS') return CloseType.POS;
    if (normalized === 'TIENDA') return CloseType.TIENDA;
    if (normalized === 'PHYTOEMAGRY' || normalized === 'PHYTO')
      return CloseType.PHYTOEMAGRY;
    return undefined;
  }

  private normalizeDayRange(input: Date) {
    const start = new Date(input);
    start.setHours(0, 0, 0, 0);
    const end = new Date(input);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  private parseDate(value?: string | null, fieldName = 'fecha') {
    const raw = (value ?? '').trim();
    if (!raw) return null;

const parsed = /^\d{4}-\d{2}-\d{2}$/.test(raw)
      ? new Date(`${raw}T00:00:00`)
      : new Date(raw);

    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException(`La ${fieldName} no es válida.`);
    }

    return parsed;
  }

  private normalizeTransferBank(value?: string | null) {
    const cleaned = (value ?? '').trim();
    if (cleaned.length == 0) return null;

    const normalized = cleaned.toUpperCase();
    if (this.allowedTransferBanks.has(normalized)) {
      return normalized;
    }

    return cleaned;
  }

  private validateTransferData(transfer: number, transferBank?: string | null) {
    if (transfer <= 0) {
      return;
    }

    const cleaned = (transferBank ?? '').trim();
    if (cleaned.length === 0) {
      throw new BadRequestException(
        'Cuando hay transferencia debes indicar banco y monto',
      );
    }
  }

  private ensureAllowedDailyCloseType(type: CloseType) {
    if (this.allowedDailyCloseTypes.has(type)) return;
    throw new BadRequestException(
      'Solo se permiten cierres diarios de Tecnologia y PhytoEmagry.',
    );
  }

  private decimal(value: unknown) {
    const n =
      typeof value === 'number'
        ? value
        : value instanceof Prisma.Decimal
          ? value.toNumber()
          : Number(value ?? 0);
    if (!Number.isFinite(n) || n < 0) {
      throw new BadRequestException(
        'Los montos del cierre no pueden ser negativos.',
      );
    }
    return Math.round(n * 100) / 100;
  }

  private roundMoney(value: number) {
    if (!Number.isFinite(value)) {
      throw new BadRequestException('Monto invÃ¡lido.');
    }
    return Math.round(value * 100) / 100;
  }

  private normalizeTransfers(transfers?: CloseTransferEntryDto[]) {
    return (transfers ?? []).map((entry, index) => {
      const bankName = this.toNullableTrimmed(entry.bankName);
      if (!bankName) {
        throw new BadRequestException(
          `La transferencia #${index + 1} requiere banco.`,
        );
      }
      const amount = this.decimal(entry.amount);
      if (amount <= 0) {
        throw new BadRequestException(
          `La transferencia #${index + 1} requiere monto mayor a cero.`,
        );
      }
      const vouchers = entry.vouchers ?? [];
      if (vouchers.length === 0) {
        throw new BadRequestException(
          `La transferencia #${index + 1} requiere al menos un voucher.`,
        );
      }
      return {
        bankName,
        amount,
        referenceNumber: this.toNullableTrimmed(entry.referenceNumber),
        note: this.toNullableTrimmed(entry.note),
        vouchers: vouchers.map((voucher, voucherIndex) => {
          const storageKey = this.toNullableTrimmed(voucher.storageKey);
          const fileUrl = this.toNullableTrimmed(voucher.fileUrl);
          const fileName = this.toNullableTrimmed(voucher.fileName);
          const mimeType = this.toNullableTrimmed(voucher.mimeType);
          if (!storageKey || !fileUrl || !fileName || !mimeType) {
            throw new BadRequestException(
              `El voucher #${voucherIndex + 1} de la transferencia #${index + 1} no tiene datos completos.`,
            );
          }
          return { storageKey, fileUrl, fileName, mimeType };
        }),
      };
    });
  }

  private calculateCloseTotals(params: {
    cash: number;
    transfers: Array<{ amount: number }>;
    card: number;
    otherIncome: number;
    expenses: number;
    cashDelivered: number;
  }) {
    const transfer = params.transfers.reduce(
      (sum, item) => sum + item.amount,
      0,
    );
    const totalIncome =
      params.cash + transfer + params.card + params.otherIncome;
    const netTotal = totalIncome - params.expenses;
    const difference = params.cash - params.cashDelivered;
    return {
      transfer: this.decimal(transfer),
      totalIncome: this.decimal(totalIncome),
      netTotal: this.roundMoney(netTotal),
      difference: this.roundMoney(difference),
    };
  }

  private normalizeExpenseDetails(details?: CloseExpenseDetailDto[] | null) {
    if (!details || details.length === 0) return null;
    return details.map((row, index) => {
      const concept = (row.concept ?? '').trim();
      if (!concept) {
        throw new BadRequestException(
          `El gasto #${index + 1} requiere concepto.`,
        );
      }

      const amount = Math.round(Number(row.amount ?? 0) * 100) / 100;
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new BadRequestException(
          `El gasto #${index + 1} requiere monto mayor a cero.`,
        );
      }

      const vouchers = (row.vouchers ?? []).map((voucher, voucherIndex) => {
        const storageKey = this.toNullableTrimmed(voucher.storageKey);
        const fileUrl = this.toNullableTrimmed(voucher.fileUrl);
        const fileName = this.toNullableTrimmed(voucher.fileName);
        const mimeType = this.toNullableTrimmed(voucher.mimeType);
        if (!storageKey || !fileUrl || !fileName || !mimeType) {
          throw new BadRequestException(
            `El comprobante #${voucherIndex + 1} del gasto #${index + 1} no tiene datos completos.`,
          );
        }
        return { storageKey, fileUrl, fileName, mimeType };
      });

      return { concept, amount, vouchers };
    });
  }

  private async findCloseOrThrow(id: string) {
    const close = await this.prisma.close.findUnique({
      where: { id },
      include: {
        transfers: {
          include: { vouchers: true },
          orderBy: { createdAt: 'asc' },
        },
      },
    });
    if (!close) throw new NotFoundException('Cierre no encontrado');
    return close;
  }

  private async resolveCorrectionMetadata(dto: CreateCloseDto, actor: Actor) {
    const correctionOfCloseId = this.toNullableTrimmed(
      dto.correctionOfCloseId,
    );
    if (!correctionOfCloseId) {
      return { correctionOfCloseId: null, correctionReason: null };
    }

    const correctionReason = this.toNullableTrimmed(dto.correctionReason);
    if (!correctionReason) {
      throw new BadRequestException(
        'Debes indicar el motivo de la corrección.',
      );
    }

    const original = await this.prisma.close.findUnique({
      where: { id: correctionOfCloseId },
      select: { id: true, createdById: true },
    });
    if (!original) {
      throw new BadRequestException('El cierre a corregir no existe.');
    }
    if (!this.isReviewer(actor) && original.createdById !== actor.id) {
      throw new ForbiddenException(
        'No puedes corregir cierres creados por otro usuario.',
      );
    }

    return { correctionOfCloseId, correctionReason };
  }

  async createClose(dto: CreateCloseDto, actor: Actor) {
    this.normalizeRoleGuard(actor);
    this.ensureAllowedDailyCloseType(dto.type);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    const transfers = this.normalizeTransfers(dto.transfers);
    const cash = this.decimal(dto.cash);
    const card = this.decimal(dto.card);
    const otherIncome = this.decimal(dto.otherIncome ?? 0);
    const expenses = this.decimal(dto.expenses);
    // Calcular automáticamente: cashDelivered = cash - expenses
    const cashDelivered = this.decimal(cash - expenses);
    const totals = this.calculateCloseTotals({
      cash,
      transfers,
      card,
      otherIncome,
      expenses,
      cashDelivered,
    });
    const date = this.accountingDay(new Date(dto.date));
    const correction = await this.resolveCorrectionMetadata(dto, actor);
    if (!correction.correctionOfCloseId) {
      const existing = await this.prisma.close.findFirst({
        where: { type: dto.type, date, status: { not: CloseStatus.REJECTED } },
        select: { id: true },
      });
      if (existing) {
        throw new BadRequestException(
          'Ya existe un cierre activo para esta unidad de negocio en esa fecha.',
        );
      }
    }

    const close = await this.prisma.close.create({
      data: {
        type: dto.type,
        date,
        status: CloseStatus.PENDING,
        cash,
        transfer: totals.transfer,
        transferBank: transfers.map((item) => item.bankName).join(', ') || null,
        card,
        otherIncome,
        expenses,
        cashDelivered,
        totalIncome: totals.totalIncome,
        netTotal: totals.netTotal,
        difference: totals.difference,
        notes: this.toNullableTrimmed(dto.notes),
        evidenceUrl: this.toNullableTrimmed(dto.evidenceUrl),
        evidenceFileName: this.toNullableTrimmed(dto.evidenceFileName),
        evidenceStorageKey: this.toNullableTrimmed(dto.evidenceStorageKey),
        evidenceMimeType: this.toNullableTrimmed(dto.evidenceMimeType),
        expenseDetails: (this.normalizeExpenseDetails(dto.expenseDetails) ?? Prisma.JsonNull) as Prisma.NullableJsonNullValueInput | Prisma.InputJsonValue,
        correctionOfCloseId: correction.correctionOfCloseId,
        correctionReason: correction.correctionReason,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
        transfers: {
          create: transfers.map((entry) => ({
            bankName: entry.bankName,
            amount: entry.amount,
            referenceNumber: entry.referenceNumber,
            note: entry.note,
            vouchers: { create: entry.vouchers },
          })),
        },
      },
      include: { transfers: { include: { vouchers: true } } },
    });

    return this.afterCloseSubmitted(close.id);
  }

  async getCloses(query: GetClosesQuery, actor?: Actor) {
    const where: Record<string, unknown> = {};
    if (!this.canReadAllCloses(actor ?? {})) {
      this.normalizeRoleGuard(actor ?? {});
      where.createdById = actor!.id;
    }

    if (query.date) {
      const parsedDate = this.parseDate(query.date, 'fecha');
      if (!parsedDate) {
        throw new BadRequestException('La fecha no es válida.');
      }
      const { start, end } = this.normalizeDayRange(parsedDate);
      where.date = { gte: start, lte: end };
    } else if (query.from || query.to) {
      const from = this.parseDate(query.from, 'from');
      const to = this.parseDate(query.to, 'to');
      if (from || to) {
        const fromRange = from ? this.normalizeDayRange(from) : null;
        const toRange = to ? this.normalizeDayRange(to) : null;
        where.date = {
          ...(fromRange != null ? { gte: fromRange.start } : {}),
          ...(toRange != null ? { lte: toRange.end } : {}),
        };
      }
    }

    const type = this.parseType(query.type);
    if (type) {
      where.type = type;
    }

    return this.prisma.close.findMany({
      where,
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
      include: {
        transfers: {
          include: { vouchers: true },
          orderBy: { createdAt: 'asc' },
        },
      },
    });
  }

  async getCloseFinancialSummary(
    query: CloseFinancialSummaryQueryDto,
    actor: Actor,
  ) {
    this.ensureAdmin(actor);

    const parseDate = (value?: string | null) => {
      return this.parseDate(value, 'rango de fechas');
    };
    const toNumber = (value: unknown) => {
      if (value instanceof Prisma.Decimal) return value.toNumber();
      if (typeof value === 'number') return value;
      if (typeof value === 'string') {
        const n = Number(value);
        return Number.isFinite(n) ? n : 0;
      }
      return 0;
    };
    const toMoney = (value: number) => this.roundMoney(value);
    const fromRaw = parseDate(query.fromDate);
    const toRaw = parseDate(query.toDate);
    const now = new Date();
    const fromDate = this.accountingDay(fromRaw ?? now);
    const toDate = this.accountingDay(toRaw ?? fromRaw ?? now);
    if (toDate.getTime() < fromDate.getTime()) {
      throw new BadRequestException(
        'La fecha final no puede ser menor que la fecha inicial.',
      );
    }

    const { start } = this.normalizeDayRange(fromDate);
    const { end } = this.normalizeDayRange(toDate);
    const businessType = query.businessType ?? null;

    const where: Prisma.CloseWhereInput = {
      date: { gte: start, lte: end },
      ...(businessType != null ? { type: businessType } : {}),
    };

    const closes = await this.prisma.close.findMany({
      where,
      include: {
        transfers: {
          select: {
            bankName: true,
            amount: true,
          },
        },
      },
    });

    const bankTotals = new Map<string, number>([
      ['Banco Popular', 0],
      ['Banco BHD', 0],
      ['Banreservas', 0],
      ['Otros bancos', 0],
      ['Sin banco especificado', 0],
    ]);
    const classifyBank = (bankName?: string | null) => {
      const normalized = (bankName ?? '').trim().toUpperCase();
      if (!normalized) return 'Sin banco especificado';
      if (normalized.includes('POPULAR')) return 'Banco Popular';
      if (normalized.includes('BHD')) return 'Banco BHD';
      if (normalized.includes('BANRESERVAS') || normalized.includes('RESERVAS')) {
        return 'Banreservas';
      }
      return 'Otros bancos';
    };

    let cashDeclared = 0;
    let cashDelivered = 0;
    let transfers = 0;
    let cardPayments = 0;
    let otherIncome = 0;
    let expenses = 0;
    let netTotal = 0;
    let difference = 0;

    for (const close of closes) {
      cashDeclared += toNumber(close.cash);
      cashDelivered += toNumber(close.cashDelivered);
      transfers += toNumber(close.transfer);
      cardPayments += toNumber(close.card);
      otherIncome += toNumber(close.otherIncome);
      expenses += toNumber(close.expenses);
      netTotal += toNumber(close.netTotal);
      difference += toNumber(close.difference);

      for (const transfer of close.transfers) {
        const key = classifyBank(transfer.bankName);
        bankTotals.set(key, (bankTotals.get(key) ?? 0) + toNumber(transfer.amount));
      }
    }

    const deposits = await this.prisma.depositOrder.findMany({
      where: {
        status: DepositOrderStatus.EXECUTED,
        windowFrom: { lte: end },
        windowTo: { gte: start },
      },
      orderBy: [{ executedAt: 'desc' }, { createdAt: 'desc' }],
    });

    const depositFromOrder = (order: {
      depositTotal: Prisma.Decimal;
      depositByType: Prisma.JsonValue;
    }) => {
      if (businessType == null) {
        return toNumber(order.depositTotal);
      }

      const payload =
        order.depositByType && typeof order.depositByType === 'object'
          ? (order.depositByType as Record<string, unknown>)
          : null;
      if (!payload) return 0;
      return toNumber(payload[businessType]);
    };

    let deposited = 0;
    let lastDepositDate: string | null = null;
    let destinationBank: string | null = null;
    for (const order of deposits) {
      const amount = depositFromOrder(order);
      if (amount <= 0) continue;
      deposited += amount;
      if (lastDepositDate == null) {
        lastDepositDate = (order.executedAt ?? order.createdAt).toISOString();
        destinationBank = (order.bankName ?? '').trim() || null;
      }
    }

    const cashBase = cashDelivered > 0 ? cashDelivered : cashDeclared;
    const depositedToCash = Math.min(deposited, cashBase);
    const remainingDeposit = Math.max(deposited - depositedToCash, 0);
    const depositedToTransfers = Math.min(remainingDeposit, transfers);

    const availableCash = Math.max(cashBase - depositedToCash, 0);
    const availableTransfers = Math.max(transfers - depositedToTransfers, 0);
    const totalAvailable = availableCash + availableTransfers;

    const status =
      deposited <= 0
        ? 'pending'
        : totalAvailable <= 0.009
          ? 'deposited'
          : 'partial';

    const orderedBanks = [
      'Banco Popular',
      'Banco BHD',
      'Banreservas',
      'Otros bancos',
      'Sin banco especificado',
    ];
    const transfersByBank = orderedBanks
      .map((bank) => ({ bank, amount: toMoney(bankTotals.get(bank) ?? 0) }))
      .filter(
        (item) => item.amount > 0 || item.bank === 'Sin banco especificado',
      );

    return {
      range: {
        fromDate: start.toISOString().slice(0, 10),
        toDate: end.toISOString().slice(0, 10),
        businessType,
        companyId: this.toNullableTrimmed(query.companyId),
      },
      count: closes.length,
      totals: {
        cashDeclared: toMoney(cashDeclared),
        cashDelivered: toMoney(cashDelivered),
        cashAvailable: toMoney(availableCash),
        transfers: toMoney(transfers),
        cardPayments: toMoney(cardPayments),
        otherIncome: toMoney(otherIncome),
        expenses: toMoney(expenses),
        netTotal: toMoney(netTotal),
        deposited: toMoney(deposited),
        pendingDeposit: toMoney(totalAvailable),
        difference: toMoney(difference),
      },
      transfersByBank,
      availableForDeposit: {
        cash: toMoney(availableCash),
        transfers: toMoney(availableTransfers),
        total: toMoney(totalAvailable),
      },
      depositStatus: {
        status,
        lastDepositDate,
        destinationBank,
      },
    };
  }

  async getCloseById(id: string, actor?: Actor) {
    const close = await this.findCloseOrThrow(id);
    if (!this.canReadAllCloses(actor ?? {})) {
      this.normalizeRoleGuard(actor ?? {});
    }
    if (
      !this.canReadAllCloses(actor ?? {}) &&
      close.createdById !== actor!.id
    ) {
      throw new ForbiddenException('No puedes ver cierres de otro usuario.');
    }
    return close;
  }

  async updateClose(id: string, dto: UpdateCloseDto, actor: Actor) {
    this.normalizeRoleGuard(actor);
    this.ensureAdmin(actor);

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');
    if (!this.isReviewer(actor) && close.createdById !== actor.id) {
      throw new ForbiddenException('No puedes editar cierres de otro usuario.');
    }
    if (
      close.status === CloseStatus.APPROVED ||
      close.status === CloseStatus.REJECTED
    ) {
      throw new BadRequestException(
        'Este cierre ya fue revisado y no se puede editar.',
      );
    }

    const transfers =
      dto.transfers === undefined
        ? await this.prisma.closeTransfer
            .findMany({ where: { closeId: id }, select: { amount: true } })
            .then((items) =>
              items.map((item) => ({ amount: Number(item.amount) })),
            )
        : this.normalizeTransfers(dto.transfers);
    const cash = this.decimal(dto.cash ?? close.cash);
    const card = this.decimal(dto.card ?? close.card);
    const otherIncome = this.decimal(dto.otherIncome ?? close.otherIncome);
    const expenses = this.decimal(dto.expenses ?? close.expenses);
    // Calcular automáticamente: cashDelivered = cash - expenses
    const cashDelivered = this.decimal(cash - expenses);
    const totals = this.calculateCloseTotals({
      cash,
      transfers,
      card,
      otherIncome,
      expenses,
      cashDelivered,
    });

    return this.prisma.close.update({
      where: { id },
      data: {
        cash,
        card,
        otherIncome,
        expenses,
        cashDelivered,
        transfer: totals.transfer,
        totalIncome: totals.totalIncome,
        netTotal: totals.netTotal,
        difference: totals.difference,
        notes:
          dto.notes === undefined
            ? undefined
            : this.toNullableTrimmed(dto.notes),
        evidenceUrl:
          dto.evidenceUrl === undefined
            ? undefined
            : this.toNullableTrimmed(dto.evidenceUrl),
        evidenceFileName:
          dto.evidenceFileName === undefined
            ? undefined
            : this.toNullableTrimmed(dto.evidenceFileName),
        evidenceStorageKey:
          dto.evidenceStorageKey === undefined
            ? undefined
            : this.toNullableTrimmed(dto.evidenceStorageKey),
        evidenceMimeType:
          dto.evidenceMimeType === undefined
            ? undefined
            : this.toNullableTrimmed(dto.evidenceMimeType),
        expenseDetails:
          dto.expenseDetails === undefined
            ? undefined
            : ((this.normalizeExpenseDetails(dto.expenseDetails) ?? Prisma.JsonNull) as Prisma.NullableJsonNullValueInput | Prisma.InputJsonValue),
        transferBank:
          dto.transfers === undefined
            ? undefined
            : this.normalizeTransfers(dto.transfers)
                .map((item) => item.bankName)
                .join(', ') || null,
        ...(dto.transfers === undefined
          ? {}
          : {
              transfers: {
                deleteMany: {},
                create: this.normalizeTransfers(dto.transfers).map((entry) => ({
                  bankName: entry.bankName,
                  amount: entry.amount,
                  referenceNumber: entry.referenceNumber,
                  note: entry.note,
                  vouchers: { create: entry.vouchers },
                })),
              },
            }),
      },
      include: { transfers: { include: { vouchers: true } } },
    });
  }

  private async validateAdminPassword(actor: Actor, adminPassword: string) {
    this.ensureAdmin(actor);
    const cleaned = (adminPassword ?? '').trim();
    if (cleaned.length === 0) {
      throw new BadRequestException('Debes confirmar la contrasena de administrador.');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { passwordHash: true },
    });
    if (!user) {
      throw new ForbiddenException('No autorizado para eliminar cierres');
    }

    const validPassword = await bcrypt.compare(cleaned, user.passwordHash);
    if (!validPassword) {
      throw new ForbiddenException('Contrasena de administrador incorrecta');
    }
  }

  private async cleanupCloseStorage(closeId: string) {
    const close = await this.prisma.close.findUnique({
      where: { id: closeId },
      include: {
        transfers: {
          include: { vouchers: true },
        },
      },
    });
    if (!close) return;

    const storageKeys = new Set<string>();
    if (close.pdfStorageKey) storageKeys.add(close.pdfStorageKey);
    if (close.evidenceStorageKey) storageKeys.add(close.evidenceStorageKey);
    for (const transfer of close.transfers) {
      for (const voucher of transfer.vouchers) {
        if (voucher.storageKey) storageKeys.add(voucher.storageKey);
      }
    }
    const expenseDetails = Array.isArray(close.expenseDetails)
      ? close.expenseDetails
      : [];
    for (const row of expenseDetails) {
      if (!row || typeof row !== 'object') continue;
      const vouchers = Array.isArray((row as { vouchers?: unknown[] }).vouchers)
        ? ((row as { vouchers: Array<{ storageKey?: unknown }> }).vouchers ?? [])
        : [];
      for (const voucher of vouchers) {
        const storageKey =
          typeof voucher.storageKey === 'string'
            ? voucher.storageKey.trim()
            : '';
        if (storageKey) storageKeys.add(storageKey);
      }
    }

    for (const storageKey of storageKeys) {
      try {
        await this.r2.deleteObject(storageKey);
      } catch {
        // Non-fatal cleanup step.
      }
    }
  }

  async deleteClose(id: string, adminPassword: string, actor: Actor) {
    this.normalizeRoleGuard(actor);
    await this.validateAdminPassword(actor, adminPassword);

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');

    await this.cleanupCloseStorage(id);
    await this.prisma.close.delete({ where: { id } });

    return { deletedCount: 1, deletedIds: [id] };
  }

  async deleteClosesBulk(closeIds: string[], adminPassword: string, actor: Actor) {
    this.normalizeRoleGuard(actor);
    await this.validateAdminPassword(actor, adminPassword);

    const uniqueIds = Array.from(
      new Set((closeIds ?? []).map((item) => (item ?? '').trim()).filter((item) => item.length > 0)),
    );
    if (uniqueIds.length === 0) {
      throw new BadRequestException('Debes enviar al menos un cierre para eliminar.');
    }

    const existing = await this.prisma.close.findMany({
      where: { id: { in: uniqueIds } },
      select: { id: true },
    });
    const foundIds = existing.map((row) => row.id);
    const missingIds = uniqueIds.filter((idItem) => !foundIds.includes(idItem));
    if (missingIds.length > 0) {
      throw new NotFoundException('Uno o varios cierres ya no existen. Actualiza la lista e intenta de nuevo.');
    }

    for (const closeId of foundIds) {
      await this.cleanupCloseStorage(closeId);
    }
    await this.prisma.close.deleteMany({ where: { id: { in: foundIds } } });

    return { deletedCount: foundIds.length, deletedIds: foundIds };
  }

  async toggleCloseCashDeposit(id: string, cashDeposited: boolean, actor: Actor) {
    this.ensureAdmin(actor);

    const close = await this.prisma.close.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!close) throw new NotFoundException('Cierre no encontrado');

    const user = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.close.update({
      where: { id },
      data: {
        cashDeposited,
        cashDepositedAt: cashDeposited ? new Date() : null,
        cashDepositedById: cashDeposited ? actor.id! : null,
        cashDepositedByName: cashDeposited
          ? user?.nombreCompleto ?? null
          : null,
      },
      include: { transfers: { include: { vouchers: true } } },
    });
  }

  async reviewClose(id: string, status: CloseStatus, actor: Actor) {
    this.ensureReviewer(actor);
    if (status !== CloseStatus.APPROVED && status !== CloseStatus.REJECTED) {
      throw new BadRequestException('Estado de revisiÃ³n invÃ¡lido');
    }

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');
    if (close.status !== CloseStatus.PENDING) {
      throw new BadRequestException(
        'Solo los cierres pendientes se pueden revisar.',
      );
    }

    const reviewer = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.close.update({
      where: { id },
      data: {
        status,
        reviewedById: actor.id!,
        reviewedByName: reviewer?.nombreCompleto ?? null,
        reviewedAt: new Date(),
      },
    });
  }

  async reviewCloseWithNote(
    id: string,
    status: CloseStatus,
    actor: Actor,
    reviewNote?: string | null,
  ) {
    if (status === CloseStatus.REJECTED && !this.toNullableTrimmed(reviewNote)) {
      throw new BadRequestException('El motivo de rechazo es obligatorio.');
    }
    const reviewed = await this.reviewClose(id, status, actor);
    return this.prisma.close.update({
      where: { id: reviewed.id },
      data: { reviewNote: this.toNullableTrimmed(reviewNote) },
      include: { transfers: { include: { vouchers: true } } },
    });
  }

  private async afterCloseSubmitted(closeId: string) {
    const close = await this.findCloseOrThrow(closeId);
    // PDF generation, R2 upload and notifications are best-effort.
    // The close record is always returned regardless of errors here.
    try {
      const pdf = await this.generateClosePdf(close);
      const yyyy = close.date.getUTCFullYear();
      const mm = String(close.date.getUTCMonth() + 1).padStart(2, '0');
      const objectKey = `contabilidad/daily-closes/${yyyy}/${mm}/${close.id}/${pdf.fileName}`;
      await this.r2.putObject({
        objectKey,
        body: pdf.bytes,
        contentType: 'application/pdf',
      });
      const builtPdfUrl = this.r2.buildPublicUrl(objectKey);
      const pdfUrl = /^https?:\/\//i.test(builtPdfUrl)
        ? builtPdfUrl
        : `/public/contabilidad/object?key=${encodeURIComponent(objectKey)}`;

      await this.prisma.close.update({
        where: { id: close.id },
        data: {
          pdfStorageKey: objectKey,
          pdfUrl,
          pdfFileName: pdf.fileName,
          notificationStatus: 'pending',
          notificationError: null,
        },
      });

      await this.enqueueCloseNotifications(
        close.id,
        pdf.bytes,
        pdf.fileName,
        pdfUrl,
      );
    } catch (pdfError) {
      const msg = pdfError instanceof Error ? pdfError.message : String(pdfError);
      console.error('[afterCloseSubmitted] PDF/notification error (non-fatal):', msg);
      try {
        await this.prisma.close.update({
          where: { id: close.id },
          data: { notificationStatus: 'failed', notificationError: msg },
        });
      } catch {
        // ignore secondary error
      }
    }
    return this.findCloseOrThrow(close.id);
  }

  private money(value: unknown) {
    const n =
      value instanceof Prisma.Decimal ? value.toNumber() : Number(value ?? 0);
    return new Intl.NumberFormat('es-DO', {
      style: 'currency',
      currency: 'DOP',
      minimumFractionDigits: 2,
    }).format(Number.isFinite(n) ? n : 0);
  }

  private dateLabel(value: Date) {
    return new Intl.DateTimeFormat('es-DO', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(value);
  }

  private async tryFetchImageBuffer(storageKey: string): Promise<Buffer | null> {
    try {
      const result = await this.r2.getObject(storageKey);
      return result.body;
    } catch {
      return null;
    }
  }

  private isSupportedAiImage(
    mimeType?: string | null,
    fileName?: string | null,
    fileUrl?: string | null,
  ) {
    const mime = (mimeType ?? '').toLowerCase().trim();
    const name = (fileName ?? '').toLowerCase().trim();
    const url = (fileUrl ?? '').toLowerCase().trim();
    return (
      /^image\/(jpeg|jpg|png|webp)$/i.test(mime) ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png') ||
      name.endsWith('.webp') ||
      url.includes('.jpg') ||
      url.includes('.jpeg') ||
      url.includes('.png') ||
      url.includes('.webp')
    );
  }

  private inferAiImageMime(
    mimeType?: string | null,
    fileName?: string | null,
    fileUrl?: string | null,
  ) {
    const mime = (mimeType ?? '').toLowerCase().trim();
    if (/^image\/(jpeg|jpg|png|webp)$/i.test(mime)) {
      return mime === 'image/jpg' ? 'image/jpeg' : mime;
    }
    const value = `${fileName ?? ''} ${fileUrl ?? ''}`.toLowerCase();
    if (value.includes('.png')) return 'image/png';
    if (value.includes('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  private async buildCloseAiEvidence(
    close: Awaited<ReturnType<ContabilidadService['findCloseOrThrow']>>,
  ): Promise<CloseAiEvidence[]> {
    const rawItems: Array<Omit<CloseAiEvidence, 'imageUrl' | 'includedInVision'>> = [];

    if (close.evidenceUrl || close.evidenceStorageKey || close.evidenceFileName) {
      rawItems.push({
        label: 'Boucher POS del cierre',
        source: 'pos',
        fileName: close.evidenceFileName ?? null,
        mimeType: close.evidenceMimeType ?? null,
        fileUrl: close.evidenceUrl ?? null,
        storageKey: close.evidenceStorageKey ?? null,
      });
    }

    for (const [transferIndex, transfer] of close.transfers.entries()) {
      for (const [voucherIndex, voucher] of transfer.vouchers.entries()) {
        rawItems.push({
          label: `Transferencia ${transferIndex + 1} (${transfer.bankName}) - voucher ${voucherIndex + 1}`,
          source: 'transfer',
          fileName: voucher.fileName ?? null,
          mimeType: voucher.mimeType ?? null,
          fileUrl: voucher.fileUrl ?? null,
          storageKey: voucher.storageKey ?? null,
        });
      }
    }

    const expenseDetails = Array.isArray(close.expenseDetails)
      ? close.expenseDetails
      : [];
    for (const [expenseIndex, row] of expenseDetails.entries()) {
      if (!row || typeof row !== 'object') continue;
      const concept =
        typeof (row as { concept?: unknown }).concept === 'string'
          ? (row as { concept: string }).concept.trim()
          : `Gasto ${expenseIndex + 1}`;
      const vouchers = Array.isArray((row as { vouchers?: unknown[] }).vouchers)
        ? ((row as { vouchers: unknown[] }).vouchers ?? [])
        : [];
      for (const [voucherIndex, voucherRaw] of vouchers.entries()) {
        if (!voucherRaw || typeof voucherRaw !== 'object') continue;
        const voucher = voucherRaw as {
          fileName?: unknown;
          mimeType?: unknown;
          fileUrl?: unknown;
          storageKey?: unknown;
        };
        rawItems.push({
          label: `${concept || `Gasto ${expenseIndex + 1}`} - comprobante ${voucherIndex + 1}`,
          source: 'expense',
          fileName:
            typeof voucher.fileName === 'string' ? voucher.fileName.trim() : null,
          mimeType:
            typeof voucher.mimeType === 'string' ? voucher.mimeType.trim() : null,
          fileUrl:
            typeof voucher.fileUrl === 'string' ? voucher.fileUrl.trim() : null,
          storageKey:
            typeof voucher.storageKey === 'string'
              ? voucher.storageKey.trim()
              : null,
        });
      }
    }

    const evidence: CloseAiEvidence[] = [];
    for (const item of rawItems) {
      const supportedImage = this.isSupportedAiImage(
        item.mimeType,
        item.fileName,
        item.fileUrl,
      );
      let imageUrl: string | null = null;
      let note: string | undefined;

      if (supportedImage && item.storageKey) {
        const buffer = await this.tryFetchImageBuffer(item.storageKey);
        if (buffer) {
          const mime = this.inferAiImageMime(
            item.mimeType,
            item.fileName,
            item.fileUrl,
          );
          imageUrl = `data:${mime};base64,${buffer.toString('base64')}`;
        } else {
          note = 'No se pudo leer la imagen desde almacenamiento.';
        }
      }

      if (!imageUrl && supportedImage && item.fileUrl && /^https?:\/\//i.test(item.fileUrl)) {
        imageUrl = item.fileUrl;
      }

      evidence.push({
        ...item,
        imageUrl,
        includedInVision: imageUrl != null,
        ...(note ? { note } : {}),
      });
    }

    return evidence;
  }

  private async generateClosePdf(
    close: Awaited<ReturnType<ContabilidadService['findCloseOrThrow']>>,
  ) {
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { companyName: true, rnc: true, phone: true, address: true },
    });
    const companyName = appConfig?.companyName?.trim() || 'FULLTECH';
    const doc = new PDFDocument({ margin: 42, size: 'A4' });
    const chunks: Buffer[] = [];
    const bytesPromise = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const line = (label: string, value: string, x = 42, width = 500) => {
      doc
        .font('Helvetica-Bold')
        .text(`${label}: `, x, doc.y, { continued: true });
      doc.font('Helvetica').text(value, { width });
    };
    const section = (title: string) => {
      doc.moveDown(0.8);
      doc.fontSize(13).font('Helvetica-Bold').fillColor('#0f172a').text(title);
      doc
        .moveTo(42, doc.y + 3)
        .lineTo(553, doc.y + 3)
        .strokeColor('#d1d5db')
        .stroke();
      doc.moveDown(0.6);
    };
    const embedImage = async (
      storageKey: string,
      mimeType: string,
      label?: string,
      fileName?: string,
    ) => {
      const normalizedMime = (mimeType ?? '').toLowerCase();
      const normalizedName = (fileName ?? '').toLowerCase();
      const supportedByMime = /^image\/(jpeg|jpg|png|webp)$/i.test(normalizedMime);
      const supportedByName =
        normalizedName.endsWith('.jpg') ||
        normalizedName.endsWith('.jpeg') ||
        normalizedName.endsWith('.png') ||
        normalizedName.endsWith('.webp');
      if (!supportedByMime && !supportedByName) return;
      const buf = await this.tryFetchImageBuffer(storageKey);
      if (!buf) return;
      if (label) doc.font('Helvetica-Bold').text(label);
      try {
        doc.image(buf, { fit: [460, 280], align: 'center' });
        doc.moveDown(0.5);
      } catch {
        doc
          .font('Helvetica')
          .fillColor('#92400e')
          .text(
            `No se pudo incrustar la imagen ${fileName ?? ''}. Verifica formato/archivo.`,
          );
        doc.fillColor('#0f172a');
      }
    };

    doc.rect(0, 0, 595, 92).fill('#0f5b6b');
    doc
      .fillColor('#ffffff')
      .fontSize(20)
      .font('Helvetica-Bold')
      .text(companyName, 42, 28);
    doc.fontSize(11).font('Helvetica').text('Cierre Diario', 42, 55);
    doc.fillColor('#0f172a');
    doc.y = 116;

    section('Datos generales');
    line(
      'Unidad',
      close.type === CloseType.PHYTOEMAGRY ? 'PhytoEmagry' : 'Tienda',
    );
    line('Fecha cierre', new Intl.DateTimeFormat('es-DO').format(close.date));
    line('Creado por', close.createdByName ?? close.createdById ?? 'N/D');
    line('Creado en', this.dateLabel(close.createdAt));
    line('Estado', close.status);

    section('Totales');
    const totalRows = [
      ['Efectivo', this.money(close.cash)],
      ['Transferencias', this.money(close.transfer)],
      ['Tarjeta', this.money(close.card)],
      ['Otros ingresos', this.money(close.otherIncome)],
      ['Gastos del d�a', this.money(close.expenses)],
      ['Total ingresos', this.money(close.totalIncome)],
      ['Total neto', this.money(close.netTotal)],
      ['Efectivo entregado', this.money(close.cashDelivered)],
      ['Diferencia', this.money(close.difference)],
    ];
    for (const [label, value] of totalRows) line(label, value);

    // Expense details breakdown
    const expenseDetails =
      (close.expenseDetails as
        | Array<{
            concept: string;
            amount: number;
            vouchers?: Array<{
              storageKey: string;
              fileUrl: string;
              fileName: string;
              mimeType: string;
            }>;
          }>
        | null) ?? null;
    if (expenseDetails && expenseDetails.length > 0) {
      section('Detalle de gastos');
      const colX = [42, 370];
      doc.font('Helvetica-Bold');
      doc.text('Concepto', colX[0], doc.y, { continued: true });
      doc.text('  ');
      doc.font('Helvetica-Bold').text('Monto', colX[1], doc.y - doc.currentLineHeight());
      doc.moveDown(0.3);
      doc
        .moveTo(42, doc.y)
        .lineTo(553, doc.y)
        .strokeColor('#d1d5db')
        .stroke();
      doc.moveDown(0.3);
      for (const row of expenseDetails) {
        const rowY = doc.y;
        doc.font('Helvetica').text(row.concept, colX[0], rowY, { width: 310 });
        doc.font('Helvetica').text(this.money(row.amount), colX[1], rowY, { width: 160 });
        doc.moveDown(0.15);

        if (Array.isArray(row.vouchers) && row.vouchers.length > 0) {
          doc.moveDown(0.1);
          for (const [voucherIndex, voucher] of row.vouchers.entries()) {
            doc
              .font('Helvetica')
              .fillColor('#0f5b6b')
              .text(
                `Comprobante ${voucherIndex + 1}: ${voucher.fileName}`,
                colX[0],
                doc.y,
                { width: 470 },
              );
            doc.fillColor('#0f172a');
            await embedImage(
              voucher.storageKey,
              voucher.mimeType,
              undefined,
              voucher.fileName,
            );
          }
        }
      }
      doc.moveDown(0.3);
      doc
        .moveTo(42, doc.y)
        .lineTo(553, doc.y)
        .strokeColor('#d1d5db')
        .stroke();
      doc.moveDown(0.3);
      const totalY = doc.y;
      doc.font('Helvetica-Bold').text('Total gastos', colX[0], totalY, { width: 310 });
      doc.font('Helvetica-Bold').text(this.money(close.expenses), colX[1], totalY, { width: 160 });
      doc.moveDown(0.5);
    }

    section('Transferencias');
    if (close.transfers.length === 0) {
      doc.font('Helvetica').text('Sin transferencias declaradas.');
    } else {
      for (const [index, transfer] of close.transfers.entries()) {
        doc
          .font('Helvetica-Bold')
          .text(
            `${index + 1}. ${transfer.bankName} - ${this.money(transfer.amount)}`,
          );
        if (transfer.referenceNumber)
          doc.font('Helvetica').text(`Referencia: ${transfer.referenceNumber}`);
        if (transfer.note) doc.font('Helvetica').text(`Nota: ${transfer.note}`);
        for (const [vi, voucher] of transfer.vouchers.entries()) {
          doc
            .font('Helvetica')
            .fillColor('#0f5b6b')
            .text(`Voucher ${vi + 1}: ${voucher.fileName}`);
          doc.fillColor('#0f172a');
          await embedImage(
            voucher.storageKey,
            voucher.mimeType,
            undefined,
            voucher.fileName,
          );
        }
        doc.moveDown(0.4);
      }
    }

    // POS closing voucher (boucher del punto de ventas)
    if (close.evidenceUrl && close.evidenceFileName) {
      section('Boucher del cierre POS');
      doc.font('Helvetica').text(`Archivo: ${close.evidenceFileName}`);
      if (close.evidenceStorageKey && close.evidenceMimeType) {
        await embedImage(
          close.evidenceStorageKey,
          close.evidenceMimeType,
          undefined,
          close.evidenceFileName ?? undefined,
        );
      } else {
        doc.font('Helvetica').fillColor('#0f5b6b').text(close.evidenceUrl);
        doc.fillColor('#0f172a');
      }
    }

    section('Auditoria');
    line('Revisado por', close.reviewedByName ?? close.reviewedById ?? 'N/D');
    line(
      'Revisado en',
      close.reviewedAt ? this.dateLabel(close.reviewedAt) : 'N/D',
    );
    line('Nota revision', close.reviewNote ?? 'N/D');
    if (close.aiReportSummary) {
      line('Riesgo IA', close.aiRiskLevel ?? 'N/D');
      line('Resumen IA', close.aiReportSummary);
    }
    if (close.notes) {
      section('Notas');
      doc.font('Helvetica').text(close.notes, { width: 500 });
    }

    doc.end();
    const bytes = await bytesPromise;
    return {
      bytes,
      fileName: `cierre_diario_${close.type}_${close.date.toISOString().slice(0, 10)}_${close.id.slice(0, 8)}.pdf`,
    };
  }
  private buildCloseAdminMessage(
    close: Awaited<ReturnType<ContabilidadService['findCloseOrThrow']>>,
    pdfUrl: string,
  ) {
    return [
      'Cierre diario pendiente',
      `Unidad: ${close.type === CloseType.PHYTOEMAGRY ? 'PhytoEmagry' : 'Tienda'}`,
      `Fecha: ${new Intl.DateTimeFormat('es-DO').format(close.date)}`,
      `Creado por: ${close.createdByName ?? close.createdById ?? 'N/D'}`,
      `Efectivo: ${this.money(close.cash)}`,
      `Transferencias: ${this.money(close.transfer)}`,
      `Tarjeta: ${this.money(close.card)}`,
      `Gastos: ${this.money(close.expenses)}`,
      `Total neto: ${this.money(close.netTotal)}`,
      `Efectivo entregado: ${this.money(close.cashDelivered)}`,
      `Diferencia: ${this.money(close.difference)}`,
      'Estado: pending',
      `PDF: ${pdfUrl}`,
    ].join('\n');
  }

  private async enqueueCloseNotifications(
    closeId: string,
    pdfBytes: Uint8Array,
    fileName: string,
    pdfUrl: string,
  ) {
    const close = await this.findCloseOrThrow(closeId);
    const recipients = await this.prisma.user.findMany({
      where: { role: { in: ['ADMIN', 'ASISTENTE'] }, blocked: false },
      select: { id: true, telefono: true },
    });
    const message = this.buildCloseAdminMessage(close, pdfUrl);
    let sent = 0;
    const errors: string[] = [];
    for (const recipient of recipients) {
      try {
        await this.notifications.enqueueWhatsAppDocument({
          recipientUserId: recipient.id,
          toNumber: recipient.telefono,
          messageText: message,
          fileName,
          bytes: pdfBytes,
          mimeType: 'application/pdf',
          dedupeKey: `daily-close:${close.id}:${recipient.id}`,
          payload: { kind: 'daily_close', closeId: close.id, pdfUrl },
          allowOutsideBusinessHours: true,
        });
        sent += 1;
      } catch (error) {
        errors.push(error instanceof Error ? error.message : String(error));
      }
    }

    await this.prisma.close.update({
      where: { id: close.id },
      data: {
        notificationStatus: sent > 0 ? 'sent' : 'failed',
        notificationError: errors.length ? errors.join(' | ') : null,
      },
    });
  }

  async generateAiReport(id: string, actor: Actor) {
    this.ensureReviewer(actor);
    const close = await this.findCloseOrThrow(id);
    const previous = await this.prisma.close.findMany({
      where: {
        type: close.type,
        id: { not: close.id },
        date: { lt: close.date },
      },
      orderBy: { date: 'desc' },
      take: 10,
      include: { transfers: { include: { vouchers: true } } },
    });

    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { openAiApiKey: true, openAiModel: true },
    });
    const apiKey =
      (
        this.config.get<string>('OPENAI_API_KEY') ??
        process.env.OPENAI_API_KEY ??
        ''
      ).trim() || (appConfig?.openAiApiKey ?? '').trim();
    const model =
      (
        this.config.get<string>('OPENAI_MODEL') ??
        process.env.OPENAI_MODEL ??
        ''
      ).trim() ||
      (appConfig?.openAiModel ?? '').trim() ||
      'gpt-4o-mini';

    const aiEvidence = await this.buildCloseAiEvidence(close);
    const evidenceReviewed = aiEvidence.map((evidence) => ({
      label: evidence.label,
      source: evidence.source,
      fileName: evidence.fileName,
      mimeType: evidence.mimeType,
      fileUrl: evidence.fileUrl,
      storageKey: evidence.storageKey,
      includedInVision: evidence.includedInVision,
      note: evidence.note ?? null,
    }));
    const visionEvidence = aiEvidence.filter((evidence) => evidence.imageUrl);
    const expectedDifference = Number(close.cash) - Number(close.cashDelivered);
    const normalizedDifference = Number(close.difference);
    const expenseDetails = Array.isArray(close.expenseDetails)
      ? close.expenseDetails
      : [];
    const context = {
      close: {
        ...close,
        expectedDifference,
        normalizedDifference,
        expenseDetails,
      },
      analysisFocus: {
        mustReadUploadedImagesBeforeReport: true,
        mustPrioritizePosClosingVoucherImage: true,
        imageEvidenceCount: visionEvidence.length,
        uploadedEvidenceCount: aiEvidence.length,
        mustEvaluateDifferenceAgainstExpenses: true,
        differenceCanBeJustifiedByDocumentedExpenses: true,
        prioritizeFraudSignalsOnlyWhenUnsupportedByEvidence: true,
      },
      evidenceReviewed,
      previousClosings: previous.map((item) => ({
        id: item.id,
        date: item.date,
        totalIncome: item.totalIncome,
        netTotal: item.netTotal,
        transfer: item.transfer,
        expenses: item.expenses,
        difference: item.difference,
      })),
    };

    let report: Record<string, unknown>;
    if (!apiKey) {
      report = {
        riskLevel: 'medium',
        summary:
          'No hay API key de OpenAI configurada. Se guardo una revision basica del sistema.',
        detectedIssues:
          aiEvidence.length === 0 ? ['No hay vouchers visibles.'] : [],
        suggestedAdminActions: [
          'Configurar OpenAI para analisis completo con imagenes.',
          'Revisar vouchers manualmente.',
        ],
        confidenceLevel: 'low',
        evidenceReviewed,
        visionEvidenceCount: 0,
      };
    } else {
      const content: Array<Record<string, unknown>> = [
        {
          type: 'text',
          text:
            'Analiza este cierre diario contable y sus evidencias. Antes de emitir el reporte debes revisar TODAS las imagenes adjuntas en este mensaje, dando prioridad al boucher POS del cierre del punto de venta. Devuelve SOLO JSON con: riskLevel(low|medium|high), summary, detectedIssues[], suggestedAdminActions[], confidenceLevel, evidenceReviewed[], financialBreakdown{difference,expenses,isDifferenceReasonable,reasoning}, fraudSignals[], and auditorNotes[]. Regla critica: evalua si la diferencia se explica por gastos registrados y soportes (voucher/evidencia); no elevar riesgo sin justificar contradiccion. En evidenceReviewed indica cada archivo revisado y si fue leido visualmente. ' +
            JSON.stringify(context),
        },
        ...visionEvidence.map((evidence) => ({
          type: 'image_url',
          image_url: { url: evidence.imageUrl },
        })),
      ];
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model,
          temperature: 0.1,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content:
                'Eres auditor contable. No apruebas ni rechazas; solo alertas riesgos.',
            },
            { role: 'user', content },
          ],
        }),
      });
      if (!res.ok) {
        throw new BadRequestException(
          `No se pudo generar Informe IA: HTTP ${res.status}`,
        );
      }
      const json = (await res.json()) as any;
      const raw = json?.choices?.[0]?.message?.content;
      report = raw ? JSON.parse(raw) : {};
    }

    const differenceValue = Number(close.difference ?? 0);
    const expensesValue = Number(close.expenses ?? 0);
    const incomeValue = Number(close.totalIncome ?? 0);
    const absDifference = Math.abs(differenceValue);
    const likelyExplainedByExpenses = absDifference > 0 && expensesValue > 0;
    const currentFinancialBreakdown =
      (report.financialBreakdown as Record<string, unknown> | undefined) ?? {};
    report.financialBreakdown = {
      difference: differenceValue,
      expenses: expensesValue,
      totalIncome: incomeValue,
      isDifferenceReasonable:
        currentFinancialBreakdown.isDifferenceReasonable ??
        (likelyExplainedByExpenses ? 'possibly' : absDifference === 0),
      reasoning:
        currentFinancialBreakdown.reasoning ??
        (likelyExplainedByExpenses
          ? 'La diferencia puede estar relacionada con gastos registrados. Validar que cada gasto tenga soporte y corresponda a la operación del día.'
          : absDifference === 0
            ? 'No hay diferencia entre efectivo declarado y efectivo entregado.'
            : 'Se detecta diferencia sin gasto suficiente que la justifique. Requiere validación manual de caja y soportes.'),
    };
    if (!Array.isArray(report.detectedIssues)) {
      report.detectedIssues = [];
    }
    if (absDifference > 0) {
      (report.detectedIssues as string[]).push(
        `Diferencia reportada en caja: ${differenceValue.toFixed(2)} DOP.`,
      );
    }
    if (!Array.isArray(report.suggestedAdminActions)) {
      report.suggestedAdminActions = [];
    }
    (report.suggestedAdminActions as string[]).push(
      'Cruzar diferencia con detalle de gastos y comprobantes del día.',
      'Verificar entradas de dinero y transferencias declaradas contra evidencias.',
    );

    const riskLevel = String(
      report.riskLevel ?? report.ai_risk_level ?? 'medium',
    ).toLowerCase();
    const summary = String(
      report.summary ??
        report.ai_report_summary ??
        `Resumen IA: ingresos ${incomeValue.toFixed(2)} DOP, gastos ${expensesValue.toFixed(2)} DOP y diferencia ${differenceValue.toFixed(2)} DOP. ${likelyExplainedByExpenses ? 'Existe gasto que podría explicar parte de la diferencia, revisar soportes.' : 'No hay gasto suficiente para justificar la diferencia, revisar caja y evidencias.'}`,
    );
    return this.prisma.close.update({
      where: { id: close.id },
      data: {
        aiRiskLevel: ['low', 'medium', 'high'].includes(riskLevel)
          ? riskLevel
          : 'medium',
        aiReportSummary: summary,
        aiReportJson: report as Prisma.InputJsonValue,
        aiGeneratedAt: new Date(),
      },
      include: { transfers: { include: { vouchers: true } } },
    });
  }

  async createDepositOrder(dto: CreateDepositOrderDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const payload = await this.normalizeDepositPayload({
      windowFrom: dto.windowFrom,
      windowTo: dto.windowTo,
      bankName: dto.bankName,
      bankAccount: dto.bankAccount,
      collaboratorName: dto.collaboratorName,
      note: dto.note,
      reserveAmount: dto.reserveAmount,
      totalAvailableCash: dto.totalAvailableCash,
      depositTotal: dto.depositTotal,
      closesCountByType: dto.closesCountByType,
      depositByType: dto.depositByType,
      accountByType: dto.accountByType,
    });
    const correction = await this.resolveDepositCorrection(dto, actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    const correctedNote =
      correction.correctionOfDepositOrderId && correction.correctionReason
        ? [
            payload.note,
            `Corrección del depósito ${correction.correctionOfDepositOrderId}. Motivo: ${correction.correctionReason}`,
          ]
            .filter((item): item is string => (item ?? '').trim().length > 0)
            .join('\n')
        : payload.note;

    const created = await this.prisma.depositOrder.create({
      data: {
        ...payload,
        note: this.toNullableTrimmed(correctedNote),
        status: DepositOrderStatus.PENDING,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
      select: this.depositOrderLegacySelect,
    });
    return this.enrichDepositOrderRow(created);
  }

  async getDepositOrders(query: DepositOrdersQueryDto, actor: Actor) {
    const from = this.parseDate(query.from, 'from');
    const to = this.parseDate(query.to, 'to');

    // Temporary diagnostics for persistent 500 on deposit list.
    // eslint-disable-next-line no-console
    console.log('[deposit-orders][service] getDepositOrders:start', {
      actorId: actor.id ?? null,
      actorRole: actor.role ?? null,
      from: query.from ?? null,
      to: query.to ?? null,
      status: query.status ?? null,
      parsedFrom: from?.toISOString() ?? null,
      parsedTo: to?.toISOString() ?? null,
    });

    try {
      this.normalizeRoleGuard(actor);
      const where: Record<string, unknown> = {};

      if (!this.isReviewer(actor)) {
        // ASISTENTE: sees ALL open (non-executed) deposits across the company.
        // Not restricted to own deposits (createdById). EXECUTED is blocked for this role.
        const requestedStatus = query.status as string | undefined;
        if (requestedStatus && requestedStatus !== 'EXECUTED') {
          where.status = requestedStatus;
        } else {
          where.status = { not: 'EXECUTED' };
        }
      } else if (query.status) {
        // ADMIN: apply explicit status filter as requested.
        where.status = query.status;
      }

      if (from != null || to != null) {
        if (from != null && to != null) {
          where.AND = [
            { windowFrom: { lte: to } },
            { windowTo: { gte: from } },
          ];
        } else if (from != null) {
          where.windowTo = { gte: from };
        } else if (to != null) {
          where.windowFrom = { lte: to };
        }
      }

      // eslint-disable-next-line no-console
      console.log('[deposit-orders][service] getDepositOrders:query', {
        actorId: actor.id ?? null,
        actorRole: actor.role ?? null,
        where,
        orderBy: [{ createdAt: 'desc' }],
      });

      const rows = await this.findManyDepositOrdersWithFallback({
        where,
        orderBy: [{ createdAt: 'desc' }],
      });
      // eslint-disable-next-line no-console
      console.log('[deposit-orders][service] getDepositOrders:success', {
        actorId: actor.id ?? null,
        actorRole: actor.role ?? null,
        resultCount: rows.length,
      });
      return rows.map((row) => this.enrichDepositOrderRow(row));
    } catch (error: unknown) {
      const err = error as {
        name?: unknown;
        message?: unknown;
        code?: unknown;
        meta?: unknown;
        stack?: unknown;
      };
      // eslint-disable-next-line no-console
      console.error('[deposit-orders][service] getDepositOrders:error', {
        actorId: actor.id ?? null,
        actorRole: actor.role ?? null,
        from: query.from ?? null,
        to: query.to ?? null,
        status: query.status ?? null,
        errorName: err?.name,
        errorMessage: err?.message,
        errorCode: err?.code,
        errorMeta: err?.meta,
        errorStack: err?.stack,
      });
      throw error;
    }
  }

  async getDepositOrderById(id: string, actor: Actor) {
    this.normalizeRoleGuard(actor);
    const row = await this.prisma.depositOrder.findUnique({
      where: { id },
      select: this.depositOrderLegacySelect,
    });
    if (!row) throw new NotFoundException('Depósito bancario no encontrado');
    if (!this.isReviewer(actor) && row.createdById !== actor.id) {
      throw new ForbiddenException(
        'Solo puedes ver depósitos bancarios creados por tu usuario.',
      );
    }
    return this.enrichDepositOrderRow(row);
  }

  async updateDepositOrder(
    id: string,
    dto: UpdateDepositOrderDto,
    actor: Actor,
  ) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        windowFrom: true,
        windowTo: true,
        bankName: true,
        bankAccount: true,
        collaboratorName: true,
        note: true,
        reserveAmount: true,
        totalAvailableCash: true,
        depositTotal: true,
        closesCountByType: true,
        depositByType: true,
        accountByType: true,
      },
    });
    if (!existing)
      throw new NotFoundException('Depósito bancario no encontrado');

    if (existing.status !== DepositOrderStatus.PENDING) {
      throw new BadRequestException(
        'Solo se pueden editar depósitos pendientes y no anulados.',
      );
    }
    if (
      dto.status != null ||
      dto.voucherUrl != null ||
      dto.voucherFileName != null ||
      dto.voucherMimeType != null ||
      dto.correctionOfDepositOrderId != null ||
      dto.correctionReason != null
    ) {
      throw new BadRequestException(
        'El cambio de estado, voucher o corrección debe hacerse por su flujo específico.',
      );
    }

    const payload = await this.normalizeDepositPayload({
      windowFrom: dto.windowFrom ?? existing.windowFrom,
      windowTo: dto.windowTo ?? existing.windowTo,
      bankName: dto.bankName ?? existing.bankName,
      bankAccount: dto.bankAccount ?? existing.bankAccount,
      collaboratorName: dto.collaboratorName ?? existing.collaboratorName,
      note: dto.note ?? existing.note,
      reserveAmount: dto.reserveAmount ?? existing.reserveAmount,
      totalAvailableCash: dto.totalAvailableCash ?? existing.totalAvailableCash,
      depositTotal: dto.depositTotal ?? existing.depositTotal,
      closesCountByType: dto.closesCountByType ?? existing.closesCountByType,
      depositByType: dto.depositByType ?? existing.depositByType,
      accountByType: dto.accountByType ?? existing.accountByType,
    });

    const updated = await this.prisma.depositOrder.update({
      where: { id },
      data: payload,
      select: this.depositOrderLegacySelect,
    });
    return this.enrichDepositOrderRow(updated);
  }

  async approveDepositOrder(id: string, _reviewNote: string | undefined, actor: Actor) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        voucherUrl: true,
      },
    });
    if (!existing) {
      throw new NotFoundException('Depósito bancario no encontrado');
    }
    if (existing.status === DepositOrderStatus.EXECUTED) {
      throw new BadRequestException('El depósito ya fue ejecutado.');
    }
    if (existing.status === DepositOrderStatus.CANCELLED) {
      throw new BadRequestException(
        'No se puede aprobar un depósito anulado o rechazado.',
      );
    }
    if (!this.toNullableTrimmed(existing.voucherUrl)) {
      throw new BadRequestException(
        'Debes adjuntar un voucher antes de ejecutar el depósito.',
      );
    }

    const executor = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    const updated = await this.prisma.depositOrder.update({
      where: { id },
      data: {
        status: DepositOrderStatus.EXECUTED,
        executedAt: new Date(),
        executedById: actor.id!,
        executedByName: executor?.nombreCompleto ?? null,
      },
      select: this.depositOrderLegacySelect,
    });
    return this.enrichDepositOrderRow(updated);
  }

  async cancelDepositOrder(id: string, reviewNote: string | undefined, actor: Actor) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        note: true,
      },
    });
    if (!existing) {
      throw new NotFoundException('Depósito bancario no encontrado');
    }
    if (existing.status === DepositOrderStatus.EXECUTED) {
      throw new BadRequestException(
        'Los depósitos ejecutados son inmutables y no pueden anularse.',
      );
    }
    if (existing.status === DepositOrderStatus.CANCELLED) {
      throw new BadRequestException('El depósito ya fue anulado o rechazado.');
    }

    const reason = this.toNullableTrimmed(reviewNote);
    if (!reason) {
      throw new BadRequestException('El motivo de anulación es obligatorio.');
    }

    const reasonLine = `Anulación: ${reason}`;
    const mergedNote = [existing.note, reasonLine]
      .filter((item): item is string => (item ?? '').trim().length > 0)
      .join('\n');

    const updated = await this.prisma.depositOrder.update({
      where: { id },
      data: {
        status: DepositOrderStatus.CANCELLED,
        note: this.toNullableTrimmed(mergedNote),
      },
      select: this.depositOrderLegacySelect,
    });
    return this.enrichDepositOrderRow(updated);
  }

  async attachDepositOrderVoucher(
    id: string,
    params: {
      voucherUrl: string;
      voucherFileName: string;
      voucherMimeType: string;
    },
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        createdById: true,
      },
    });
    if (!existing)
      throw new NotFoundException('Depósito bancario no encontrado');
    if (!this.isReviewer(actor) && existing.createdById !== actor.id) {
      throw new ForbiddenException(
        'Solo puedes subir voucher a depósitos creados por tu usuario.',
      );
    }
    if (existing.status === DepositOrderStatus.CANCELLED) {
      throw new BadRequestException(
        'No se puede adjuntar voucher a un depósito cancelado',
      );
    }
    if (existing.status === DepositOrderStatus.EXECUTED) {
      throw new BadRequestException(
        'Los depósitos ejecutados son inmutables y no admiten cambio de voucher.',
      );
    }

    const updated = await this.prisma.depositOrder.update({
      where: { id },
      data: {
        voucherUrl: params.voucherUrl.trim(),
        voucherFileName: params.voucherFileName.trim(),
        voucherMimeType: params.voucherMimeType.trim(),
      },
      select: this.depositOrderLegacySelect,
    });
    return this.enrichDepositOrderRow(updated);
  }

  async deleteDepositOrder(id: string, actor: Actor) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!existing)
      throw new NotFoundException('Depósito bancario no encontrado');

    const correctionCount = await this.prisma.depositOrder.count({
      where: { correctionOfDepositOrderId: id },
    });
    if (correctionCount > 0) {
      throw new BadRequestException(
        'No puedes eliminar este depósito porque tiene correcciones vinculadas. Elimina primero las correcciones.',
      );
    }

    await this.prisma.depositOrder.delete({ where: { id } });

    return {
      ok: true,
      message: 'Depósito eliminado correctamente.',
    };
  }

  async createFiscalInvoice(dto: CreateFiscalInvoiceDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.fiscalInvoice.create({
      data: {
        kind: dto.kind,
        invoiceDate: new Date(dto.invoiceDate),
        imageUrl: dto.imageUrl.trim(),
        note: dto.note?.trim() || null,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
    });
  }

  async getFiscalInvoices(query: FiscalInvoicesQueryDto) {
    const where: Record<string, unknown> = {};

    if (query.kind) {
      where.kind = query.kind;
    }

    if (query.from || query.to) {
      const from = this.parseDate(query.from, 'from');
      const to = this.parseDate(query.to, 'to');

      where.invoiceDate = {
        ...(from != null ? { gte: from } : {}),
        ...(to != null ? { lte: to } : {}),
      };
    }

    return this.prisma.fiscalInvoice.findMany({
      where,
      orderBy: [{ invoiceDate: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async updateFiscalInvoice(
    id: string,
    dto: UpdateFiscalInvoiceDto,
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.fiscalInvoice.findUnique({
      where: { id },
    });
    if (!existing) throw new NotFoundException('Factura fiscal no encontrada');

    return this.prisma.fiscalInvoice.update({
      where: { id },
      data: {
        ...(dto.kind != null ? { kind: dto.kind } : {}),
        ...(dto.invoiceDate != null
          ? { invoiceDate: new Date(dto.invoiceDate) }
          : {}),
        ...(dto.imageUrl != null ? { imageUrl: dto.imageUrl.trim() } : {}),
        ...(dto.note != null ? { note: dto.note.trim() || null } : {}),
      },
    });
  }

  async deleteFiscalInvoice(id: string, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.fiscalInvoice.findUnique({
      where: { id },
    });
    if (!existing) throw new NotFoundException('Factura fiscal no encontrada');

    return this.prisma.fiscalInvoice.delete({ where: { id } });
  }

  async createPayableService(dto: CreatePayableServiceDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.payableService.create({
      data: {
        title: dto.title.trim(),
        providerKind: dto.providerKind,
        providerName: dto.providerName.trim(),
        description: this.toNullableTrimmed(dto.description),
        frequency: dto.frequency,
        defaultAmount: dto.defaultAmount,
        nextDueDate: new Date(dto.nextDueDate),
        active: dto.active ?? true,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
      include: {
        payments: {
          orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        },
      },
    });
  }

  async getPayableServices(query: PayableServicesQueryDto) {
    const where: Prisma.PayableServiceWhereInput = {};

    if (query.active != null) {
      where.active = query.active;
    }

    return this.prisma.payableService.findMany({
      where,
      include: {
        payments: {
          orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        },
      },
      orderBy: [
        { active: 'desc' },
        { nextDueDate: 'asc' },
        { createdAt: 'desc' },
      ],
    });
  }

  async updatePayableService(
    id: string,
    dto: UpdatePayableServiceDto,
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.payableService.findUnique({
      where: { id },
    });
    if (!existing) {
      throw new NotFoundException('Servicio por pagar no encontrado');
    }

    return this.prisma.payableService.update({
      where: { id },
      data: {
        ...(dto.title != null ? { title: dto.title.trim() } : {}),
        ...(dto.providerKind != null ? { providerKind: dto.providerKind } : {}),
        ...(dto.providerName != null
          ? { providerName: dto.providerName.trim() }
          : {}),
        ...(dto.description != null
          ? { description: this.toNullableTrimmed(dto.description) }
          : {}),
        ...(dto.frequency != null ? { frequency: dto.frequency } : {}),
        ...(dto.defaultAmount != null
          ? { defaultAmount: dto.defaultAmount }
          : {}),
        ...(dto.nextDueDate != null
          ? { nextDueDate: new Date(dto.nextDueDate) }
          : {}),
        ...(dto.active != null ? { active: dto.active } : {}),
      },
      include: {
        payments: {
          orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        },
      },
    });
  }

  async registerPayablePayment(
    serviceId: string,
    dto: RegisterPayablePaymentDto,
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    if (dto.amount <= 0) {
      throw new BadRequestException('El monto debe ser mayor a 0');
    }

    const service = await this.prisma.payableService.findUnique({
      where: { id: serviceId },
    });

    if (!service) {
      throw new NotFoundException('Servicio por pagar no encontrado');
    }

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    const paidAt = dto.paidAt ? new Date(dto.paidAt) : new Date();
    const nextDueDate = this.nextDueDateFrom(service.frequency, paidAt);

    const result = await this.prisma.$transaction(async (tx) => {
      const payment = await tx.payablePayment.create({
        data: {
          serviceId: service.id,
          amount: dto.amount,
          paidAt,
          note: this.toNullableTrimmed(dto.note),
          createdById: actor.id!,
          createdByName: creator?.nombreCompleto ?? null,
        },
      });

      await tx.payableService.update({
        where: { id: service.id },
        data: {
          lastPaidAt: paidAt,
          nextDueDate,
          active:
            service.frequency === PayableFrequency.ONE_TIME ? false : true,
        },
      });

      return payment;
    });

    return this.prisma.payablePayment.findUnique({
      where: { id: result.id },
      include: {
        service: true,
      },
    });
  }

  async getPayablePayments(query: PayablePaymentsQueryDto) {
    const where: Prisma.PayablePaymentWhereInput = {};

    if (query.serviceId) {
      where.serviceId = query.serviceId;
    }

    if (query.from || query.to) {
      const from = this.parseDate(query.from, 'from');
      const to = this.parseDate(query.to, 'to');
      where.paidAt = {
        ...(from ? { gte: from } : {}),
        ...(to ? { lte: to } : {}),
      };
    }

    return this.prisma.payablePayment.findMany({
      where,
      include: {
        service: true,
      },
      orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async deletePayableService(id: string, actor: Actor) {
    this.ensureAdmin(actor);
    const existing = await this.prisma.payableService.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Servicio por pagar no encontrado');
    await this.prisma.payableService.delete({ where: { id } });
    return { deleted: true, id };
  }

  async deletePayablePayment(id: string, actor: Actor) {
    this.ensureAdmin(actor);
    const existing = await this.prisma.payablePayment.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Pago no encontrado');
    await this.prisma.payablePayment.delete({ where: { id } });
    return { deleted: true, id };
  }

  async updatePayablePayment(id: string, dto: UpdatePayablePaymentDto, actor: Actor) {
    this.ensureAdmin(actor);
    const existing = await this.prisma.payablePayment.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Pago no encontrado');
    if (dto.amount !== undefined && dto.amount <= 0) {
      throw new BadRequestException('El monto debe ser mayor a 0');
    }
    return this.prisma.payablePayment.update({
      where: { id },
      data: {
        ...(dto.amount !== undefined ? { amount: dto.amount } : {}),
        ...(dto.paidAt !== undefined ? { paidAt: new Date(dto.paidAt) } : {}),
        ...(dto.note !== undefined ? { note: this.toNullableTrimmed(dto.note) } : {}),
      },
      include: { service: true },
    });
  }
}
