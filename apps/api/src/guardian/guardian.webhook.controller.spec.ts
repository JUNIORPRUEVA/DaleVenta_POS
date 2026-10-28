import { createHmac } from 'node:crypto';
import { GuardianWebhookController } from './guardian.webhook.controller';

/**
 * Pruebas del webhook de WhatsApp Cloud API (Meta) sin tráfico real.
 *
 * Se cubren los controles exigidos: verificación GET, HMAC SHA-256 sobre el
 * cuerpo CRUDO, fail-closed sin App Secret, aislamiento por Phone Number ID,
 * eventos duplicados, eventos desordenados y confirmación de estados
 * desconocidos sin tocar la alerta.
 */

const APP_SECRET = 'app-secret-uat';
const VERIFY_TOKEN = 'verify-token-uat';
const PHONE_ID = '109999999999001';
const OTHER_PHONE_ID = '109999999999002';

function sign(raw: string, secret = APP_SECRET): string {
  return `sha256=${createHmac('sha256', secret).update(raw).digest('hex')}`;
}

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

function statusesPayload(phoneId: string, statuses: Array<Record<string, unknown>>) {
  return JSON.stringify({
    object: 'whatsapp_business_account',
    entry: [
      {
        id: 'waba-uat',
        changes: [
          {
            field: 'messages',
            value: { metadata: { phone_number_id: phoneId }, statuses },
          },
        ],
      },
    ],
  });
}

