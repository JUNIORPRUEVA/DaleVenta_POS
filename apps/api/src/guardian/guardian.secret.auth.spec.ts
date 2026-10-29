import { createHmac } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { GuardianPlatformGuard } from './guardian.platform.guard';
import { GuardianWebhookController } from './guardian.webhook.controller';

/**
 * Autenticación REAL usando secretos montados como archivo (Docker Secrets).
 *
 * Complementa `guardian.secret.spec.ts`: aquel comprueba la resolución del
 * valor; este comprueba que los consumidores (webhook de Meta y guard de
 * plataforma) aceptan credenciales servidas por archivo. Sin estas pruebas el
 * defecto de UAT (archivos montados que el proceso no usaba) podría volver sin
 * que nada fallara.
 */
describe('autenticación con secretos servidos por archivo', () => {
  const originalEnv = { ...process.env };
  const APP_SECRET = 'app-secret-desde-archivo';
  const VERIFY_TOKEN = 'verify-token-desde-archivo';
  const PLATFORM_TOKEN = 'platform-token-desde-archivo';
  const PHONE_ID = '109999999999001';
  let dir: string;

  const writeSecret = (name: string, content: string): string => {
    const path = join(dir, name);
    writeFileSync(path, content, 'utf8');
    return path;
  };

  function makeRes() {
    const res: any = {
      statusCode: 200,
      body: undefined,
      status(code: number) {
        res.statusCode = code;
        return res;
      },
      json(payload: unknown) {
        res.body = payload;
        return res;
      },
      send(payload: unknown) {
        res.body = payload;
        return res;
      },
    };
    return res;
  }

  function makeReq(raw: string, signature?: string) {
    return {
      rawBody: Buffer.from(raw, 'utf8'),
      header: (name: string) =>
        String(name).toLowerCase() === 'x-hub-signature-256' ? signature : undefined,
    } as any;
  }

  function statusesPayload(phoneId: string) {
    return JSON.stringify({
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'waba-uat',
          changes: [
            {
              field: 'messages',
              value: {
                metadata: { phone_number_id: phoneId },
                statuses: [{ id: 'wamid.archivo', status: 'delivered' }],
              },
            },
          ],
        },
      ],
    });
  }

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'guardian-auth-'));
    // Entorno hermético: solo las variables *_FILE que define cada prueba.
    process.env = { ...originalEnv, GUARDIAN_WA_PHONE_NUMBER_ID: PHONE_ID };
    for (const name of [
      'GUARDIAN_WA_APP_SECRET',
      'GUARDIAN_WA_VERIFY_TOKEN',
      'GUARDIAN_PLATFORM_TOKEN',
      'GUARDIAN_WA_WABA_ID',
    ]) {
      delete process.env[name];
    }
    delete process.env.GUARDIAN_WA_APP_SECRET_FILE;
    delete process.env.GUARDIAN_WA_VERIFY_TOKEN_FILE;
    delete process.env.GUARDIAN_PLATFORM_TOKEN_FILE;
  });

  afterEach(() => {
    process.env = { ...originalEnv };
    rmSync(dir, { recursive: true, force: true });
  });

  it('el GET de verificación acepta el token servido por archivo', () => {
    process.env.GUARDIAN_WA_VERIFY_TOKEN_FILE = writeSecret('verify', `${VERIFY_TOKEN}\n`);
    const controller = new GuardianWebhookController({ markDelivery: jest.fn() } as any);
    const res = makeRes();

    controller.verify('subscribe', VERIFY_TOKEN, 'challenge-abc', res);

    expect(res.statusCode).toBe(200);
    expect(res.body).toBe('challenge-abc');
  });

  it('el GET de verificación sigue fallando en cerrado sin archivo ni variable', () => {
    const controller = new GuardianWebhookController({ markDelivery: jest.fn() } as any);
    const res = makeRes();

    controller.verify('subscribe', VERIFY_TOKEN, 'challenge-abc', res);

    expect(res.statusCode).toBe(403);
  });

  it('el POST acepta una firma HMAC válida calculada con el App Secret del archivo', async () => {
    process.env.GUARDIAN_WA_APP_SECRET_FILE = writeSecret('app', APP_SECRET);
    const markDelivery = jest.fn(async () => ({ updated: 1 }));
    const controller = new GuardianWebhookController({ markDelivery } as any);
    const raw = statusesPayload(PHONE_ID);
    const signature = `sha256=${createHmac('sha256', APP_SECRET).update(raw).digest('hex')}`;
    const res = makeRes();

    await controller.receive(makeReq(raw, signature), res);

    expect(res.statusCode).toBe(200);
    expect(markDelivery).toHaveBeenCalledTimes(1);
  });

  it('el POST rechaza una firma calculada con otro secreto', async () => {
    process.env.GUARDIAN_WA_APP_SECRET_FILE = writeSecret('app', APP_SECRET);
    const markDelivery = jest.fn(async () => ({ updated: 1 }));
    const controller = new GuardianWebhookController({ markDelivery } as any);
    const raw = statusesPayload(PHONE_ID);
    const signature = `sha256=${createHmac('sha256', 'secreto-equivocado').update(raw).digest('hex')}`;
    const res = makeRes();

    await controller.receive(makeReq(raw, signature), res);

    expect(res.statusCode).toBe(401);
    expect(markDelivery).not.toHaveBeenCalled();
  });

  it('sin App Secret por ninguna vía el POST sigue respondiendo 503', async () => {
    const controller = new GuardianWebhookController({
      markDelivery: jest.fn(async () => ({ updated: 1 })),
    } as any);
    const raw = statusesPayload(PHONE_ID);
    const res = makeRes();

    await controller.receive(makeReq(raw, `sha256=${'0'.repeat(64)}`), res);

    expect(res.statusCode).toBe(503);
    expect(res.body).toEqual({ ok: false, reason: 'WEBHOOK_NOT_CONFIGURED' });
  });

  it('el guard de plataforma acepta el token servido por archivo', () => {
    process.env.GUARDIAN_PLATFORM_TOKEN_FILE = writeSecret('platform', PLATFORM_TOKEN);
    const guard = new GuardianPlatformGuard();
    const context: any = {
      switchToHttp: () => ({
        getRequest: () => ({ headers: { 'x-guardian-platform-token': PLATFORM_TOKEN } }),
      }),
    };

    expect(guard.canActivate(context)).toBe(true);
  });

  it('el guard de plataforma rechaza un token distinto aunque el archivo exista', () => {
    process.env.GUARDIAN_PLATFORM_TOKEN_FILE = writeSecret('platform', PLATFORM_TOKEN);
    const guard = new GuardianPlatformGuard();
    const context: any = {
      switchToHttp: () => ({
        getRequest: () => ({ headers: { 'x-guardian-platform-token': 'token-equivocado' } }),
      }),
    };

    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  it('el guard de plataforma falla en cerrado (503) sin secreto configurado', () => {
    const guard = new GuardianPlatformGuard();
    const context: any = {
      switchToHttp: () => ({
        getRequest: () => ({ headers: { 'x-guardian-platform-token': PLATFORM_TOKEN } }),
      }),
    };

    expect(() => guard.canActivate(context)).toThrow(ServiceUnavailableException);
  });
});
