import { UnauthorizedException } from '@nestjs/common';
import { LicenseStatus } from '@prisma/client';

import {
  buildEntitlements,
  isFeatureIncluded,
} from './plans/license-entitlements.service';
import { LicenseActivationService } from './orders/license-activation.service';
import { describeBankFailure, parseBankReceipt, validateBankTransfer } from './evidence/bank-transfer.analysis';
import { resolveLicenseAccess } from './license.access.policy';
import { LicenseService } from './license.service';

/**
 * REGRESION: un cliente **ACTIVO** no puede perder nada.
 *
 * Estos casos fijan el comportamiento que ya tenia una licencia pagada vigente
 * antes de los estados nuevos (VENCIDO, DEMO FINALIZADA, SUSPENDIDO):
 * - su acceso es FULL y entra a todo;
 * - el trabajo offline sigue autorizado solo para el;
 * - una renovacion **suma** meses al vencimiento, nunca los recorta;
 * - una empresa sin plan (legada) conserva todas sus funciones y multi-almacen.
 */
describe('proteccion de una licencia ACTIVA', () => {
  const future = new Date('2026-12-31T12:00:00.000Z');
  const now = new Date('2026-11-18T12:00:00.000Z');

  it('una licencia pagada vigente tiene acceso FULL', () => {
    const access = resolveLicenseAccess(
      {
        status: 'ACTIVE',
        licenseStatus: LicenseStatus.ACTIVE,
        trialEndsAt: null,
        licenseExpiresAt: future,
      },
      now,
    );

    expect(access.level).toBe('FULL');
    expect(access.reason).toBe('ACTIVE');
    expect(access.restricted).toBe(false);
    expect(access.daysRemaining).toBeGreaterThan(0);
  });

  it('el trabajo offline sigue autorizado solo con acceso FULL', async () => {
    const service = new LicenseService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    ) as never as {
      assertCompanyCanUseApp: (id: string) => Promise<void>;
      getLicenseAccess: unknown;
      getCompanyLicenseStatus: unknown;
    };

    service.getLicenseAccess = async () => ({ level: 'FULL', reason: 'ACTIVE' });
    await expect(service.assertCompanyCanUseApp('company-1')).resolves.toBeUndefined();

    service.getLicenseAccess = async () => ({ level: 'RESTRICTED', reason: 'EXPIRED' });
    service.getCompanyLicenseStatus = async () => ({
      status: 'EXPIRED',
      rawStatus: 'ACTIVE',
      blockReason: 'Licencia expirada',
    });
    await expect(service.assertCompanyCanUseApp('company-1')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );

    service.getLicenseAccess = async () => ({ level: 'BLOCKED', reason: 'BLOCKED' });
    await expect(service.assertCompanyCanUseApp('company-1')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('renovar una licencia vigente suma al vencimiento y no toca los limites pagados', async () => {
    const expiresAt = new Date('2026-12-01T00:00:00.000Z');
    const update = jest.fn().mockResolvedValue({ id: 'company-1' });
    const tx = {
      // A1: la activacion bloquea la fila de la empresa antes de leer.
      $queryRaw: jest.fn().mockResolvedValue([{ id: 'company-1' }]),
      company: {
        findUnique: jest.fn().mockResolvedValue({
          licenseStatus: LicenseStatus.ACTIVE,
          licenseActivatedAt: new Date('2026-01-01T00:00:00.000Z'),
          licenseExpiresAt: expiresAt,
          ncfEnabled: true,
          taxEnabled: true,
          wholesalePriceListsEnabled: true,
          measurementUnitsEnabled: true,
        }),
        update,
      },
    };
    const prisma = {
      licensePlan: {
        findUnique: jest.fn().mockResolvedValue({
          code: 'pro',
          name: 'FullPOS Pro',
          version: 1,
          maxUsers: 4,
          maxProducts: 1000,
          maxWarehouses: 5,
          ecf: true,
          taxes: true,
          wholesale: true,
          uom: true,
          active: true,
        }),
      },
    };
    const activation = new LicenseActivationService(prisma as never);

    const result = await activation.applyPlan({
      companyId: 'company-1',
      planCode: 'pro',
      months: 1,
      now,
      tx: tx as never,
    });

    // El nuevo periodo empieza donde terminaba el pagado: se suman meses.
    expect(result.periodStart.toISOString()).toBe(expiresAt.toISOString());
    expect(result.periodEnd.toISOString()).toBe('2027-01-01T00:00:00.000Z');
    expect(result.turnedOff).toEqual([]);
    const data = update.mock.calls[0]?.[0]?.data as Record<string, unknown>;
    expect(data.licenseExpiresAt).toEqual(result.periodEnd);
    // Las funciones que el plan incluye se conservan encendidas.
    expect(data.ncfEnabled).toBe(true);
    expect(data.taxEnabled).toBe(true);
  });

  it('una empresa legada sin plan conserva funciones y multi-almacen', () => {
    const entitlements = buildEntitlements(
      {
        planCode: null,
        planCatalogVersion: null,
        maxUsers: 5,
        maxProducts: 200,
        maxWarehouses: 3,
      },
      null,
      null,
    );

    expect(entitlements.source).toBe('none');
    expect(entitlements.maxUsers).toBe(5);
    expect(entitlements.maxProducts).toBe(200);
    expect(entitlements.maxWarehouses).toBe(3);
    expect(entitlements.multiWarehouse).toBe(true);
    expect(isFeatureIncluded(entitlements, 'ecf')).toBe(true);
    expect(isFeatureIncluded(entitlements, 'taxes')).toBe(true);
    expect(isFeatureIncluded(entitlements, 'wholesale')).toBe(true);
    expect(isFeatureIncluded(entitlements, 'uom')).toBe(true);
  });

  it('un comprobante de un cliente ACTIVO sigue validando igual', () => {
    const text = `Banco Popular Dominicano
Transferencia a terceros
Estado: Realizada
Monto: RD$5,000.00
Cuenta destino: 841360753
Beneficiario: FULLTECH, SRL
Referencia: 00123456789
Fecha: 17/11/2026 14:35`;
    const result = validateBankTransfer({
      parsed: parseBankReceipt(text),
      order: { amount: 5000, createdAt: new Date('2026-11-17T00:00:00.000Z') },
      now,
    });
    expect(result.passed).toBe(true);
    expect(describeBankFailure(result)).toBeNull();
  });
});
