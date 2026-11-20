import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  LicenseOrderStatus,
  LicenseStatus,
  Prisma,
} from '@prisma/client';
import { randomInt } from 'node:crypto';
import { isAdminLike, requireTenant, type TenantUser } from '../../auth/tenant-context';
import { PrismaService } from '../../prisma/prisma.service';
import { addMonths, LicenseActivationService } from './license-activation.service';
import { LicenseEvidenceStorage } from './license-evidence.storage';
import {
  canAcceptEvidence,
  evaluateEvidence,
} from './license-evidence.validation';
import {
  AUTHORIZED_ACCOUNT_SUFFIX,
  parseBankReceipt,
  RECEIPT_UTC_OFFSET_HOURS,
  startOfLocalDayUtc,
  validateBankTransfer,
} from '../evidence/bank-transfer.analysis';
import { OcrEngine } from '../evidence/ocr.engine';
import {
  describeOrders,
  InvalidInsightsError,
  normalizeEvidenceInsights,
} from './license-order-insights';
import {
  LicenseProvisionalService,
  provisionalWindowDays,
  SNAPSHOT_SELECT,
  snapshotOf,
} from './license-provisional.service';

/** La orden se puede pagar durante 48 h; despues caduca sola. */
export const ORDER_TTL_HOURS = 48;
/**
 * Las ordenes de **renovacion** viven mas: se generan hasta 10 dias antes del
 * vencimiento y la referencia debe seguir siendo la misma cuando el cliente
 * transfiera. Con 48 h habria que regenerarla dos veces en la misma ventana.
 */
export const RENEWAL_ORDER_TTL_HOURS = 24 * 15;
/**
 * Tope de subidas por empresa y dia local (America/Santo_Domingo).
 *
 * Cada intento consume OCR, asi que el limite existe para evitar abuso; pero
 * un cliente que se equivoca de archivo no puede quedarse sin poder pagar el
 * mismo dia, asi que se deja margen para cinco intentos.
 */
export const MAX_DAILY_UPLOADS = 5;
/** Dias que se usan para valorar lo no consumido del periodo al cambiar de plan. */
export const PERIOD_DAYS = 30;

/** Importe de una compra: precio x meses menos lo no consumido del plan actual. */
export type OrderQuote = {
  planCode: string;
  planName: string;
  months: number;
  currency: string;
  monthlyPrice: number;
  subtotal: number;
  /** Valor de los dias que aun no se han consumido del periodo actual. */
  credit: number;
  creditDays: number;
  /** Plan cuyo periodo se esta descontando (solo al cambiar de plan). */
  creditPlanCode: string | null;
  /** Lo que el cliente debe transferir hoy. */
  amountDue: number;
  /** true cuando la orden cambia de plan y aplica credito. */
  planChange: boolean;
};

const OPEN_STATUSES: LicenseOrderStatus[] = [
  LicenseOrderStatus.CREATED,
  LicenseOrderStatus.AWAITING_TRANSFER,
];

export type EvidenceFile = {
  originalname?: string;
  mimetype?: string;
  size?: number;
  buffer?: Buffer;
};

@Injectable()
export class LicenseOrdersService {
  private readonly logger = new Logger(LicenseOrdersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly activation: LicenseActivationService,
    private readonly storage: LicenseEvidenceStorage,
    private readonly provisional: LicenseProvisionalService,
    private readonly ocr: OcrEngine,
  ) {}

  /**
   * Datos para transferir. **Nunca** se inventan: si no estan configurados, se
   * dice explicitamente.
   *
   * La cuenta es **unica** para pagos y se puede sobrescribir por entorno
   * (`LICENSE_BANK_*`); los valores por defecto son los comerciales de
   * FULLTECH y coinciden con lo que ve el cliente en el panel.
   */
  paymentInstructions() {
    const recipientName = value(this.config, 'LICENSE_BANK_HOLDER') || 'FULLTECH, SRL';
    const recipientTaxId =
      value(this.config, 'LICENSE_BANK_HOLDER_TAX_ID') || '133080206';
    const accountNumber =
      value(this.config, 'LICENSE_BANK_ACCOUNT') || '841360753';
    const bankName = value(this.config, 'LICENSE_BANK_NAME');
    const accountType =
      value(this.config, 'LICENSE_BANK_ACCOUNT_TYPE') || 'Ahorro o corriente';
    const configured = !!(recipientName && accountNumber);
    return {
      configured,
      currency: 'DOP',
      bankName: bankName || null,
      accountNumber,
      accountType,
      holder: recipientName,
      holderTaxId: recipientTaxId,
      /** Solo hay una cuenta: si el banco del cliente es otro, pago al instante. */
      singleAccount: true,
      beforeTransfer: `Antes de transferir: el monto exacto y a nombre de ${recipientName}.`,
      otherBankNote:
        `Si tu banco es distinto, haz un pago al instante indicando el RNC ${recipientTaxId}.`,
      instructions: configured
        ? 'Transfiere el monto exacto. La referencia ayuda, pero si no la pones tu comprobante se identifica igual.'
        : 'Contacta soporte para recibir los datos de transferencia.',
      orderTtlHours: ORDER_TTL_HOURS,
    };
  }

