import { ConflictException, ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { SaleReconciliationObligationService } from './sale-reconciliation-obligation.service';

describe('Administrative declaration resolution preserves financial evidence', () => {
  const user = {id:'admin',companyId:'company-a',role:'ADMIN'};
  let row:any, db:any, service:SaleReconciliationObligationService;
  const input = {decision:'CHECK' as const,expectedVersion:1,note:'Comprobación sintética del registro'};
  beforeEach(() => {
    row={id:'obligation',companyId:'company-a',clientRequestId:'original',status:'PENDING',version:1,
      totalDeclared:new Prisma.Decimal(7),currency:'DOP',paymentMethod:'cash',declaredByUserId:'cashier',declaredByRole:'CAJERO',
      declaredAtUtc:new Date(),createdAt:new Date(),resolvedAt:null,note:null,operationFingerprint:null,
      resolutionNote:null,resolvedByUserId:null,declarationCount:1,lastDeclaredAtUtc:null,attemptPayload:{originCashSessionId:'shift'}};
    db={saleReconciliationObligation:{findFirst:jest.fn(async({where}:any)=>where.companyId===row.companyId?row:null),
      updateMany:jest.fn(async({data}:any)=>{row={...row,...data,version:row.version+1};return {count:1};})},
      saleReconciliationDeclarationEvent:{create:jest.fn(async()=>({}))},
      sale:{findFirst:jest.fn(async()=>({id:'sale',userId:'cashier',totalSold:new Prisma.Decimal(7),paymentMethod:'cash',cashSessionId:'shift'}))}};
    db.$transaction=jest.fn(async(work:any)=>work(db));
    service=new SaleReconciliationObligationService(db);
  });
  test('exact record reconciles once; a repeated request writes no second event',async()=>{
    expect((await service.resolve(user,'obligation',input)).status).toBe('RECONCILED');
    await service.resolve(user,'obligation',input);
    expect(db.saleReconciliationDeclarationEvent.create).toHaveBeenCalledTimes(1);
    expect(row.totalDeclared.toNumber()).toBe(7);
  });
  for(const mismatch of ['missing','amount','user','session','payment']) {
    test(`uncertain ${mismatch} stays pending`,async()=>{
      const sale={id:'sale',userId:'cashier',totalSold:new Prisma.Decimal(7),paymentMethod:'cash',cashSessionId:'shift'};
      if(mismatch==='amount')sale.totalSold=new Prisma.Decimal(8);
      if(mismatch==='user')sale.userId='another';
      if(mismatch==='session')sale.cashSessionId='another';
      if(mismatch==='payment')sale.paymentMethod='transfer';
      db.sale.findFirst.mockResolvedValue(mismatch==='missing'?null:sale);
      await expect(service.resolve(user,'obligation',input)).rejects.toBeInstanceOf(ConflictException);
      expect(row.status).toBe('PENDING');
      expect(db.saleReconciliationDeclarationEvent.create).not.toHaveBeenCalled();
    });
  }
  test('dismissal conserves the original declaration and adds an audit event',async()=>{
    db.sale.findFirst.mockResolvedValue(null);
    const occurred=row.declaredAtUtc;
    expect((await service.resolve(user,'obligation',{...input,decision:'DISMISS'})).status).toBe('DISMISSED');
    expect(row.totalDeclared.toNumber()).toBe(7);
    expect(row.declaredAtUtc).toBe(occurred);
    expect(db.saleReconciliationDeclarationEvent.create).toHaveBeenCalledTimes(1);
  });
  test('an existing sale cannot be dismissed as an absent operation',async()=>{
    await expect(service.resolve(user,'obligation',{...input,decision:'DISMISS'})).rejects.toBeInstanceOf(ConflictException);
  });
  test('another tenant, cashier and stale version cannot resolve evidence',async()=>{
    await expect(service.resolve({...user,companyId:'company-b'},'obligation',input)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.resolve({...user,role:'CAJERO'},'obligation',input)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.resolve(user,'obligation',{...input,expectedVersion:2})).rejects.toBeInstanceOf(ConflictException);
    expect(db.saleReconciliationObligation.updateMany).not.toHaveBeenCalled();
  });
});
