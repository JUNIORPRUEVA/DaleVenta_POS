[CmdletBinding()]
param(
  [string]$KeyFile = (Join-Path $env:USERPROFILE '.ssh/daleventas_codex'),
  [ValidatePattern('^ghcr\.io/juniorprueva/fullpos-cloud-api@sha256:[a-f0-9]{64}$')]
  [string]$ExpectedApiImage,
  [ValidatePattern('^ghcr\.io/juniorprueva/fullpos-cloud-web@sha256:[a-f0-9]{64}$')]
  [string]$ExpectedPwaImage
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $KeyFile -PathType Leaf)) { throw 'No se encontró la clave SSH configurada.' }
if ([bool]$ExpectedApiImage -ne [bool]$ExpectedPwaImage) { throw 'Indica ambas imágenes por digest o ninguna.' }
# Read-only. Never reads or prints the private key contents.
# Exit 2: verified server, but production activation flags are not prepared.
$remote = @'
import json,subprocess,sys
expected_sources=dict(zip(['backend','pwa'],sys.argv[1:]))
EXPECTED={"20261113040000_ecf_numbering_environment":"1523a7fd7199627535a1408197e922d6f0761d86872d2acf0ec0f081811691d6","20261113050000_ecf_reviewed_legacy_test_classification":"649d2845b063f1e5eb5f7db669afbd73fd545d8e934060e80ff22a3be5920c4f","20261113060000_ecf_public_print_stamp":"76de09a3c058016f8dbaa3ccd89d712068ae0043248af9e891720e5a2624ce49"}
def run(*a):return subprocess.check_output(a,text=True).strip()
def cid(name):
 ids=run('docker','ps','-q','--filter','label=com.docker.swarm.service.name='+name).splitlines()
 if len(ids)!=1:raise RuntimeError('service-not-unique')
 return ids[0]
try:
 api=cid('daleventapos_backend');db=cid('daleventapos_database')
 q="SELECT json_agg(json_build_object('name',migration_name,'checksum',checksum,'applied',finished_at IS NOT NULL,'rolledBack',rolled_back_at IS NOT NULL)) FROM _prisma_migrations WHERE migration_name IN ("+','.join("'"+n+"'" for n in EXPECTED)+")"
 p=subprocess.run(['docker','exec','-i',db,'sh','-c','exec psql -X -qAt -v ON_ERROR_STOP=1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\"'],input=q,text=True,capture_output=True)
 if p.returncode:raise RuntimeError('schema-query-failed')
 rows=json.loads(p.stdout.strip()) or []
 legacy_query="SELECT count(*) FROM ecf_electronic_documents WHERE environment IS NULL"
 legacy_result=subprocess.run(['docker','exec','-i',db,'sh','-c','exec psql -X -qAt -v ON_ERROR_STOP=1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\"'],input=legacy_query,text=True,capture_output=True)
 if legacy_result.returncode:raise RuntimeError('legacy-state-query-failed')
 unclassified=int(legacy_result.stdout.strip())
 migrations=len(rows)==3 and all(r['applied'] and not r['rolledBack'] and r['checksum']==EXPECTED[r['name']] for r in rows)
 health="require('node:http').get('http://127.0.0.1:'+(process.env.PORT||4000)+'/health',r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>{try{console.log(JSON.stringify({ok:r.statusCode===200&&JSON.parse(d).status==='ok'}))}catch{process.exit(2)}})}).on('error',()=>process.exit(2))"
 healthy=json.loads(run('docker','exec',api,'node','-e',health))['ok']
 config=json.loads(run('docker','inspect',api))[0]
 env=dict(x.split('=',1) for x in config['Config']['Env'] if '=' in x)
 panel=cid('easypanel')
 js=r'''(async()=>{const db=require('lmdb').open({path:'/etc/easypanel/data',readOnly:true});const on=function(text,key){let enabled=false;for(const line of text.split(String.fromCharCode(10))){let at=line.indexOf('=');if(at<0||line.slice(0,at).trim()!==key)continue;let value=line.slice(at+1).trim();let first=value.charCodeAt(0);if(first===34||first===39){let end=value.indexOf(value[0],1);value=end>0?value.slice(1,end):'';}else value=value.split('#')[0].trim();enabled=value==='true';}return enabled;};let result=[];for(const name of ['backend','pwa']){let raw=db.get('services:daleventapos:'+name),v=typeof raw==='string'?JSON.parse(raw):raw;let cfg=v.json;let text=typeof cfg.env==='string'?cfg.env:'';result.push({service:name,autoDeployDisabled:cfg.source.autoDeploy===false,productionBranch:cfg.source.ref==='production-main',productionGateStored:on(text,'DOSA_PRODUCTION_EMISSION_ENABLED'),confirmedGateStored:on(text,'DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED')})}console.log(JSON.stringify(result));await db.close()})().catch(()=>process.exit(2))'''
 settings=json.loads(run('docker','exec',panel,'node','-e',js))
 # Image sources must match both operator-supplied immutable digests exactly.
 # No expected images preserves the original GitHub production-main check.
 source_js=r'''(()=>{const db=require('lmdb').open({path:'/etc/easypanel/data',readOnly:true});let out=[];for(const name of ['backend','pwa']){let raw=db.get('services:daleventapos:'+name),v=typeof raw==='string'?JSON.parse(raw):raw;let s=v.json.source;out.push({service:name,type:s.type,image:s.type==='image'?s.image:null,autoDeploy:s.autoDeploy===true})}console.log(JSON.stringify(out));db.close()})()'''
 sources=json.loads(run('docker','exec',panel,'node','-e',source_js))
 for s in settings:
  source=next(v for v in sources if v['service']==s['service'])
  s['sourceMatchesExpected']=bool(source['type']=='image' and source['image']==expected_sources.get(s['service'])) if expected_sources else s['productionBranch']
  if expected_sources:s['autoDeployDisabled']=not source['autoDeploy']
 backend=next(s for s in settings if s['service']=='backend')
 base=migrations and unclassified==0 and healthy and env.get('RUN_MIGRATIONS') in ['false','0'] and all(s['autoDeployDisabled'] and s['sourceMatchesExpected'] for s in settings)
 ready=base and backend['productionGateStored'] and backend['confirmedGateStored']
 print(json.dumps({'serverChecksPassed':base,'migrationChecksumsMatch':migrations,'unclassifiedFiscalDocuments':unclassified,'apiHealthy':healthy,'autoMigrationsDisabled':env.get('RUN_MIGRATIONS') in ['false','0'],'services':settings,'productionActivationPrepared':ready,'noDeploymentExecuted':True}))
 sys.exit(0 if ready else (2 if base else 1))
except Exception:
 print(json.dumps({'serverChecksPassed':False,'error':'READ_ONLY_PREDEPLOY_CHECK_FAILED_NO_SECRETS_LOGGED'}));sys.exit(1)

'@
$remoteCommand = if ($ExpectedApiImage) { "python3 - $ExpectedApiImage $ExpectedPwaImage" } else { 'python3 -' }
$previousNativeErrorMode = $PSNativeCommandUseErrorActionPreference
try {
  $PSNativeCommandUseErrorActionPreference = $false
  $remote | & ssh -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 root@31.97.99.70 $remoteCommand
  $preflightExit = $LASTEXITCODE
} finally { $PSNativeCommandUseErrorActionPreference = $previousNativeErrorMode }
exit $preflightExit
