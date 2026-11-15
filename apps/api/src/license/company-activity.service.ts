import { BadRequestException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException, HttpException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { LicenseService } from './license.service';
import { Cron } from '@nestjs/schedule';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const DAY = 86400000, OFFSET = -4 * 3600000;
const BUSINESS = ['SALE_COMPLETED','SALE_CANCELLED','QUOTATION_CREATED','QUOTATION_UPDATED','QUOTATION_CONVERTED_TO_SALE','PRODUCT_CREATED','PRODUCT_UPDATED','PRODUCT_ARCHIVED','PRODUCT_REACTIVATED','PRODUCT_DELETED','INVENTORY_ADJUSTED','STOCK_RECEIVED','WAREHOUSE_TRANSFER_COMPLETED','CASH_SESSION_OPENED','CASH_SESSION_CLOSED','CUSTOMER_CREATED','WAREHOUSE_CREATED','WAREHOUSE_DEACTIVATED','PURCHASE_ORDER_CREATED','PURCHASE_ORDER_UPDATED','PURCHASE_ORDER_APPROVED','PURCHASE_ORDER_SENT','PURCHASE_ORDER_RECEIVED','PURCHASE_INVOICE_CREATED'];

@Injectable()
export class CompanyActivityService {
  constructor(private readonly prisma: PrismaService, private readonly config: ConfigService, private readonly licenses: LicenseService) {}
  enabled() { return this.config.get('CRM_ACTIVITY_COLLECTION_ENABLED') === 'true'; }

  // Only this new auxiliary table; never licenses, sessions or existing telemetry.
  // Bounded hourly batches retain 35 days for the 30-day report plus a margin.
  @Cron('17 * * * *')
  async purgeExpiredPulses(now = new Date()) {
    if (!this.enabled()) return 0;
    const cutoff = new Date(now.getTime() - 35 * DAY);
    let deleted = 0;
    for (let batch = 0; batch < 6; batch++) {
      const count = await this.prisma.$transaction(async tx => {
        await tx.$executeRaw`SET LOCAL statement_timeout = '5s'`;
        return tx.$executeRaw`DELETE FROM company_usage_pulses WHERE id IN (SELECT id FROM company_usage_pulses WHERE observed_at < ${cutoff} ORDER BY observed_at LIMIT 10000 FOR UPDATE SKIP LOCKED)`;
      }, { timeout: 7000 });
      deleted += count;
      if (count < 10000) break;
    }
    return deleted;
  }

  async pulse(actor: { companyId?: string; sessionId?: string }, value: unknown, now = new Date()) {
    if (!this.enabled()) throw new ServiceUnavailableException('activity_collection_disabled');
    if (!UUID.test(actor?.companyId??'') || !UUID.test(actor?.sessionId??'')) throw new ForbiddenException('authenticated_company_session_required');
    const v=value as Record<string,unknown>;
    if(v && (typeof v.streamId!=='string'||typeof v.platform!=='string'))throw new BadRequestException('invalid_activity_pulse');
    if (!v || typeof v!=='object' || Array.isArray(v) || Object.keys(v).some(k=>!['streamId','sequence','active','activeMilliseconds','platform','appVersion'].includes(k)) || !UUID.test(String(v.streamId??'')) || typeof v.sequence!=='number' || !Number.isSafeInteger(v.sequence) || v.sequence<1 || v.sequence>2147483647 || typeof v.active!=='boolean' || typeof v.activeMilliseconds!=='number' || !Number.isInteger(v.activeMilliseconds) || v.activeMilliseconds<0 || v.activeMilliseconds>30000 || !['windows','android','ios','web','macos','linux'].includes(String(v.platform)) || typeof v.appVersion!=='string' || v.appVersion.length>80) throw new BadRequestException('invalid_activity_pulse');
    const companyId=actor.companyId!.toLowerCase(),sessionId=actor.sessionId!.toLowerCase(),streamId=String(v.streamId).toLowerCase(),sequence=v.sequence;
    return this.prisma.$transaction(async tx=>{
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext(${`crm-activity:${companyId}:${sessionId}`})) IS NULL AS locked`;
      const previous=await tx.companyUsagePulse.findFirst({where:{companyId,sessionId,streamId},orderBy:{sequence:'desc'}});
      if(previous && sequence<=previous.sequence) return {accepted:false,reason:'duplicate_or_old_sequence'};
      const rate=await tx.companyUsagePulse.count({where:{companyId,sessionId,observedAt:{gte:new Date(now.getTime()-60000)}}});
      if(rate>=12)throw new HttpException('activity_rate_limited',429);
      const gap=previous ? now.getTime()-previous.observedAt.getTime() : 0;
      const milliseconds=previous?.active && sequence===previous.sequence+1 && gap>0 && gap<=90000 ? Math.min(v.activeMilliseconds as number,gap,30000) : 0;
      const row=await tx.companyUsagePulse.create({data:{companyId,sessionId,streamId,sequence,observedAt:now,activeFrom:milliseconds ? new Date(now.getTime()-milliseconds):null,active:v.active as boolean,platform:String(v.platform),appVersion:v.appVersion as string}});
      return {accepted:true,observedAt:row.observedAt,recordedMilliseconds:milliseconds};
    });
  }

  async report(id: string, now=new Date()) {
    if(!UUID.test(id))throw new BadRequestException('invalid_company_id');
    const today=new Date(now.getTime()+OFFSET).toISOString().slice(0,10);
    const from=new Date(Date.parse(today+'T00:00:00.000-04:00')-29*DAY);
    return this.prisma.$transaction(async tx=>{
      await tx.$executeRaw`SET LOCAL TIME ZONE 'UTC'`;
      if(!await tx.company.findUnique({where:{id},select:{id:true}}))throw new NotFoundException('company_not_found');
      const [productsActive,productsArchived,users,usersEnabled,customers,warehouses,sales,quotations,lastConnection,lastLogin,eventDays,recentEvents,table]=await Promise.all([
        tx.product.count({where:{companyId:id,archivedAt:null}}),tx.product.count({where:{companyId:id,archivedAt:{not:null}}}),
        tx.user.count({where:{OR:[{companyId:id},{companyMemberships:{some:{companyId:id}}}]}}),this.licenses.countBillableUsers(id,tx),tx.client.count({where:{companyId:id,isDeleted:false}}),tx.warehouse.count({where:{companyId:id}}),
        tx.sale.count({where:{companyId:id,kind:'invoice',isDeleted:false,saleDate:{gte:from,lte:now}}}),tx.cotizacion.count({where:{companyId:id,createdAt:{gte:from,lte:now}}}),
        tx.authSession.findFirst({where:{companyId:id},orderBy:{lastUsedAt:{sort:'desc',nulls:'last'}},select:{lastUsedAt:true}}),
        tx.telemetryOutbox.findFirst({where:{companyId:id,eventType:'USER_LOGIN_SUCCESS',occurredAt:{lte:now}},orderBy:{occurredAt:'desc'},select:{occurredAt:true}}),
        tx.$queryRaw<Array<{date:string;count:number;first:Date;last:Date}>>`SELECT to_char(occurred_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Santo_Domingo','YYYY-MM-DD') AS date,count(*)::int AS count,min(occurred_at) AS first,max(occurred_at) AS last FROM telemetry_outbox WHERE company_id=${id}::uuid AND occurred_at>=${from} AND occurred_at<=${now} AND event_type IN (${Prisma.join(BUSINESS)}) GROUP BY 1 ORDER BY 1`,
        tx.telemetryOutbox.findMany({where:{companyId:id,occurredAt:{gte:from,lte:now},eventType:{in:BUSINESS}},orderBy:[{occurredAt:'desc'},{id:'asc'}],take:20,select:{occurredAt:true,eventType:true}}),
        tx.$queryRaw<Array<{present:string|null}>>`SELECT to_regclass('public.company_usage_pulses')::text AS present`,
      ]);
      const [pointDays,durations,lastPulse,firstPulse,platforms,versions]=table[0]?.present ? await Promise.all([
        tx.$queryRaw<Array<{date:string;count:number}>>`SELECT to_char(observed_at AT TIME ZONE 'America/Santo_Domingo','YYYY-MM-DD') AS date,count(*)::int AS count FROM company_usage_pulses WHERE company_id=${id}::uuid AND observed_at>=${from} AND observed_at<=${now} GROUP BY 1`,
        tx.$queryRaw<Array<{date:string;seconds:number}>>`WITH days AS (SELECT generate_series(${from}::timestamptz,${now}::timestamptz,interval '1 day') AS start), pieces AS (SELECT d.start,range_agg(tstzrange(greatest(p.active_from,d.start),least(p.observed_at,d.start+interval '1 day'),'[)')) AS ranges FROM days d JOIN company_usage_pulses p ON p.company_id=${id}::uuid AND p.active_from IS NOT NULL AND p.observed_at>d.start AND p.observed_at<=least(d.start+interval '1 day 30 seconds',${now}) AND p.active_from<least(d.start+interval '1 day',${now}) GROUP BY d.start) SELECT to_char(start AT TIME ZONE 'America/Santo_Domingo','YYYY-MM-DD') AS date,(SELECT floor(sum(extract(epoch FROM upper(v)-lower(v))))::int FROM unnest(ranges) AS v) AS seconds FROM pieces`,
        tx.companyUsagePulse.findFirst({where:{companyId:id,observedAt:{gte:from,lte:now}},orderBy:{observedAt:'desc'},select:{observedAt:true,active:true}}),
        tx.companyUsagePulse.findFirst({where:{companyId:id,observedAt:{gte:from,lte:now}},orderBy:{observedAt:'asc'},select:{observedAt:true}}),
        tx.companyUsagePulse.groupBy({by:['platform'],where:{companyId:id,observedAt:{gte:from,lte:now}},take:6,orderBy:{platform:'asc'}}),
        tx.companyUsagePulse.groupBy({by:['appVersion'],where:{companyId:id,observedAt:{gte:from,lte:now}},_max:{observedAt:true},orderBy:{_max:{observedAt:'desc'}},take:20}),
      ]) : [[],[],null,null,[],[]] as const;
      const daily=Array.from({length:30},(_,i)=>({date:new Date(from.getTime()+i*DAY+OFFSET).toISOString().slice(0,10),businessEvents:0,firstActivityAt:null as Date|null,lastActivityAt:null as Date|null,recordedSeconds:null as number|null,measurementPoints:0}));
      const days=new Map(daily.map(d=>[d.date,d]));
      for(const e of eventDays){const day=days.get(e.date);if(day){day.businessEvents=e.count;day.firstActivityAt=e.first;day.lastActivityAt=e.last;}}
      for(const p of pointDays){const day=days.get(p.date);if(day)day.measurementPoints=p.count;}
      for(const d of durations){const day=days.get(d.date);if(day)day.recordedSeconds=d.seconds;}
      const sessions=table[0]?.present ? await tx.$queryRaw<Array<{startedAt:Date;lastReportedAt:Date;recordedSeconds:number|null;platform:string;appVersion:string}>>`SELECT min(observed_at) AS "startedAt",max(observed_at) AS "lastReportedAt",floor(sum(extract(epoch FROM observed_at-active_from)))::int AS "recordedSeconds",min(platform) AS platform,min(app_version) AS "appVersion" FROM company_usage_pulses WHERE company_id=${id}::uuid AND observed_at>=${from} AND observed_at<=${now} GROUP BY session_id,stream_id ORDER BY max(observed_at) DESC LIMIT 20` : [];
      const latestBusiness=await tx.telemetryOutbox.findFirst({where:{companyId:id,eventType:{in:BUSINESS},occurredAt:{lte:now}},orderBy:{occurredAt:'desc'},select:{occurredAt:true}});
      return {companyId:id,authority:'DALEVENTAS',asOf:now,timeZone:'America/Santo_Domingo',refreshAfterSeconds:60,
        inventory:{productsActive,productsArchived,users,usersEnabled,customers,warehouses,sales30Days:sales,quotations30Days:quotations},
        lastBusinessActivityAt:latestBusiness?.occurredAt??null,lastLoginAt:lastLogin?.occurredAt??null,lastAuthenticatedConnectionAt:lastConnection?.lastUsedAt??null,
        measurement:{status:!table[0]?.present?'not_installed':lastPulse?'recorded':this.enabled()?'awaiting_compatible_client':'disabled',collectionEnabled:this.enabled(),lastReportedAt:lastPulse?.observedAt??null,currentlyReporting:this.enabled() && !!lastPulse?.active && now.getTime()-lastPulse.observedAt.getTime()<=90000,resolutionSeconds:30,idleLimitSeconds:300,source:'authenticated_foreground_client',historicalDurationReconstructed:false,platforms:platforms.map(p=>p.platform),versions:versions.map(p=>p.appVersion).filter(Boolean)},
        daily:daily.reverse(),sessions,recentEvents:recentEvents.map(e=>({type:e.eventType,occurredAt:e.occurredAt})),coverage:{businessEventsSince:eventDays[0]?.first??null,measurementSince:firstPulse?.observedAt??null,includesOfflineUsage:false,durationIsAttentionMeasurement:false},
      };
    },{isolationLevel:Prisma.TransactionIsolationLevel.RepeatableRead,timeout:15000});
  }
}
