// Synthetic local acceptance. No production URLs, credentials or customer data.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const fs=require('node:fs/promises');
const {PrismaClient,Prisma}=require('@prisma/client');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private'}}});
const base='http://127.0.0.1:4017';
const run=Date.now();const evidence={run,scenarios:[]};
async function request(route,token,body,method=body?'POST':'GET'){
 const response=await fetch(base+route,{method,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
 const data=await response.json().catch(()=>({}));return{status:response.status,data};
}
function expectHttp(result,status,label){assert.equal(result.status,status,`${label}: HTTP ${result.status}, ${result.data.code||result.data.message||''}`);return result.data;}
async function business(label){
 const password=crypto.randomBytes(24).toString('base64url')+'aA1!';
 const email=`lifecycle-${label}-${run}@example.test`;
 const account=expectHttp(await request('/auth/register-business',null,{commercialName:`Lifecycle ${label} ${run}`,
   firstName:'Synthetic',lastName:label,email,password,confirmPassword:password,phone:'8095550109'}),201,'register');
 return{token:account.accessToken,user:account.user,password,email};
}
async function main(){
 expectHttp(await request('/health'),200,'health');
 const a=await business('a'),b=await business('b');
 const own={id:a.user.companyId};
 async function create(name,stock=0){return expectHttp(await request('/products',a.token,{
   nombre:`${name} ${run}`,categoria:'UAT',precio:10,costo:5,stock,operationId:crypto.randomUUID(),
 }),201,`create ${name}`);}
 async function state(id){return expectHttp(await request(`/products/${id}/lifecycle`,a.token),200,'lifecycle');}
 async function stockSnapshot(id){
  return JSON.parse(JSON.stringify({product:await db.product.findFirst({where:{companyId:own.id,id}}),
   stocks:await db.warehouseStock.findMany({where:{companyId:own.id,productId:id},orderBy:{id:'asc'}}),
   movements:await db.inventoryMovement.findMany({where:{companyId:own.id,productId:id},orderBy:{id:'asc'}})}));
 }
 for(const endpoint of ['products','sales','cotizaciones','clients','service-orders']){
   const result=await request(`/${endpoint}/debug/purge`,a.token,null,'DELETE');
   assert.ok([404,405].includes(result.status),`${endpoint} purge must be unavailable, got ${result.status}`);
 }
 evidence.scenarios.push('five debug purge routes unavailable to company administrator');
 const empty=await create('empty');expectHttp(await request(`/products/${empty.id}`,a.token,null,'DELETE'),200,'delete empty');
 assert.equal(await db.product.count({where:{companyId:own.id,id:empty.id}}),0);
 evidence.scenarios.push('zero stock without references physically deleted');
 const initial=await create('initial',20);const before=await stockSnapshot(initial.id);
 expectHttp(await request(`/products/${initial.id}`,a.token,null,'DELETE'),409,'reject stock delete');
 assert.deepEqual(await stockSnapshot(initial.id),before);
 evidence.scenarios.push('initial stock cannot be physically deleted; original snapshot unchanged');
 const inspected=await state(initial.id);assert.equal(inspected.canAnnul,true);
 const command={operationId:crypto.randomUUID(),expectedVersion:inspected.lifecycleVersion,reason:'Synthetic product created by mistake'};
 const annulled=expectHttp(await request(`/products/${initial.id}/annul`,a.token,command),200,'annul initial');
 assert.equal(annulled.product.lifecycleStatus,'ANNULLED');assert.equal(annulled.product.stock,0);
 const after=await stockSnapshot(initial.id);assert.equal(after.movements.length,2);
 const original=after.movements.find(row=>row.id===before.movements[0].id);assert.deepEqual(original,before.movements[0]);
 const compensation=after.movements.find(row=>row.sourceType==='PRODUCT_ANNULMENT');
 assert.equal(Number(compensation.quantityDelta),-20);assert.equal(Number(compensation.resultingQuantity),0);
 assert.ok(after.stocks.every(row=>Number(row.quantity)===0));
 evidence.scenarios.push('initial stock compensated atomically; original movement preserved');
 const replay=expectHttp(await request(`/products/${initial.id}/annul`,a.token,command),200,'replay');assert.equal(replay.replayed,true);
 assert.deepEqual(await stockSnapshot(initial.id),after);
 expectHttp(await request(`/products/${initial.id}/annul`,a.token,{...command,operationId:crypto.randomUUID()}),409,'different annul command');
 expectHttp(await request(`/products/${initial.id}/reactivate`,a.token,{},'PATCH'),409,'cannot restore annulled');
 evidence.scenarios.push('lost-response replay does not duplicate compensation; annulled cannot restore');
 expectHttp(await request(`/products/${initial.id}/annul`,b.token,command),404,'foreign company annul');
 expectHttp(await request(`/products/${initial.id}/lifecycle`,b.token),404,'foreign company inspection');
 expectHttp(await request(`/products/${initial.id}/annul`,null,command),401,'unauthenticated annul');
 expectHttp(await request('/products/not-a-uuid/annul',a.token,command),400,'malformed id');
 assert.deepEqual(await stockSnapshot(initial.id),after);
 evidence.scenarios.push('foreign company, missing authentication and malformed IDs rejected');
 const archived=await create('archive',7);const archiveBefore=await stockSnapshot(archived.id);
 expectHttp(await request(`/products/${archived.id}/archive`,a.token,{},'PATCH'),200,'archive');
 const firstArchive=await stockSnapshot(archived.id);
 expectHttp(await request(`/products/${archived.id}/archive`,a.token,{},'PATCH'),200,'archive replay');
 const twice=await stockSnapshot(archived.id);assert.deepEqual(twice,firstArchive);
 assert.deepEqual(twice.movements,archiveBefore.movements);assert.deepEqual(twice.stocks,archiveBefore.stocks);
 expectHttp(await request(`/products/${archived.id}`,a.token,null,'DELETE'),409,'archived not falsely deleted');
 const duplicate=await request('/products',a.token,{nombre:`archive ${run}`,categoria:'UAT',precio:10,costo:5,stock:7,operationId:crypto.randomUUID()});
 expectHttp(duplicate,409,'archived create identity');assert.equal(duplicate.data.code,'PRODUCT_ARCHIVED_EXISTS');
 assert.equal(duplicate.data.productId,archived.id);assert.equal(duplicate.data.canRestore,true);
 const restored=expectHttp(await request(`/products/${archived.id}/reactivate`,a.token,{},'PATCH'),200,'restore');
 assert.equal(restored.product.id,archived.id);assert.equal(restored.product.stock,7);
 evidence.scenarios.push('archive conserves inventory; repeated archive idempotent; creation offers restoration; same ID restored');
 // Legacy fixtures model stock without Kardex and inconsistent per-warehouse stock.
 const warehouse=await db.warehouse.findFirstOrThrow({where:{companyId:own.id,isDefault:true}});
 for(const [label,productStock,warehouseStock] of [['legacy-positive',5,5],['mismatch',5,3],['negative',-1,-1]]){
  const id=crypto.randomUUID();await db.product.create({data:{id,companyId:own.id,nombre:label,categoria:'UAT',precio:1,costo:0,stock:productStock}});
  await db.warehouseStock.create({data:{companyId:own.id,productId:id,warehouseId:warehouse.id,quantity:warehouseStock}});
  const untouched=await stockSnapshot(id);
  const denied=await request(`/products/${id}`,a.token,null,'DELETE');expectHttp(denied,409,label);
  assert.deepEqual(await stockSnapshot(id),untouched);
 }
 evidence.scenarios.push('legacy positive stock without Kardex, mismatched and negative stocks protected');
 const stale=await create('stale-version',4);const old=await state(stale.id);
 expectHttp(await request(`/products/${stale.id}`,a.token,{nombre:`stale edited ${run}`},'PATCH'),200,'edit before annul');
 expectHttp(await request(`/products/${stale.id}/annul`,a.token,{...command,operationId:crypto.randomUUID(),expectedVersion:old.lifecycleVersion}),409,'stale annul version');
 assert.equal((await state(stale.id)).stock,4);
 evidence.scenarios.push('concurrent edit invalidates stale administrative confirmation');
 await fs.writeFile('.uat/product-lifecycle/native-fixture.json',JSON.stringify({api:base,...a}),{mode:0o600});
 await fs.writeFile('.uat/product-lifecycle/acceptance.json',JSON.stringify({...evidence,result:'PASS',companyId:own.id},null,2));
 console.log(JSON.stringify({result:'PASS',scenarios:evidence.scenarios}));
}
main().catch(error=>{console.error(error.name+': '+error.message);process.exitCode=1;}).finally(()=>db.$disconnect());
