import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import { PrismaService } from '../../prisma/prisma.service';
import {
  describeBalanceState,
  isBalanceAlertState,
  probeDeepSeekBalance,
  resolveDeepSeekBalanceEndpoint,
} from './guardian.ai.balance';
import { GuardianAiBalanceMonitor } from '../guardian.ai.balance.monitor';
import { resolveGuardianConfig } from '../guardian.config';

/**
 * Saldo y facturación de IA.
 *
 * Regla que estas pruebas protegen: **nunca se reporta un saldo inventado**.
 * Si el proveedor no responde o no es DeepSeek, el estado es explícito y los
 * importes quedan vacíos.
 */

const BASE_ENV = { ...process.env };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function textResponse(text: string, status: number): Response {
  return new Response(text, { status, headers: { 'content-type': 'text/plain' } });
}

describe('endpoint oficial de saldo', () => {
  it('deriva /user/balance desde la base URL de DeepSeek', () => {
    expect(resolveDeepSeekBalanceEndpoint('https://api.deepseek.com/v1')).toBe(
      'https://api.deepseek.com/user/balance',
    );
    expect(resolveDeepSeekBalanceEndpoint('https://api.deepseek.com')).toBe(
      'https://api.deepseek.com/user/balance',
    );
    expect(resolveDeepSeekBalanceEndpoint('https://api.deepseek.com/v1/')).toBe(
      'https://api.deepseek.com/user/balance',
    );
  });

  it('no consulta hosts de otros proveedores (nunca envia la clave fuera)', () => {
    expect(resolveDeepSeekBalanceEndpoint('https://api.openai.com/v1')).toBeNull();
    expect(resolveDeepSeekBalanceEndpoint('https://ejemplo.test/v1')).toBeNull();
    expect(resolveDeepSeekBalanceEndpoint('')).toBeNull();
    expect(resolveDeepSeekBalanceEndpoint(null)).toBeNull();
  });
});

describe('probeDeepSeekBalance', () => {
  it('sin clave no consulta y no inventa cifras', async () => {
    let called = 0;
    const snapshot = await probeDeepSeekBalance({
      apiKey: '',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () => {
        called += 1;
        return jsonResponse({});
      }) as unknown as typeof fetch,
    });

    expect(called).toBe(0);
    expect(snapshot.state).toBe('NOT_CONFIGURED');
    expect(snapshot.totalBalance).toBeNull();
    expect(snapshot.currency).toBeNull();
  });

  it('con un proveedor que no expone el endpoint, no consulta', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.openai.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () => jsonResponse({})) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('NOT_CONFIGURED');
    expect(snapshot.totalBalance).toBeNull();
    expect(snapshot.endpoint).toBeNull();
  });

  it('reporta el saldo tal cual lo devuelve el proveedor', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () =>
        jsonResponse({
          is_available: true,
          balance_infos: [
            { currency: 'USD', total_balance: '110.00', granted_balance: '10.00', topped_up_balance: '100.00' },
          ],
        })) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('OK');
    expect(snapshot.provider).toBe('deepseek');
    expect(snapshot.currency).toBe('USD');
    expect(snapshot.totalBalance).toBe('110.00');
    expect(snapshot.grantedBalance).toBe('10.00');
    expect(snapshot.isAvailable).toBe(true);
    expect(snapshot.endpoint).toBe('https://api.deepseek.com/user/balance');
  });

  it('clasifica saldo bajo por debajo del umbral', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () =>
        jsonResponse({ is_available: true, balance_infos: [{ currency: 'USD', total_balance: '2.50' }] })) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('LOW');
    expect(snapshot.totalBalance).toBe('2.50');
  });

  it('clasifica saldo agotado', async () => {
    const byFlag = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () =>
        jsonResponse({ is_available: false, balance_infos: [{ currency: 'USD', total_balance: '0.00' }] })) as unknown as typeof fetch,
    });
    expect(byFlag.state).toBe('EXHAUSTED');

    const byAmount = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () =>
        jsonResponse({ is_available: true, balance_infos: [{ currency: 'USD', total_balance: '0.00' }] })) as unknown as typeof fetch,
    });
    expect(byAmount.state).toBe('EXHAUSTED');
  });

  it('usa la moneda informada cuando solo hay CNY', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () =>
        jsonResponse({ is_available: true, balance_infos: [{ currency: 'CNY', total_balance: '800.00' }] })) as unknown as typeof fetch,
    });

    expect(snapshot.currency).toBe('CNY');
    expect(snapshot.totalBalance).toBe('800.00');
    expect(snapshot.state).toBe('OK');
  });

  it('trata 401/402/403 como fallo de facturacion, sin cifras', async () => {
    for (const status of [401, 402, 403]) {
      const snapshot = await probeDeepSeekBalance({
        apiKey: 'sk-test',
        baseUrl: 'https://api.deepseek.com/v1',
        lowThreshold: 5,
        fetchImpl: (async () => textResponse('no autorizado', status)) as unknown as typeof fetch,
      });
      expect(snapshot.state).toBe('BILLING_ERROR');
      expect(snapshot.httpStatus).toBe(status);
      expect(snapshot.totalBalance).toBeNull();
    }
  });

  it('trata 5xx como proveedor no disponible, sin cifras', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () => textResponse('boom', 503)) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('UNAVAILABLE');
    expect(snapshot.httpStatus).toBe(503);
    expect(snapshot.totalBalance).toBeNull();
  });

  it('un fallo de red no lanza ni inventa cifras', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () => {
        throw new Error('ECONNREFUSED');
      }) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('UNAVAILABLE');
    expect(snapshot.totalBalance).toBeNull();
    expect(snapshot.error).toContain('ECONNREFUSED');
  });

  it('una respuesta no interpretable no produce importes', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () => textResponse('<html>proxy</html>', 200)) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('UNAVAILABLE');
    expect(snapshot.totalBalance).toBeNull();
  });

  it('una respuesta sin importes ni disponibilidad es no disponible', async () => {
    const snapshot = await probeDeepSeekBalance({
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      lowThreshold: 5,
      fetchImpl: (async () => jsonResponse({ balance_infos: [] })) as unknown as typeof fetch,
    });

    expect(snapshot.state).toBe('UNAVAILABLE');
    expect(snapshot.totalBalance).toBeNull();
  });

  it('las etiquetas y el criterio de aviso son coherentes', () => {
    expect(isBalanceAlertState('OK')).toBe(false);
    expect(isBalanceAlertState('LOW')).toBe(true);
    expect(isBalanceAlertState('EXHAUSTED')).toBe(true);
    expect(isBalanceAlertState('BILLING_ERROR')).toBe(true);
    expect(isBalanceAlertState('UNAVAILABLE')).toBe(true);
    expect(isBalanceAlertState('NOT_CONFIGURED')).toBe(false);
    expect(describeBalanceState('LOW')).toBe('saldo bajo');
  });
});

