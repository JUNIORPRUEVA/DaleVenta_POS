const assert=require('node:assert/strict'),fs=require('node:fs/promises');
const {PrismaClient}=require('@prisma/client');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private'}}});
async function main(){
 const results=[];
 for(const file of ['windows/native-result.json','android/files/product-lifecycle-evidence/native-result.json']){
  const r=JSON.parse(await fs.readFile(`.uat/product-lifecycle/${file}`,'utf8'));assert.equal(r.result,'PASS');
  const product=await db.product.findFirstOrThrow({where:{companyId:r.companyId,id:r.productId}});
  assert.ok(product.annulledAt);assert.ok(product.archivedAt);assert.equal(Number(product.stock),0);
  assert.equal(product.annulmentOperationId,r.annulmentOperationId);
  const movements=await db.inventoryMovement.findMany({where:{companyId:r.companyId,productId:r.productId}});assert.equal(movements.length,2);
  const initial=movements.find(m=>m.type==='INITIAL_STOCK'),inverse=movements.find(m=>m.sourceType==='PRODUCT_ANNULMENT');
  assert.ok(initial&&inverse);assert.equal(Number(initial.quantityDelta),7);assert.equal(Number(inverse.quantityDelta),-7);
  assert.equal(inverse.sourceItemId,initial.id);
  assert.equal(await db.productLifecycleEvent.count({where:{companyId:r.companyId,productId:r.productId,action:'PRODUCT_ANNULLED'}}),1);
  assert.equal(await db.product.count({where:{companyId:r.companyId,id:r.deletedProductId}}),0);
  const valid=await db.product.findFirstOrThrow({where:{companyId:r.companyId,id:r.reconnectProductId}});assert.equal(Number(valid.stock),5);
  const validMovements=await db.inventoryMovement.findMany({where:{companyId:r.companyId,productId:r.reconnectProductId}});assert.equal(validMovements.length,1);assert.equal(Number(validMovements[0].quantityDelta),5);
  assert.equal(r.archivePendingDeletePreserved,true);
  const archived=await db.product.findFirstOrThrow({where:{companyId:r.companyId,id:r.archivedResolutionProductId}});
  assert.ok(archived.archivedAt);assert.equal(Number(archived.stock),3);
  assert.equal(await db.inventoryMovement.count({where:{companyId:r.companyId,productId:archived.id}}),1);
  results.push({platform:r.platform,result:'PASS',originalAndCompensationRetained:true,exactlyOneAnnulment:true,validReplayExactlyOnce:true,pendingDeleteArchivedWithStockPreserved:true});
 }
 await fs.writeFile('.uat/product-lifecycle/native-data.json',JSON.stringify({result:'PASS',results},null,2));console.log(JSON.stringify({result:'PASS',results}));
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(()=>db.$disconnect());
