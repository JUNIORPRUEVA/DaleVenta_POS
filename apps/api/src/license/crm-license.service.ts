import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { describeOrders } from './orders/license-order-insights';
import { LicenseProvisionalService } from './orders/license-provisional.service';
import { LicenseService } from './license.service';
import { LicenseActivationService } from './orders/license-activation.service';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const invalid = () => { throw new BadRequestException('invalid_crm_command'); };
export function parseCrmCommand(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
  const v = value as Record<string, unknown>;
  if (Object.keys(v).some(k => !['operationId', 'expectedVersion', 'action', 'reason', 'fields', 'confirmationName', 'actorId', 'serviceId', 'paymentOrderId', 'paymentStatus'].includes(k))) return invalid();
  if (typeof v.operationId !== 'string' || !UUID.test(v.operationId) || typeof v.serviceId !== 'string' || !UUID.test(v.serviceId) || typeof v.actorId !== 'string' || !/^usr_[a-f0-9]{24}$/.test(v.actorId)) return invalid();
  if (typeof v.expectedVersion !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(v.expectedVersion) || !Number.isFinite(Date.parse(v.expectedVersion))) return invalid();
  if (!['update', 'suspend', 'reactivate', 'revoke'].includes(String(v.action)) || typeof v.reason !== 'string' || v.reason.trim().length < 5 || v.reason.length > 500) return invalid();
  const fields: Record<string, string | number | boolean> = {};
  if (v.action === 'update') {
    if (!v.fields || typeof v.fields !== 'object' || Array.isArray(v.fields)) return invalid();
    for (const [k, x] of Object.entries(v.fields)) {
      if (k === 'name' && typeof x === 'string' && x.trim().length >= 2 && x.trim().length <= 160) fields[k] = x.trim();
      else if (k === 'notes' && typeof x === 'string' && x.length <= 2000) fields[k] = x.trim();
      else if (['maxUsers', 'maxProducts', 'maxWarehouses'].includes(k) && typeof x === 'number' && Number.isSafeInteger(x) && x >= 1 && x <= 1000000) fields[k] = x;
      else if (['allowEcf', 'allowTaxes', 'allowWholesale', 'allowUom', 'allowMultiWarehouse'].includes(k) && typeof x === 'boolean') fields[k] = x;
      else return invalid();
    }
  } else if (v.fields !== undefined) return invalid();
  const payment = parsePaymentMark(v, String(v.action));
  if (v.action === 'update' && !Object.keys(fields).length && !payment) return invalid();
  if (v.action === 'revoke' ? typeof v.confirmationName !== 'string' || v.confirmationName.length > 160 : v.confirmationName !== undefined) return invalid();
  return {
    operationId: v.operationId.toLowerCase(), expectedVersion: v.expectedVersion,
    serviceId: v.serviceId.toLowerCase(), actorId: v.actorId, action: String(v.action),
    reason: v.reason.trim(), fields: Object.fromEntries(Object.entries(fields).sort()),
    confirmationName: v.action === 'revoke' ? String(v.confirmationName).trim() : null,
    paymentOrderId: payment?.orderId ?? null, paymentStatus: payment?.status ?? null,
  };
}

/** Pago recibido / no confirmado: siempre con orden concreta y motivo obligatorio. */
function parsePaymentMark(v: Record<string, unknown>, action: string) {
  if (v.paymentOrderId === undefined && v.paymentStatus === undefined) return null;
  if (!['update', 'reactivate'].includes(action)) return invalid();
  if (typeof v.paymentOrderId !== 'string' || !UUID.test(v.paymentOrderId)) return invalid();
  const status = String(v.paymentStatus ?? '').trim().toUpperCase();
  if (!['SETTLED', 'UNCONFIRMED', 'REJECTED'].includes(status)) return invalid();
  return { orderId: v.paymentOrderId.toLowerCase(), status: status as 'SETTLED' | 'UNCONFIRMED' | 'REJECTED' };
}

