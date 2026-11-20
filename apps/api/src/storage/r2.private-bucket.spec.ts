import { ConfigModule, ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { createServer, Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { R2Service } from './r2.service';
import { evidenceSha256, LicenseEvidenceStorage } from '../license/orders/license-evidence.storage';
import { LicenseModule } from '../license/license.module';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

describe('Private evidence through the existing S3 transport (local HTTP fixture)', () => {
  let server: Server;
  let r2: R2Service;
  let settings: Record<string, string>;
  const requests: { method: string; path: string }[] = [];
  const body = Buffer.from('%PDF-1.7\nsynthetic receipt\n%%EOF');

  beforeAll(async () => {
    server = createServer((req, res) => {
      requests.push({ method: req.method!, path: req.url!.split('?')[0] });
      req.resume();
      req.on('end', () => {
        if (req.method === 'GET') { res.setHeader('Content-Type', 'application/pdf'); res.end(body); }
        else { res.setHeader('ETag', '"synthetic"'); res.end(); }
      });
    });
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
    settings = { R2_ENDPOINT: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, R2_REGION: 'auto', R2_ACCESS_KEY_ID: 'synthetic-access-key', R2_SECRET_ACCESS_KEY: 'synthetic-secret-not-real', R2_BUCKET: 'public-media', LICENSE_EVIDENCE_R2_BUCKET: 'private-receipts', LICENSE_EVIDENCE_STORAGE_DRIVER: 'r2' };
    r2 = new R2Service({ get: (key: string) => settings[key] } as unknown as ConfigService);
  });
  afterAll(async () => { await new Promise<void>(resolve => server.close(() => resolve())); });
  beforeEach(() => { requests.length = 0; });

  it('retains the default bucket for existing upload and download callers', async () => {
    await r2.putObject({ objectKey: 'uploads/existing.pdf', body, contentType: 'application/pdf' });
    await expect(r2.getObject('uploads/existing.pdf')).resolves.toMatchObject({ body });
    expect(requests).toEqual([{ method: 'PUT', path: '/public-media/uploads/existing.pdf' }, { method: 'GET', path: '/public-media/uploads/existing.pdf' }]);
  });

  it('stores and downloads receipts using only the separate bucket; denies the other company before HTTP', async () => {
    const storage = new LicenseEvidenceStorage({ get: (key: string) => settings[key] } as unknown as ConfigService, r2);
    const companyId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const saved = await storage.save({ companyId, buffer: body, ext: 'pdf', sha256: evidenceSha256(body) });
    await expect(storage.read(saved.storageKey, companyId)).resolves.toEqual(body);
    await expect(storage.read(saved.storageKey, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')).rejects.toThrow('No encontramos');
    const path = `/private-receipts/license-evidence/companies/${companyId}/${evidenceSha256(body)}.pdf`;
    expect(requests).toEqual([{ method: 'PUT', path }, { method: 'GET', path }]);
  });

  it('resolves the shared R2 transport through the real Nest license module', async () => {
    const module = await Test.createTestingModule({ imports: [ConfigModule.forRoot({ isGlobal: true, ignoreEnvFile: true }), LicenseModule] })
      .useMocker(token => token === CatalogRealtimeRelayService ? { emitCompany: jest.fn() } : undefined)
      .overrideProvider(ConfigService).useValue({ get: (key: string) => settings[key] })
      .overrideProvider(PrismaService).useValue({})
      .compile();
    try {
      const storage = module.get(LicenseEvidenceStorage);
      const saved = await storage.save({ companyId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', buffer: body, ext: 'pdf', sha256: evidenceSha256(body) });
      await expect(storage.read(saved.storageKey, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).resolves.toEqual(body);
      expect(requests).toHaveLength(2);
      expect(requests.every(request => request.path.startsWith('/private-receipts/'))).toBe(true);
    } finally { await module.close(); }
  });
});
