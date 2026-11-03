const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const bcrypt = require('bcryptjs');
const {PrismaClient} = require('@prisma/client');
const EMAIL = 'alanube.admin@fullpos.local';
const SLUG = 'fullpos-alanube-uat-access';
const NAME = 'SYNTHETIC Fullpos Alanube UAT Access';
function assertTarget(env) {
  const url = new URL(env.DATABASE_URL || '');
  if (env.APP_ENV !== 'uat' || env.UAT_LOCAL_ONLY !== 'true' || !['postgres:','postgresql:'].includes(url.protocol) || url.search || url.hash || url.hostname !== '127.0.0.1' || url.port !== '56550' || url.pathname !== '/fullpos_alanube_uat' ||
      ['ALANUBE_ENABLE_REAL_CALLS','ECF_EMISSION_ENABLED','ECF_ALANUBE_AUTH_TESTS_ENABLED','ALANUBE_HTTP_TRANSPORT_ENABLED'].some(k => env[k] === 'true')) throw Error('UAT_TARGET_REFUSED');
}
function assertPassword(password) {
  if (typeof password !== 'string' || password.length < 8 || Buffer.byteLength(password,'utf8') > 72 || /[\r\n\0]/.test(password)) throw Error('PASSWORD_POLICY_REQUIRED');
}
function assertVacant(company, user) {
  // Never adopt, promote, reset or move an existing account, synthetic or real.
  if (company || user) throw Error('EXISTING_IDENTITY_REQUIRES_SEPARATE_RESET_REVIEW');
}
async function main() {
  assertTarget(process.env);
  const root = path.resolve(__dirname,'../..');
  if (process.cwd() !== root || path.basename(root).toUpperCase() !== 'FULLPOS-ECF-ALANUBE' || execFileSync('git',['branch','--show-current'],{encoding:'utf8',windowsHide:true}).trim() !== 'feature/ecf-alanube') throw Error('WORKTREE_REQUIRED');
  if (execFileSync('docker',['port','fullpos_alanube_uat_postgres','5432/tcp'],{encoding:'utf8',windowsHide:true}).trim() !== '127.0.0.1:56550') throw Error('UAT_BINDING_REQUIRED');
  const backup = JSON.parse(fs.readFileSync(path.join(root,'artifacts/e32-first-trial/admin-access-backup.json'),'utf8').replace(/^\uFEFF/,''));
  if (!/^ecf_before_admin_access_\d{8}_\d{6}\.dump$/.test(backup.file) || backup.fullArchiveReadVerified !== true || !Number.isFinite(Date.parse(backup.verifiedAtUtc)) || Date.now()-Date.parse(backup.verifiedAtUtc) > 3600000 || Date.parse(backup.verifiedAtUtc)>Date.now()) throw Error('RECENT_VERIFIED_BACKUP_REQUIRED');
  const dump = fs.readFileSync(path.join(root,'artifacts/uat-backups',backup.file));
  if (dump.length !== backup.bytes || crypto.createHash('sha256').update(dump).digest('hex').toUpperCase() !== backup.sha256) throw Error('BACKUP_HASH_MISMATCH');
  let input = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) { input += chunk; if (Buffer.byteLength(input)>4096) throw Error('INPUT_LIMIT'); }
  let {password} = JSON.parse(input); input = '';
  assertPassword(password);
  // Identical library and cost to AuthService.registerBusiness/resetPassword and UAT seed.
  const passwordHash = await bcrypt.hash(password,10); password = undefined;
  const prisma = new PrismaClient();
  try {
    const db = await prisma.$queryRaw`SELECT current_database() AS name`;
    if (db[0]?.name !== 'fullpos_alanube_uat') throw Error('UAT_DATABASE_REQUIRED');
    const result = await prisma.$transaction(async tx => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('fullpos-alanube-uat-admin-access'))`;
      assertVacant(await tx.company.findUnique({where:{slug:SLUG},select:{id:true}}),await tx.user.findUnique({where:{email:EMAIL},select:{id:true}}));
      const now = new Date();
      const company = await tx.company.create({data:{name:NAME,slug:SLUG,status:'ACTIVE',plan:'STANDARD',licenseStatus:'TRIAL',trialStartedAt:now,
        trialEndsAt:new Date(now.getTime()+7*86400000),maxUsers:2,maxProducts:100,productSource:'LOCAL',taxEnabled:false,ncfEnabled:false}});
      const user = await tx.user.create({data:{companyId:company.id,email:EMAIL,passwordHash,nombreCompleto:'Administrador sintetico Alanube UAT',telefono:'0000000000',edad:0,role:'ADMIN',blocked:false}});
      await tx.companyMember.create({data:{companyId:company.id,userId:user.id,role:'OWNER',status:'ACTIVE',joinedAt:now}});
      return {identifier:EMAIL,companyId:company.id,companySlug:company.slug,syntheticCompany:true,role:user.role,licenseStatus:company.licenseStatus,trialEndsAt:company.trialEndsAt,changedExistingUsers:0};
    });
    console.log(JSON.stringify({status:'SYNTHETIC_ADMIN_CREATED',...result}));
  } finally { await prisma.$disconnect(); }
}
module.exports = {assertTarget,assertPassword,assertVacant};
if (require.main === module) main().catch(()=>{console.log(JSON.stringify({status:'ADMIN_PROVISION_BLOCKED_NO_AUTOMATIC_RETRY'}));process.exitCode=2;});
