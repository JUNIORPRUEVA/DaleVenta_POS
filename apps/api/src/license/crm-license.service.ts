import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { LicenseService } from './license.service';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const invalid = () => { throw new BadRequestException('invalid_crm_command'); };
export function parseCrmCommand(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
  const v = value as Record<string, unknown>;
  if (Object.keys(v).some(k => !['operationId', 'expectedVersion', 'action', 'reason', 'fields', 'confirmationName', 'actorId', 'serviceId'].includes(k))) return invalid();
  if (typeof v.operationId !== 'string' || !UUID.test(v.operationId) || typeof v.serviceId !== 'string' || !UUID.test(v.serviceId) || typeof v.actorId !== 'string' || !/^usr_[a-f0-9]{24}$/.test(v.actorId)) return invalid();
  if (typeof v.expectedVersion !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(v.expectedVersion) || !Number.isFinite(Date.parse(v.expectedVersion))) return invalid();
  if (!['update', 'suspend', 'reactivate', 'revoke'].includes(String(v.action)) || typeof v.reason !== 'string' || v.reason.trim().length < 5 || v.reason.length > 500) return invalid();
  const fields: Record<string, string | number> = {};
  if (v.action === 'update') {
    if (!v.fields || typeof v.fields !== 'object' || Array.isArray(v.fields)) return invalid();
    for (const [k, x] of Object.entries(v.fields)) {
      if (k === 'name' && typeof x === 'string' && x.trim().length >= 2 && x.trim().length <= 160) fields[k] = x.trim();
      else if (k === 'notes' && typeof x === 'string' && x.length <= 2000) fields[k] = x.trim();
      else if (['maxUsers', 'maxProducts'].includes(k) && typeof x === 'number' && Number.isSafeInteger(x) && x >= 1 && x <= 1000000) fields[k] = x;
      else return invalid();
    }
    if (!Object.keys(fields).length) return invalid();
  } else if (v.fields !== undefined) return invalid();
  if (v.action === 'revoke' ? typeof v.confirmationName !== 'string' || v.confirmationName.length > 160 : v.confirmationName !== undefined) return invalid();
  return {
    operationId: v.operationId.toLowerCase(), expectedVersion: v.expectedVersion,
    serviceId: v.serviceId.toLowerCase(), actorId: v.actorId, action: String(v.action),
    reason: v.reason.trim(), fields: Object.fromEntries(Object.entries(fields).sort()),
    confirmationName: v.action === 'revoke' ? String(v.confirmationName).trim() : null,
  };
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
  constructor(private readonly prisma: PrismaService, private readonly licenses: LicenseService, private readonly config: ConfigService) {}

  enabled() { return String(this.config.get('CRM_LICENSE_MANAGEMENT_ENABLED') ?? '') === 'true'; }

  private async projection(id: string, tx: Prisma.TransactionClient) {
    const row = await this.licenses.getCompanyLicenseStatus(id, tx);
    // An expired TRIAL still has its original trial period. Leave legacy DTOs unchanged.
    if (row.rawStatus !== 'TRIAL') return row;
    return { ...row, periodStartedAt: row.trialStartedAt, periodEndsAt: row.trialEndsAt,
      daysRemaining: row.trialEndsAt ? Math.ceil((row.trialEndsAt.getTime() - Date.now()) / 86400000) : null };
  }

  async detail(id: string) {
    if (!UUID.test(id)) throw new BadRequestException('invalid_company_id');
    return this.prisma.$transaction(async tx => {
      if (!await tx.company.findUnique({ where: { id }, select: { id: true } })) throw new NotFoundException('company_not_found');
      const license = await this.projection(id, tx);
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
          return { license: await this.projection(companyId, tx), operationId: command.operationId, deduplicated: true };
        }
        if (company.updatedAt.toISOString() !== command.expectedVersion) throw new ConflictException('license_changed_reload');
        const before = await this.projection(companyId, tx);
        const data: Prisma.CompanyUpdateInput = { updatedAt: new Date(Math.max(Date.now(), company.updatedAt.getTime() + 1)) };
        if (command.action === 'update') {
          for (const key of ['maxUsers', 'maxProducts'] as const) {
            const count = key === 'maxUsers' ? before.usage.users : before.usage.products;
            if (command.fields[key] !== undefined && Number(command.fields[key]) < count) throw new ConflictException('limit_below_current_usage');
            if (command.fields[key] !== undefined) data[key] = Number(command.fields[key]);
          }
          if (command.fields.name !== undefined) data.name = String(command.fields.name);
          if (command.fields.notes !== undefined) data.licenseNotes = String(command.fields.notes);
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
        const after = await this.projection(companyId, tx);
        const snapshot = (v: typeof after) => ({ name: v.companyName, status: v.status, rawStatus: v.rawStatus, expiresAt: v.licenseExpiresAt?.toISOString() ?? null, maxUsers: v.limits.maxUsers, maxProducts: v.limits.maxProducts, notes: v.notes, version: v.updatedAt.toISOString() });
        // Mandatory receipt and audit in the SAME transaction. No raw keys or payment data.
        await tx.companyLicenseAuditLog.create({ data: {
          id: command.operationId, companyId, actorEmail: `crm:${command.actorId}`,
          action: `license.crm.${command.action}`, reason: command.reason,
          before: snapshot(before), after: { ...snapshot(after), _crmCommand: { requestHash, actorId: command.actorId, serviceId: command.serviceId, action: command.action } },
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
}
