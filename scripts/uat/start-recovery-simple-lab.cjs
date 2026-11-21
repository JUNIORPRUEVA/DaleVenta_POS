const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
const root=path.resolve(__dirname,'../..');
const keyPath=process.env.FULLPOS_LOCAL_RECOVERY_KEY_FILE;
if(!keyPath || !keyPath.replaceAll('\\','/').endsWith('/.uat/recovery-closing-20261120/local-auth-key.json')) throw Error('Local test key path required');
const {key}=JSON.parse(fs.readFileSync(keyPath,'utf8'));
const port=process.env.FULLPOS_LOCAL_RECOVERY_PORT || '4006';
if(!['4005','4006'].includes(port)) throw Error('Only the dedicated local lab ports are allowed');
const dir=path.join(root,'.uat/recovery-simple');fs.mkdirSync(dir,{recursive:true});
const log=fs.openSync(path.join(dir,'api.log'),'a');
const child=spawn(process.execPath,['dist/main.js'],{cwd:path.join(root,'apps/api'),windowsHide:true,
  env:{...process.env,DATABASE_URL:'postgresql://postgres@127.0.0.1:56560/fullpos_recovery_closing',
    APP_ENV:'uat',UAT_LOCAL_ONLY:'true',UAT_EXPECTED_DB_NAME:'fullpos_recovery_closing',UAT_EXPECTED_DB_PORT:'56560',
    HOST:'127.0.0.1',PORT:port,JWT_SECRET:key,CASH_SHIFT_MAX_SPAN_HOURS:'24'},stdio:['ignore',log,log]});
console.log(`Recovery UI lab bound to loopback port ${port}; PID ${child.pid}.`);
child.on('exit',code=>{fs.closeSync(log);process.exitCode=code??1;});
