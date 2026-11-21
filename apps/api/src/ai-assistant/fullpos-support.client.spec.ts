import { ConfigService } from '@nestjs/config';
import { createHmac } from 'node:crypto';
import { FullposSupportClient, supportIntent } from './fullpos-support.client';

describe('FullPOS CRM support bridge', () => {
  const secret = 'local-fixture-shared-support-secret-only';
  const client = (url = 'http://127.0.0.1:1234') => new FullposSupportClient(new ConfigService({
    APPYRA_CRM_SUPPORT_URL: url, FULLPOS_SUPPORT_SHARED_SECRET: secret,
  }));
  afterEach(() => jest.restoreAllMocks());
  it('only acts on explicit report / human intent, never on quoted or ordinary help', () => {
    expect(supportIntent('Quiero hablar con soporte humano')).toBe('human');
    expect(supportIntent('Pásame con un humano por favor')).toBe('human');
    expect(supportIntent('Me gustaría hablar con una persona porque necesito ayuda')).toBe('human');
    expect(supportIntent('soporte humano')).toBe('human');
    expect(supportIntent('Quiero reportar una avería: no carga')).toBe('incident');
    expect(supportIntent('¿Cómo reportar una avería?')).toBeNull();
    expect(supportIntent('No quiero hablar con soporte humano')).toBeNull();
    expect(supportIntent('Explícame la pantalla')).toBeNull();
    expect(supportIntent('Quiero reportar una avería')).toBeNull();
  });
  it('signs the exact scope and body and never forwards credentials through redirects', async () => {
    const input = { action: 'open', companyId: 'company-a', userId: 'user-a' };
    const fetchMock = jest.spyOn(globalThis, 'fetch').mockResolvedValue({ ok: true,
      json: async () => ({ ok: true, case: { id: 'case-a', reference: 'SUP-1', messages: [] } }) } as Response);
    await client().request(input);
    const [url, options] = fetchMock.mock.calls[0];
    expect(String(url)).toBe('http://127.0.0.1:1234/api/integrations/fullpos/support');
    expect(options?.redirect).toBe('error');
    const headers = options?.headers as Record<string, string>;
    expect(headers['x-fullpos-signature']).toBe(createHmac('sha256', secret)
      .update(`${headers['x-fullpos-timestamp']}\nPOST\n/api/integrations/fullpos/support\n${JSON.stringify(input)}`).digest('hex'));
  });
  it('does not claim success for a missing configuration, timeout or invalid receipt', async () => {
    await expect(new FullposSupportClient(new ConfigService()).request({})).rejects.toThrow('No pudimos confirmar');
    const fetchMock = jest.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('timeout'));
    await expect(client().request({})).rejects.toThrow('No pudimos confirmar');
    fetchMock.mockResolvedValue({ ok: true, json: async () => ({ ok: true }) } as Response);
    await expect(client().request({})).rejects.toThrow('No pudimos confirmar');
    await expect(client('http://untrusted.invalid').request({})).rejects.toThrow('No pudimos confirmar');
  });
});
