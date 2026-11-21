// Local-only laboratory. A stable, private test key allows process restarts
// without making previously issued synthetic offline receipts unverifiable.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {spawn}=require('node:child_process');
const root=path.resolve(__dirname,'../..');
const dir=path.join(root,'.uat/recovery-closing-20261120');
fs.mkdirSync(dir,{recursive:true});
const keyFile=path.join(dir,'local-auth-key.json');
if(!fs.existsSync(keyFile))fs.writeFileSync(keyFile,JSON.stringify({key:crypto.randomBytes(48).toString('base64url')}),{mode:0o600,flag:'wx'});
const {key}=JSON.parse(fs.readFileSync(keyFile,'utf8'));
if(typeof key!=='string'||key.length<48)throw new Error('Invalid local test key');
const env={...process.env,
  DATABASE_URL:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing',
  APP_ENV:'uat',UAT_LOCAL_ONLY:'true',UAT_EXPECTED_DB_NAME:'fullpos_recovery_closing',UAT_EXPECTED_DB_PORT:'56560',
  HOST:'127.0.0.1',PORT:'4005',JWT_SECRET:key,CASH_SHIFT_MAX_SPAN_HOURS:'24',
};
const log=fs.openSync(path.join(dir,'api.log'),'a');
const child=spawn(process.execPath,['dist/main.js'],{cwd:path.join(root,'apps/api'),env,stdio:['ignore',log,log],windowsHide:true});
console.log('Local recovery API started with protected UAT configuration.');
child.on('exit',code=>{fs.closeSync(log);process.exitCode=code??1;});
process.on('SIGINT',()=>child.kill());
process.on('SIGTERM',()=>child.kill());
