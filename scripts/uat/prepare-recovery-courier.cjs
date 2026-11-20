// Read-only fixture selection; no credentials are printed, sessions changed or money posted.
const fs = require('node:fs/promises');
const jwt = require('jsonwebtoken');
const {PrismaClient} = require('@prisma/client');
const db = new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing'}}});
async function main() {
  const dir = '.uat/courier'; await fs.mkdir(dir,{recursive:true});
  const {key} = JSON.parse(await fs.readFile(process.env.FULLPOS_LOCAL_RECOVERY_KEY_FILE,'utf8'));
  const active = {revokedAt:null,expiresAt:{gt:new Date()}};
  const cashier = await db.authSession.findFirstOrThrow({where:{...active,user:{role:'CAJERO',blocked:false}},include:{user:true}});
  const admin = await db.authSession.findFirstOrThrow({where:{...active,companyId:cashier.companyId,user:{role:'ADMIN',blocked:false}},include:{user:true}});
  const foreign = await db.authSession.findFirstOrThrow({where:{...active,companyId:{not:cashier.companyId},user:{role:'ADMIN',blocked:false}},include:{user:true}});
  const fixture = {api:'http://127.0.0.1:4004'};
  for (const [name,session] of Object.entries({cashier,admin,foreign})) {
    const u = session.user;
    fixture[name] = {user:{id:u.id,companyId:u.companyId,email:u.email,nombreCompleto:u.nombreCompleto,role:u.role},
      access:jwt.sign({sub:u.id,companyId:u.companyId,sessionId:session.id,tokenType:'access'},key,{expiresIn:'1h'})};
  }
  await fs.writeFile(`${dir}/auth.json`,JSON.stringify(fixture),{mode:0o600});
  const before = {
    sales:await db.sale.findMany({orderBy:{id:'asc'},select:{id:true,totalSold:true,userId:true,cashSessionId:true,clientRequestId:true}}),
    movements:await db.cashMovement.findMany({orderBy:{id:'asc'},select:{id:true,amount:true,occurredAt:true,operationId:true,sessionId:true}}),
  };
  await fs.writeFile(`${dir}/financial-before.json`,JSON.stringify(before));
  console.log('Local cashier, company administrator and foreign administrator fixtures prepared. Financial snapshot preserved.');
}
main().catch(error=>{console.error(error.name+': '+error.message);process.exitCode=1;}).finally(()=>db.$disconnect());
