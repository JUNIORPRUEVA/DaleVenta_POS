const {spawnSync,spawn}=require('node:child_process');
const fs=require('node:fs');
const crypto=require('node:crypto');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const command=process.argv[2];
if(!['init','serve'].includes(command))throw Error('Only isolated lab commands are supported');
const target=new URL('postgresql://postgres@127.0.0.1:56562/fullpos_product_lifecycle_private');
if(target.hostname!=='127.0.0.1'||target.port!=='56562'||target.pathname!=='/fullpos_product_lifecycle_private')throw Error('Unsafe target');
if(command==='serve'){
  const directory=path.join(root,'.uat/product-lifecycle');fs.mkdirSync(directory,{recursive:true});
  const keyPath=path.join(directory,'lab-key.json');
  const key=fs.existsSync(keyPath)?JSON.parse(fs.readFileSync(keyPath,'utf8')).key:crypto.randomBytes(48).toString('base64url');
  if(!fs.existsSync(keyPath))fs.writeFileSync(keyPath,JSON.stringify({key}),{mode:0o600});
  const log=fs.openSync(path.join(directory,'api.log'),'a');
  const child=spawn(process.execPath,['dist/main.js'],{cwd:path.join(root,'apps/api'),windowsHide:true,
    env:{...process.env,DATABASE_URL:target.href,APP_ENV:'uat',UAT_LOCAL_ONLY:'true',
      UAT_EXPECTED_DB_NAME:'fullpos_product_lifecycle_private',UAT_EXPECTED_DB_PORT:'56562',
      HOST:'127.0.0.1',PORT:'4017',JWT_SECRET:key,PRODUCT_LIFECYCLE_ANNULMENT_ENABLED:'true',
      DOSA_EMISSION_ENABLED:'false',DOSA_PRODUCTION_EMISSION_ENABLED:'false'},stdio:['ignore',log,log]});
  console.log(`Isolated product lifecycle API: loopback 4017, PID ${child.pid}.`);
  child.on('exit',code=>{fs.closeSync(log);process.exitCode=code??1;});
}else{
const result=spawnSync(process.execPath,[require.resolve('prisma/build/index.js'),'migrate','deploy',
  '--schema',path.join(root,'apps/api/prisma/schema.prisma')],{
  cwd:root,env:{...process.env,DATABASE_URL:target.href},stdio:'inherit',windowsHide:true,
});
process.exitCode=result.status??1;
}
