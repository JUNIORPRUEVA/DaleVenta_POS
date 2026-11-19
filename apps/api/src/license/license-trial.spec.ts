import { ConflictException } from '@nestjs/common';
import { LicenseStatus } from '@prisma/client';

import { LicenseService } from './license.service';

/**
 * La demo de 7 dias se abre **una sola vez** y solo a empresas nuevas.
 *
 * Estas reglas son las que impiden que una empresa antigua (o una que ya pago)
 * consiga siete dias gratis por entrar, cerrar sesion o reinstalar.
 */
function build(company: Record<string, unknown> | null) {
  const update = jest.fn().mockResolvedValue({ id: 'company-1' });
  const createAudit = jest.fn().mockResolvedValue({ id: 'audit-1' });
  const prisma = {
    company: {
      findUnique: jest.fn().mockResolvedValue(company),
      update,
    },
    companyLicenseAuditLog: { create: createAudit },
  };
  const service = new LicenseService(
    prisma as never,
    {} as never,
    {} as never,
    {} as never,
  );
  return { service, update, createAudit };
}

const NEW_COMPANY = {
  id: 'company-1',
  licenseStatus: LicenseStatus.TRIAL,
  trialStartedAt: null,
  trialEndsAt: null,
  licenseActivatedAt: null,
  licenseExpiresAt: null,
  licenseBlockedAt: null,
};

describe('demo de 7 dias', () => {
  it('una empresa nueva recibe exactamente 7 dias y queda auditado', async () => {
    const { service, update, createAudit } = build(NEW_COMPANY);

    const result = await service.ensureTrialForCompany('company-1', 'soporte@fulltech');

    expect(result.days).toBe(7);
    const days =
      (result.endsAt.getTime() - result.startedAt.getTime()) / 86_400_000;
    expect(days).toBe(7);
    expect(update).toHaveBeenCalledTimes(1);
    const data = update.mock.calls[0]?.[0]?.data as Record<string, unknown>;
    expect(data.maxUsers).toBe(2);
    expect(data.maxProducts).toBe(100);
    expect(createAudit).toHaveBeenCalledTimes(1);
  });

  it('no se puede empezar una segunda prueba', async () => {
    const { service, update } = build({
      ...NEW_COMPANY,
      trialStartedAt: new Date('2026-01-01T00:00:00Z'),
      trialEndsAt: new Date('2026-01-08T00:00:00Z'),
    });

    await expect(service.ensureTrialForCompany('company-1')).rejects.toThrow(
      ConflictException,
    );
    expect(update).not.toHaveBeenCalled();
  });

  it('una empresa que ya pago no vuelve a demo', async () => {
    const { service, update } = build({
      ...NEW_COMPANY,
      licenseStatus: LicenseStatus.EXPIRED,
      licenseActivatedAt: new Date('2026-02-01T00:00:00Z'),
      licenseExpiresAt: new Date('2026-03-01T00:00:00Z'),
    });

    await expect(service.ensureTrialForCompany('company-1')).rejects.toThrow(
      ConflictException,
    );
    expect(update).not.toHaveBeenCalled();
  });

  it('una cuenta suspendida no se convierte en demo', async () => {
    const { service, update } = build({
      ...NEW_COMPANY,
      licenseStatus: LicenseStatus.BLOCKED,
      licenseBlockedAt: new Date('2026-02-01T00:00:00Z'),
    });

    await expect(service.ensureTrialForCompany('company-1')).rejects.toThrow(
      ConflictException,
    );
    expect(update).not.toHaveBeenCalled();
  });
});
