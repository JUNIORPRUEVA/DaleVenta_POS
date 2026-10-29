import { ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import { GUARDIAN_MACHINE_RATE_LIMIT_PER_MINUTE, GuardianMachineGuard } from './guardian.machine.guard';
import type { GuardianMachineIdentity } from './guardian.machine.service';

/**
 * Guard de la ruta de ingesta por credencial de máquina.
 *
 * Comprueba el comportamiento fail-closed y que no exista ninguna vía para que
 * una instalación declare incidentes de otra empresa.
 */
describe('guard de credencial de máquina', () => {
  const identity: GuardianMachineIdentity = {
    credentialId: 'cred-1',
    companyId: '11111111-1111-1111-1111-111111111111',
    installId: 'pos-uat',
    label: 'DaleVentas POS UAT',
  };

  const makeContext = (headers: Record<string, string>) => {
    const request: { headers: Record<string, string>; guardianMachine?: GuardianMachineIdentity } = {
      headers,
    };
    const context = {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;
    return { context, request };
  };

  const makeMachine = (overrides: Partial<{ authenticate: jest.Mock }> = {}) =>
    ({
      authenticate: jest.fn().mockResolvedValue(identity),
      ...overrides,
    }) as any;

  it('exige la cabecera de credencial', async () => {
    const guard = new GuardianMachineGuard(makeMachine());
    const { context } = makeContext({});
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rechaza una credencial inválida sin revelar el motivo real', async () => {
    const guard = new GuardianMachineGuard(makeMachine({ authenticate: jest.fn().mockResolvedValue(null) }));
    const { context } = makeContext({ 'x-guardian-key': 'gmk_invalida' });
    await expect(guard.canActivate(context)).rejects.toMatchObject({
      response: { code: 'MACHINE_KEY_INVALID' },
    });
  });

  it('adjunta la identidad verificada a la petición', async () => {
    const machine = makeMachine();
    const guard = new GuardianMachineGuard(machine);
    const { context, request } = makeContext({ 'x-guardian-key': 'gmk_valida' });

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.guardianMachine).toEqual(identity);
    expect(machine.authenticate).toHaveBeenCalledWith('gmk_valida');
  });

  it('rechaza un sello temporal fuera de ventana (anti-replay)', async () => {
    const guard = new GuardianMachineGuard(makeMachine());
    const stale = String(Math.floor(Date.now() / 1000) - 3600);
    const { context } = makeContext({ 'x-guardian-key': 'gmk_valida', 'x-guardian-ts': stale });
    await expect(guard.canActivate(context)).rejects.toMatchObject({
      response: { code: 'MACHINE_TIMESTAMP_OUT_OF_WINDOW' },
    });
  });

  it('acepta un sello temporal reciente en segundos y en milisegundos', async () => {
    const guard = new GuardianMachineGuard(makeMachine());
    const now = Date.now();
    for (const ts of [String(Math.floor(now / 1000)), String(now)]) {
      const { context } = makeContext({ 'x-guardian-key': 'gmk_valida', 'x-guardian-ts': ts });
      await expect(guard.canActivate(context)).resolves.toBe(true);
    }
  });

  it('responde 503 cuando no puede verificar (nunca 401)', async () => {
    const guard = new GuardianMachineGuard(
      makeMachine({ authenticate: jest.fn().mockRejectedValue(new Error('db down')) }),
    );
    const { context } = makeContext({ 'x-guardian-key': 'gmk_valida' });
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('limita el caudal por credencial', async () => {
    const guard = new GuardianMachineGuard(makeMachine());
    const { context } = makeContext({ 'x-guardian-key': 'gmk_valida' });

    for (let i = 0; i < GUARDIAN_MACHINE_RATE_LIMIT_PER_MINUTE; i += 1) {
      await expect(guard.canActivate(context)).resolves.toBe(true);
    }
    await expect(guard.canActivate(context)).rejects.toMatchObject({
      response: { code: 'MACHINE_RATE_LIMITED' },
    });
  });
});
