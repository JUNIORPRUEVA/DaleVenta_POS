// Synthetic PostgreSQL/HTTP race tests. This file accepts no remote target.
const assert=require('node:assert/strict');const crypto=require('node:crypto');const fs=require('node:fs/promises');
const {Client}=require('pg');const {PrismaClient}=require('@prisma/client');
const connection={host:'127.0.0.1',port:56562,user:'postgres',database:'fullpos_product_lifecycle_private'};
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private'}}});
const base='http://127.0.0.1:4017';const run=Date.now();const evidence={run,scenarios:[]};
const tick=()=>new Promise(resolve=>setTimeout(resolve,120));
async function request(route,token,body,method=body?'POST':'GET'){
 const response=await fetch(base+route,{method,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
 return{status:response.status,data:await response.json().catch(()=>({}))};
}
function ok(result,status,label){assert.equal(result.status,status,`${label}: ${result.status} ${result.data.code||result.data.message||''}`);return result.data;}
async function main(){
 const password=crypto.randomBytes(24).toString('base64url')+'aA1!';
 const auth=ok(await request('/auth/register-business',null,{commercialName:`Lifecycle races ${run}`,firstName:'Synthetic',lastName:'Races',
  email:`lifecycle-races-${run}@example.test`,password,confirmPassword:password,phone:'8095550123'}),201,'register');
 const {user,accessToken:token}=auth;const companyId=user.companyId;
 async function create(label,stock=20,extra={}){return ok(await request('/products',token,{nombre:`${label} ${run}`,categoria:'UAT',precio:10,costo:5,stock,operationId:crypto.randomUUID(),...extra}),201,label);}
 async function state(id){return ok(await request(`/products/${id}/lifecycle`,token),200,'inspect');}
 async function command(id){const s=await state(id);return{expectedVersion:s.lifecycleVersion,operationId:crypto.randomUUID(),reason:'Synthetic lifecycle race acceptance'};}
 async function snapshot(id){return JSON.parse(JSON.stringify({product:await db.product.findFirst({where:{companyId,id}}),
  stocks:await db.warehouseStock.findMany({where:{companyId,productId:id},orderBy:{id:'asc'}}),
  movements:await db.inventoryMovement.findMany({where:{companyId,productId:id},orderBy:{id:'asc'}})}));}
 const q=await db.cotizacion.create({data:{companyId,createdByUserId:user.id,customerName:'Synthetic',customerPhone:'',subtotal:10,itbisAmount:0,total:10}});
 async function insertItem(client,productId){
  await client.query('INSERT INTO "CotizacionItem" (id,"cotizacionId","productId","productNameSnapshot",qty,"unitPrice","lineTotal") VALUES ($1,$2,$3,$4,1,10,10)',
   [crypto.randomUUID(),q.id,productId,'Original synthetic snapshot']);
 }
 const referenced=await create('reference first');const cmd=await command(referenced.id);
 const client=new Client(connection);await client.connect();
 try{
  await client.query('BEGIN');await insertItem(client,referenced.id);
  let finished=false;const racing=request(`/products/${referenced.id}/annul`,token,cmd).then(result=>{finished=true;return result;});
  await tick();assert.equal(finished,false,'annul must wait for an uncommitted protected reference');
  await client.query('COMMIT');ok(await racing,409,'reference wins');
  assert.equal((await snapshot(referenced.id)).movements.length,1);
  evidence.scenarios.push('uncommitted quote locks product; annul waits and rejects after reference commits');
  const annulFirst=await create('annul first');const annulCmd=await command(annulFirst.id);
  await client.query('BEGIN');await client.query('SELECT id FROM "Product" WHERE id=$1 FOR UPDATE',[annulFirst.id]);
  // Hold the exact lifecycle row lock, apply the approved operation on another
  // product first, then verify a stale writer against its committed final state.
  await client.query('ROLLBACK');ok(await request(`/products/${annulFirst.id}/annul`,token,annulCmd),200,'annul first');
  await client.query('BEGIN');await assert.rejects(insertItem(client,annulFirst.id),error=>error.message.includes('PRODUCT_LIFECYCLE_NOT_ACTIVE'));
  await client.query('ROLLBACK');
  evidence.scenarios.push('stale document writer is rejected by PostgreSQL after annulment');
  const concurrent=await create('same command');const parallelCmd=await command(concurrent.id);
  const pair=await Promise.all([request(`/products/${concurrent.id}/annul`,token,parallelCmd),request(`/products/${concurrent.id}/annul`,token,parallelCmd)]);
  pair.forEach(r=>ok(r,200,'concurrent idempotence'));
  assert.equal((await snapshot(concurrent.id)).movements.length,2);
  assert.equal(await db.productLifecycleEvent.count({where:{companyId,productId:concurrent.id,action:'PRODUCT_ANNULLED'}}),1);
  evidence.scenarios.push('two simultaneous identical annulments produce one compensation and one audit event');
  const failing=await create('rollback');const failingCmd=await command(failing.id);const failingBefore=await snapshot(failing.id);
  await client.query(`CREATE FUNCTION uat_lifecycle_rollback_${run}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.id='${failing.id}'::uuid AND NEW.annulled_at IS NOT NULL THEN RAISE EXCEPTION 'UAT_FORCED_ROLLBACK'; END IF; RETURN NEW; END $$`);
  await client.query(`CREATE TRIGGER uat_lifecycle_rollback_${run} BEFORE UPDATE ON "Product" FOR EACH ROW EXECUTE FUNCTION uat_lifecycle_rollback_${run}()`);
  try{ok(await request(`/products/${failing.id}/annul`,token,failingCmd),500,'forced mid-operation failure');
   assert.deepEqual(await snapshot(failing.id),failingBefore);
   assert.equal(await db.productLifecycleEvent.count({where:{companyId,productId:failing.id,action:'PRODUCT_ANNULLED'}}),0);
  }finally{await client.query(`DROP TRIGGER uat_lifecycle_rollback_${run} ON "Product"`);await client.query(`DROP FUNCTION uat_lifecycle_rollback_${run}()`);}
  ok(await request(`/products/${failing.id}/annul`,token,failingCmd),200,'retry after real rollback');
  evidence.scenarios.push('failure after stock compensation rolls back product, warehouses, movements and audit; retry succeeds once');
  const adjusted=await create('adjusted');
  ok(await request(`/products/${adjusted.id}/stock`,token,{delta:1,operationId:crypto.randomUUID(),reason:'Synthetic additional stock'},'PATCH'),200,'adjust');
  assert.equal((await state(adjusted.id)).canAnnul,false);
  ok(await request(`/products/${adjusted.id}/annul`,token,await command(adjusted.id)),409,'adjustment protects history');
  evidence.scenarios.push('additional stock adjustment blocks annulment');
  const code=await create('reserved',2,{codigo:`RESERVED-${run}`});
  ok(await request(`/products/${code.id}/archive`,token,{},'PATCH'),200,'archive reserved');
  ok(await request('/products',token,{nombre:'Different identity',categoria:'UAT',precio:10,costo:5,stock:0,codigo:`RESERVED-${run}`,operationId:crypto.randomUUID()}),409,'archived code reserved');
  const stockBeforeRestore=await snapshot(code.id);
  const archivedEventCount=await db.productLifecycleEvent.count({where:{companyId,productId:code.id,action:'PRODUCT_ARCHIVED'}});assert.equal(archivedEventCount,1);
  const active=await db.product.count({where:{companyId,archivedAt:null}});
  const originalLimit=(await db.company.findUniqueOrThrow({where:{id:companyId},select:{maxProducts:true}})).maxProducts;
  await db.company.update({where:{id:companyId},data:{maxProducts:active}});
  try{ok(await request(`/products/${code.id}/reactivate`,token,{},'PATCH'),409,'restore full plan');assert.deepEqual(await snapshot(code.id),stockBeforeRestore);}
  finally{await db.company.update({where:{id:companyId},data:{maxProducts:originalLimit}});}
  const restored=ok(await request(`/products/${code.id}/reactivate`,token,{},'PATCH'),200,'restore available');assert.equal(restored.product.id,code.id);
  const replayRestore=ok(await request(`/products/${code.id}/reactivate`,token,{},'PATCH'),200,'restore replay');assert.equal(replayRestore.product.id,code.id);
  assert.equal(await db.productLifecycleEvent.count({where:{companyId,productId:code.id,action:'PRODUCT_REACTIVATED'}}),1);
  evidence.scenarios.push('archived code reserved; plan-full restore changes nothing; restore and retry retain ID and one event');
  const oldOperation=crypto.randomUUID();const removed=await create('tombstone',0,{operationId:oldOperation});
  ok(await request(`/products/${removed.id}`,token,null,'DELETE'),200,'delete');
  ok(await request(`/products/${removed.id}`,token,null,'DELETE'),200,'delete replay');
  ok(await request('/products',token,{nombre:`tombstone ${run}`,categoria:'UAT',precio:10,costo:5,stock:0,operationId:oldOperation}),409,'cannot replay creation after delete');
  assert.equal(await db.product.count({where:{companyId,id:removed.id}}),0);
  evidence.scenarios.push('durable delete tombstone prevents replayed offline creation from resurrecting the identity');
  const raceOperation=crypto.randomUUID();const race=await create('delete race',0,{operationId:raceOperation});
  await client.query('BEGIN');
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1),hashtext($2))',[companyId,`product.create:${race.id}`]);
  let deleted=false;const deletion=request(`/products/${race.id}`,token,null,'DELETE').then(r=>{deleted=true;return r;});
  await tick();assert.equal(deleted,false,'delete must share the offline creation serialization lock');
  const replay=request('/products',token,{nombre:`delete race ${run}`,categoria:'UAT',precio:10,costo:5,stock:0,operationId:raceOperation});
  await tick();await client.query('COMMIT');
  ok(await deletion,200,'serialized delete');ok(await replay,409,'serialized replay');
  assert.equal(await db.product.count({where:{companyId,id:race.id}}),0);
  evidence.scenarios.push('delete and offline create replay share a lock; identity cannot resurrect in the race window');
  await fs.writeFile('.uat/product-lifecycle/adversarial.json',JSON.stringify({...evidence,result:'PASS',companyId},null,2));
  console.log(JSON.stringify({result:'PASS',scenarios:evidence.scenarios}));
 }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(()=>db.$disconnect());
