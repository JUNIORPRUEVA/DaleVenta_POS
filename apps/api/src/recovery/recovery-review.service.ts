import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, RecoveryReviewCase } from '@prisma/client';
import { createHash } from 'node:crypto';
import { requireTenant, TenantUser } from '../auth/tenant-context';
import { PrismaService } from '../prisma/prisma.service';
import { RecoveryDecisionDto, SubmitRecoveryReviewDto } from './recovery-review.dto';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RESOLVED=['RESOLVED_REGISTERED','RESOLVED_NOT_PERFORMED'];
@Injectable()
export class RecoveryReviewService {
  constructor(private readonly prisma:PrismaService) {}
  private requireAdmin(user:TenantUser) {
    if(user.role!=='ADMIN')throw new ForbiddenException('Solo el administrador puede abrir el Centro de recuperación.');
  }
  private ownerWhere(user:TenantUser) {
    return {companyId:requireTenant(user),...(user.role==='ADMIN'?{}:{sourceUserId:user.id})};
  }
  private sanitize(value:Record<string,unknown>):Prisma.InputJsonObject {
    const result:Record<string,Prisma.InputJsonValue>={};
    for(const key of ['clientRequestId','operationId','clientSessionId','sessionId','originCashSessionId','expectedTotalSold',
      'openingAmount','closingAmount','amount','type','movementType','paymentMethod','saleOccurredAt','occurredAt','createdAt','openedAt']) {
      const input=value[key];
      if(typeof input==='string'&&input.length<=1000)result[key]=input;
      else if(typeof input==='number'&&Number.isFinite(input))result[key]=input;
      else if(typeof input==='boolean')result[key]=input;
    }
    if(JSON.stringify(result).length>16000)throw new BadRequestException('El resumen de la incidencia supera el tamaño permitido.');
    return result;
  }
  private dto(row:RecoveryReviewCase) {
    return {...row,expectedAmount:row.expectedAmount?.toNumber()??null,
      financiallyConfirmed:row.status==='RESOLVED_REGISTERED',
      needsIntervention:!RESOLVED.includes(row.status),retryFinancialOperation:false};
  }
  private async get(user:TenantUser,id:string) {
    this.requireAdmin(user);
    if(!UUID.test(id))throw new NotFoundException('No encontramos la revisión solicitada.');
    const row=await this.prisma.recoveryReviewCase.findFirst({where:{...this.ownerWhere(user),id}});
    if(!row)throw new NotFoundException('No encontramos la revisión solicitada.');
    return row;
  }
  async list(user:TenantUser,cursor?:string) {
    this.requireAdmin(user);
    const where=this.ownerWhere(user);
    if(cursor&&!UUID.test(cursor))throw new BadRequestException('La página de revisiones no es válida.');
    // Verify the cursor belongs to the caller's scope before pagination.
    if(cursor)await this.get(user,cursor);
    const rows=await this.prisma.recoveryReviewCase.findMany({where,orderBy:{id:'asc'},take:100,
      ...(cursor?{cursor:{id:cursor},skip:1}:{})});
    return {items:rows.map(row=>this.dto(row)),nextCursor:rows.length===100?rows[rows.length-1].id:null};
  }
  async detail(user:TenantUser,id:string) {
    const row=await this.get(user,id);
    const events=await this.prisma.recoveryReviewEvent.findMany({where:{companyId:row.companyId,caseId:row.id},orderBy:[{createdAt:'asc'},{id:'asc'}]});
    return {...this.dto(row),events};
  }
  async submit(user:TenantUser,input:SubmitRecoveryReviewDto) {
    const companyId=requireTenant(user);
    const payloadSummary=this.sanitize(input.payloadSummary);
    const identity=input.actionType==='sales.create'?payloadSummary.clientRequestId:
      input.actionType==='cash.movement'?payloadSummary.operationId:
      input.actionType==='cash.open'?payloadSummary.clientSessionId:payloadSummary.sessionId;
    const supplied=input.actionType==='cash.open'?input.operationId.replace(/^cash\.open:/,''):
      input.actionType==='cash.close'?input.operationId.replace(/^cash\.close:/,''):input.operationId;
    if(identity!==undefined&&identity!==supplied)throw new BadRequestException('La identidad de la incidencia no coincide con su operación original.');
    const summaryAmount=input.actionType==='sales.create'?payloadSummary.expectedTotalSold:
      input.actionType==='cash.open'?payloadSummary.openingAmount:
      input.actionType==='cash.close'?payloadSummary.closingAmount:payloadSummary.amount;
    if(summaryAmount!==undefined&&input.expectedAmount!==undefined&&Number(summaryAmount)!==input.expectedAmount){
      throw new BadRequestException('El importe esperado no coincide con la operación original.');
    }
    const summarySession=payloadSummary.sessionId??payloadSummary.originCashSessionId??payloadSummary.clientSessionId;
    if(summarySession!==undefined&&input.originalSessionId!==undefined&&summarySession!==input.originalSessionId){
      throw new BadRequestException('El turno de la incidencia no coincide con su operación original.');
    }
    const snapshotHash=createHash('sha256').update(JSON.stringify({
      sourceActionId:input.sourceActionId,actionType:input.actionType,operationId:input.operationId,
      originalSessionId:input.originalSessionId??null,expectedAmount:input.expectedAmount??null,payloadSummary,
    })).digest('hex');
    const where={companyId,sourceUserId:user.id,actionType:input.actionType,operationId:input.operationId};
    const reuse=(row:RecoveryReviewCase)=>{
      if(row.snapshotHash!==snapshotHash)throw new ConflictException('Ya existe una revisión de esta operación con datos diferentes. Conserva ambas evidencias y solicita revisión.');
      return this.dto(row);
    };
    const existing=await this.prisma.recoveryReviewCase.findFirst({where});
    if(existing)return reuse(existing);
    try {
      const row=await this.prisma.$transaction(async tx=>{
        const created=await tx.recoveryReviewCase.create({data:{...where,sourceActionId:input.sourceActionId,
          originalSessionId:input.originalSessionId,expectedAmount:input.expectedAmount,
          snapshotHash,payloadSummary}});
        await tx.recoveryReviewEvent.create({data:{companyId,caseId:created.id,actorUserId:user.id,
          actorRole:String(user.role),kind:'SUBMITTED',caseVersion:created.version}});
        return created;
      });
      return this.dto(row);
    }catch(error){
      if(error instanceof Prisma.PrismaClientKnownRequestError&&error.code==='P2002'){
        const winner=await this.prisma.recoveryReviewCase.findFirst({where});
        if(winner)return reuse(winner);
      }
      throw error;
    }
  }
  private async registered(row:RecoveryReviewCase,db:Prisma.TransactionClient|PrismaService=this.prisma) {
    const scope={companyId:row.companyId};
    const amount=row.expectedAmount;
    const summary=row.payloadSummary as Record<string,unknown>;
    const matches=(value:Prisma.Decimal|null|undefined)=>amount!==null&&value!=null&&value.minus(amount).abs().lte(0.005);
    if(row.actionType==='sales.create'){
      const sale=await db.sale.findFirst({where:{...scope,clientRequestId:row.operationId},select:{id:true,userId:true,totalSold:true,cashSessionId:true}});
      return {exists:!!sale,id:sale?.id,exact:!!sale&&sale.userId===row.sourceUserId&&matches(sale.totalSold)&&
        (!row.originalSessionId||sale.cashSessionId===row.originalSessionId)};
    }
    if(row.actionType==='cash.movement'){
      const movement=await db.cashMovement.findFirst({where:{...scope,operationId:row.operationId},
        select:{id:true,userId:true,amount:true,sessionId:true,type:true}});
      return {exists:!!movement,id:movement?.id,exact:!!movement&&movement.userId===row.sourceUserId&&
        matches(movement.amount)&&!!row.originalSessionId&&movement.sessionId===row.originalSessionId&&movement.type===summary.type};
    }
    const id=row.originalSessionId??String(summary.clientSessionId??'');
    if(!UUID.test(id))return {exists:false,exact:false,id:undefined};
    const session=await db.cashSession.findFirst({where:{...scope,id},select:{id:true,openedByUserId:true,closedByUserId:true,status:true,closedAt:true,initialAmount:true,closingAmount:true}});
    const close=row.actionType==='cash.close';
    const exists=!!session&&(!close||session.status==='CLOSED'||session.closedAt!=null);
    return {exists,id:session?.id,exact:exists&&!!session&&(close?session.closedByUserId:session.openedByUserId)===row.sourceUserId&&
      (close?session.status==='CLOSED'&&matches(session.closingAmount):matches(session.initialAmount))};
  }
  async verify(user:TenantUser,id:string) {
    const row=await this.get(user,id);
    if(RESOLVED.includes(row.status))return this.dto(row);
    const found=await this.registered(row);
    if(!found.exact||!found.id)return {...this.dto(row),verification:found.exists?'MISMATCH':'NOT_FOUND'};
    return this.transition(user,row,'RESOLVED_REGISTERED','REGISTERED_VERIFIED',undefined,undefined,found.id);
  }
  async decide(user:TenantUser,id:string,input:RecoveryDecisionDto) {
    if(user.role!=='ADMIN')throw new ForbiddenException('Solo el administrador de la empresa puede resolver esta revisión.');
    const row=await this.get(user,id);
    if(row.version!==input.expectedVersion||RESOLVED.includes(row.status))throw new ConflictException('La revisión cambió. Actualiza su estado antes de decidir.');
    if(input.decision==='NOT_PERFORMED'){
      const found=await this.registered(row);
      if(found.exists)throw new ConflictException('Existe un registro relacionado. No puedes declarar que no se realizó; comprueba la operación o continúa la revisión.');
    }
    return this.transition(user,row,input.decision==='NOT_PERFORMED'?'RESOLVED_NOT_PERFORMED':'REVIEWING',
      input.decision,input.note,input.evidenceReference);
  }
  private async transition(user:TenantUser,row:RecoveryReviewCase,status:string,kind:string,note?:string,evidenceReference?:string,registeredEntityId?:string) {
    return this.prisma.$transaction(async tx=>{
      if(kind==='NOT_PERFORMED'&&(await this.registered(row,tx)).exists){
        throw new ConflictException('Se encontró un registro mientras revisabas la incidencia. Actualiza antes de decidir.');
      }
      const changed=await tx.recoveryReviewCase.updateMany({where:{id:row.id,companyId:requireTenant(user),version:row.version,
        status:{notIn:RESOLVED}},data:{status,version:{increment:1},...(registeredEntityId?{registeredEntityId}:{})}});
      if(changed.count!==1)throw new ConflictException('Otra persona actualizó la revisión. Recarga antes de continuar.');
      await tx.recoveryReviewEvent.create({data:{companyId:row.companyId,caseId:row.id,actorUserId:user.id,
        actorRole:String(user.role),kind,note,evidenceReference,caseVersion:row.version+1}});
      const updated=await tx.recoveryReviewCase.findFirst({where:{companyId:row.companyId,id:row.id}});
      if(!updated)throw new NotFoundException('No encontramos la revisión actualizada.');
      return this.dto(updated);
    },{isolationLevel:Prisma.TransactionIsolationLevel.Serializable});
  }
}