describe('GuardianAiBalanceMonitor', () => {
  afterEach(() => {
    process.env = { ...BASE_ENV };
    jest.restoreAllMocks();
  });

  function monitor(): GuardianAiBalanceMonitor {
    return new GuardianAiBalanceMonitor();
  }

  it('avisa por webhook cuando el saldo esta bajo e incluye el importe real', async () => {
    process.env.GUARDIAN_AI_API_KEY = 'sk-test';
    process.env.GUARDIAN_AI_PROVIDER = 'deepseek';
    process.env.GUARDIAN_ALERT_RECIPIENTS = '18090000001';
    process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL = 'https://hook.test/guardian';
    delete process.env.GUARDIAN_WA_CLOUD_TOKEN;

    const calls: string[] = [];
    jest.spyOn(globalThis, 'fetch' as never).mockImplementation((async (input: RequestInfo | URL) => {
      const url = String(input);
      calls.push(url);
      if (url.includes('/user/balance')) {
        return jsonResponse({ is_available: true, balance_infos: [{ currency: 'USD', total_balance: '1.20' }] });
      }
      return jsonResponse({ ok: true }, 200);
    }) as never);

    const result = await monitor().check();

    expect(result.snapshot.state).toBe('LOW');
    expect(result.snapshot.totalBalance).toBe('1.20');
    expect(result.notification.sent).toBe(true);
    expect(result.notification.channel).toBe('http_webhook');
    expect(calls.some((url) => url.includes('/user/balance'))).toBe(true);
  });

  it('con notify=false no envia nada', async () => {
    process.env.GUARDIAN_AI_API_KEY = 'sk-test';
    process.env.GUARDIAN_AI_PROVIDER = 'deepseek';
    jest.spyOn(globalThis, 'fetch' as never).mockImplementation((async () =>
      jsonResponse({ is_available: true, balance_infos: [{ currency: 'USD', total_balance: '50.00' }] })) as never);

    const result = await monitor().check({ notify: false });

    expect(result.snapshot.state).toBe('OK');
    expect(result.notification.attempted).toBe(false);
  });

  it('sin canal configurado no finge un envio', async () => {
    process.env.GUARDIAN_AI_API_KEY = 'sk-test';
    process.env.GUARDIAN_AI_PROVIDER = 'deepseek';
    process.env.GUARDIAN_ALERT_RECIPIENTS = '18090000001';
    delete process.env.GUARDIAN_WA_CLOUD_TOKEN;
    delete process.env.GUARDIAN_WA_PHONE_NUMBER_ID;
    delete process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL;
    jest.spyOn(globalThis, 'fetch' as never).mockImplementation((async () =>
      jsonResponse({ is_available: false, balance_infos: [{ currency: 'USD', total_balance: '0.00' }] })) as never);

    const result = await monitor().check();

    expect(result.snapshot.state).toBe('EXHAUSTED');
    expect(result.notification.sent).toBe(false);
    expect(result.notification.channel).toBeNull();
    expect(result.notification.reason).toBe('WHATSAPP_SENDER_NOT_CONFIGURED');
  });

  it('el mensaje incluye estado, importe literal y accion, sin datos de clientes', () => {
    const message = monitor().buildAlertMessage({
      state: 'LOW',
      provider: 'deepseek',
      endpoint: 'https://api.deepseek.com/user/balance',
      checkedAt: new Date('2026-10-30T02:00:00.000Z').toISOString(),
      httpStatus: 200,
      currency: 'USD',
      totalBalance: '1.20',
      grantedBalance: '0.00',
      toppedUpBalance: '1.20',
      isAvailable: true,
      lowThreshold: 5,
      error: null,
    });

    expect(message).toContain('APPYRA GUARDIAN — IA SALDO BAJO');
    expect(message).toContain('Saldo informado: 1.20 USD');
    expect(message).toContain('Umbral de aviso: 5');
    expect(message).toContain('No se modificó información de ningún cliente.');
  });

  it('el aviso de recuperacion solo aparece tras un estado en fallo', async () => {
    process.env.GUARDIAN_AI_API_KEY = 'sk-test';
    process.env.GUARDIAN_AI_PROVIDER = 'deepseek';
    process.env.GUARDIAN_ALERT_RECIPIENTS = '18090000001';
    process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL = 'https://hook.test/guardian';
    delete process.env.GUARDIAN_WA_CLOUD_TOKEN;

    let balance = '0.00';
    const texts: string[] = [];
    jest.spyOn(globalThis, 'fetch' as never).mockImplementation((async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes('/user/balance')) {
        return jsonResponse({ is_available: balance !== '0.00', balance_infos: [{ currency: 'USD', total_balance: balance }] });
      }
      texts.push(String(init?.body ?? ''));
      return jsonResponse({ ok: true }, 200);
    }) as never);

    const subject = monitor();
    const first = await subject.check();
    expect(first.snapshot.state).toBe('EXHAUSTED');
    expect(first.notification.sent).toBe(true);

    balance = '42.00';
    const second = await subject.check();
    expect(second.snapshot.state).toBe('OK');
    expect(second.notification.sent).toBe(true);
    expect(texts.some((body) => body.includes('IA RESTABLECIDA'))).toBe(true);
  });

  it('respeta la ventana anti-ruido del mismo estado', async () => {
    process.env.GUARDIAN_AI_API_KEY = 'sk-test';
    process.env.GUARDIAN_AI_PROVIDER = 'deepseek';
    process.env.GUARDIAN_ALERT_RECIPIENTS = '18090000001';
    process.env.GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL = 'https://hook.test/guardian';
    delete process.env.GUARDIAN_WA_CLOUD_TOKEN;

    jest.spyOn(globalThis, 'fetch' as never).mockImplementation((async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/user/balance')) {
        return jsonResponse({ is_available: true, balance_infos: [{ currency: 'USD', total_balance: '0.50' }] });
      }
      return jsonResponse({ ok: true }, 200);
    }) as never);

    const subject = monitor();
    const first = await subject.check();
    const second = await subject.check();

    expect(first.notification.sent).toBe(true);
    expect(second.notification.sent).toBe(false);
    expect(second.notification.reason).toContain('anti-ruido');
  });
});

