import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { CompanyActivityService } from './company-activity.service';
import { LicenseService } from './license.service';

const url = process.env.CRM_LICENSE_FIXTURE_URL;
(url ? describe : describe.skip)('Company activity: disposable database only', () => {
  let db: PrismaClient, service: CompanyActivityService, company: any, other: any;
  const now = new Date('2026-11-15T15:00:00Z');
  beforeAll(async () => {
    const target = new URL(url!);
    if (target.hostname !== '127.0.0.1' || !['55519', '56701'].includes(target.port) || target.pathname !== '/crm_license_fixture' || target.search || target.hash) throw Error('unsafe_fixture_target');
    db = new PrismaClient({ datasources: { db: { url } } });
    const licenses = new LicenseService(db as any, {} as any, { emitCompany: jest.fn() } as any);
    service = new CompanyActivityService(db as any, { get: () => 'true' } as any, licenses);
    await db.$connect();
  });
  beforeEach(async () => {
    await db.user.deleteMany(); await db.company.deleteMany();
    company = await db.company.create({ data: { name: 'Ficticia activity', slug: 'activity-fixture' } });
    other = await db.company.create({ data: { name: 'Otra ficticia', slug: 'activity-other' } });
  });
  afterAll(async () => db.$disconnect());
  const body = (streamId = randomUUID(), sequence = 1) => ({ streamId, sequence, active: true, activeMilliseconds: 30000, platform: 'windows', appVersion: 'fixture-only' });

  it('does not invent historical duration and never changes license/company data', async () => {
    const report = await service.report(company.id, now);
    expect(report.daily).toHaveLength(30);
    expect(report.daily.every(d => d.recordedSeconds === null)).toBe(true);
    expect(report.inventory.productsActive).toBe(0);
    expect(await db.company.findUnique({ where: { id: company.id } })).toEqual(company);
  });
  it('rejects tenant overrides, invalid sessions and disabled collection', async () => {
    const actor = { companyId: company.id, sessionId: randomUUID() };
    await expect(service.pulse(actor, { ...body(), companyId: other.id }, now)).rejects.toThrow('invalid_activity_pulse');
    await expect(service.pulse({ companyId: company.id }, body(), now)).rejects.toThrow('authenticated_company_session_required');
    const disabled = new CompanyActivityService(db as any, { get: () => 'false' } as any, {} as any);
    await expect(disabled.pulse(actor, body(), now)).rejects.toThrow('activity_collection_disabled');
    expect(await db.companyUsagePulse.count()).toBe(0);
  });
  it('deduplicates concurrency, rejects gaps and isolates companies', async () => {
    const actor = { companyId: company.id, sessionId: randomUUID() }, b = body();
    const first = await Promise.all([service.pulse(actor, b, now), service.pulse(actor, b, now)]);
    expect(first.filter(x => x.accepted)).toHaveLength(1);
    expect((await service.pulse(actor, { ...b, sequence: 2 }, new Date(+now + 30000))) as any).toMatchObject({ recordedMilliseconds: 30000 });
    expect((await service.pulse(actor, { ...b, sequence: 4 }, new Date(+now + 60000))) as any).toMatchObject({ recordedMilliseconds: 0 });
    const own = await service.report(company.id, new Date(+now + 90000));
    expect(own.daily[0].recordedSeconds).toBe(30);
    expect(own.sessions).toHaveLength(1);
    expect(own.sessions[0].recordedSeconds).toBe(30);
    expect(Object.keys(own.sessions[0]).sort()).toEqual(['appVersion','lastReportedAt','platform','recordedSeconds','startedAt']);
    const unrelated = await service.report(other.id, new Date(+now + 90000));
    expect(unrelated.daily.every(d => d.recordedSeconds === null)).toBe(true);
  });
  it('unions simultaneous sessions and splits midnight in UTC minus four', async () => {
    const end = new Date('2026-11-15T04:00:15Z');
    await db.companyUsagePulse.createMany({ data: [0, 1].map(() => ({ companyId: company.id, sessionId: randomUUID(), streamId: randomUUID(), sequence: 1, observedAt: end, activeFrom: new Date(+end - 30000), active: true, platform: 'windows', appVersion: 'fixture-only' })) });
    const report = await service.report(company.id, now);
    expect(report.daily.find(d => d.date === '2026-11-14')?.recordedSeconds).toBe(15);
    expect(report.daily.find(d => d.date === '2026-11-15')?.recordedSeconds).toBe(15);
  });
  it('bounds per-session pulse rate', async () => {
    const actor = { companyId: company.id, sessionId: randomUUID() };
    for (let i = 0; i < 12; i++) await service.pulse(actor, body(), new Date(+now + i));
    await expect(service.pulse(actor, body(), new Date(+now + 20))).rejects.toThrow('activity_rate_limited');
    expect(await db.companyUsagePulse.count()).toBe(12);
  });
  it('counts actual products and groups only business events by UTC minus four', async () => {
    await db.unitOfMeasure.upsert({where:{id:'UNIT'},create:{id:'UNIT',code:'UNIT',name:'Unidad',symbol:'ud',category:'COUNT'},update:{}});
    await db.product.createMany({data:[{companyId:company.id,nombre:'Ficticio',categoria:'fixture',costo:1,precio:2},{companyId:company.id,nombre:'Archivado',categoria:'fixture',costo:1,precio:2,archivedAt:now},{companyId:other.id,nombre:'Otro tenant',categoria:'fixture',costo:1,precio:2}]});
    await db.telemetryOutbox.createMany({data:[{companyId:company.id,eventId:randomUUID(),eventType:'SALE_COMPLETED',payload:{},occurredAt:new Date('2026-11-15T03:59:00Z')},{companyId:company.id,eventId:randomUUID(),eventType:'DAILY_USAGE_SUMMARY',payload:{},occurredAt:now},{companyId:other.id,eventId:randomUUID(),eventType:'SALE_COMPLETED',payload:{},occurredAt:now}]});
    const report=await service.report(company.id,now);
    expect(report.inventory.productsActive).toBe(1);expect(report.inventory.productsArchived).toBe(1);
    expect(report.daily.find(d=>d.date==='2026-11-14')?.businessEvents).toBe(1);
    expect(report.daily[0].businessEvents).toBe(0);
    expect(report.lastBusinessActivityAt?.toISOString()).toBe('2026-11-15T03:59:00.000Z');
    expect(report.recentEvents).toHaveLength(1);
  });
  it('retains recent measurements and purges only expired auxiliary pulses', async()=>{
    await db.companyUsagePulse.createMany({data:[0,36].map(days=>({companyId:company.id,sessionId:randomUUID(),streamId:randomUUID(),sequence:1,observedAt:new Date(+now-days*86400000),active:true,platform:'windows',appVersion:'fixture-only'}))});
    expect(await service.purgeExpiredPulses(now)).toBe(1);
    expect(await db.companyUsagePulse.count()).toBe(1);
    expect(await db.company.findUnique({where:{id:company.id}})).toEqual(company);
  });
  it('keeps current statistics available before the optional measurement migration', async()=>{
    await db.$executeRawUnsafe('ALTER TABLE company_usage_pulses RENAME TO fixture_hidden_usage_pulses');
    try {
      const report=await service.report(company.id,now);
      expect(report.measurement.status).toBe('not_installed');
      expect(report.daily.every(d=>d.recordedSeconds===null)).toBe(true);
      expect(report.inventory.productsActive).toBe(0);
    } finally {
      await db.$executeRawUnsafe('ALTER TABLE fixture_hidden_usage_pulses RENAME TO company_usage_pulses');
    }
  });
});
