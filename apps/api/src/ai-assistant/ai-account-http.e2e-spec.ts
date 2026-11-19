import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { INestApplication } from '@nestjs/common';
import { createHmac, randomBytes } from 'node:crypto';
import request from 'supertest';
import { AiAccountController } from './ai-account.controller';
import { LicenseService } from '../license/license.service';

describe('IA: consulta de cuenta HTTP de solo lectura', () => {
  let app: INestApplication;
  const secret = randomBytes(32).toString('hex');
  const summary = jest.fn(async (companyId: string) => ({ companyName: companyId, planLabel: 'Plan ficticio' }));
  function token(companyId: string, extra = {}) {
    const payload = { c: companyId, u: 'synthetic-user', r: 'ADMIN', i: 'appyra-ai', a: 'fullpos-cloud',
      e: Math.floor(Date.now() / 1000) + 60, j: 'synthetic-nonce', ...extra };
    const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
    return `${encoded}.${createHmac('sha256', secret).update(encoded).digest('hex')}`;
  }
  beforeAll(async () => {
    const module = await Test.createTestingModule({ controllers: [AiAccountController], providers: [
      { provide: ConfigService, useValue: { get: () => secret } },
      { provide: LicenseService, useValue: { getAssistantAccountSummary: summary } },
    ] }).compile();
    app = module.createNestApplication(); await app.init();
  });
  afterAll(async () => { await app?.close(); });
  beforeEach(() => summary.mockClear());
  it('rechaza ausencia, manipulacion, caducidad y direccion equivocada sin consultar cuentas', async () => {
    await request(app.getHttpServer()).get('/ai/account').expect(401);
    for (const invalid of [token('a') + 'bad', token('a', { e: 1 }), token('a', { i: 'fullpos-cloud', a: 'appyra-ai' })]) {
      await request(app.getHttpServer()).get('/ai/account').set('x-appyra-context', invalid).expect(401);
    }
    expect(summary).not.toHaveBeenCalled();
  });
  it('ignora empresa por query y mantiene separados los contextos firmados', async () => {
    await request(app.getHttpServer()).get('/ai/account?companyId=other').set('x-appyra-context', token('a'))
      .expect(200).expect({ ok: true, account: { companyName: 'a', planLabel: 'Plan ficticio' } });
    await request(app.getHttpServer()).get('/ai/account').set('x-appyra-context', token('b')).expect(200);
    expect(summary.mock.calls).toEqual([['a'], ['b']]);
  });
});
