import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { CrmLicenseController } from './crm-license.controller';
import { CrmLicenseService } from './crm-license.service';
import { LicenseService } from './license.service';
import { LicenseOrdersService } from './orders/license-orders.service';
import { LicensePlanRequestService } from './renewal/license-plan-request.service';

describe('CRM license HTTP boundary after fiscal consolidation', () => {
  let app: INestApplication;
  const secret = 'synthetic-local-admin-secret';
  const companyId = 'c4f19567-e16d-4f6c-9510-41dfc16908d4';
  const crm = {
    enabled: jest.fn(() => false),
    list: jest.fn(async () => ({ total: 0, items: [] })),
    detail: jest.fn(async (id: string) => ({ companyId: id })),
    command: jest.fn(async (id: string) => ({ companyId: id })),
  };

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [CrmLicenseController],
      providers: [
        { provide: CrmLicenseService, useValue: crm },
        { provide: LicenseOrdersService, useValue: { getAdminEvidence: jest.fn() } },
        {
          provide: LicensePlanRequestService,
          useValue: {
            listAdmin: jest.fn(async () => ({ requests: [] })),
            setStatus: jest.fn(async () => ({ ok: true })),
          },
        },
        { provide: LicenseService, useFactory: () => new LicenseService(
          {} as any,
          { get: (key: string) => key === 'LICENSE_ADMIN_SECRET' ? secret : undefined } as ConfigService,
          {} as any,
          {} as any,
        ) },
      ],
    }).compile();
    app = module.createNestApplication();
    await app.init();
  });
  afterAll(async () => { await app?.close(); });
  beforeEach(() => jest.clearAllMocks());

  it.each([
    ['get', '/license/integrations/crm/capabilities'],
    ['get', '/license/integrations/crm/companies'],
    ['get', `/license/integrations/crm/companies/${companyId}`],
    ['post', `/license/integrations/crm/${companyId}/commands`],
  ])('rejects missing or wrong bridge secret on %s %s', async (method, path) => {
    for (const headers of [{}, { 'x-license-admin-secret': 'wrong-secret' }, { Authorization: 'Bearer ordinary-client-token' }]) {
      const operation = request(app.getHttpServer());
      const response = await (method === 'post' ? operation.post(path) : operation.get(path)).set(headers);
      expect(response.status).toBe(403);
    }
    expect(crm.list).not.toHaveBeenCalled();
    expect(crm.detail).not.toHaveBeenCalled();
    expect(crm.command).not.toHaveBeenCalled();
  });

  it('advertises read capability but does not enable CRM writes by default', async () => {
    const response = await request(app.getHttpServer())
      .get('/license/integrations/crm/capabilities').set('x-license-admin-secret', secret);
    expect(response.status).toBe(200);
    // `payments` y `overrides` dicen si el puente puede marcar pagos y conceder
    // excepciones; siguen colgando del mismo interruptor de escritura.
    expect(response.body).toEqual({
      licenseRead: true,
      licenseWrite: false,
      bankTransfers: false,
      payments: true,
      overrides: true,
      contactWrite: false,
      assignPlan: false,
      extendPeriod: false,
      loginEmailWrite: false,
    });
    expect(crm.command).not.toHaveBeenCalled();
  });

  it('passes only the selected company to the authenticated command service', async () => {
    const body = { operationId: 'synthetic-command' };
    const response = await request(app.getHttpServer())
      .post(`/license/integrations/crm/${companyId}/commands`)
      .set('x-license-admin-secret', secret).send(body);
    expect(response.status).toBe(201);
    expect(crm.command).toHaveBeenCalledWith(companyId, body);
  });
});