  async createOrder(
    user: TenantUser,
    dto: { planCode?: unknown; months?: unknown },
  ) {
    const companyId = requireTenant(user);
    this.requireAdmin(user);
    const plan = await this.resolvePlan(dto.planCode);
    const months = normalizeMonths(dto.months);

    // Renovacion (mismo plan, un mes): la orden tiene que sobrevivir a la
    // ventana de pago anticipado. Con 48 h el cliente que transfiere el dia 8
    // se quedaria sin poder subir el comprobante.
    const quote = await this.quoteFor({ companyId, plan, months });
    const renewal = !quote.planChange && months === 1;

    return this.createOrReuseOrder({
      companyId,
      plan,
      months,
      createdByUserId: user.id,
      ttlHours: renewal ? RENEWAL_ORDER_TTL_HOURS : undefined,
    });
  }

  /**
   * Lo que el cliente pagaria hoy por ese plan y esos meses, aplicando el
   * credito de los dias no consumidos cuando cambia de plan. La misma cuenta
   * se usa al crear la orden: lo cotizado es lo que viaja a la transferencia.
   */
  async quote(
    user: TenantUser,
    dto: { planCode?: unknown; months?: unknown },
  ): Promise<OrderQuote> {
    const companyId = requireTenant(user);
    this.requireAdmin(user);
    const plan = await this.resolvePlan(dto.planCode);
    const months = normalizeMonths(dto.months);
    return this.quoteFor({ companyId, plan, months });
  }

  private async resolvePlan(rawCode: unknown) {
    const planCode = String(rawCode ?? '').trim().toLowerCase();
    if (!planCode) {
      throw new BadRequestException({
        code: 'PLAN_CODE_REQUIRED',
        message: 'Elige un plan para crear la orden.',
      });
    }
    const plan = await this.prisma.licensePlan.findUnique({
      where: { code: planCode },
    });
    if (!plan || !plan.active) {
      throw new NotFoundException({
        code: 'PLAN_NOT_AVAILABLE',
        message: 'Ese plan no esta disponible.',
        planCode,
      });
    }
    return plan;
  }

