import {
  GuardianEnrollmentService,
  generateEnrollmentCode,
  generateInstallCredential,
  hashGuardianEnrollmentCode,
  isWellFormedEnrollmentCode,
  installCredentialDays,
} from './guardian.enrollment.service';

/**
 * Enrolamiento de instalaciones: garantías de seguridad.
 *
 * Lo que se protege aquí:
 * - Un código no se puede canjear dos veces (consumo atómico).
 * - Un código caducado o revocado no emite credenciales.
 * - La empresa sale del código, nunca del cuerpo de la petición.
 * - La clave emitida se entrega una sola vez y solo se guarda su hash.
 */
describe('enrolamiento de instalaciones Guardian', () => {
  const COMPANY = '11111111-1111-1111-1111-111111111111';
  const CODE = generateEnrollmentCode();

  const makePrisma = (overrides: {
    codeRow?: unknown;
    consumedCount?: number;
    existingCredential?: unknown;
  } = {}) => {
    const prisma = {
      guardianEnrollmentCode: {
        findUnique: jest.fn().mockResolvedValue(
          overrides.codeRow === undefined
            ? {
                id: 'code-1',
                companyId: COMPANY,
                maxUses: 1,
                uses: 0,
                expiresAt: new Date(Date.now() + 3_600_000),
                revokedAt: null,
              }
            : overrides.codeRow,
        ),
        updateMany: jest.fn().mockResolvedValue({ count: overrides.consumedCount ?? 1 }),
      },
      guardianMachineCredential: {
        findFirst: jest.fn().mockResolvedValue(overrides.existingCredential ?? null),
        create: jest.fn().mockResolvedValue({}),
        update: jest.fn().mockResolvedValue({}),
      },
      guardianAccessLog: { create: jest.fn().mockResolvedValue({}) },
    } as any;
    return prisma;
  };

  const serviceFor = (prisma: any) => new GuardianEnrollmentService(prisma);

  it('emite una credencial de instalación válida y la asocia a la empresa del código', async () => {
    const prisma = makePrisma();
    const outcome = await serviceFor(prisma).enroll({
      code: CODE,
      installId: 'pos-uat-01',
      platform: 'windows',
      appVersion: '1.0.5',
    });

    expect(outcome.ok).toBe(true);
    if (!outcome.ok) return;
    expect(outcome.companyId).toBe(COMPANY);
    expect(outcome.installId).toBe('pos-uat-01');
    expect(outcome.credential.startsWith('gmk_')).toBe(true);
    expect(new Date(outcome.expiresAt).getTime()).toBeGreaterThan(Date.now());

    const createArgs = prisma.guardianMachineCredential.create.mock.calls[0][0];
    expect(createArgs.data.companyId).toBe(COMPANY);
    expect(createArgs.data.installId).toBe('pos-uat-01');
    // Nunca se guarda la clave en claro, solo su hash.
    expect(createArgs.data.keyHash).toHaveLength(64);
    expect(JSON.stringify(createArgs.data)).not.toContain(outcome.credential);
  });

  it('rota la credencial existente de la misma instalación', async () => {
    const prisma = makePrisma({ existingCredential: { id: 'cred-1' } });
    const outcome = await serviceFor(prisma).enroll({ code: CODE, installId: 'pos-uat-01' });

    expect(outcome.ok).toBe(true);
    expect(prisma.guardianMachineCredential.update).toHaveBeenCalledTimes(1);
    expect(prisma.guardianMachineCredential.create).not.toHaveBeenCalled();
  });

  it('rechaza código inválido, caducado, revocado o agotado', async () => {
    expect((await serviceFor(makePrisma({ codeRow: null })).enroll({ code: CODE, installId: 'pos-01' })).ok).toBe(
      false,
    );
    expect(
      (
        await serviceFor(
          makePrisma({ codeRow: null }),
        ).enroll({ code: 'no-es-un-codigo', installId: 'pos-01' })
      ).ok,
    ).toBe(false);

    const expired = await serviceFor(
      makePrisma({
        codeRow: {
          id: 'code-1',
          companyId: COMPANY,
          maxUses: 1,
          uses: 0,
          expiresAt: new Date(Date.now() - 1000),
          revokedAt: null,
        },
      }),
    ).enroll({ code: CODE, installId: 'pos-01' });
    expect(expired.ok).toBe(false);

    const revoked = await serviceFor(
      makePrisma({
        codeRow: {
          id: 'code-1',
          companyId: COMPANY,
          maxUses: 1,
          uses: 0,
          expiresAt: new Date(Date.now() + 60_000),
          revokedAt: new Date(),
        },
      }),
    ).enroll({ code: CODE, installId: 'pos-01' });
    expect(revoked.ok).toBe(false);

    const exhaustedByUses = await serviceFor(
      makePrisma({
        codeRow: {
          id: 'code-1',
          companyId: COMPANY,
          maxUses: 1,
          uses: 1,
          expiresAt: new Date(Date.now() + 60_000),
          revokedAt: null,
        },
      }),
    ).enroll({ code: CODE, installId: 'pos-01' });
    expect(exhaustedByUses.ok).toBe(false);

    // Carrera perdida: otro proceso consumió el último uso.
    const raced = await serviceFor(makePrisma({ consumedCount: 0 })).enroll({
      code: CODE,
      installId: 'pos-01',
    });
    expect(raced.ok).toBe(false);
    if (!raced.ok) expect(raced.code).toBe('ENROLLMENT_CODE_EXHAUSTED');
  });

  it('valida el formato del código y del installId', () => {
    expect(isWellFormedEnrollmentCode(CODE)).toBe(true);
    expect(isWellFormedEnrollmentCode('corto')).toBe(false);
    expect(isWellFormedEnrollmentCode('otro_' + 'a'.repeat(40))).toBe(false);
    expect(hashGuardianEnrollmentCode(CODE)).toHaveLength(64);
    expect(generateInstallCredential()).not.toBe(generateInstallCredential());
  });

  it('la credencial de instalación caduca en el plazo configurado', () => {
    expect(installCredentialDays({} as NodeJS.ProcessEnv)).toBe(30);
    expect(installCredentialDays({ GUARDIAN_INSTALL_CREDENTIAL_DAYS: '7' } as NodeJS.ProcessEnv)).toBe(7);
    expect(installCredentialDays({ GUARDIAN_INSTALL_CREDENTIAL_DAYS: '9999' } as NodeJS.ProcessEnv)).toBe(365);
    expect(installCredentialDays({ GUARDIAN_INSTALL_CREDENTIAL_DAYS: 'cero' } as NodeJS.ProcessEnv)).toBe(30);
  });

  it('rechaza installId con formato inválido sin tocar la base', async () => {
    const prisma = makePrisma();
    const outcome = await serviceFor(prisma).enroll({ code: CODE, installId: 'corto' });
    expect(outcome.ok).toBe(false);
    expect(prisma.guardianEnrollmentCode.findUnique).not.toHaveBeenCalled();
  });
});
