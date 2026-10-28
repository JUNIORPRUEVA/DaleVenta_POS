import {
  GUARDIAN_COMPANY_DISABLED,
  isGuardianEnabledForCompany,
} from './guardian.company.policy';

/**
 * FASE 7 — política de activación por empresa.
 *
 * Criterios cubiertos: activación, desactivación, empresa inexistente,
 * aislamiento entre empresas y fail-closed ante errores de lectura.
 */
function reader(rows: Record<string, boolean | null>, options: { throws?: boolean } = {}) {
  const calls: string[] = [];
  return {
    calls,
    company: {
      async findUnique(args: { where: { id: string }; select: { guardianEnabled: true } }) {
        calls.push(args.where.id);
        if (options.throws) throw new Error('db down');
        if (!(args.where.id in rows)) return null;
        const value = rows[args.where.id];
        return value === null ? null : { guardianEnabled: value };
      },
    },
  };
}

describe('guardian company policy', () => {
  it('empresa activada → true', async () => {
    const prisma = reader({ 'c-1': true });
    await expect(isGuardianEnabledForCompany(prisma, 'c-1')).resolves.toBe(true);
  });

  it('empresa desactivada → false', async () => {
    const prisma = reader({ 'c-1': false });
    await expect(isGuardianEnabledForCompany(prisma, 'c-1')).resolves.toBe(false);
  });

  it('empresa inexistente → false', async () => {
    const prisma = reader({});
    await expect(isGuardianEnabledForCompany(prisma, 'no-existe')).resolves.toBe(false);
  });

  it('id vacío o nulo → false sin consultar', async () => {
    const prisma = reader({ 'c-1': true });
    await expect(isGuardianEnabledForCompany(prisma, '')).resolves.toBe(false);
    await expect(isGuardianEnabledForCompany(prisma, null)).resolves.toBe(false);
    expect(prisma.calls).toEqual([]);
  });

  it('un error de lectura es fail-closed', async () => {
    const prisma = reader({ 'c-1': true }, { throws: true });
    await expect(isGuardianEnabledForCompany(prisma, 'c-1')).resolves.toBe(false);
  });

  it('aislamiento entre empresas: consulta exactamente la empresa indicada', async () => {
    const prisma = reader({ 'c-1': true, 'c-2': false });
    await expect(isGuardianEnabledForCompany(prisma, 'c-1')).resolves.toBe(true);
    await expect(isGuardianEnabledForCompany(prisma, 'c-2')).resolves.toBe(false);
    expect(prisma.calls).toEqual(['c-1', 'c-2']);
  });

  it('expone un código estable para los rechazos', () => {
    expect(GUARDIAN_COMPANY_DISABLED).toBe('COMPANY_GUARDIAN_DISABLED');
  });
});
