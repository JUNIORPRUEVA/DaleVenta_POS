import { ConfigService } from '@nestjs/config';

import { AppyraIaClient, AppyraIaError, toFullPosChatResponse } from './appyra-ia.client';
import type { AppyraIaChatResult } from './appyra-ia.client';

const TEST_TOKEN = 'appyra_test_token_no_real';

function buildClient(overrides: Record<string, string> = {}): AppyraIaClient {
  const values: Record<string, string> = {
    APPYRA_IA_ENABLED: 'true',
    APPYRA_IA_BASE_URL: 'http://127.0.0.1:4400/v1/',
    APPYRA_IA_RUNTIME_TOKEN: TEST_TOKEN,
    APPYRA_IA_PRODUCT_KEY: 'fullpos',
    APPYRA_IA_TIMEOUT_MS: '20000',
    ...overrides,
  };
  const config = {
    get: (key: string): string | undefined => values[key],
  } as unknown as ConfigService;
  return new AppyraIaClient(config);
}

function buildResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  } as unknown as Response;
}

const OK_BODY = {
  conversationId: '11111111-1111-1111-1111-111111111111',
  agent: { id: 'agent-1', name: 'Laura (soporte FullPOS)', version: 1 },
  reply: {
    text: 'Respuesta de prueba',
    mode: 'local',
    model: 'qwen2.5-coder:7b',
    escalated: false,
    requiresHumanReview: false,
    handoffReasons: [],
    limitations: [],
    sources: [{ title: 'Procedimiento aprobado', category: 'fullpos', source: 'kb:1' }],
  },
  duplicate: false,
};

