import 'reflect-metadata';
import { PATH_METADATA } from '@nestjs/common/constants';
import { Prisma } from '@prisma/client';
import { ProductsController } from './products.controller';
import { SalesController } from '../sales/sales.controller';
import { CotizacionesController } from '../cotizaciones/cotizaciones.controller';
import { ClientsController } from '../clients/clients.controller';
import { ServiceOrdersController } from '../service-orders/service-orders.controller';
import { ProductsService } from './products.service';

describe('Product lifecycle: destructive entry points and stock protection',()=>{
  const user={id:'22222222-2222-4222-8222-222222222222',companyId:'11111111-1111-4111-8111-111111111111',role:'ADMIN'} as any;
  const productId='33333333-3333-4333-8333-333333333333';
  for(const Controller of [ProductsController,SalesController,CotizacionesController,ClientsController,ServiceOrdersController]){
    test(`${Controller.name}: no HTTP route for debug purge`,()=>{
      expect(Reflect.getMetadata(PATH_METADATA,Controller.prototype.purgeAllForDebug)).toBeUndefined();
    });
  }
  function setup(stock:number,quantities:number[],history=false){
    const row={id:productId,archivedAt:null,stock:new Prisma.Decimal(stock)};
    const db:any={product:{findFirst:jest.fn(async()=>row),deleteMany:jest.fn(async()=>({count:1}))},
      $queryRaw:jest.fn(async()=>[row]),warehouseStock:{findMany:jest.fn(async()=>quantities.map(quantity=>({quantity:new Prisma.Decimal(quantity)})))}};
    for(const name of ['inventoryMovement','warehouseTransferItem','saleItem','cotizacionItem','purchaseOrderItem','purchaseReceiptItem','priceListProductRule','websiteProductOverride']){
      db[name]={count:jest.fn(async()=>history&&name==='inventoryMovement'?1:0)};
    }
    db.$transaction=jest.fn(async(work:any)=>work(db));
    db.$executeRaw=jest.fn(async()=>1);
    db.productLifecycleEvent={findFirst:jest.fn(async()=>null),findMany:jest.fn(async()=>[]),create:jest.fn(async()=>({}))};
    const service=new ProductsService(db,{} as any,{resolveForCompany:async()=>({source:'LOCAL',readOnly:false})} as any,{get:()=>''} as any,{} as any);
    return{service,db,row};
  }
  test('direct product purge cannot execute even for a tenant administrator',async()=>{
    const{service,db}=setup(0,[]);await expect(service.purgeAllForDebug(user)).rejects.toMatchObject({status:404});
    expect(db.product.deleteMany).not.toHaveBeenCalled();
  });
  test('annulment is disabled by default and cannot be called by a non-administrator',async()=>{
    const {service,db}=setup(7,[7]);
    const command={operationId:'44444444-4444-4444-8444-444444444444',expectedVersion:0,reason:'Synthetic protected command'};
    await expect(service.annul(user,productId,command)).rejects.toMatchObject({status:404});
    await expect(service.annul({...user,role:'ASISTENTE'},productId,command)).rejects.toMatchObject({status:403});
    expect(db.$transaction).not.toHaveBeenCalled();
  });
  test('schema compatibility fallback retains active-state and search filters',async()=>{
    const {service,db}=setup(0,[]);
    db.product.findMany=jest.fn().mockRejectedValueOnce(new Prisma.PrismaClientKnownRequestError('Missing optional column',{
      code:'P2022',clientVersion:'5.22.0',
    })).mockResolvedValueOnce([]);
    await service.findAll(user,{search:'Test'});
    const fallback=db.product.findMany.mock.calls[1][0];
    expect(fallback.where).toMatchObject({companyId:user.companyId,archivedAt:null,OR:expect.any(Array)});
    expect(fallback.select.archivedAt).toBe(true);
  });
  test.each([[5,[5]],[0,[2,-2]],[-1,[-1]],[2,[1]],[0,[1]]])('rejects stock %s and warehouse quantities %j without deleting',async(stock,quantities)=>{
    const{service,db}=setup(stock as number,quantities as number[]);
    await expect(service.remove(user,productId)).rejects.toMatchObject({status:409});
    expect(db.product.deleteMany).not.toHaveBeenCalled();
  });
  test('checks stock and protected history after taking the product row lock',async()=>{
    const{service,db}=setup(0,[],true);await expect(service.remove(user,productId)).rejects.toMatchObject({status:409});
    expect(db.$queryRaw.mock.calls[0][0].join('')).toContain('FOR UPDATE');
    expect(db.$queryRaw.mock.invocationCallOrder[0]).toBeLessThan(db.inventoryMovement.count.mock.invocationCallOrder[0]);
    expect(db.product.deleteMany).not.toHaveBeenCalled();
  });
  test('only reconciled zero stock with no references is physically deleted',async()=>{
    const{service,db}=setup(0,[0,0]);await expect(service.remove(user,productId)).resolves.toEqual({ok:true});
    expect(db.product.deleteMany).toHaveBeenCalledWith({where:{id:productId,companyId:user.companyId}});
  });
  test('archived delete is an explicit conflict, never a false success',async()=>{
    const{service,db,row}=setup(0,[]);(row as any).archivedAt=new Date();
    await expect(service.remove(user,productId)).rejects.toMatchObject({response:{code:'PRODUCT_ARCHIVED'}});
    expect(db.product.deleteMany).not.toHaveBeenCalled();
  });
});
