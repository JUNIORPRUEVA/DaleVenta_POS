import { INestApplication, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '@nestjs/passport';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { CompanyActivityController } from './company-activity.controller';
import { CompanyActivityService } from './company-activity.service';
import { LicenseService } from './license.service';

describe('Company activity HTTP authentication boundaries', () => {
  let app: INestApplication;
  const companyId = 'c4f19567-e16d-4f6c-9510-41dfc16908d4';
  const actor = { companyId, sessionId: '24047771-fcc5-44c1-bb76-f742a3ded772' };
  const secret = 'synthetic-local-activity-secret';
  const activity = {
    pulse: jest.fn(async () => ({ accepted: true })),
    report: jest.fn(async (id: string) => ({ companyId: id })),
  };
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [CompanyActivityController],
      providers: [
        { provide: CompanyActivityService, useValue: activity },
        { provide: LicenseService, useFactory: () => new LicenseService({} as any,
          { get: (key: string) => key === 'LICENSE_ADMIN_SECRET' ? secret : undefined } as ConfigService, {} as any) },
      ],
    }).overrideGuard(AuthGuard('jwt')).useValue({
      canActivate(context: any) {
        const req = context.switchToHttp().getRequest();
        if (req.headers.authorization !== 'Bearer synthetic-actor') throw new UnauthorizedException();
        req.user = actor;
        return true;
      },
    }).compile();
    app = module.createNestApplication();
    await app.init();
  });
  afterAll(async () => app?.close());
  beforeEach(() => jest.clearAllMocks());

  it.each([{}, { 'x-license-admin-secret': 'wrong' }, { Authorization: 'Bearer synthetic-actor' }])(
    'does not expose company activity without the bridge secret (%j)', async headers => {
      await request(app.getHttpServer()).get(`/activity/admin/companies/${companyId}`).set(headers).expect(403);
      expect(activity.report).not.toHaveBeenCalled();
    });
  it('allows only the selected company report with the existing bridge secret', async () => {
    await request(app.getHttpServer()).get(`/activity/admin/companies/${companyId}`)
      .set('x-license-admin-secret', secret).expect(200);
    expect(activity.report).toHaveBeenCalledWith(companyId);
  });
  it('rejects unauthenticated pulse calls before the service', async () => {
    await request(app.getHttpServer()).post('/activity/pulse').send({}).expect(401);
    expect(activity.pulse).not.toHaveBeenCalled();
  });
  it('derives company and session from authentication, not a submitted company', async () => {
    const payload = { companyId: 'forbidden-override' };
    await request(app.getHttpServer()).post('/activity/pulse')
      .set('Authorization', 'Bearer synthetic-actor').send(payload).expect(201);
    expect(activity.pulse).toHaveBeenCalledWith(actor, payload);
    // Service integration separately verifies that this forbidden field is rejected.
  });
});