/** Uses the same effective status rules as LicenseService, including unbounded legacy periods. */
export function crmStatusWhere(status: string, now: Date): Prisma.CompanyWhereInput {
  switch (status) {
    case 'ACTIVA': return { licenseStatus: 'ACTIVE', OR: [{ licenseExpiresAt: null }, { licenseExpiresAt: { gte: now } }] };
    case 'PRUEBA': return { licenseStatus: 'TRIAL', OR: [{ trialEndsAt: null }, { trialEndsAt: { gte: now } }] };
    case 'BLOQUEADA': return { licenseStatus: 'BLOCKED' };
    case 'VENCIDA': return { OR: [{ licenseStatus: 'EXPIRED' }, { licenseStatus: 'ACTIVE', licenseExpiresAt: { lt: now } }, { licenseStatus: 'TRIAL', trialEndsAt: { lt: now } }] };
    case '': return {};
    default: throw new BadRequestException('invalid_status');
  }
}

@Injectable()
export class CrmLicenseService {
  constructor(private readonly prisma: PrismaService, private readonly licenses: LicenseService, private readonly config: ConfigService,
    private readonly provisional: LicenseProvisionalService = new LicenseProvisionalService(),
    private readonly activation: LicenseActivationService = new LicenseActivationService(prisma)) {}

  enabled() { return String(this.config.get('CRM_LICENSE_MANAGEMENT_ENABLED') ?? '') === 'true'; }

  private async projection(id: string, tx: Prisma.TransactionClient, includeCommercial = false) {
    const row = await this.licenses.getCompanyLicenseStatus(id, tx);
    const commercial = includeCommercial ? {
      plan: row.planCode ? await tx.licensePlan.findUnique({ where: { code: row.planCode }, select: {
        code: true, name: true, maxUsers: true, maxProducts: true, maxWarehouses: true,
        ecf: true, taxes: true, wholesale: true, uom: true, multiWarehouse: true,
      } }) : null,
      override: await tx.licenseCompanyOverride.findUnique({ where: { companyId: id }, select: {
        extraUsers: true, extraProducts: true, extraWarehouses: true, allowEcf: true,
        allowTaxes: true, allowWholesale: true, allowUom: true, allowMultiWarehouse: true, expiresAt: true,
      } }),
    } : null;
    const result = { ...row, commercial };
    // An expired TRIAL still has its original trial period. Leave legacy DTOs unchanged.
    if (row.rawStatus !== 'TRIAL') return result;
    return { ...result, periodStartedAt: row.trialStartedAt, periodEndsAt: row.trialEndsAt,
      daysRemaining: row.trialEndsAt ? Math.ceil((row.trialEndsAt.getTime() - Date.now()) / 86400000) : null };
  }

