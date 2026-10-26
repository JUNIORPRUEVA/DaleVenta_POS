import {
  EvolutionOutboxChannel,
  HttpWebhookChannel,
  WhatsAppCloudChannel,
} from './guardian.alert.channels';

function fetchDouble(response: { ok: boolean; status: number; body?: string }) {
  return jest.fn(async () => ({
    ok: response.ok,
    status: response.status,
    text: async () => response.body ?? '{}',
  })) as unknown as typeof fetch;
}

describe('WhatsAppCloudChannel', () => {
  const baseOptions = { token: 'token-uat', phoneNumberId: '123456789' };

  it('sin credenciales no está configurado', () => {
    const channel = new WhatsAppCloudChannel({ token: '', phoneNumberId: '' });
    expect(channel.isConfigured()).toBe(false);
  });

  it('envía plantilla HSM con 8 parámetros cuando está configurada', async () => {
    const fetchImpl = fetchDouble({
      ok: true,
      status: 200,
      body: JSON.stringify({ messages: [{ id: 'wamid.ABC' }] }),
    });
    const channel = new WhatsAppCloudChannel({
      ...baseOptions,
      templateName: 'guardian_alerta_admin',
      templateLanguage: 'es',
      fetchImpl,
    });

    const result = await channel.send({
      to: '+1 809 555 0000',
      text: 'mensaje de respaldo',
      dedupeKey: 'k1',
      allowOutsideBusinessHours: true,
      templateParams: ['CRÍTICO', 'Empresa', 'cash / close', '03:14 a. m.', 'Problema', 'Pendiente', 'Impacto', 'INC-ABCD12'],
    });

    expect(result.ok).toBe(true);
    expect(result.providerMessageId).toBe('wamid.ABC');

    const body = JSON.parse((fetchImpl as jest.Mock).mock.calls[0][1].body);
    expect(body.type).toBe('template');
    expect(body.template.name).toBe('guardian_alerta_admin');
    expect(body.template.language.code).toBe('es');
    expect(body.template.components[0].parameters).toHaveLength(8);
    expect(body.to).toBe('18095550000');
  });

  it('usa texto plano cuando no hay plantilla configurada', async () => {
    const fetchImpl = fetchDouble({ ok: true, status: 200, body: '{}' });
    const channel = new WhatsAppCloudChannel({ ...baseOptions, fetchImpl });

    await channel.send({
      to: '18095550000',
      text: 'hola',
      dedupeKey: 'k2',
      allowOutsideBusinessHours: true,
    });

    const body = JSON.parse((fetchImpl as jest.Mock).mock.calls[0][1].body);
    expect(body.type).toBe('text');
    expect(body.text.body).toBe('hola');
  });

  it('clasifica 429/5xx como transitorio y 400 como permanente', async () => {
    const throttled = new WhatsAppCloudChannel({
      ...baseOptions,
      fetchImpl: fetchDouble({ ok: false, status: 429, body: 'rate limit' }),
    });
    const throttledResult = await throttled.send({
      to: '18095550000',
      text: 'x',
      dedupeKey: 'k3',
      allowOutsideBusinessHours: true,
    });
    expect(throttledResult.ok).toBe(false);
    expect(throttledResult.classification).toBe('transient');

    const invalid = new WhatsAppCloudChannel({
      ...baseOptions,
      fetchImpl: fetchDouble({ ok: false, status: 400, body: 'invalid recipient' }),
    });
    const invalidResult = await invalid.send({
      to: '18095550000',
      text: 'x',
      dedupeKey: 'k4',
      allowOutsideBusinessHours: true,
    });
    expect(invalidResult.classification).toBe('permanent');
  });
});

describe('canales de respaldo', () => {
  it('el webhook de respaldo envía el payload esperado', async () => {
    const fetchImpl = fetchDouble({ ok: true, status: 202 });
    const channel = new HttpWebhookChannel({
      url: 'https://respaldo.example.com/hook',
      secret: 'secreto-uat',
      fetchImpl,
    });

    const result = await channel.send({
      to: '18095550000',
      text: 'alerta',
      dedupeKey: 'k5',
      allowOutsideBusinessHours: true,
    });

    expect(result.ok).toBe(true);
    const [url, init] = (fetchImpl as jest.Mock).mock.calls[0];
    expect(url).toBe('https://respaldo.example.com/hook');
    expect(init.headers['x-guardian-secret']).toBe('secreto-uat');
    expect(JSON.parse(init.body).source).toBe('appyra-guardian');
  });

  it('el canal Evolution reutiliza el outbox y respeta 24/7', async () => {
    const enqueue = jest.fn(async () => ({ id: 'outbox-9' }));
    const channel = new EvolutionOutboxChannel({ enabled: () => true, enqueue });

    const result = await channel.send({
      to: '18095550000',
      text: 'alerta',
      dedupeKey: 'k6',
      allowOutsideBusinessHours: true,
    });

    expect(result.ok).toBe(true);
    expect(result.providerMessageId).toBe('outbox:outbox-9');
    expect(enqueue).toHaveBeenCalledWith(
      expect.objectContaining({ allowOutsideBusinessHours: true, dedupeKey: 'k6' }),
    );
  });
});
