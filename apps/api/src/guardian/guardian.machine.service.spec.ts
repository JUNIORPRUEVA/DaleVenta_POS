import { GuardianMachineService, hashGuardianMachineKey, isWellFormedGuardianMachineKey } from './guardian.machine.service';

/**
 * Autenticación de máquina: aislamiento multiempresa y fail-closed.
 *
 * La empresa SIEMPRE viene de la credencial. Estas pruebas fijan esa garantía:
 * si alguien intentara derivar la empresa del cuerpo de la petición, la prueba
 * de aislamiento debe fallar.
 */
describe('servicio de credenciales de máquina Guardian', () => {
  const COMPANY_A = '11111111-1111-1111-1111-111111111111';
  const KEY = 'gmk_' + 'a'.repeat(40);

  const makePrisma = (row: unknown) =>
    ({
      guardianMachineCredential: {
        findUnique: jest.fn().mockResolvedValue(row),
        update: jest.fn().mockResolvedValue({}),
      },
      guardianAccessLog: { create: jest.fn().mockResolvedValue({}) },
    }) as any;

  const baseRow = {
    id: 'cred-1',
    companyId: COMPANY_A,
    installId: 'pos-uat',
    label: 'DaleVentas POS UAT',
    enabled: true,
    revokedAt: null,
    expiresAt: null,
  };

  it('valida el formato de la clave antes de tocar la base de datos', () => {
    expect(isWellFormedGuardianMachineKey(KEY)).toBe(true);
    expect(isWellFormedGuardianMachineKey('corta')).toBe(false);
    expect(isWellFormedGuardianMachineKey('jwt_' + 'a'.repeat(40))).toBe(false);
    expect(isWellFormedGuardianMachineKey('gmk_ tiene espacios')).toBe(false);
  });

  it('el hash es estable y no reversible', () => {
    expect(hashGuardianMachineKey(KEY)).toBe(hashGuardianMachineKey(` ${KEY} `));
    expect(hashGuardianMachineKey(KEY)).toHaveLength(64);
    expect(hashGuardianMachineKey(KEY)).not.toContain('gmk_');
  });

  it('resuelve la empresa desde la credencial, no desde la petición', async () => {
    const prisma = makePrisma(baseRow);
    const service = new GuardianMachineService(prisma);
    const identity = await service.authenticate(KEY);

    expect(identity).toEqual({
      credentialId: 'cred-1',
      companyId: COMPANY_A,
      installId: 'pos-uat',
      label: 'DaleVentas POS UAT',
    });
    expect(prisma.guardianMachineCredential.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { keyHash: hashGuardianMachineKey(KEY) } }),
    );
  });

  it('rechaza credencial inexistente, deshabilitada, revocada o caducada', async () => {
    await expect(
      new GuardianMachineService(makePrisma(null)).authenticate(KEY),
    ).resolves.toBeNull();

    for (const row of [
      { ...baseRow, enabled: false },
      { ...baseRow, revokedAt: new Date('2026-01-01T00:00:00Z') },
      { ...baseRow, expiresAt: new Date('2026-01-01T00:00:00Z') },
    ]) {
      await expect(
        new GuardianMachineService(makePrisma(row)).authenticate(
          KEY,
          new Date('2026-06-01T00:00:00Z'),
        ),
      ).resolves.toBeNull();
    }
  });

  it('acepta una credencial vigente con caducidad futura', async () => {
    const row = { ...baseRow, expiresAt: new Date('2027-01-01T00:00:00Z') };
    await expect(
      new GuardianMachineService(makePrisma(row)).authenticate(KEY, new Date('2026-06-01T00:00:00Z')),
    ).resolves.not.toBeNull();
  });

  it('no consulta la base con una clave mal formada', async () => {
    const prisma = makePrisma(baseRow);
    await expect(
      new GuardianMachineService(prisma).authenticate('no-es-una-clave'),
    ).resolves.toBeNull();
    expect(prisma.guardianMachineCredential.findUnique).not.toHaveBeenCalled();
  });

  it('la auditoría de uso es best-effort: nunca rompe la ingesta', async () => {
    const prisma = makePrisma(baseRow);
    prisma.guardianMachineCredential.update.mockRejectedValue(new Error('db down'));
    const service = new GuardianMachineService(prisma);

    await expect(
      service.recordUsage({
        identity: { credentialId: 'cred-1', companyId: COMPANY_A, installId: null, label: 'x' },
        ip: '10.0.0.1',
        requestId: 'req-1',
        acceptedEvents: 1,
        totalEvents: 1,
      }),
    ).resolves.toBeUndefined();
  });
});