  async detail(id: string) {
    if (!UUID.test(id)) throw new BadRequestException('invalid_company_id');
    return this.prisma.$transaction(async tx => {
      if (!await tx.company.findUnique({ where: { id }, select: { id: true } })) throw new NotFoundException('company_not_found');
      const license = await this.projection(id, tx, true);
      const auditLogs = await tx.companyLicenseAuditLog.findMany({ where: { companyId: id }, take: 25, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }], select: { action: true, reason: true, createdAt: true } });
      return { ...license, auditLogs };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead, timeout: 15000 });
  }

  async list(q: Record<string, unknown>) {
    if (Object.keys(q).some(k => !['page', 'limit', 'query', 'status'].includes(k))) throw new BadRequestException('unsupported_filter');
    const page = Number(q.page ?? 1), limit = Number(q.limit ?? 25), query = q.query ?? '';
    if (!Number.isSafeInteger(page) || page < 1 || page > 40001 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100 || typeof query !== 'string' || query.length > 160 || (q.status !== undefined && typeof q.status !== 'string')) throw new BadRequestException('invalid_pagination');
    const where: Prisma.CompanyWhereInput = { AND: [crmStatusWhere(String(q.status ?? ''), new Date()), ...(query.trim() ? [{ OR: ['name', 'slug', 'licenseKey'].map(k => ({ [k]: { contains: query.trim(), mode: 'insensitive' } })) } as Prisma.CompanyWhereInput] : [])] };
    return this.prisma.$transaction(async tx => {
      const total = await tx.company.count({ where });
      const rows = await tx.company.findMany({ where, skip: (page - 1) * limit, take: limit, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }], select: { id: true } });
      const items = await Promise.all(rows.map(row => this.projection(row.id, tx)));
      return { total, page, limit, items };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead, timeout: 15000 });
  }

  async command(companyId: string, value: unknown) {
    if (!this.enabled()) throw new ForbiddenException('crm_management_disabled');
    if (!UUID.test(companyId)) throw new BadRequestException('invalid_company_id');
    companyId = companyId.toLowerCase();
    const command = parseCrmCommand(value);
    const requestHash = createHash('sha256').update(JSON.stringify([companyId.toLowerCase(), command])).digest('hex');
    try {
      const result = await this.prisma.$transaction(async tx => {
        // Same lock order and names as the existing user/product quota guards.
        for (const resource of ['users', 'products']) await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext(${`daleventas:quota:${resource}:${companyId}`})) IS NULL AS locked`;
        // Serialize mutations of this company before checking either version or receipt.
        await tx.$queryRaw`SELECT id FROM companies WHERE id = ${companyId}::uuid FOR UPDATE`;
        const company = await tx.company.findUnique({ where: { id: companyId } });
        if (!company) throw new NotFoundException('company_not_found');
        const receipt = await tx.companyLicenseAuditLog.findUnique({ where: { id: command.operationId } });
        if (receipt) {
          const meta = (receipt.after as any)?._crmCommand;
          if (receipt.companyId !== company.id || meta?.requestHash !== requestHash) throw new ConflictException('operation_id_reused');
          return { license: await this.projection(companyId, tx, true), operationId: command.operationId, deduplicated: true };
        }
        if (company.updatedAt.toISOString() !== command.expectedVersion) throw new ConflictException('license_changed_reload');
        const before = await this.projection(companyId, tx, true);
        const data: Prisma.CompanyUpdateInput = { updatedAt: new Date(Math.max(Date.now(), company.updatedAt.getTime() + 1)) };
        if (command.action === 'update') {
          for (const key of ['maxUsers', 'maxProducts'] as const) {
            const count = key === 'maxUsers' ? before.usage.users : before.usage.products;
            if (command.fields[key] !== undefined && Number(command.fields[key]) < count) throw new ConflictException('limit_below_current_usage');
            if (command.fields[key] !== undefined) data[key] = Number(command.fields[key]);
          }
          if (command.fields.name !== undefined) data.name = String(command.fields.name);
          if (command.fields.notes !== undefined) data.licenseNotes = String(command.fields.notes);
          if (command.fields.maxWarehouses !== undefined) {
            const activeWarehouses = await tx.warehouse.count({ where: { companyId, isActive: true } });
            if (Number(command.fields.maxWarehouses) < activeWarehouses) throw new ConflictException('limit_below_current_usage');
            data.maxWarehouses = Number(command.fields.maxWarehouses);
          }
          const plan = before.commercial?.plan;
          const additions: Prisma.LicenseCompanyOverrideUncheckedUpdateInput = {};
          if (plan) {
            for (const [field, extra] of [['maxUsers', 'extraUsers'], ['maxProducts', 'extraProducts'], ['maxWarehouses', 'extraWarehouses']] as const) {
              if (command.fields[field] === undefined) continue;
              const desired = Number(command.fields[field]);
              if (desired < plan[field]) throw new ConflictException('limit_below_plan');
              additions[extra] = desired - plan[field];
            }
          }
          for (const field of ['allowEcf', 'allowTaxes', 'allowWholesale', 'allowUom', 'allowMultiWarehouse'] as const) {
            if (command.fields[field] !== undefined) additions[field] = Boolean(command.fields[field]);
          }
          if (Object.keys(additions).length) {
            const previous = before.commercial?.override;
            if (previous?.expiresAt && previous.expiresAt <= new Date()) throw new ConflictException('override_expired');
            await tx.licenseCompanyOverride.upsert({ where: { companyId },
              create: { ...additions, companyId, grantedBy: command.actorId } as Prisma.LicenseCompanyOverrideUncheckedCreateInput,
              update: { ...additions, grantedBy: command.actorId, grantedAt: new Date() },
            });
          }
        } else if (command.action === 'reactivate') {
          if (company.licenseStatus !== 'BLOCKED' || !company.licenseKey || !company.licenseExpiresAt || company.licenseExpiresAt <= new Date()) throw new ConflictException('paid_period_required');
          Object.assign(data, { status: 'ACTIVE', licenseStatus: 'ACTIVE', licenseBlockedAt: null });
        } else {
          if (command.action === 'suspend' && !['ACTIVE', 'TRIAL'].includes(before.status)) throw new ConflictException('license_not_active');
          if (command.action === 'revoke' && command.confirmationName !== company.name) throw new BadRequestException('confirmation_name_mismatch');
          Object.assign(data, { status: 'SUSPENDED', licenseStatus: 'BLOCKED', licenseBlockedAt: new Date() });
          if (command.action === 'revoke') Object.assign(data, { licenseKey: null, licenseExpiresAt: null });
          await tx.authSession.updateMany({ where: { companyId, revokedAt: null }, data: { revokedAt: new Date() } });
        }
        await tx.company.update({ where: { id: companyId }, data });
        if (command.fields.name !== undefined) await this.licenses.syncAppConfigCompanyName(tx, companyId, String(command.fields.name));
        if (command.paymentOrderId && command.paymentStatus) {
          await tx.$queryRaw`SELECT id FROM license_payment_orders WHERE id=${command.paymentOrderId}::uuid AND company_id=${companyId}::uuid FOR UPDATE`;
          const order = await tx.licensePaymentOrder.findFirst({ where: { id: command.paymentOrderId, companyId },
            include: { evidences: { select: { id: true } } } });
          if (!order) throw new NotFoundException('payment_order_not_found');
          if (!['EVIDENCE_RECEIVED', 'UNCONFIRMED'].includes(order.status) || order.evidences.length === 0) {
            throw new ConflictException('payment_not_reviewable');
          }
          const reviewed = command.paymentStatus === 'SETTLED' || command.paymentStatus === 'REJECTED';
          await tx.licensePaymentOrder.update({ where: { id: order.id }, data: {
            status: command.paymentStatus,
            ...(reviewed ? {
              reviewedBy: `crm:${command.actorId}`.slice(0, 120),
              reviewedAt: new Date(),
              reviewNote: command.reason.slice(0, 500),
            } : {}),
          } });
          // «Pagada» consolida la activacion provisional (sin volver a sumar
          // meses). «Pago no acreditado» devuelve la licencia a su estado
          // legitimo anterior, solo si nadie la movio despues.
          if (command.paymentStatus === 'SETTLED') {
            if (order.activationState === 'NONE') {
              const applied = await this.activation.applyPlan({ companyId, planCode: order.planCode, months: order.months, tx });
              await tx.licensePaymentOrder.update({ where: { id: order.id }, data: {
                periodStart: applied.periodStart, periodEnd: applied.periodEnd,
              } });
            } else if (order.activationState !== 'PROVISIONAL' && order.activationState !== 'CONFIRMED') {
              throw new ConflictException('payment_not_reviewable');
            }
            await this.provisional.confirm(tx, order.id);
          } else if (command.paymentStatus === 'REJECTED') {
            await this.provisional.revert(tx, { orderId: order.id });
          }
        }
        const after = await this.projection(companyId, tx, true);
        const snapshot = (v: typeof after) => ({ name: v.companyName, status: v.status, rawStatus: v.rawStatus, expiresAt: v.licenseExpiresAt?.toISOString() ?? null, maxUsers: v.limits.maxUsers, maxProducts: v.limits.maxProducts, maxWarehouses: v.limits.maxWarehouses, notes: v.notes, version: v.updatedAt.toISOString(), commercial: JSON.parse(JSON.stringify(v.commercial ?? null)) });
        // Mandatory receipt and audit in the SAME transaction. No raw keys or payment data.
        await tx.companyLicenseAuditLog.create({ data: {
          id: command.operationId, companyId, actorEmail: `crm:${command.actorId}`,
          action: `license.crm.${command.action}`, reason: command.reason,
          before: snapshot(before), after: { ...snapshot(after), _crmCommand: { requestHash, actorId: command.actorId, serviceId: command.serviceId, action: command.action, paymentOrderId: command.paymentOrderId, paymentStatus: command.paymentStatus } },
        } });
        return { license: after, operationId: command.operationId, deduplicated: false };
      }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted, timeout: 15000 });
      if (!result.deduplicated) this.licenses.publishCrmLicenseChange(companyId, command.action, result.license);
      return result;
    } catch (error) {
      if ((error as any)?.code === 'P2002') throw new ConflictException('operation_id_reused');
      throw error;
    }
  }

  /** Ordenes de pago con su comprobante, para revisar desde el CRM. */
  async orders(q: Record<string, unknown>) {
    if (Object.keys(q).some(k => !['status', 'companyId', 'orderId', 'limit', 'offset', 'paymentState'].includes(k))) throw new BadRequestException('unsupported_filter');
    const where: Prisma.LicensePaymentOrderWhereInput = {};
    if (q.companyId !== undefined) { if (typeof q.companyId !== 'string' || !UUID.test(q.companyId)) throw new BadRequestException('invalid_company_id'); where.companyId = q.companyId.toLowerCase(); }
    if (q.orderId !== undefined) { if (typeof q.orderId !== 'string' || !UUID.test(q.orderId)) throw new BadRequestException('invalid_order_id'); where.id = q.orderId.toLowerCase(); }
    if (q.status !== undefined) { const status = String(q.status).toUpperCase(); if (!['CREATED', 'AWAITING_TRANSFER', 'EVIDENCE_RECEIVED', 'UNCONFIRMED', 'SETTLED', 'REJECTED', 'CANCELLED', 'EXPIRED'].includes(status)) throw new BadRequestException('invalid_status'); where.status = status as any; }
    if (q.paymentState !== undefined) {
      if (q.status !== undefined || !['pending', 'review', 'confirmed', 'rejected'].includes(String(q.paymentState))) throw new BadRequestException('invalid_status');
      where.status = q.paymentState === 'pending' ? { in: ['CREATED', 'AWAITING_TRANSFER', 'EVIDENCE_RECEIVED', 'UNCONFIRMED'] }
        : q.paymentState === 'review' ? { in: ['EVIDENCE_RECEIVED', 'UNCONFIRMED'] }
        : q.paymentState === 'confirmed' ? 'SETTLED' : 'REJECTED';
    }
    const limit = Number(q.limit ?? 50);
    const offset = Number(q.offset ?? 0);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 200 || !Number.isSafeInteger(offset) || offset < 0 || offset > 1000000) throw new BadRequestException('invalid_pagination');
    const total = await this.prisma.licensePaymentOrder.count({ where });
    const rows = await this.prisma.licensePaymentOrder.findMany({ where, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }], take: limit, skip: offset,
      include: { company: { select: { id: true, name: true, slug: true, planCode: true } }, evidences: { select: { id: true, orderId: true, mime: true, sizeBytes: true, status: true, createdAt: true, originalName: true, extracted: true, extractedAt: true, extractedSource: true }, orderBy: { createdAt: 'desc' } } } });    // El agente sabe de un golpe si es renovacion o mejora, y cuanto saldo se aplico.
    const operations = await describeOrders(this.prisma, rows);
    return { total, limit, offset, items: rows.map(row => ({ id: row.id, companyId: row.companyId, companyName: row.company?.name ?? null, companySlug: row.company?.slug ?? null,
      ...(operations.get(row.id) ?? {}),
      planCode: row.planCode, catalogVersion: row.catalogVersion, amount: row.amount.toNumber(), currency: row.currency, months: row.months,
      status: row.status, reference: row.reference, expiresAt: row.expiresAt, periodStart: row.periodStart, periodEnd: row.periodEnd, createdAt: row.createdAt, reviewedAt: row.reviewedAt,
      activationState: row.activationState, provisionalUntil: row.provisionalUntil,
      evidences: row.evidences })) };
  }

  /**
   * Excepciones autorizadas: mas usuarios/productos/almacenes o una funcion
   * que el plan no incluye, sin cambiar de plan. Queda auditado con su motivo.
   */
  async override(companyId: string, body: Record<string, unknown>) {
    if (!this.enabled()) throw new ForbiddenException('crm_management_disabled');
    if (!UUID.test(companyId)) throw new BadRequestException('invalid_company_id');
    const id = companyId.toLowerCase();
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new BadRequestException('invalid_override');
    const allowed = ['extraUsers', 'extraProducts', 'extraWarehouses', 'allowEcf', 'allowTaxes', 'allowWholesale', 'allowUom', 'allowMultiWarehouse', 'note', 'expiresAt', 'actorId', 'reason'];
    if (Object.keys(body).some(k => !allowed.includes(k))) throw new BadRequestException('invalid_override');
    const data = parseOverride(body);
    return this.prisma.$transaction(async tx => {
      const company = await tx.company.findUnique({ where: { id }, select: { id: true, name: true } });
      if (!company) throw new NotFoundException('company_not_found');
      const before = await tx.licenseCompanyOverride.findUnique({ where: { companyId: id } });
      const saved = await tx.licenseCompanyOverride.upsert({
        where: { companyId: id },
        create: { companyId: id, ...data.values, grantedBy: data.actorId, note: data.note, expiresAt: data.expiresAt },
        update: { ...data.values, grantedBy: data.actorId, note: data.note, expiresAt: data.expiresAt, grantedAt: new Date() },
      });
      await tx.companyLicenseAuditLog.create({ data: { companyId: id, actorEmail: `crm:${data.actorId}`,
        action: 'license.override.granted', reason: data.reason,
        before: before ? overrideSnapshot(before) : undefined,
        after: overrideSnapshot(saved) } });
      return { ok: true, override: overrideSnapshot(saved) };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted, timeout: 15000 });
  }

  async clearOverride(companyId: string, body: Record<string, unknown>) {
    if (!this.enabled()) throw new ForbiddenException('crm_management_disabled');
    if (!UUID.test(companyId)) throw new BadRequestException('invalid_company_id');
    const id = companyId.toLowerCase();
    const reason = typeof body?.reason === 'string' ? body.reason.trim() : '';
    if (reason.length < 5 || reason.length > 500) throw new BadRequestException('invalid_reason');
    return this.prisma.$transaction(async tx => {
      const before = await tx.licenseCompanyOverride.findUnique({ where: { companyId: id } });
      if (!before) throw new NotFoundException('override_not_found');
      await tx.licenseCompanyOverride.delete({ where: { companyId: id } });
      await tx.companyLicenseAuditLog.create({ data: { companyId: id, action: 'license.override.cleared', reason, before: overrideSnapshot(before) } });
      return { ok: true };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted, timeout: 15000 });
  }
}

function parseOverride(body: Record<string, unknown>) {
  const values: { extraUsers?: number; extraProducts?: number; extraWarehouses?: number; allowEcf?: boolean; allowTaxes?: boolean; allowWholesale?: boolean; allowUom?: boolean; allowMultiWarehouse?: boolean } = {};
  for (const key of ['extraUsers', 'extraProducts', 'extraWarehouses'] as const) {
    const raw = body[key];
    if (raw === undefined) continue;
    if (typeof raw !== 'number' || !Number.isSafeInteger(raw) || raw < 0 || raw > 1000000) throw new BadRequestException('invalid_override');
    values[key] = raw;
  }
  for (const key of ['allowEcf', 'allowTaxes', 'allowWholesale', 'allowUom', 'allowMultiWarehouse'] as const) {
    const raw = body[key];
    if (raw === undefined) continue;
    if (typeof raw !== 'boolean') throw new BadRequestException('invalid_override');
    values[key] = raw;
  }
  if (!Object.keys(values).length) throw new BadRequestException('invalid_override');
  const note = body.note === undefined ? null : String(body.note);
  if (note !== null && note.length > 2000) throw new BadRequestException('invalid_override');
  let expiresAt: Date | null = null;
  if (body.expiresAt !== undefined) {
    const parsed = new Date(String(body.expiresAt));
    if (Number.isNaN(parsed.getTime())) throw new BadRequestException('invalid_override');
    expiresAt = parsed;
  }
  const actorId = typeof body.actorId === 'string' && /^usr_[a-f0-9]{24}$/.test(body.actorId) ? body.actorId : 'usr_sistema';
  const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
  if (reason.length < 5 || reason.length > 500) throw new BadRequestException('invalid_reason');
  return { values, note, expiresAt, actorId, reason };
}

function overrideSnapshot(row: {
  extraUsers: number; extraProducts: number; extraWarehouses: number;
  allowEcf: boolean; allowTaxes: boolean; allowWholesale: boolean; allowUom: boolean;
  allowMultiWarehouse: boolean;
  note: string | null; grantedBy: string | null; grantedAt: Date; expiresAt: Date | null;
}) {
  return {
    extraUsers: row.extraUsers, extraProducts: row.extraProducts, extraWarehouses: row.extraWarehouses,
    allowEcf: row.allowEcf, allowTaxes: row.allowTaxes, allowWholesale: row.allowWholesale, allowUom: row.allowUom,
    allowMultiWarehouse: row.allowMultiWarehouse,
    note: row.note, grantedBy: row.grantedBy, grantedAt: row.grantedAt.toISOString(), expiresAt: row.expiresAt?.toISOString() ?? null,
  };
}
