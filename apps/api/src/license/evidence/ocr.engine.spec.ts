import { createServer, Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { randomBytes, randomUUID } from 'node:crypto';
import { ConfigService } from '@nestjs/config';
import { OcrEngine } from './ocr.engine';

describe('OCR de planes: contrato HTTP de APPYRA', () => {
  let server: Server;
  let baseUrl: string;
  let calls: Array<{ method: string; url: string; body: string; authorization?: string }>;
  let handler: (method: string, url: string) => { status: number; body: unknown };
  const token = randomBytes(24).toString('hex');
  const jobId = randomUUID();
  const input = { buffer: Buffer.from('synthetic-image'), mime: 'image/png', fileName: 'prueba.png' };
  const completed = (extra = {}) => ({ jobId, status: 'COMPLETED', capability: 'EXTRACT_IMAGE_TEXT',
    externalCalls: 0, result: { capability: 'EXTRACT_IMAGE_TEXT', text: 'Texto sintetico' }, ...extra });

  beforeEach(async () => {
    calls = [];
    handler = method => method === 'POST' ? { status: 202, body: { jobId, status: 'PENDING' } }
      : { status: 200, body: completed() };
    server = createServer(async (req, res) => {
      let body = ''; for await (const chunk of req) body += chunk.toString();
      calls.push({ method: req.method!, url: req.url!, body, authorization: req.headers.authorization });
      const response = handler(req.method!, req.url!);
      res.writeHead(response.status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(response.body));
    });
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
    baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterEach(async () => { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); });
  function engine(extra: Record<string, unknown> = {}) {
    const values: Record<string, unknown> = { APPYRA_MEDIA_BASE_URL: baseUrl, APPYRA_MEDIA_TOKEN: token,
      APPYRA_MEDIA_OCR_PROTOCOL: 'appyra-jobs', ...extra };
    return new OcrEngine({ get: (key: string) => values[key] } as ConfigService);
  }

  it('sube una sola vez, espera el trabajo y acepta un resultado correlacionado sin llamadas externas', async () => {
    let reads = 0;
    handler = method => method === 'POST' ? { status: 202, body: { jobId } }
      : { status: 200, body: ++reads === 1 ? { jobId, status: 'PROCESSING', capability: 'EXTRACT_IMAGE_TEXT' } : completed() };
    await expect(engine().extractText(input)).resolves.toEqual({ ok: true, text: 'Texto sintetico', engine: 'media-engine' });
    expect(calls.map(c => `${c.method} ${c.url}`)).toEqual(['POST /v1/media', `GET /v1/media/${jobId}/result`, `GET /v1/media/${jobId}/result`]);
    expect(calls.every(c => c.authorization === `Bearer ${token}`)).toBe(true);
    expect(calls[0].body).toContain('name="capability"\r\n\r\nEXTRACT_IMAGE_TEXT');
    expect(calls[0].body).toContain('name="allowExternal"\r\n\r\nfalse');
    expect(calls[0].body).not.toContain('name="mode"');
  });
  it('solicita extraccion de documentos para PDF', async () => {
    handler = method => method === 'POST' ? { status: 202, body: { jobId } }
      : { status: 200, body: completed({ capability: 'EXTRACT_DOCUMENT', result: { capability: 'EXTRACT_DOCUMENT', text: 'PDF sintetico' } }) };
    await expect(engine().extractText({ ...input, mime: 'application/pdf', fileName: 'prueba.pdf' })).resolves.toMatchObject({ ok: true });
    expect(calls[0].body).toContain('EXTRACT_DOCUMENT');
  });
  it('sin token no envia el comprobante', async () => {
    await expect(engine({ APPYRA_MEDIA_TOKEN: '' }).extractText(input)).resolves.toMatchObject({ ok: false, error: 'ocr-token-required' });
    expect(calls).toHaveLength(0);
  });
  it('no reintenta un POST rechazado', async () => {
    handler = () => ({ status: 401, body: {} });
    await expect(engine().extractText(input)).resolves.toMatchObject({ ok: false, error: 'ocr-http-401' });
    expect(calls).toHaveLength(1);
  });
  it('no sigue identificadores de trabajo arbitrarios', async () => {
    handler = () => ({ status: 202, body: { jobId: '../otro' } });
    await expect(engine().extractText(input)).resolves.toMatchObject({ ok: false, error: 'ocr-invalid-job' });
    expect(calls).toHaveLength(1);
  });
  it.each([
    { jobId: randomUUID() }, { capability: 'ANALYZE_IMAGE' }, { status: 'FAILED' },
    { status: 'CANCELLED' }, { externalCalls: 1 }, { result: { capability: 'EXTRACT_IMAGE_TEXT', text: '' } },
  ])('rechaza resultados ajenos, fallidos, externos o vacios: %j', async extra => {
    handler = method => method === 'POST' ? { status: 202, body: { jobId } } : { status: 200, body: completed(extra) };
    await expect(engine().extractText(input)).resolves.toMatchObject({ ok: false });
    expect(calls.filter(c => c.method === 'POST')).toHaveLength(1);
  });
  it('limita la espera sin volver a subir el archivo', async () => {
    handler = method => method === 'POST' ? { status: 202, body: { jobId } }
      : { status: 200, body: { jobId, status: 'PROCESSING', capability: 'EXTRACT_IMAGE_TEXT' } };
    await expect(engine({ APPYRA_MEDIA_OCR_TIMEOUT_MS: 1000 }).extractText(input)).resolves.toMatchObject({ ok: false, error: 'ocr-timeout' });
    expect(calls.filter(c => c.method === 'POST')).toHaveLength(1);
  });
  it('conserva el adaptador sincrono cuando no se selecciona el protocolo nuevo', async () => {
    handler = () => ({ status: 200, body: { text: 'Legado', engine: 'sync-test' } });
    await expect(engine({ APPYRA_MEDIA_OCR_PROTOCOL: undefined }).extractText(input)).resolves.toEqual({ ok: true, text: 'Legado', engine: 'sync-test' });
    expect(calls[0].url).toBe('/v1/media/ocr'); expect(calls).toHaveLength(1);
  });
});
