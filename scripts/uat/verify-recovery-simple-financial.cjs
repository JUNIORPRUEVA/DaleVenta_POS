const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const {PrismaClient}=require('@prisma/client');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing'}}});
async function main(){
 const previous=JSON.parse(await fs.readFile('.uat/simple-financial-before.json','utf8'));
 const where={companyId:previous.companyId};
 const current={
  sales:await db.sale.findMany({where,orderBy:{id:'asc'},select:{id:true,clientRequestId:true,totalSold:true,cashSessionId:true}}),
  movements:await db.cashMovement.findMany({where,orderBy:{id:'asc'},select:{id:true,operationId:true,sessionId:true,amount:true,occurredAt:true}}),
  sessions:await db.cashSession.findMany({where,orderBy:{id:'asc'},select:{id:true,status:true,closingAmount:true,expectedAmount:true,difference:true}}),
 };
 assert.deepEqual(JSON.parse(JSON.stringify(current)),previous.financial);
 const native=JSON.parse(await fs.readFile('.uat/simple-native-evidence/native-ui.json','utf8'));
 assert.equal(native.result,'PASS');
 const result={result:'PASS',sales:current.sales.length,movements:current.movements.length,
  financialRecordsUnchanged:true,originalIncidentsPreserved:native.originalIncidents,incidentsAfter:native.retainedIncidents,
  editableDraftVisible:native.editableDraftVisible,originalAttemptStillPending:native.originalAttemptStillPending};
 await fs.writeFile('.uat/simple-native-evidence/financial-check.json',JSON.stringify(result,null,2));
 console.log(JSON.stringify(result));
}
main().catch(error=>{console.error(`${error.name}: ${error.message}`);process.exitCode=1;}).finally(()=>db.$disconnect());
