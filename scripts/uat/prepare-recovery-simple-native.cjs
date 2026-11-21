const fs=require('node:fs/promises');
const jwt=require('jsonwebtoken');
const {PrismaClient}=require('@prisma/client');
const db=new PrismaClient({datasources:{db:{url:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing'}}});
async function main(){
 const previous=JSON.parse(await fs.readFile('.uat/simple-financial-before.json','utf8'));
 const session=await db.authSession.findFirstOrThrow({where:{companyId:previous.companyId,userId:previous.userId,revokedAt:null,expiresAt:{gt:new Date()}}});
 const {key}=JSON.parse(await fs.readFile(process.env.FULLPOS_LOCAL_RECOVERY_KEY_FILE,'utf8'));
 const access=jwt.sign({sub:previous.userId,companyId:previous.companyId,sessionId:session.id,tokenType:'access'},key,{expiresIn:'1h'});
 await fs.writeFile('.uat/simple-native-auth.json',JSON.stringify({access}),{mode:0o600});
 console.log('Fresh synthetic access token prepared for the copied UAT profile; no session or security settings changed.');
}
main().catch(error=>{console.error(error.name+': '+error.message);process.exitCode=1;}).finally(()=>db.$disconnect());
