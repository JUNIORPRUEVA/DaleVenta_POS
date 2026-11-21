// Real HTTP commerce on synthetic companies in the isolated loopback database.
const assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs/promises');
const {PrismaClient}=require('@prisma/client');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private'}}});
const base='http://127.0.0.1:4017',run=Date.now(),scenarios=[];
async function main(){
 const password=crypto.randomBytes(24).toString('base64url')+'aA1!';
 let token;
 async function req(path,body,method=body?'POST':'GET',status=200){
  const r=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
  const data=await r.json().catch(()=>({}));assert.equal(r.status,status,`${method} ${path}: ${r.status} ${data.code||data.message||''}`);return data;
 }
 const a=await req('/auth/register-business',{commercialName:`Commerce lifecycle ${run}`,firstName:'Synthetic',lastName:'Commerce',email:`commerce-${run}@example.test`,password,confirmPassword:password,phone:'8095550100'},'POST',201);
 token=a.accessToken;const companyId=a.user.companyId;
 const json=v=>JSON.parse(JSON.stringify(v));
 async function create(label,stock=20){return req('/products',{nombre:`${label} ${run}`,categoria:'UAT',precio:10,costo:5,stock,operationId:crypto.randomUUID()},'POST',201);}
 async function inspect(id){return req(`/products/${id}/lifecycle`);}
 async function denyAnnul(id){const state=await inspect(id);assert.equal(state.canAnnul,false);
  await req(`/products/${id}/annul`,{operationId:crypto.randomUUID(),expectedVersion:state.lifecycleVersion,reason:'Synthetic blocked lifecycle operation'},'POST',409);}
 async function snapshot(id){return json({product:await db.product.findFirst({where:{id,companyId}}),movements:await db.inventoryMovement.findMany({where:{companyId,productId:id},orderBy:{id:'asc'}}),stocks:await db.warehouseStock.findMany({where:{companyId,productId:id},orderBy:{id:'asc'}})});}
 const cash=await req('/cash/sessions/open',{openingAmount:0},'POST',201);
 const sold=await create('sold');
 const salePayload={clientRequestId:crypto.randomUUID(),originCashSessionId:cash.shiftId,paymentMethod:'cash',paymentCashAmount:10,cashReceived:10,expectedTotalSold:10,
  items:[{productId:sold.id,qty:1,priceSoldUnit:10}]};
 const sale=await req('/sales',salePayload,'POST',201);const saleId=sale.id||sale.sale?.id;assert.ok(saleId);
 const documents=json(await db.sale.findMany({where:{companyId,id:saleId},include:{items:true}}));
 await denyAnnul(sold.id);const beforeArchive=await snapshot(sold.id);
 await req(`/products/${sold.id}/archive`,{},'PATCH');
 const afterArchive=await snapshot(sold.id);assert.deepEqual(afterArchive.movements,beforeArchive.movements);assert.deepEqual(afterArchive.stocks,beforeArchive.stocks);
 assert.deepEqual(json(await db.sale.findMany({where:{companyId,id:saleId},include:{items:true}})),documents);
 await req('/sales',{...salePayload,clientRequestId:crypto.randomUUID()},'POST',400);
 const item=await db.saleItem.findFirstOrThrow({where:{saleId,productId:sold.id}});
 const returned=await req(`/sales/${saleId}/return`,{clientRequestId:crypto.randomUUID(),originalSaleCashSessionId:cash.shiftId,operationCashSessionId:cash.shiftId,operationOccurredAt:new Date().toISOString(),restoreInventory:true,reason:'Synthetic historical return after archive',items:[{saleItemId:item.id,qty:1}]},'POST',201);
 assert.ok(returned);assert.equal((await inspect(sold.id)).stock,20);await denyAnnul(sold.id);
 scenarios.push('real sale protects identity; archive preserves sale/item snapshots; new archived sale rejected; historical return restores inventory');
 const purchased=await create('purchased',0);
 const order=await req('/purchases/orders',{items:[{productId:purchased.id,productName:purchased.nombre,quantity:3,unitCost:5}]},'POST',201);
 const orderId=order.id||order.order?.id;assert.ok(orderId);
 const orderItem=await db.purchaseOrderItem.findFirstOrThrow({where:{productId:purchased.id,purchaseOrderId:orderId}});
 await denyAnnul(purchased.id);
 const receipt=await req(`/purchases/orders/${orderId}/receive`,{clientRequestId:crypto.randomUUID(),updateInventory:true,items:[{purchaseOrderItemId:orderItem.id,quantityReceived:3,unitCost:5}]},'POST',201);
 assert.ok(receipt);assert.equal((await inspect(purchased.id)).stock,3);
 const purchaseBefore=json(await db.purchaseOrder.findFirst({where:{id:orderId,companyId},include:{items:true,receipts:{include:{items:true}}}}));
 await req(`/products/${purchased.id}/archive`,{},'PATCH');
 assert.deepEqual(json(await db.purchaseOrder.findFirst({where:{id:orderId,companyId},include:{items:true,receipts:{include:{items:true}}}})),purchaseBefore);
 scenarios.push('real purchase order and receipt protect product and remain byte-equivalent after archive');
 const transferred=await create('transferred');
 await req('/settings',{multiWarehouseEnabled:true},'PATCH');
 const source=await db.warehouse.findFirstOrThrow({where:{companyId,isDefault:true}});
 const destination=await req('/warehouses',{name:`Secondary ${run}`,code:`SEC-${run}`},'POST',201);
 const warehouseId=destination.id||destination.warehouse?.id;assert.ok(warehouseId);
 const transfer=await req('/warehouses/transfers',{sourceWarehouseId:source.id,destinationWarehouseId:warehouseId,clientRequestId:crypto.randomUUID(),items:[{productId:transferred.id,quantity:'4'}]},'POST',201);
 assert.ok(transfer);await denyAnnul(transferred.id);
 const before=await snapshot(transferred.id);assert.equal(before.stocks.reduce((sum,row)=>sum+Number(row.quantity),0),20);
 await req(`/products/${transferred.id}`,null,'DELETE',409);assert.deepEqual(await snapshot(transferred.id),before);
 scenarios.push('real transfer conserves principal/warehouse total and blocks delete and annulment');
 const negative=await create('opposing-stock',0);
 await db.warehouseStock.updateMany({where:{companyId,productId:negative.id,warehouseId:source.id},data:{quantity:2}});
 await db.warehouseStock.create({data:{companyId,productId:negative.id,warehouseId,quantity:-2}});
 const mixedBefore=await snapshot(negative.id);await req(`/products/${negative.id}`,null,'DELETE',409);assert.deepEqual(await snapshot(negative.id),mixedBefore);
 scenarios.push('opposite warehouse quantities cannot conceal nonzero stock behind a zero principal balance');
 await fs.writeFile('.uat/product-lifecycle/commerce.json',JSON.stringify({result:'PASS',companyId,saleId,orderId,scenarios},null,2));
 console.log(JSON.stringify({result:'PASS',scenarios}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(()=>db.$disconnect());
