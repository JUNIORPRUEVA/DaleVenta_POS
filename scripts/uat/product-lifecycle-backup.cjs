// Backup/restore rehearsal limited to our existing synthetic Docker container.
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),crypto=require('node:crypto');
const {spawnSync}=require('node:child_process'),{PrismaClient}=require('@prisma/client');
const container='fullpos_product_lifecycle_private_7e92',source='fullpos_product_lifecycle_private';
const clone=`fullpos_product_restore_${Date.now()}`;
const url=name=>`postgresql://postgres@127.0.0.1:56562/${name}`;
const original=new PrismaClient({datasources:{db:{url:url(source)}}});let restored;
function docker(args,input){const r=spawnSync('docker',args,{input,maxBuffer:128*1024*1024,windowsHide:true});if(r.status!==0)throw Error(`Isolated Docker command failed: ${args[2]||args[0]}`);return r.stdout;}
async function main(){
 const inspection=JSON.parse(docker(['inspect',container]).toString())[0];
 const published=inspection.NetworkSettings.Ports['5432/tcp'];assert.deepEqual(published,[{HostIp:'127.0.0.1',HostPort:'56562'}]);
 const fixture=JSON.parse(await fs.readFile('.uat/product-lifecycle/windows/native-result.json','utf8'));
 async function stable(db){return JSON.parse(JSON.stringify({
   product:await db.product.findFirst({where:{companyId:fixture.companyId,id:fixture.productId}}),
   movements:await db.inventoryMovement.findMany({where:{companyId:fixture.companyId,productId:fixture.productId},orderBy:{id:'asc'}}),
   events:await db.productLifecycleEvent.findMany({where:{companyId:fixture.companyId,productId:fixture.productId},orderBy:{id:'asc'}}),
 }));}
 const before=await stable(original);assert.ok(before.product.annulledAt);assert.equal(before.movements.length,2);
 const dump=docker(['exec',container,'pg_dump','-U','postgres','-d',source,'-Fc']);
 await fs.writeFile('.uat/product-lifecycle/backup.dump',dump,{mode:0o600});
 docker(['exec',container,'createdb','-U','postgres',clone]);
 docker(['exec','-i',container,'pg_restore','-U','postgres','-d',clone,'--exit-on-error'],dump);
 restored=new PrismaClient({datasources:{db:{url:url(clone)}}});assert.deepEqual(await stable(restored),before);
 for(const sql of [
   'UPDATE "Product" SET archived_at=NULL WHERE company_id=$1::uuid AND id=$2::uuid',
   'UPDATE "Product" SET stock=1 WHERE company_id=$1::uuid AND id=$2::uuid',
 ]){
   await assert.rejects(restored.$executeRawUnsafe(sql,fixture.companyId,fixture.productId),e=>JSON.stringify(e).includes('PRODUCT_LIFECYCLE_ANNULLED'));
 }
 await assert.rejects(restored.$executeRawUnsafe('UPDATE warehouse_stocks SET quantity=1 WHERE company_id=$1::uuid AND product_id=$2::uuid',fixture.companyId,fixture.productId),e=>JSON.stringify(e).includes('PRODUCT_LIFECYCLE_NOT_ACTIVE'));
 assert.deepEqual(await stable(restored),before);assert.deepEqual(await stable(original),before);
 const migrations=await restored.$queryRawUnsafe('SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND migration_name LIKE $1 ORDER BY migration_name','%product_lifecycle%');
 assert.equal(migrations.length,4);
 const result={result:'PASS',backupSha256:crypto.createHash('sha256').update(dump).digest('hex'),bytes:dump.length,restoredDatabase:clone,
  protectedNativeProductIdentical:true,originalDatabaseUnchanged:true,oldWriterRestoreAndStockRejected:true,migrations:migrations.map(m=>m.migration_name)};
 await fs.writeFile('.uat/product-lifecycle/backup-restore.json',JSON.stringify(result,null,2));
 console.log(JSON.stringify(result));
}
main().catch(e=>{console.error(e.name+': '+e.message);process.exitCode=1;}).finally(async()=>{await original.$disconnect();await restored?.$disconnect();});