describe('GuardianWebhookController (WhatsApp Cloud API)', () => {
  const originalEnv = { ...process.env };
  let markDelivery: jest.Mock;
  let controller: GuardianWebhookController;

  beforeEach(() => {
    markDelivery = jest.fn(async () => ({ updated: 1 }));
    controller = new GuardianWebhookController({ markDelivery } as any);
    process.env = {
      ...originalEnv,
      GUARDIAN_WA_APP_SECRET: APP_SECRET,
      GUARDIAN_WA_VERIFY_TOKEN: VERIFY_TOKEN,
      GUARDIAN_WA_PHONE_NUMBER_ID: PHONE_ID,
    };
    // El spec debe ser hermético: ninguna variable del entorno real (por ejemplo
    // un WABA ID de la máquina) puede alterar el resultado.
    delete process.env.GUARDIAN_WA_WABA_ID;
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  describe('verificación GET de Meta', () => {
    it('devuelve el challenge cuando el token coincide', () => {
      const res = makeRes();
      controller.verify('subscribe', VERIFY_TOKEN, 'challenge-123', res);

      expect(res.statusCode).toBe(200);
      expect(res.body).toBe('challenge-123');
    });

    it('rechaza con 403 un token incorrecto', () => {
      const res = makeRes();
      controller.verify('subscribe', 'otro-token', 'challenge-123', res);

      expect(res.statusCode).toBe(403);
    });

    it('rechaza con 403 si no hay verify token configurado (fail-closed)', () => {
      delete process.env.GUARDIAN_WA_VERIFY_TOKEN;
      const res = makeRes();
      controller.verify('subscribe', VERIFY_TOKEN, 'challenge-123', res);

      expect(res.statusCode).toBe(403);
    });

    it('rechaza un modo distinto de subscribe', () => {
      const res = makeRes();
      controller.verify('unsubscribe', VERIFY_TOKEN, 'challenge-123', res);

      expect(res.statusCode).toBe(403);
    });
  });

  describe('firma HMAC del cuerpo crudo', () => {
    it('sin App Secret responde 503 y no procesa nada', async () => {
      delete process.env.GUARDIAN_WA_APP_SECRET;
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.1', status: 'delivered' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(res.statusCode).toBe(503);
      expect(markDelivery).not.toHaveBeenCalled();
    });

    it('sin cabecera de firma responde 401', async () => {
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.1', status: 'delivered' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw), res);

      expect(res.statusCode).toBe(401);
      expect(markDelivery).not.toHaveBeenCalled();
    });

    it('con firma inválida responde 401', async () => {
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.1', status: 'delivered' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw, 'secreto-equivocado')), res);

      expect(res.statusCode).toBe(401);
      expect(markDelivery).not.toHaveBeenCalled();
    });

    it('valida sobre el cuerpo crudo: un JSON reserializado ya no coincide', async () => {
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.1', status: 'delivered' }]);
      const reformatted = JSON.stringify(JSON.parse(raw), null, 2);
      const res = makeRes();

      await controller.receive(makeReq(reformatted, sign(raw)), res);

      expect(res.statusCode).toBe(401);
      expect(markDelivery).not.toHaveBeenCalled();
    });

    it('acepta una firma válida y aplica el estado', async () => {
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.1', status: 'delivered' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(res.statusCode).toBe(200);
      expect(markDelivery).toHaveBeenCalledWith('wamid.1', 'delivered', null);
      expect(res.body).toMatchObject({ ok: true, processed: 1, ignored: 0 });
    });

    it('rechaza un cuerpo que no es JSON válido tras validar la firma', async () => {
      const raw = 'esto-no-es-json';
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(res.statusCode).toBe(400);
      expect(markDelivery).not.toHaveBeenCalled();
    });
  });

  describe('aislamiento por número emisor', () => {
    it('ignora un webhook de otro Phone Number ID', async () => {
      const raw = statusesPayload(OTHER_PHONE_ID, [{ id: 'wamid.ajeno', status: 'read' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(res.statusCode).toBe(200);
      expect(markDelivery).not.toHaveBeenCalled();
      expect(res.body).toMatchObject({ processed: 0 });
      expect(res.body.ignored).toBeGreaterThan(0);
    });

    it('ignora el lote si el WABA ID configurado no coincide', async () => {
      process.env.GUARDIAN_WA_WABA_ID = 'waba-propia';
      const raw = JSON.stringify({
        object: 'whatsapp_business_account',
        entry: [
          {
            id: 'waba-ajena',
            changes: [
              {
                value: {
                  metadata: { phone_number_id: PHONE_ID },
                  statuses: [{ id: 'wamid.otra-waba', status: 'read' }],
                },
              },
            ],
          },
        ],
      });
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery).not.toHaveBeenCalled();
      expect(res.body.ignored).toBe(1);
    });

    it('procesa el lote cuando el WABA ID coincide', async () => {
      process.env.GUARDIAN_WA_WABA_ID = 'waba-uat';
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.waba-ok', status: 'read' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery).toHaveBeenCalledWith('wamid.waba-ok', 'read', null);
    });

    it('sin Phone Number ID configurado procesa el estado: la firma HMAC ya autentica el payload', async () => {
      delete process.env.GUARDIAN_WA_PHONE_NUMBER_ID;
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.sin-id', status: 'delivered' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery).toHaveBeenCalledWith('wamid.sin-id', 'delivered', null);
      expect(res.body.processed).toBe(1);
    });

    it('procesa solo el número propio dentro de un lote mixto', async () => {
      const raw = JSON.stringify({
        object: 'whatsapp_business_account',
        entry: [
          {
            id: 'waba-uat',
            changes: [
              {
                value: {
                  metadata: { phone_number_id: PHONE_ID },
                  statuses: [{ id: 'wamid.propio', status: 'delivered' }],
                },
              },
              {
                value: {
                  metadata: { phone_number_id: OTHER_PHONE_ID },
                  statuses: [{ id: 'wamid.ajeno', status: 'read' }],
                },
              },
            ],
          },
        ],
      });
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery).toHaveBeenCalledTimes(1);
      expect(markDelivery).toHaveBeenCalledWith('wamid.propio', 'delivered', null);
      expect(res.body.ignored).toBe(1);
    });
  });

  describe('eventos duplicados, desordenados y desconocidos', () => {
    it('un evento duplicado se reenvía al servicio, que es idempotente por estado', async () => {
      const raw = statusesPayload(PHONE_ID, [
        { id: 'wamid.dup', status: 'delivered' },
        { id: 'wamid.dup', status: 'delivered' },
      ]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(res.statusCode).toBe(200);
      expect(markDelivery).toHaveBeenCalledTimes(2);
      expect(res.body.processed).toBe(2);
    });

    it('un lote desordenado se procesa en el orden recibido sin descartar eventos', async () => {
      const raw = statusesPayload(PHONE_ID, [
        { id: 'wamid.ord', status: 'read' },
        { id: 'wamid.ord', status: 'delivered' },
      ]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery.mock.calls.map((call) => call[1])).toEqual(['read', 'delivered']);
    });

    it('un estado desconocido se cuenta como ignorado y no toca la alerta', async () => {
      const raw = statusesPayload(PHONE_ID, [{ id: 'wamid.x', status: 'deleted' }]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery).not.toHaveBeenCalled();
      expect(res.body).toMatchObject({ ok: true, processed: 0, ignored: 1 });
    });

    it('propaga el mensaje de error del proveedor en un fallo permanente', async () => {
      const raw = statusesPayload(PHONE_ID, [
        {
          id: 'wamid.fail',
          status: 'failed',
          errors: [{ code: 131047, title: 'Re-engagement message' }],
        },
      ]);
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(markDelivery).toHaveBeenCalledWith('wamid.fail', 'failed', 'Re-engagement message');
    });

    it('un payload sin entry no rompe el endpoint', async () => {
      const raw = JSON.stringify({ object: 'whatsapp_business_account' });
      const res = makeRes();

      await controller.receive(makeReq(raw, sign(raw)), res);

      expect(res.statusCode).toBe(200);
      expect(markDelivery).not.toHaveBeenCalled();
    });
  });
});
