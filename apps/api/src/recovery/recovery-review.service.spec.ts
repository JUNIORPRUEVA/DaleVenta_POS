import { BadRequestException, ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { RecoveryReviewService } from './recovery-review.service';

describe('Recovery review: conserved evidence and strict financial confirmation', () => {
  const companyId='11111111-1111-4111-8111-111111111111';
  const userId='22222222-2222-4222-8222-222222222222';
  const id='33333333-3333-4333-8333-333333333333';
  const sessionId='44444444-4444-4444-8444-444444444444';
  const user={id:userId,companyId,role:'ADMIN'} as any;
  let db:any;
  let row:any;
  let service:RecoveryReviewService;
  beforeEach(()=>{
    row={id,companyId,sourceUserId:userId,sourceActionId:'cash.movement:one',actionType:'cash.movement',
      operationId:'one',originalSessionId:sessionId,expectedAmount:new Prisma.Decimal(7),
      payloadSummary:{operationId:'one',sessionId,type:'IN',amount:7},status:'OPEN',version:1};
    db={
      recoveryReviewCase:{findFirst:jest.fn(async()=>row),findMany:jest.fn(async()=>[row]),
        updateMany:jest.fn(async({data}:any)=>{row={...row,...data,version:row.version+1};return {count:1};}),
        create:jest.fn(async({data}:any)=>({...data,id,version:1,status:'OPEN'}))},
      recoveryReviewEvent:{create:jest.fn(async()=>({})),findMany:jest.fn(async()=>[])},
      cashMovement:{findFirst:jest.fn(async()=>null)},cashSession:{findFirst:jest.fn(async()=>null)},
      sale:{findFirst:jest.fn(async()=>null)},
    };
    db.$transaction=jest.fn(async(work:any)=>work(db));
    service=new RecoveryReviewService(db);
  });
  test('non-admin cannot read or verify recovery cases, even their own',async()=>{
    const cashier={...user,role:'CAJERO'};
    await expect(service.list(cashier)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.detail(cashier,id)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.verify(cashier,id)).rejects.toBeInstanceOf(ForbiddenException);
    expect(db.recoveryReviewCase.findMany).not.toHaveBeenCalled();
    expect(db.cashMovement.findFirst).not.toHaveBeenCalled();
  });
  test('an unavailable record is never confirmed',async()=>{
    expect(await service.verify(user,id)).toMatchObject({status:'OPEN',verification:'NOT_FOUND',financiallyConfirmed:false});
    expect(db.recoveryReviewCase.updateMany).not.toHaveBeenCalled();
  });
  test.each([
    {amount:new Prisma.Decimal(8)}, {userId:'someone-else'},
    {sessionId:'another-shift'}, {type:'OUT'},
  ])('mismatched amount, actor, shift or movement type is retained: %p',async(change)=>{
    db.cashMovement.findFirst.mockResolvedValue({id:'movement-1',userId,sessionId,type:'IN',amount:new Prisma.Decimal(7),...change});
    expect(await service.verify(user,id)).toMatchObject({status:'OPEN',verification:'MISMATCH',needsIntervention:true});
    expect(db.recoveryReviewCase.updateMany).not.toHaveBeenCalled();
  });
  test('a missing expected amount prevents confirmation',async()=>{
    row.expectedAmount=null;
    db.cashMovement.findFirst.mockResolvedValue({id:'movement-1',userId,sessionId,type:'IN',amount:new Prisma.Decimal(7)});
    expect(await service.verify(user,id)).toMatchObject({verification:'MISMATCH',financiallyConfirmed:false});
  });
  test('exact registered operation is confirmed with an append-only event',async()=>{
    db.cashMovement.findFirst.mockResolvedValue({id:'movement-1',userId,sessionId,type:'IN',amount:new Prisma.Decimal(7)});
    expect(await service.verify(user,id)).toMatchObject({status:'RESOLVED_REGISTERED',registeredEntityId:'movement-1',financiallyConfirmed:true});
    expect(db.recoveryReviewEvent.create).toHaveBeenCalledWith(expect.objectContaining({data:expect.objectContaining({companyId,kind:'REGISTERED_VERIFIED',caseVersion:2})}));
    expect(db.cashMovement.findFirst).toHaveBeenCalledWith(expect.objectContaining({where:{companyId,operationId:'one'}}));
  });
  test('non-admin cannot make an administrative decision',async()=>{
    await expect(service.decide({...user,role:'CAJERO'},id,{decision:'NOT_PERFORMED',note:'Audited synthetic evidence',expectedVersion:1})).rejects.toBeInstanceOf(ForbiddenException);
  });
  test('closing confirmation checks the closing actor rather than opening actor',async()=>{
    row.actionType='cash.close';
    db.cashSession.findFirst.mockResolvedValue({id:sessionId,openedByUserId:'another-opener',closedByUserId:userId,
      status:'CLOSED',initialAmount:new Prisma.Decimal(0),closingAmount:new Prisma.Decimal(7)});
    expect(await service.verify(user,id)).toMatchObject({status:'RESOLVED_REGISTERED',financiallyConfirmed:true});
  });
  test('a close performed by another actor stays under review',async()=>{
    row.actionType='cash.close';
    db.cashSession.findFirst.mockResolvedValue({id:sessionId,openedByUserId:userId,closedByUserId:'another-closer',
      status:'CLOSED',initialAmount:new Prisma.Decimal(0),closingAmount:new Prisma.Decimal(7)});
    expect(await service.verify(user,id)).toMatchObject({status:'OPEN',verification:'MISMATCH'});
  });
  test('an open session is not evidence that its rejected close was performed',async()=>{
    row.actionType='cash.close';
    db.cashSession.findFirst.mockResolvedValue({id:sessionId,openedByUserId:userId,closedByUserId:null,
      status:'OPEN',closedAt:null,initialAmount:new Prisma.Decimal(0),closingAmount:null});
    expect(await service.verify(user,id)).toMatchObject({status:'OPEN',verification:'NOT_FOUND',financiallyConfirmed:false});
    expect(await service.decide(user,id,{decision:'NOT_PERFORMED',note:'Synthetic evidence: close not performed',expectedVersion:1}))
      .toMatchObject({status:'RESOLVED_NOT_PERFORMED',financiallyConfirmed:false});
  });
  test('a close committed during the review forbids declaring not performed',async()=>{
    row.actionType='cash.close';
    db.cashSession.findFirst.mockResolvedValueOnce({id:sessionId,status:'OPEN',closedAt:null})
      .mockResolvedValueOnce({id:sessionId,status:'CLOSED',closedAt:new Date()});
    await expect(service.decide(user,id,{decision:'NOT_PERFORMED',note:'Synthetic review with concurrent close',expectedVersion:1}))
      .rejects.toBeInstanceOf(ConflictException);
    expect(db.recoveryReviewCase.updateMany).not.toHaveBeenCalled();
  });
  test('an existing mismatched record forbids declaring not performed',async()=>{
    db.cashMovement.findFirst.mockResolvedValue({id:'related',userId,sessionId,type:'OUT',amount:new Prisma.Decimal(70)});
    await expect(service.decide(user,id,{decision:'NOT_PERFORMED',note:'Audited synthetic evidence',expectedVersion:1})).rejects.toBeInstanceOf(ConflictException);
  });
  test('human not-performed retains case and does not confirm a financial record',async()=>{
    expect(await service.decide(user,id,{decision:'NOT_PERFORMED',note:'Audited synthetic evidence',expectedVersion:1}))
      .toMatchObject({status:'RESOLVED_NOT_PERFORMED',financiallyConfirmed:false,retryFinancialOperation:false});
    expect(db.cashMovement.findFirst).toHaveBeenCalledTimes(2);
  });
  test('stale administrator decisions are rejected',async()=>{
    await expect(service.decide(user,id,{decision:'ESCALATE',note:'Audited synthetic evidence',expectedVersion:2})).rejects.toBeInstanceOf(ConflictException);
  });
  test('foreign or missing cases remain inaccessible',async()=>{
    db.recoveryReviewCase.findFirst.mockResolvedValue(null);
    await expect(service.detail(user,id)).rejects.toBeInstanceOf(NotFoundException);
    expect(db.recoveryReviewCase.findFirst).toHaveBeenCalledWith({where:{companyId,id}});
  });
  test('submission rejects identity substitution before persistence',async()=>{
    await expect(service.submit(user,{sourceActionId:'one',actionType:'cash.movement',operationId:'one',payloadSummary:{operationId:'two'}}))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(db.recoveryReviewCase.create).not.toHaveBeenCalled();
  });
  test('submission rejects replacing the original expected amount',async()=>{
    await expect(service.submit(user,{sourceActionId:'one',actionType:'cash.movement',operationId:'one',expectedAmount:9,payloadSummary:{operationId:'one',amount:7}}))
      .rejects.toBeInstanceOf(BadRequestException);
  });
});