describe('configuracion sin cuotas de tokens', () => {
  it('ya no existen presupuestos diarios ni mensuales de tokens', () => {
    process.env = { ...BASE_ENV };
    const config = resolveGuardianConfig();
    expect(config).not.toHaveProperty('aiTokensPerCompanyDay');
    expect(config).not.toHaveProperty('aiTokensGlobalDay');
    expect(config).not.toHaveProperty('aiTokensGlobalMonth');
    // Salvaguardas que SI se conservan.
    expect(config.aiMaxConcurrency).toBeGreaterThanOrEqual(1);
    expect(config.diagnosisMaxAttempts).toBeGreaterThanOrEqual(1);
    expect(config.aiBalanceLowThreshold).toBeGreaterThan(0);
  });
});

describe('GuardianAiBalanceMonitor — modulo Nest', () => {
  it('resuelve la inyeccion de dependencias', async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [GuardianAiBalanceMonitor],
    }).compile();

    expect(moduleRef.get(GuardianAiBalanceMonitor)).toBeDefined();
    // ConfigService/Reflector no forman parte del monitor: si aparecen en el
    // constructor, esta prueba deja de compilar el modulo y avisa.
    expect(ConfigService).toBeDefined();
    expect(Reflector).toBeDefined();
    expect(PrismaService).toBeDefined();
  });
});
