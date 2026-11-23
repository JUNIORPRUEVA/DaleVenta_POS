import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Company, CompanyPlan, Prisma } from '@prisma/client';
import { isEmail } from 'class-validator';
import { buildEntitlements } from './plans/license-entitlements.service';

const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export const crmAdministrationActions = ['contact', 'assignPlan', 'extend', 'loginEmail'];
export function parseAdministrationFields(action: string, value: unknown): Record<string, string | number> {
  const invalid = () => { throw new BadRequestException('invalid_crm_command'); };
  if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
  const fields = value as Record<string, unknown>;
  const keys: Record<string, string[]> = {
    contact: ['name', 'contactEmail', 'phone', 'address'], assignPlan: ['planCode'],
    extend: ['days'], loginEmail: ['userId', 'expectedLoginEmail', 'loginEmail'],
  };
  if (!Object.keys(fields).length || Object.keys(fields).some(k => !keys[action]?.includes(k))) return invalid();
  const result: Record<string, string | number> = {};
  for (const [key, raw] of Object.entries(fields)) {
    if (key === 'days') {
      if (!Number.isInteger(raw) || Number(raw) < 1 || Number(raw) > 3650) return invalid();
      result.days = Number(raw); continue;
    }
    if (typeof raw !== 'string') return invalid();
    const text = raw.trim();
    if (key === 'name' && (text.length < 2 || text.length > 160)) return invalid();
    if (['contactEmail', 'expectedLoginEmail', 'loginEmail'].includes(key) &&
      ((key !== 'contactEmail' || text !== '') && (!isEmail(text) || text.length > 254))) return invalid();
    if (key === 'phone' && (text.length > 40 || (text && !/^[+\d\s().-]+$/.test(text)))) return invalid();
    if (key === 'address' && text.length > 500) return invalid();
    if (key === 'planCode' && !/^[a-z0-9][a-z0-9_-]{0,31}$/.test(text)) return invalid();
    if (key === 'userId' && !uuid.test(text)) return invalid();
    result[key] = key.toLowerCase().includes('email') ? text.toLowerCase() : text;
  }
  if (action === 'assignPlan' && !result.planCode || action === 'extend' && !result.days ||
    action === 'loginEmail' && (!result.userId || !result.expectedLoginEmail || !result.loginEmail)) return invalid();
  return result;
}

/** Se ejecuta dentro del comando existente: misma transacción, versión y recibo. */
export async function applyAdministration(
  tx: Prisma.TransactionClient, company: Company, action: string,
  fields: Record<string, string | number | boolean>,
  usage: { users: number; products: number },
): Promise<Prisma.CompanyUpdateInput> {
  const now = new Date();
  if (action === 'contact') {
    const data: Prisma.CompanyUpdateInput = {};
    if (fields.name !== undefined) data.name = String(fields.name);
    if (fields.contactEmail !== undefined) data.contactEmail = String(fields.contactEmail) || null;
    if (fields.phone !== undefined || fields.address !== undefined) {
      const contact = { ...(fields.phone !== undefined ? { phone: String(fields.phone) } : {}),
        ...(fields.address !== undefined ? { address: String(fields.address) } : {}) };
      await tx.appConfig.upsert({ where: { companyId: company.id },
        create: { id: company.id, companyId: company.id, companyName: String(fields.name ?? company.name), ...contact }, update: contact });
    }
    return data;
  }
  if (action === 'assignPlan' || action === 'extend') {
    if (await tx.licensePaymentOrder.findFirst({ where: { companyId: company.id,
      activationState: { in: ['PROVISIONAL', 'EXPIRED_REVIEW'] } }, select: { id: true } })) {
      throw new ConflictException('payment_review_required');
    }
  }
  if (action === 'assignPlan') {
    const plan = await tx.licensePlan.findUnique({ where: { code: String(fields.planCode) } });
    if (!plan?.active) throw new NotFoundException('plan_not_available');
    const override = await tx.licenseCompanyOverride.findUnique({ where: { companyId: company.id } });
    const effective = buildEntitlements(company, plan, override, now);
    const warehouses = await tx.warehouse.count({ where: { companyId: company.id, isActive: true } });
    if (effective.maxUsers < usage.users || effective.maxProducts < usage.products || effective.maxWarehouses < warehouses) {
      throw new ConflictException('limit_below_current_usage');
    }
    if (company.ncfEnabled && !effective.features.ecf || company.taxEnabled && !effective.features.taxes ||
      company.wholesalePriceListsEnabled && !effective.features.wholesale ||
      company.measurementUnitsEnabled && !effective.features.uom || company.multiWarehouseEnabled && !effective.multiWarehouse) {
      throw new ConflictException('plan_removes_active_module');
    }
    return { planCode: plan.code, planCatalogVersion: plan.version,
      plan: ['empresa', 'enterprise'].includes(plan.code) ? CompanyPlan.ENTERPRISE : CompanyPlan.STANDARD,
      maxUsers: plan.maxUsers, maxProducts: plan.maxProducts, maxWarehouses: plan.maxWarehouses };
  }
  if (action === 'extend') {
    const trial = company.licenseStatus === 'TRIAL';
    const current = trial ? company.trialEndsAt : company.licenseExpiresAt;
    if (!current || !trial && !company.licenseKey) throw new ConflictException('existing_period_required');
    const end = new Date(Math.max(now.getTime(), current.getTime()) + Number(fields.days) * 86400000);
    if (!Number.isFinite(end.getTime())) throw new BadRequestException('invalid_crm_command');
    return trial ? { trialEndsAt: end } : { licenseExpiresAt: end,
      ...(company.licenseStatus === 'EXPIRED' && company.status === 'ACTIVE' ? { licenseStatus: 'ACTIVE' } : {}) };
  }
  if (action === 'loginEmail') {
    const userId = String(fields.userId);
    const owner = await tx.companyMember.findFirst({ where: { companyId: company.id, userId, role: 'OWNER', status: 'ACTIVE' } });
    if (!owner) throw new NotFoundException('owner_not_found');
    await tx.$queryRaw`SELECT id FROM users WHERE id=${userId}::uuid FOR UPDATE`;
    const user = await tx.user.findUnique({ where: { id: userId } });
    if (!user || user.email.toLowerCase() !== fields.expectedLoginEmail) throw new ConflictException('account_changed_reload');
    const memberships = await tx.companyMember.count({ where: { userId, status: 'ACTIVE' } });
    if (memberships > 1 || user.companyId && user.companyId !== company.id) throw new ConflictException('shared_account_requires_review');
    const email = String(fields.loginEmail);
    const duplicate = await tx.user.findFirst({ where: { email: { equals: email, mode: 'insensitive' }, NOT: { id: userId } }, select: { id: true } });
    if (duplicate) throw new ConflictException('login_email_in_use');
    await tx.user.update({ where: { id: userId }, data: { email } });
    await tx.authSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now, revocationReason: 'crm_email_changed' } });
    await tx.sessionHandoffTicket.updateMany({ where: { userId, usedAt: null }, data: { usedAt: now } });
    await tx.passwordResetToken.updateMany({ where: { userId, usedAt: null, revokedAt: null }, data: { revokedAt: now } });
    return {};
  }
  throw new BadRequestException('invalid_crm_command');
}