describe('AppyraIaClient', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  describe('activación', () => {
    it('está desactivado si la bandera está apagada', () => {
      const client = buildClient({ APPYRA_IA_ENABLED: 'false' });
      expect(client.isEnabled()).toBe(false);
    });

    it('está desactivado si falta la credencial', () => {
      const client = buildClient({ APPYRA_IA_RUNTIME_TOKEN: '' });
      expect(client.isEnabled()).toBe(false);
    });

    it('está activo con bandera, URL y credencial', () => {
      expect(buildClient().isEnabled()).toBe(true);
    });
  });

  describe('cuerpo enviado', () => {
    it('sólo envía el contexto de la lista blanca', async () => {
      const fetchMock = jest.fn().mockResolvedValue(buildResponse(OK_BODY));
      global.fetch = fetchMock as unknown as typeof fetch;

      const contextWithExtra = {
        route: '/catalogo',
        module: 'catalogo',
        screenName: 'Catálogo',
        entityType: 'client',
        entityId: 'client-123',
      };

      await buildClient().chat({
        message: '¿Dónde creo un producto?',
        conversationId: '11111111-1111-1111-1111-111111111111',
        clientMessageId: 'msg-1',
        context: contextWithExtra,
      });

      expect(fetchMock).toHaveBeenCalledTimes(1);
      const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      expect(url).toBe('http://127.0.0.1:4400/v1/agent-runtime/chat');
      expect((init.headers as Record<string, string>)['Authorization']).toBe(`Bearer ${TEST_TOKEN}`);

      const body = JSON.parse(init.body as string);
      expect(body).toEqual({
        productKey: 'fullpos',
        message: '¿Dónde creo un producto?',
        conversationId: '11111111-1111-1111-1111-111111111111',
        clientMessageId: 'msg-1',
        context: { route: '/catalogo', module: 'catalogo', screenName: 'Catálogo' },
      });
      expect(JSON.stringify(body)).not.toContain('client-123');
      expect(JSON.stringify(body)).not.toContain('entityType');
    });

    it('descarta una ruta que APPYRA IA rechazaría', async () => {
      const fetchMock = jest.fn().mockResolvedValue(buildResponse(OK_BODY));
      global.fetch = fetchMock as unknown as typeof fetch;

      await buildClient().chat({
        message: 'hola',
        context: { route: '/clientes?id=7', module: 'clientes' },
      });

      const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      const body = JSON.parse(init.body as string);
      expect(body.context).toEqual({ module: 'clientes' });
    });
  });

  describe('mapeo de respuesta', () => {
    it('extrae texto, agente, conversación y fuentes', async () => {
      global.fetch = jest
        .fn()
        .mockResolvedValue(buildResponse(OK_BODY)) as unknown as typeof fetch;

      const result = await buildClient().chat({ message: 'hola', context: { module: 'catalogo' } });

      expect(result).toEqual({
        conversationId: '11111111-1111-1111-1111-111111111111',
        agentName: 'Laura (soporte FullPOS)',
        agentVersion: 1,
        text: 'Respuesta de prueba',
        mode: 'local',
        model: 'qwen2.5-coder:7b',
        escalated: false,
        requiresHumanReview: false,
        handoffReasons: [],
        limitations: [],
        sources: [{ title: 'Procedimiento aprobado', category: 'fullpos', source: 'kb:1' }],
      });
    });

    it('conserva la derivación a revisión humana', async () => {
      const escalatedBody = {
        ...OK_BODY,
        reply: {
          ...OK_BODY.reply,
          escalated: true,
          requiresHumanReview: true,
          handoffReasons: ['Sin procedimiento publicado'],
        },
      };
      global.fetch = jest
        .fn()
        .mockResolvedValue(buildResponse(escalatedBody)) as unknown as typeof fetch;

      const result = await buildClient().chat({ message: 'hola', context: { module: 'general' } });
      expect(result.escalated).toBe(true);
      expect(result.handoffReasons).toEqual(['Sin procedimiento publicado']);
    });

    it('rechaza una respuesta sin turno', async () => {
      global.fetch = jest
        .fn()
        .mockResolvedValue(buildResponse({ conversationId: null })) as unknown as typeof fetch;

      await expect(
        buildClient().chat({ message: 'hola', context: { module: 'general' } }),
      ).rejects.toMatchObject({ kind: 'payload' });
    });
  });

  describe('errores', () => {
    it.each([401, 403, 404, 409, 500])('propaga el estado HTTP %i sin exponer el token', async (status) => {
      global.fetch = jest
        .fn()
        .mockResolvedValue(buildResponse({ code: 'ERR', message: 'fallo' }, status)) as unknown as typeof fetch;

      const error = await buildClient()
        .chat({ message: 'hola', context: { module: 'general' } })
        .catch((caught: unknown) => caught);

      expect(error).toBeInstanceOf(AppyraIaError);
      expect((error as AppyraIaError).kind).toBe('http');
      expect((error as AppyraIaError).status).toBe(status);
      expect((error as Error).message).not.toContain(TEST_TOKEN);
    });

    it('marca el timeout cuando la petición se aborta', async () => {
      const aborted = Object.assign(new Error('aborted'), { name: 'AbortError' });
      global.fetch = jest.fn().mockRejectedValue(aborted) as unknown as typeof fetch;

      await expect(
        buildClient().chat({ message: 'hola', context: { module: 'general' } }),
      ).rejects.toMatchObject({ kind: 'timeout' });
    });
  });

  describe('toFullPosChatResponse', () => {
    const baseResult: AppyraIaChatResult = {
      conversationId: '11111111-1111-1111-1111-111111111111',
      agentName: 'Laura',
      agentVersion: 1,
      text: 'Texto',
      mode: 'local',
      model: 'qwen2.5-coder:7b',
      escalated: false,
      requiresHumanReview: false,
      handoffReasons: [],
      limitations: [],
      sources: [{ title: 'Regla', category: 'fullpos' }],
    };

    it('mapea a la respuesta del panel con citas numeradas', () => {
      const mapped = toFullPosChatResponse(baseResult, 'catalogo');
      expect(mapped.source).toBe('appyra-ia');
      expect(mapped.content).toBe('Texto');
      expect(mapped.citations).toEqual([
        { id: 'appyra:1', module: 'catalogo', category: 'fullpos', title: 'Regla' },
      ]);
      expect(mapped.conversationId).toBe(baseResult.conversationId);
    });

    it('marca como reglas una respuesta simulada', () => {
      const mapped = toFullPosChatResponse({ ...baseResult, mode: 'simulated' }, 'general');
      expect(mapped.source).toBe('appyra-ia-rules');
    });

    it('marca revisión humana cuando hay derivación', () => {
      const mapped = toFullPosChatResponse({ ...baseResult, escalated: true }, 'general');
      expect(mapped.requiresHumanReview).toBe(true);
    });
  });

  describe('adjuntos', () => {
    it('sube el archivo con la credencial multimedia y devuelve el trabajo', async () => {
      const fetchMock = jest
        .fn()
        .mockResolvedValueOnce(buildResponse({ jobId: 'job-1' }, 202))
        .mockResolvedValueOnce(
          buildResponse({ jobId: 'job-1', status: 'COMPLETED', engine: 'rapidocr' }),
        );
      global.fetch = fetchMock as unknown as typeof fetch;

      const result = await buildClient({ APPYRA_IA_MEDIA_TOKEN: 'appyra_media_falso' }).uploadMedia({
        buffer: Buffer.from('imagen'),
        filename: 'captura.png',
        mimetype: 'image/png',
      });

      expect(result).toEqual({ jobId: 'job-1', status: 'COMPLETED', engine: 'rapidocr' });
      const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      expect(url).toBe('http://127.0.0.1:4400/v1/media');
      expect((init.headers as Record<string, string>)['Authorization']).toBe(
        'Bearer appyra_media_falso',
      );
    });

    it('sin credencial multimedia no intenta subir', async () => {
      await expect(
        buildClient({ APPYRA_IA_MEDIA_TOKEN: '' }).uploadMedia({
          buffer: Buffer.from('x'),
          filename: 'a.png',
          mimetype: 'image/png',
        }),
      ).rejects.toMatchObject({ kind: 'configuration' });
    });

    it('un archivo rechazado por el motor se informa como error', async () => {
      global.fetch = jest
        .fn()
        .mockResolvedValue(buildResponse({ code: 'UNSUPPORTED' }, 415)) as unknown as typeof fetch;

      await expect(
        buildClient({ APPYRA_IA_MEDIA_TOKEN: 'appyra_media_falso' }).uploadMedia({
          buffer: Buffer.from('x'),
          filename: 'a.exe',
          mimetype: 'application/octet-stream',
        }),
      ).rejects.toMatchObject({ kind: 'http', status: 415 });
    });
  });
});
