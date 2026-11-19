import { ForbiddenException } from '@nestjs/common';
import { of } from 'rxjs';

import { LicenseAccessInterceptor } from './license-access.interceptor';

/**
 * La compuerta de acceso: con la licencia vencida **o la cuenta suspendida** el
 * cliente entra, pero solo a Planes y Soporte. Todo lo demas falla cerrado.
 */
function context(level: string, method: string, path: string) {
  return {
    switchToHttp: () => ({
      getRequest: () => ({
        method,
        path,
        user: { licenseAccess: { level, reason: level } },
      }),
    }),
  } as never;
}

const next = { handle: () => of('ok') } as never;

describe('LicenseAccessInterceptor', () => {
  const interceptor = new LicenseAccessInterceptor();

  it('una licencia al dia pasa por cualquier ruta', () => {
    expect(() =>
      interceptor.intercept(context('FULL', 'POST', '/sales'), next),
    ).not.toThrow();
    expect(() =>
      interceptor.intercept(context('FULL', 'PATCH', '/settings'), next),
    ).not.toThrow();
  });

  it('una licencia vencida sigue viendo su licencia y puede pagar', () => {
    for (const [method, path] of [
      ['GET', '/license'],
      ['GET', '/license/plans'],
      ['GET', '/license/orders/quote'],
      ['POST', '/license/orders'],
      ['GET', '/license/payment-instructions'],
      ['POST', '/support/tickets'],
    ]) {
      expect(() =>
        interceptor.intercept(context('RESTRICTED', method, path), next),
      ).not.toThrow();
    }
  });

  it('una licencia vencida ya no puede activarse sin pagar', () => {
    expect(() =>
      interceptor.intercept(context('RESTRICTED', 'POST', '/license/activate'), next),
    ).toThrow(ForbiddenException);
  });

  it('la cuenta suspendida entra a ver su estado y a pagar si debe', () => {
    for (const [method, path] of [
      ['GET', '/license'],
      ['GET', '/license/plans'],
      ['POST', '/license/orders'],
      ['POST', '/support/tickets'],
    ]) {
      expect(() =>
        interceptor.intercept(context('BLOCKED', method, path), next),
      ).not.toThrow();
    }
  });

  it('la cuenta suspendida no puede seguir vendiendo', () => {
    expect(() =>
      interceptor.intercept(context('BLOCKED', 'POST', '/sales'), next),
    ).toThrow(ForbiddenException);
    try {
      interceptor.intercept(context('BLOCKED', 'GET', '/products'), next);
      throw new Error('debio lanzar');
    } catch (error) {
      const response = (error as ForbiddenException).getResponse() as {
        code?: string;
      };
      expect(response.code).toBe('LICENSE_SUSPENDED');
    }
  });
});