  private async quoteFor(input: {
    companyId: string;
    plan: {
      code: string;
      name: string;
      currency: string;
      monthlyPrice: Prisma.Decimal;
    };
    months: number;
  }): Promise<OrderQuote> {
    const { companyId, plan, months } = input;
    const monthlyPrice = plan.monthlyPrice.toNumber();
    const subtotal = round2(monthlyPrice * months);
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { planCode: true, licenseStatus: true, licenseExpiresAt: true },
    });
    const currentCode = (company?.planCode ?? '').trim().toLowerCase();
    const targetCode = plan.code.trim().toLowerCase();
    const usable =
      company?.licenseStatus === LicenseStatus.ACTIVE ||
      company?.licenseStatus === LicenseStatus.TRIAL;
    const planChange = !!currentCode && currentCode !== targetCode;

    let creditDays = 0;
    let credit = 0;
    let creditPlanCode: string | null = null;
    if (usable && planChange && company?.licenseExpiresAt) {
      const msLeft = company.licenseExpiresAt.getTime() - Date.now();
      // Se cuentan **todos** los dias pagados que quedan, incluidos los meses
      // adelantados: el cliente no pierde tiempo ni dinero al mejorar.
      creditDays = Math.max(0, Math.ceil(msLeft / 86_400_000));
      if (creditDays > 0) {
        const current = await this.prisma.licensePlan.findUnique({
          where: { code: currentCode },
        });
        if (current) {
          creditPlanCode = current.code;
          credit = round2(
            (current.monthlyPrice.toNumber() / PERIOD_DAYS) * creditDays,
          );
        }
      }
    }
    // El credito nunca paga mas que la compra: el minimo a transferir es 0.
    credit = Math.min(credit, subtotal);
    return {
      planCode: plan.code,
      planName: plan.name,
      months,
      currency: plan.currency,
      monthlyPrice,
      subtotal,
      credit: round2(credit),
      creditDays,
      creditPlanCode,
      amountDue: round2(subtotal - credit),
      planChange,
    };
  }

  /**
   * Deja una orden abierta sin intervencion humana. La usa el recordatorio de
   * vencimiento para que el aviso lleve una referencia real que el cliente
   * pueda escribir en la transferencia.
   */
  async ensureOpenOrder(input: { companyId: string; planCode: string | null }) {
    const code = (input.planCode ?? '').trim().toLowerCase();
    if (!code) return null;
    const plan = await this.prisma.licensePlan.findUnique({ where: { code } });
    if (!plan || !plan.active) return null;
    const order = await this.createOrReuseOrder({
      companyId: input.companyId,
      plan,
      months: 1,
      createdByUserId: null,
      ttlHours: RENEWAL_ORDER_TTL_HOURS,
    });
    return { id: order.id, reference: order.reference };
  }

  private async createOrReuseOrder(input: {
    companyId: string;
    plan: {
      code: string;
      name: string;
      version: number;
      currency: string;
      monthlyPrice: Prisma.Decimal;
    };
    months: number;
    createdByUserId: string | null;
    /** Horas de vida de la orden (por defecto, las de una compra normal). */
    ttlHours?: number;
  }) {
    const { companyId, plan, months } = input;
    const now = new Date();
    await this.expireStaleOrders(companyId, now);

    // Mismo importe que la cotizacion: precio x meses menos credito.
    const quote = await this.quoteFor({ companyId, plan, months });

    const openOrder = await this.prisma.licensePaymentOrder.findFirst({
      where: {
        companyId,
        status: { in: OPEN_STATUSES },
        expiresAt: { gt: now },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (openOrder) {
      if (
        openOrder.planCode === plan.code &&
        openOrder.months === months &&
        openOrder.amount.toNumber() === quote.amountDue
      ) {
        return this.toPublicOrder(openOrder, plan.name);
      }
      await this.prisma.licensePaymentOrder.update({
        where: { id: openOrder.id },
        data: { status: LicenseOrderStatus.CANCELLED },
        select: { id: true },
      });
    }

    const amount = quote.amountDue;
    const reference = await this.generateReference();
    const order = await this.prisma.licensePaymentOrder.create({
      data: {
        companyId,
        planCode: plan.code,
        catalogVersion: plan.version,
        currency: plan.currency,
        amount: new Prisma.Decimal(amount.toFixed(2)),
        months,
        status: LicenseOrderStatus.AWAITING_TRANSFER,
        reference,
        expiresAt: new Date(
          now.getTime() +
            (input.ttlHours ?? ORDER_TTL_HOURS) * 3_600_000,
        ),
        createdByUserId: input.createdByUserId,
      },
    });
    return this.toPublicOrder(order, plan.name);
  }

  async listOrders(user: TenantUser) {
    const companyId = requireTenant(user);
    const now = new Date();
    await this.expireStaleOrders(companyId, now);
    const orders = await this.prisma.licensePaymentOrder.findMany({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
      take: 20,
      include: {
        evidences: {
          select: {
            id: true,
            mime: true,
            sizeBytes: true,
            status: true,
            createdAt: true,
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    return { orders: orders.map((order) => this.toPublicOrder(order)) };
  }

  async cancelOrder(user: TenantUser, orderId: string) {
    const companyId = requireTenant(user);
    this.requireAdmin(user);
    const order = await this.prisma.licensePaymentOrder.findFirst({
      where: { id: orderId, companyId },
      include: { evidences: { select: { id: true } } },
    });
    if (!order) {
      throw new NotFoundException({
        code: 'ORDER_NOT_FOUND',
        message: 'No encontramos esa orden.',
      });
    }
    if (order.evidences.length > 0 || !OPEN_STATUSES.includes(order.status)) {
      throw new ConflictException({
        code: 'ORDER_NOT_CANCELLABLE',
        message: 'Solo se puede cancelar una orden sin comprobante enviado.',
      });
    }
    const updated = await this.prisma.licensePaymentOrder.update({
      where: { id: order.id },
      data: { status: LicenseOrderStatus.CANCELLED },
    });
    return this.toPublicOrder(updated);
  }

  /**
   * Sube el comprobante y **activa al instante**. El pago queda `UNCONFIRMED`
   * (informacion interna) y el administrador recibe el aviso para revisarlo.
   */
  async uploadEvidence(
    user: TenantUser,
    orderId: string,
    file: EvidenceFile | undefined,
  ) {
    const companyId = requireTenant(user);
    this.requireAdmin(user);
    if (!file || !file.buffer || file.buffer.length === 0) {
      throw new BadRequestException({
        code: 'EVIDENCE_REQUIRED',
        message: 'Adjunta la imagen o el PDF del comprobante.',
      });
    }
    const order = await this.prisma.licensePaymentOrder.findFirst({
      where: { id: orderId, companyId },
      select: {
        id: true,
        status: true,
        activationState: true,
        planCode: true,
        months: true,
        amount: true,
        reference: true,
        catalogVersion: true,
        createdAt: true,
      },
    });
    if (!order) {
      throw new NotFoundException({
        code: 'ORDER_NOT_FOUND',
        message: 'No encontramos esa orden.',
      });
    }
    if (!OPEN_STATUSES.includes(order.status)) {
      const gate = canAcceptEvidence(order.status, order.activationState);
      throw new ConflictException({
        code: gate.code ?? 'ORDER_NOT_PAYABLE',
        message:
          gate.code === 'ORDER_REJECTED' || gate.code === 'ORDER_ALREADY_REVIEWED'
            ? 'Esta orden ya fue revisada y no se puede reutilizar. Genera una orden nueva si necesitas pagar otra vez.'
            : order.status === LicenseOrderStatus.UNCONFIRMED ||
                order.status === LicenseOrderStatus.EVIDENCE_RECEIVED
              ? 'Esta orden ya tiene un comprobante en revision.'
              : 'Esta orden ya no admite comprobantes.',
        status: order.status,
      });
    }

    const inspected = this.storage.inspect(file.buffer, file.originalname ?? '');
    // El dia del **cliente**, no el del servidor: con el dia en UTC el cupo
    // cambiaba a las 8 de la noche hora dominicana.
    const today = new Date(
      startOfLocalDayUtc(new Date(), this.receiptOffsetHours()),
    );
    const uploadsToday = await this.prisma.licensePaymentEvidence.count({
      where: { companyId, createdAt: { gte: today } },
    });
    if (uploadsToday >= MAX_DAILY_UPLOADS) {
      throw new BadRequestException({
        code: 'EVIDENCE_DAILY_LIMIT',
        message:
          'Enviaste el maximo de comprobantes por hoy. Contacta soporte para revisarlo a mano.',
        limit: MAX_DAILY_UPLOADS,
      });
    }

    const duplicated = await this.prisma.licensePaymentEvidence.findFirst({
      where: { companyId, sha256: inspected.sha256 },
      select: { id: true, orderId: true, createdAt: true },
    });
    if (duplicated) {
      throw new ConflictException({
        code: 'EVIDENCE_DUPLICATE',
        message: 'Ese mismo comprobante ya fue enviado. No se activo otra vez.',
        evidenceId: duplicated.id,
      });
    }

    const stored = await this.storage.save({
      companyId,
      buffer: file.buffer,
      ext: inspected.ext,
      sha256: inspected.sha256,
    });

    const before = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: SNAPSHOT_SELECT,
    });
    if (!before) {
      throw new NotFoundException('Empresa no encontrada');
    }
    const targetPlan = await this.prisma.licensePlan.findUnique({
      where: { code: order.planCode },
      select: { active: true },
    });
    // 1) Lectura del comprobante con el motor OCR local (Media Engine).
    const ocr = await this.ocr.extractText({
      buffer: file.buffer,
      mime: inspected.mime,
      fileName: file.originalname ?? 'comprobante',
    });
    let bankValidation: ReturnType<typeof validateBankTransfer> | null = null;
    if (ocr.ok) {
      const offsetHours = this.receiptOffsetHours();
      const parsed = parseBankReceipt(ocr.text, offsetHours);
      const referenceAlreadyUsed = parsed.reference
        ? await this.referenceAlreadyUsed(parsed.reference)
        : false;
      bankValidation = validateBankTransfer({
        parsed,
        order: { amount: order.amount.toNumber(), createdAt: order.createdAt },
        referenceAlreadyUsed,
        // La cuenta autorizada sale de la configuracion, no de una constante
        // aparte: si cambia el numero, el OCR y el cliente no se desincronizan.
        authorizedAccountSuffix: this.authorizedAccountSuffix(),
        utcOffsetHours: offsetHours,
      });
    }
    // 2) Validaciones documentales y antifraude.
    const validation = evaluateEvidence({
      mime: inspected.mime,
      sizeBytes: inspected.sizeBytes,
      order: {
        amount: order.amount.toNumber(),
        months: order.months,
        planActive: targetPlan?.active === true,
      },
      companyActive: before.status === 'ACTIVE',
      extracted: bankValidation?.parsed.amount != null
        ? { amount: bankValidation.parsed.amount }
        : null,
      requireAnalysis:
        String(this.config.get('LICENSE_EVIDENCE_REQUIRE_ANALYSIS') ?? '') === 'true',
    });
    // 3) Solo se activa si **todo** pasa. Sin lectura no hay activacion
    // automatica cuando el OCR es obligatorio: queda para revision.
    // **Nunca** se activa sin leer el comprobante. Antes, con
    // `LICENSE_EVIDENCE_OCR_REQUIRED=false`, cualquier imagen valida activaba la
    // licencia sin mirar el monto: un cliente podia subir una foto cualquiera y
    // quedarse con el plan. La unica excepcion es el banco de pruebas
    // (`NODE_ENV=test`), que usa el interruptor explicito
    // `LICENSE_EVIDENCE_TEST_ACTIVATE`.
    const testActivation =
      process.env.NODE_ENV === 'test' &&
      String(this.config.get('LICENSE_EVIDENCE_TEST_ACTIVATE') ?? '') === 'true';
    const canActivate = bankValidation
      ? validation.passed && bankValidation.passed
      : validation.passed && testActivation;
    const validationRecord = {
      ...validation,
      passed: canActivate,
      ocr: { ok: ocr.ok, engine: ocr.engine, error: ocr.ok ? null : ocr.error },
      bank: bankValidation,
    };

    const result = await this.prisma
      .$transaction(async (tx) => {
        // A1: la orden se bloquea y se revalida **dentro** de la transaccion.
        // Dos subidas simultaneas se serializan aqui: la segunda ya la ve
        // cerrada, asi que no puede sumar los meses otra vez ni pisar el
        // periodo que la primera acaba de aplicar.
        const lockedRows = await tx.$queryRaw<
          Array<{ status: string; activation_state: string | null }>
        >`
          SELECT status::text AS status,
                 activation_state::text AS activation_state
          FROM license_payment_orders
          WHERE id = ${order.id}::uuid
          FOR UPDATE
        `;
        const locked = lockedRows[0];
        if (
          !locked ||
          !OPEN_STATUSES.includes(locked.status as LicenseOrderStatus)
        ) {
          throw new ConflictException({
            code: 'ORDER_NOT_PAYABLE',
            message:
              'Esta orden ya tiene un comprobante o ya no admite pagos. Genera una orden nueva si necesitas pagar otra vez.',
          });
        }
        if (locked.activation_state && locked.activation_state !== 'NONE') {
          throw new ConflictException({
            code: 'ORDER_ALREADY_ACTIVATED',
            message:
              'Esta orden ya fue activada. No se vuelve a aplicar el periodo pagado.',
          });
        }
        // La evidencia se guarda **antes** de activar: el indice unico
        // (empresa + huella) cierra el paso al mismo archivo subido en paralelo.
        const evidence = await tx.licensePaymentEvidence.create({
          data: {
            orderId: order.id,
            companyId,
            channel: 'APP',
            storageKey: stored.storageKey,
            originalName: (file.originalname ?? 'comprobante').slice(0, 180),
            mime: inspected.mime,
            sizeBytes: inspected.sizeBytes,
            sha256: inspected.sha256,
            status: 'RECEIVED',
            uploadedByUserId: user.id,
            // Lo leido del comprobante se guarda ya: sirve para que la misma
            // referencia bancaria no se reutilice en otra orden.
            ...(bankValidation
              ? {
                  extracted: {
                    bank: bankValidation.parsed.bankName,
                    amount: bankValidation.parsed.amount,
                    bankReference: bankValidation.parsed.reference,
                    receivedOn: bankValidation.parsed.occurredAt,
                    source: ocr.engine,
                  } as unknown as Prisma.InputJsonValue,
                  extractedAt: new Date(),
                  extractedSource: ocr.engine.slice(0, 32),
                }
              : {}),
          },
        });
        // La activacion ocurre **dentro** de la transaccion que guarda el
        // comprobante, la orden, la activacion provisional y la auditoria.
        const activation = canActivate
          ? await this.activation.applyPlan({
              companyId,
              planCode: order.planCode,
              months: order.months,
              tx,
            })
          : null;
      const updated = await tx.licensePaymentOrder.update({
        where: { id: order.id },
        data: {
          status: activation
            ? LicenseOrderStatus.UNCONFIRMED
            : LicenseOrderStatus.EVIDENCE_RECEIVED,
          validation: validationRecord as unknown as Prisma.InputJsonValue,
          ...(activation
            ? { periodStart: activation.periodStart, periodEnd: activation.periodEnd }
            : {}),
        },
      });
      if (activation) {
        // Activacion provisional: el cliente ya puede trabajar, pero el pago
        // sigue sin confirmar hasta que soporte lo verifique.
        await this.provisional.markProvisional(tx, {
          orderId: order.id,
          snapshot: snapshotOf(before),
          provisionalUntil: new Date(
            Date.now() +
              provisionalWindowDays(this.config.get<string>('LICENSE_PROVISIONAL_DAYS')) *
                86_400_000,
          ),
          periodStart: activation.periodStart,
          periodEnd: activation.periodEnd,
        });
      }
      await tx.licenseNotificationJob.create({
        data: {
          companyId,
          kind: 'ADMIN_EVIDENCE',
          payload: {
            orderId: order.id,
            evidenceId: evidence.id,
            reference: order.reference,
            planCode: order.planCode,
            amount: order.amount.toNumber(),
            companyName: await companyName(tx, companyId),
            detailed:
              String(this.config.get('LICENSE_WA_ADMIN_DETAILED') ?? '') === 'true',
            operationType: operationLabel(before.planCode, order.planCode, order.months),
            readAmount: bankValidation?.parsed.amount ?? null,
            bankReference: bankValidation?.parsed.reference ?? null,
            occurredAt: bankValidation?.parsed.occurredAt ?? null,
            analysisResult: canActivate
              ? 'valido'
              : `revisar: ${validationRecord.checks
                  .filter((check) => !check.ok)
                  .map((check) => check.code)
                  .join(', ') || 'sin lectura'}`,
            licenseState: activation
              ? 'activada provisionalmente'
              : 'pendiente de revision',
          } satisfies Prisma.InputJsonValue,
        },
      });
      await tx.companyLicenseAuditLog.create({
        data: {
          companyId,
          actorEmail: null,
          action: activation
            ? 'license.payment_evidence_received'
            : 'license.payment_evidence_pending_review',
          reason: `Orden ${order.reference}`,
          before: {
            orderStatus: order.status,
            planCode: order.planCode,
            actorUserId: user.id,
          } satisfies Prisma.InputJsonValue,
          after: {
            orderStatus: updated.status,
            planCode: activation?.planCode ?? order.planCode,
            catalogVersion: activation?.catalogVersion ?? order.catalogVersion,
            periodStart: activation?.periodStart.toISOString() ?? null,
            periodEnd: activation?.periodEnd.toISOString() ?? null,
            evidenceId: evidence.id,
            sha256: inspected.sha256,
            turnedOff: activation?.turnedOff ?? [],
            validationPassed: validationRecord.passed,
            failedChecks: validationRecord.checks
              .filter((check) => !check.ok)
              .map((check) => check.code),
          } satisfies Prisma.InputJsonValue,
        },
      });
      return { order: updated, evidence, activation };
      })
      .catch((error: unknown) => {
        // Dos subidas con el **mismo** archivo a la vez: el indice unico de la
        // evidencia deja pasar a una sola. La otra responde 409, no 500.
        if ((error as { code?: string })?.code === 'P2002') {
          throw new ConflictException({
            code: 'EVIDENCE_DUPLICATE',
            message: 'Ese mismo comprobante ya fue enviado. No se activo otra vez.',
          });
        }
        throw error;
      });

    const activation = result.activation;
    return {
      ok: true,
      activated: activation != null,
      validation: validationRecord,
      order: this.toPublicOrder(result.order),
      evidence: {
        id: result.evidence.id,
        mime: result.evidence.mime,
        sizeBytes: result.evidence.sizeBytes,
        createdAt: result.evidence.createdAt,
      },
      license: activation
        ? {
            status: 'ACTIVE',
            planCode: activation.planCode,
            periodStart: activation.periodStart,
            periodEnd: activation.periodEnd,
            months: activation.months,
          }
        : null,
      paymentStatus: activation ? 'UNCONFIRMED' : 'PENDING_REVIEW',
      message: activation
        ? 'Licencia activada. El comprobante quedo en revision para confirmar el pago.'
        : 'Recibimos tu comprobante, pero no pudimos validarlo automaticamente. Un administrador lo revisa antes de activar el plan.',
    };
  }

  async getEvidence(user: TenantUser, orderId: string, evidenceId: string) {
    const companyId = requireTenant(user);
    const evidence = await this.prisma.licensePaymentEvidence.findFirst({
      where: { id: evidenceId, orderId, companyId },
    });
    if (!evidence) {
      throw new NotFoundException({
        code: 'EVIDENCE_NOT_FOUND',
        message: 'No encontramos ese comprobante.',
      });
    }
    const buffer = await this.storage.read(evidence.storageKey);
    return { evidence, buffer };
  }

  /** Descarga para el administrador (el puente ya valido su secreto). */
  async getAdminEvidence(orderId: string, evidenceId: string) {
    const evidence = await this.prisma.licensePaymentEvidence.findFirst({
      where: { id: evidenceId, orderId },
    });
    if (!evidence) {
      throw new NotFoundException({
        code: 'EVIDENCE_NOT_FOUND',
        message: 'No encontramos ese comprobante.',
      });
    }
    const buffer = await this.storage.read(evidence.storageKey);
    return { evidence, buffer };
  }

  /**
   * Uso interno: marcar el pago con motivo. **Sin ruta HTTP a proposito**: el
   * CRM concilia por `POST /license/integrations/crm/:companyId/commands`, que
   * valida version, idempotencia y motivo en una sola transaccion. Si algun dia
   * se expone en una ruta nueva, debe reutilizar esa logica, no esta.
   */
  async setPaymentStatus(input: {
    companyId: string;
    orderId: string;
    status: LicenseOrderStatus;
    reason?: string | null;
    actor?: string | null;
  }) {
    const order = await this.prisma.licensePaymentOrder.findFirst({
      where: { id: input.orderId, companyId: input.companyId },
      select: { id: true, status: true, reference: true },
    });
    if (!order) {
      throw new NotFoundException({
        code: 'ORDER_NOT_FOUND',
        message: 'Esa orden no pertenece a la empresa.',
      });
    }
    const reviewed =
      input.status === LicenseOrderStatus.SETTLED ||
      input.status === LicenseOrderStatus.REJECTED;
    const updated = await this.prisma.licensePaymentOrder.update({
      where: { id: order.id },
      data: {
        status: input.status,
        // Quien tomo la decision queda en la propia orden, no solo en la
        // auditoria: es lo que se ve en el historial de cobros.
        ...(reviewed
          ? {
              reviewedBy: (input.actor ?? 'soporte').slice(0, 120),
              reviewedAt: new Date(),
              reviewNote: (input.reason ?? '').slice(0, 500) || null,
            }
          : {}),
      },
    });
    // Confirmar no vuelve a sumar meses; rechazar devuelve la licencia a como
    // estaba antes de esta activacion (solo si nadie la movio despues).
    let activation: { changed?: boolean; reverted?: boolean } = {};
    if (input.status === LicenseOrderStatus.SETTLED) {
      activation = await this.prisma.$transaction((tx) =>
        this.provisional.confirm(tx, order.id),
      );
    } else if (input.status === LicenseOrderStatus.REJECTED) {
      activation = await this.prisma.$transaction((tx) =>
        this.provisional.revert(tx, { orderId: order.id }),
      );
    }
    await this.prisma.companyLicenseAuditLog.create({
      data: {
        companyId: input.companyId,
        actorEmail: input.actor ?? null,
        action: 'license.payment_status',
        reason: (input.reason ?? '').slice(0, 500) || null,
        before: { orderStatus: order.status } satisfies Prisma.InputJsonValue,
        after: {
          orderStatus: updated.status,
          reference: order.reference,
        } satisfies Prisma.InputJsonValue,
      },
    });
    return { ok: true, order: this.toPublicOrder(updated), activation };
  }

  /** Lista para el CRM: pendientes de verificar, con su comprobante. */
  async listAdminOrders(params: {
    companyId?: string;
    status?: string;
    limit?: number;
  }) {
    const status = String(params.status ?? '').trim().toUpperCase();
    const where: Prisma.LicensePaymentOrderWhereInput = {};
    if (params.companyId) where.companyId = params.companyId;
    if (status && Object.values(LicenseOrderStatus).includes(status as LicenseOrderStatus)) {
      where.status = status as LicenseOrderStatus;
    }
    const orders = await this.prisma.licensePaymentOrder.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(params.limit ?? 50, 1), 200),
      include: {
        company: { select: { id: true, name: true, slug: true, planCode: true } },
        evidences: {
          select: {
            id: true,
            mime: true,
            sizeBytes: true,
            status: true,
            createdAt: true,
            originalName: true,
            extracted: true,
            extractedAt: true,
            extractedSource: true,
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    const operations = await describeOrders(this.prisma, orders);
    return {
      orders: orders.map((order) => ({
        ...this.toPublicOrder(order),
        companyName: order.company?.name ?? null,
        companySlug: order.company?.slug ?? null,
        ...(operations.get(order.id) ?? {}),
        evidences: order.evidences,
      })),
    };
  }

  /**
   * Guarda lo que el agente de APPYRA CRM leyo del comprobante.
   *
   * Es **informacion de apoyo**: no cambia el estado de la orden ni activa la
   * licencia. Aprobar exige comprobar que el dinero llego.
   */
  async saveEvidenceInsights(input: {
    orderId: string;
    evidenceId: string;
    raw: Record<string, unknown>;
  }) {
    const evidence = await this.prisma.licensePaymentEvidence.findFirst({
      where: { id: input.evidenceId, orderId: input.orderId },
      select: {
        id: true,
        companyId: true,
        orderId: true,
        order: {
          select: {
            id: true,
            status: true,
            amount: true,
            months: true,
            planCode: true,
            validation: true,
          },
        },
      },
    });
    if (!evidence) {
      throw new NotFoundException({
        code: 'EVIDENCE_NOT_FOUND',
        message: 'Ese comprobante no pertenece a la orden indicada.',
      });
    }
    // Una orden ya rechazada o cancelada no se vuelve a analizar: seria
    // reutilizar el mismo comprobante para pedir otra activacion.
    if (['REJECTED', 'CANCELLED', 'EXPIRED'].includes(evidence.order.status)) {
      throw new ConflictException({
        code: 'ORDER_ALREADY_REVIEWED',
        message: 'Esa orden ya fue resuelta; no se puede reutilizar.',
        status: evidence.order.status,
      });
    }

    let insights: ReturnType<typeof normalizeEvidenceInsights>;
    try {
      insights = normalizeEvidenceInsights(input.raw);
    } catch (error) {
      throw new BadRequestException({
        code: 'INVALID_INSIGHTS',
        message:
          error instanceof InvalidInsightsError
            ? `El analisis trae un dato invalido (${error.message}).`
            : 'El analisis del comprobante no es valido.',
      });
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const saved = await tx.licensePaymentEvidence.update({
        where: { id: evidence.id },
        data: {
          extracted: insights as unknown as Prisma.InputJsonValue,
          extractedAt: new Date(),
          extractedSource: insights.source,
        },
        select: {
          id: true,
          extracted: true,
          extractedAt: true,
          extractedSource: true,
        },
      });
      // Comparacion con la orden: si el importe leido no cuadra, se deja
      // marcado para que soporte lo vea. **No** se revoca nada aqui: solo una
      // decision humana revierte una activacion.
      const previous = (evidence.order.validation ?? null) as
        | { checks?: Array<{ code: string; ok: boolean; detail?: string }> }
        | null;
      if (insights.amount != null) {
        const expected = evidence.order.amount.toNumber();
        const matches = Math.abs(insights.amount - expected) <= Math.max(1, expected * 0.01);
        const checks = (previous?.checks ?? []).filter(
          (check) => check.code !== 'EXTRACTED_AMOUNT_MATCHES',
        );
        checks.push({
          code: 'EXTRACTED_AMOUNT_MATCHES',
          ok: matches,
          detail: `${insights.amount} vs ${expected}`,
        });
        await tx.licensePaymentOrder.update({
          where: { id: evidence.order.id },
          data: {
            validation: {
              ...(previous ?? {}),
              checks,
              analysis: matches ? 'MATCH' : 'MISMATCH',
              extractedAmount: insights.amount,
              validatedAt: new Date().toISOString(),
            } as unknown as Prisma.InputJsonValue,
            ...(matches
              ? {}
              : {
                  reviewNote: `El importe del comprobante (${insights.amount}) no coincide con la orden (${expected}).`.slice(
                    0,
                    500,
                  ),
                }),
          },
          select: { id: true },
        });
      }
      await tx.companyLicenseAuditLog.create({
        data: {
          companyId: evidence.companyId,
          actorEmail: null,
          action: 'license.payment_evidence_insights',
          reason: `Comprobante ${evidence.id}`,
          after: {
            evidenceId: evidence.id,
            orderId: evidence.orderId,
            amount: insights.amount,
            bankReference: insights.bankReference,
            source: insights.source,
          } satisfies Prisma.InputJsonValue,
        },
      });
      return saved;
    });
    return { ok: true, evidence: updated };
  }

  /** Desfase horario del comprobante (por defecto, el de Republica Dominicana). */
  private receiptOffsetHours() {
    const parsed = Number.parseFloat(
      value(this.config, 'LICENSE_RECEIPT_UTC_OFFSET_HOURS'),
    );
    return Number.isFinite(parsed) && Math.abs(parsed) <= 14
      ? parsed
      : RECEIPT_UTC_OFFSET_HOURS;
  }

  /**
   * Ultimos 4 digitos de la cuenta de cobro configurada.
   *
   * `null` = hay configuracion pero es invalida. En ese caso la validacion
   * **falla** y el comprobante queda para revision: nunca se omite el control
   * de la cuenta destino por un error de configuracion.
   */
  private authorizedAccountSuffix(): string | null {
    const configured = value(this.config, 'LICENSE_BANK_ACCOUNT');
    if (!configured) return AUTHORIZED_ACCOUNT_SUFFIX;
    const digits = configured.replace(/\D/g, '');
    if (digits.length < 4) {
      this.logger.warn(
        'LICENSE_BANK_ACCOUNT invalida: se esperan al menos 4 digitos. Los comprobantes iran a revision.',
      );
      return null;
    }
    return digits.slice(-4);
  }

  /**
   * Busca la referencia bancaria en **todas** las empresas: la cuenta de cobro
   * es una sola, asi que dos negocios del mismo dueno no pueden reutilizar el
   * mismo comprobante.
   *
   * Si la comprobacion falla, se trata como reutilizada (fallo cerrado): se
   * prefiere mandar el comprobante a revision antes que activar a ciegas.
   */
  private async referenceAlreadyUsed(reference: string) {
    try {
      const found = await this.prisma.licensePaymentEvidence.findFirst({
        where: { extracted: { path: ['bankReference'], equals: reference } },
        select: { id: true },
      });
      return found != null;
    } catch (error) {
      this.logger.warn(
        `No se pudo comprobar la referencia bancaria: ${
          (error as Error)?.message ?? 'error'
        }`,
      );
      return true;
    }
  }

  private async expireStaleOrders(companyId: string, now: Date) {
    await this.prisma.licensePaymentOrder.updateMany({
      where: {
        companyId,
        status: { in: OPEN_STATUSES },
        expiresAt: { lt: now },
      },
      data: { status: LicenseOrderStatus.EXPIRED },
    });
  }

  private async generateReference() {
    const year = new Date().getUTCFullYear();
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const reference = `FP-${year}-${String(randomInt(0, 1_000_000)).padStart(6, '0')}`;
      const existing = await this.prisma.licensePaymentOrder.findUnique({
        where: { reference },
        select: { id: true },
      });
      if (!existing) return reference;
    }
    throw new ConflictException({
      code: 'ORDER_REFERENCE_UNAVAILABLE',
      message: 'No se pudo generar la referencia. Intenta de nuevo.',
    });
  }

  private toPublicOrder(
    order: {
      id: string;
      planCode: string;
      catalogVersion: number;
      currency: string;
      amount: Prisma.Decimal;
      months: number;
      status: LicenseOrderStatus;
      reference: string;
      expiresAt: Date;
      periodStart?: Date | null;
      periodEnd?: Date | null;
      createdAt?: Date;
      notes?: string | null;
    },
    planName?: string | null,
  ) {
    return {
      id: order.id,
      planCode: order.planCode,
      planName: planName ?? null,
      catalogVersion: order.catalogVersion,
      currency: order.currency,
      amount: order.amount.toNumber(),
      months: order.months,
      status: order.status,
      reference: order.reference,
      expiresAt: order.expiresAt,
      periodStart: order.periodStart ?? null,
      periodEnd: order.periodEnd ?? null,
      createdAt: order.createdAt ?? null,
      notes: order.notes ?? null,
    };
  }

  private requireAdmin(user: TenantUser) {
    if (!isAdminLike(user)) {
      throw new BadRequestException({
        code: 'ADMIN_REQUIRED',
        message: 'Solo el propietario o un administrador puede gestionar la licencia.',
      });
    }
  }
}

export function addOrderMonths(from: Date, months: number) {
  return addMonths(from, months);
}

function normalizeMonths(value: unknown) {
  const parsed = Number.parseInt(String(value ?? '1'), 10);
  if (!Number.isFinite(parsed)) return 1;
  return Math.min(Math.max(parsed, 1), 12);
}

/** Redondeo a centavos: el importe de una transferencia no lleva fracciones raras. */
function operationLabel(
  companyPlan: string | null,
  orderPlan: string,
  months: number,
) {
  const current = (companyPlan ?? '').trim().toLowerCase();
  const target = orderPlan.trim().toLowerCase();
  if (!current) return 'compra';
  if (current === target) return months > 1 ? 'meses adelantados' : 'renovacion';
  return 'mejora';
}

function round2(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function value(config: ConfigService, key: string) {
  return (
    config.get<string>(key) ??
    process.env[key] ??
    ''
  ).trim();
}

async function companyName(
  tx: Prisma.TransactionClient,
  companyId: string,
) {
  const company = await tx.company.findUnique({
    where: { id: companyId },
    select: { name: true },
  });
  return company?.name ?? null;
}


