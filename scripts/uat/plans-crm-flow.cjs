// Real FullPOS -> credentialed bridge -> PostgreSQL CRM. Never production.
const assert = require('node:assert/strict'), fs = require('node:fs/promises'), path = require('node:path');
const { randomBytes, randomUUID } = require('node:crypto'), { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url'), { spawn } = require('node:child_process');
const { PrismaClient } = require('@prisma/client'), PDFDocument = require('pdfkit');
const root = path.resolve(__dirname, '../..'), dir = path.join(root, '.uat/plans-crm');
const crmRoot = process.env.PLANS_CRM_REPO || 'C:/t/crm-plans-20261121';
const bridgeRoot = process.env.PLANS_BRIDGE_REPO || 'C:/t/bridge-plans-20261121';
const bridgeRequire = createRequire(path.join(bridgeRoot, 'package.json'));
const { Pool } = require('pg'), express = bridgeRequire('express');
const run = Date.now().toString(36), checks = [], errors = [];
let api, bridge, crm, bridgeDb, admin, prisma, apiLog;
const clean = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/(TOKEN|SECRET|PASSWORD|KEY|URL|SMTP|WHATSAPP|GUARDIAN|DOSA|OPENAI|APPYRA|R2_|CLOUD|PGHOST|PGPORT|PGDATABASE|PGUSER)/i.test(key)));
const report = { run, realHTTP: true, realPostgreSQL: true, externalDelivery: 'recording transport only, no Meta calls', checks, errors };
async function request(base, route, { token, cookie, body, method, headers } = {}) {
  const response = await fetch(base + route, { method: method || (body ? 'POST' : 'GET'),
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(cookie ? { cookie } : {}), ...(body && !(body instanceof FormData) ? {'content-type':'application/json'} : {}), ...headers },
    body: body instanceof FormData ? body : body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  const type = response.headers.get('content-type') || '';
  return { status: response.status, body: type.includes('json') ? await response.json() : Buffer.from(await response.arrayBuffer()), cookie: response.headers.get('set-cookie')?.split(';')[0] };
}
async function check(name, fn) { try { await fn(); checks.push(name); console.log('PASS', name); } catch (error) { errors.push({name, message: error.message.slice(0, 800)}); console.log('FAIL', name, error.message.slice(0, 300)); } }
function ok(response, status=200) { assert.equal(response.status, status, JSON.stringify(response.body)); return response.body; }
const base = 'http://127.0.0.1:4019';
async function main() {
  await fs.mkdir(dir, {recursive:true});
  // Check out all code privately; do not import secret-bearing workstation env.
  for(const key of Object.keys(process.env)) if(!(key in clean)) delete process.env[key];
  const secret = randomBytes(48).toString('hex');
  const url = 'postgresql://postgres@127.0.0.1:56562/fullpos_plans_payment_20261121';
  admin = new Pool({connectionString:'postgresql://postgres@127.0.0.1:56562/postgres'});
  const crmName = `fullpos_crm_${run}`, bridgeName = `fullpos_bridge_${run}`;
  for(const name of [crmName, bridgeName]) { assert.match(name,/^fullpos_(crm|bridge)_[a-z0-9]+$/); await admin.query(`CREATE DATABASE "${name}"`); }
  report.databases = { fullpos:'fullpos_plans_payment_20261121', crm:crmName, bridge:bridgeName };
  Object.assign(process.env, clean, { DATABASE_URL:`postgresql://postgres@127.0.0.1:56562/${bridgeName}`, DOTENV_PATH:path.join(dir,'no-env'),
    DALEVENTAS_LICENSE_API_BASE_URL:base, DALEVENTAS_LICENSE_ADMIN_SECRET:secret, LICENSING_ENABLED:'true',
    LICENSING_PAYMENT_STATUS_ENABLED:'true', APPYRA_ENV:'local', NODE_ENV:'test', PHYTO_WHATSAPP_MOCK:'true', LAURA_ENABLED:'false',
    PHYTO_CRM_TOKEN:randomBytes(32).toString('hex'), PHYTO_CRM_DATA:path.join(dir,run,'crm.sqlite') });
  apiLog = await fs.open(path.join(dir, 'api.log'), 'a');
  api = spawn(process.execPath, ['dist/main.js'], {cwd:path.join(root,'apps/api'),windowsHide:true,stdio:['ignore',apiLog.fd,apiLog.fd],env:{...clean,
    DATABASE_URL:url, APP_ENV:'uat', UAT_LOCAL_ONLY:'true', UAT_EXPECTED_DB_NAME:'fullpos_plans_payment_20261121', UAT_EXPECTED_DB_PORT:'56562',
    HOST:'127.0.0.1', PORT:'4019', JWT_SECRET:randomBytes(48).toString('hex'), LICENSE_ADMIN_SECRET:secret, CRM_LICENSE_MANAGEMENT_ENABLED:'true',
    LICENSE_EVIDENCE_STORAGE_DRIVER:'local', LICENSE_EVIDENCE_DIR:path.join(dir,'private-evidence'), LICENSE_EVIDENCE_TEST_ACTIVATE:'false',
    LICENSE_BANK_NAME:'Banco de pruebas',LICENSE_BANK_ACCOUNT:'1234567890',LICENSE_BANK_HOLDER:'Empresa sintética',LICENSE_WA_DRY_RUN:'true',
    DOSA_EMISSION_ENABLED:'false',DOSA_PRODUCTION_EMISSION_ENABLED:'false'}});
  let ready=false, startupExit=null;
  api.once('exit',code=>{startupExit=code;});
  for(let i=0;i<300;i++){if(startupExit!==null)throw Error(`Private API exited during startup: ${startupExit}`);try{ready=(await request(base,'/health')).status===200;if(ready)break;}catch{} await new Promise(r=>setTimeout(r,200));} assert.ok(ready,'private FullPOS ready');
  bridgeDb = new Pool({connectionString:process.env.DATABASE_URL});
  await bridgeDb.query(await fs.readFile(path.join(bridgeRoot,'backend/db/migrations/054_create_service_credentials.sql'),'utf8'));
  const {createServiceCredential} = bridgeRequire('./backend/auth/serviceCredentials');
  const issued = await createServiceCredential({query:bridgeDb.query.bind(bridgeDb), name:`crm-${run}`, scopes:['licenses:read','licenses:write','products:read','payments:read','customers:read'],createdBy:'synthetic-lab'});
  const {createServiceDaleventasRoutes} = bridgeRequire('./backend/routes/serviceDaleventasRoutes');
  const app = express(); app.use(express.json()); app.use('/api/service/daleventas',createServiceDaleventasRoutes());
  bridge = await new Promise(resolve=>{const server=app.listen(0,'127.0.0.1',()=>resolve(server));});
  process.env.LICENSING_BASE_URL=`http://127.0.0.1:${bridge.address().port}`; process.env.LICENSING_SERVICE_TOKEN=issued.token;
  const {startCrmServer} = await import(pathToFileURL(path.join(crmRoot,'backend/server/crm-server.mjs')));
  const password = randomBytes(24).toString('hex')+'aA1!';
  crm = await startCrmServer({host:'127.0.0.1',port:0, databaseUrl:`postgresql://postgres@127.0.0.1:56562/${crmName}`, dataFile:process.env.PHYTO_CRM_DATA,
    token:process.env.PHYTO_CRM_TOKEN,quiet:true,schedulerEnabled:false,whatsappMock:true,bootstrapAdminUser:'admin@example.test',bootstrapAdminPassword:password});
  const login = await request(crm.url,'/api/admin/auth/login',{body:{username:'admin@example.test',password}}); ok(login);
  const cookie=login.cookie; assert.ok(cookie);
  const crmApi=(route,body)=>request(crm.url,route,{cookie,body});
  const customerPassword=randomBytes(24).toString('hex')+'aA1!';
  const registered=ok(await request(base,'/auth/register-business',{body:{commercialName:`Empresa sintética CRM ${run}`,firstName:'Prueba',lastName:'Integración',email:`flow-${run}@example.test`,password:customerPassword,confirmPassword:customerPassword,phone:'8095550100'}}),201);
  const companyId=registered.user.companyId, token=registered.accessToken;
  prisma = new PrismaClient({datasources:{db:{url}}});
  const order=ok(await request(base,'/license/orders',{token,body:{planCode:'pro',months:3}}),201);
  let pdf; await new Promise(resolve=>{const d=new PDFDocument(),chunks=[];d.on('data',b=>chunks.push(b));d.on('end',()=>{pdf=Buffer.concat(chunks);resolve();});d.text('SINTÉTICO. NO ES UN PAGO. '+run);d.end();});
  const form=new FormData();form.append('file',new Blob([pdf],{type:'application/pdf'}),'prueba.pdf');
  const uploaded=ok(await request(base,`/license/orders/${order.id}/evidence`,{token,body:form}),201);
  const evidenceId=uploaded.evidence.id;
  await check('new FullPOS registration appears in CRM licenses',async()=>{const data=ok(await crmApi(`/api/admin/licensing/licenses?limit=100`));assert.ok(data.licenses.some(row=>row.id===companyId));});
  await check('CRM catalog matches FullPOS authoritative catalog',async()=>{const direct=ok(await request(base,'/license/plans')).plans;const bridged=ok(await crmApi('/api/admin/licensing/plans?project=FULLPOS')).plans;for(const plan of direct){const projected=bridged.find(p=>p.code===plan.code);assert.equal(projected?.priceAmount,Number(plan.monthlyPrice));assert.equal(projected.active,true);assert.deepEqual(projected.limits,plan.limits);}});
  await check('receipt appears in CRM orders',async()=>{const data=ok(await crmApi(`/api/admin/billing/licenses/${companyId}/orders`));assert.equal(data.orders.find(row=>row.id===order.id).evidences[0].id,evidenceId);});
  await check('receipt PDF bytes reach authenticated administrator and reject a mismatched company',async()=>{const data=await request(crm.url,`/api/admin/billing/licenses/${companyId}/orders/${order.id}/evidence/${evidenceId}`,{cookie});assert.equal(data.status,200);assert.deepEqual(data.body,pdf);const anonymous=await request(crm.url,`/api/admin/billing/licenses/${companyId}/orders/${order.id}/evidence/${evidenceId}`);assert.equal(anonymous.status,401);
    assert.equal((await request(crm.url,`/api/admin/billing/licenses/${randomUUID()}/orders/${order.id}/evidence/${evidenceId}`,{cookie})).status,404);});
  await check('receipt appears in CRM Payments as pending',async()=>{const data=ok(await crmApi(`/api/admin/billing/payments?licenseId=${companyId}&kind=pending`));assert.ok(data.payments.some(row=>row.id===order.id&&Number(row.amount)===Number(order.amount)));});
  const {createLicensingClient,loadLicensingConfig}=await import(pathToFileURL(path.join(crmRoot,'backend/server/licensing/client.mjs')));
  const client=createLicensingClient(loadLicensingConfig());
  const {createEvidenceIntake,createEvidenceAdminNotifier}=await import(pathToFileURL(path.join(crmRoot,'backend/server/billing/evidence-intake.mjs')));
  await check('notice and administrator inbox persist once in CRM PostgreSQL across rescan',async()=>{
    const intake=createEvidenceIntake({client,db:crm.collections,notifyAdministrators:createEvidenceAdminNotifier({listRecipients:()=>crm.ctx.users.listUsers(),notify:crm.notifyUser})});
    const first=await intake.scan();assert.equal(first.errors,0);const second=await intake.scan();assert.equal(second.errors,0);
    const rows=await crm.collections.list('license_evidence_notices',{limit:500});assert.equal(rows.filter(row=>row.order_id===order.id).length,1);
    const bells=await crm.collections.list('user_notifications',{where:{entity_id:order.id}});assert.equal(bells.length,1);assert.equal(bells[0].type,'license_evidence');
  });
  await check('administrator notification includes original PDF and ten original fields, once', async()=>{
    const {createEvidenceNoticeDispatcher}=await import(pathToFileURL(path.join(crmRoot,'backend/server/billing/evidence-outbox.mjs')));
    const sent=[], media=[];
    const dispatcher=createEvidenceNoticeDispatcher({db:{list:(name)=>crm.collections.list(name,{where:{order_id:order.id}}),update:(...args)=>crm.collections.update(...args)},
      enabled:true,recipient:'18095550100',approvedTemplate:async(name,type)=>name==='licencia_comprobante_soporte_pdf'&&type==='DOCUMENT',
      fetchEvidence:row=>client.evidenceContent({licenseId:row.license_id,orderId:row.order_id,evidenceId:row.evidence_id}).then(file=>({buffer:file.buffer,mime:file.contentType,fileName:'prueba.pdf'})),
      uploadMedia:async file=>{assert.deepEqual(file.buffer,pdf);assert.equal(file.mime,'application/pdf');media.push(file);return{mediaId:'synthetic-media'};},
      whatsapp:{enabled:true,sendTemplate:async(to,message)=>{sent.push({to,message});return{ok:true,messageId:'synthetic-message-'+run};}}});
    assert.equal((await dispatcher.run()).sent,1);assert.equal((await dispatcher.run()).sent,0);assert.equal(sent.length,1);assert.equal(media.length,1);
    const components=sent[0].message.components;assert.equal(components[0].parameters[0].type,'document');
    const parameters=components[1].parameters;assert.equal(parameters.length,10);assert.ok(parameters[0].text.includes(run));assert.equal(parameters[1].text,'pro');assert.equal(parameters[5].text,order.reference);
    const saved=(await crm.collections.list('license_evidence_notices',{where:{order_id:order.id}}))[0];assert.equal(saved.status,'sent');
  });
  await check('administrator can edit license through versioned command',async()=>{const detail=ok(await crmApi(`/api/admin/licensing/licenses/${companyId}`));const version=detail.license.version;assert.ok(version);const body={operationId:randomUUID(),expectedVersion:version,action:'update',reason:'Prueba local autorizada',fields:{notes:'Integración verificada'}};ok(await crmApi(`/api/admin/licensing/licenses/${companyId}/commands`,body));});
  await check('administrator confirms receipt and applies exactly three paid months once',async()=>{const detail=ok(await crmApi(`/api/admin/licensing/licenses/${companyId}`));
    const body={licenseId:companyId,paymentOrderId:order.id,status:'SETTLED',reason:'Transferencia sintética verificada',operationId:randomUUID(),expectedVersion:detail.license.version};
    ok(await crmApi('/api/admin/billing/orders/payment-status',body));const saved=await prisma.licensePaymentOrder.findUniqueOrThrow({where:{id:order.id}});const company=await prisma.company.findUniqueOrThrow({where:{id:companyId}});
    assert.equal(saved.status,'SETTLED');assert.equal(saved.activationState,'CONFIRMED');assert.equal(company.licenseStatus,'ACTIVE');assert.equal(company.planCode,'pro');assert.ok(saved.periodStart&&saved.periodEnd);assert.equal(saved.periodEnd.toISOString(),company.licenseExpiresAt.toISOString());
    const end=company.licenseExpiresAt.toISOString();const retry=await crmApi('/api/admin/billing/orders/payment-status',body);assert.ok([200,409].includes(retry.status));assert.equal((await prisma.company.findUniqueOrThrow({where:{id:companyId}})).licenseExpiresAt.toISOString(),end);
    const paid=ok(await crmApi(`/api/admin/billing/payments?licenseId=${companyId}&kind=completed`));assert.ok(paid.payments.some(row=>row.id===order.id));});
  await check('settled receipt cannot be rejected or charged twice by a new command', async()=>{
    const before=await prisma.company.findUniqueOrThrow({where:{id:companyId}});
    const detail=ok(await crmApi(`/api/admin/licensing/licenses/${companyId}`));
    const response=await crmApi('/api/admin/billing/orders/payment-status',{licenseId:companyId,paymentOrderId:order.id,status:'REJECTED',reason:'Rechazo sintético de comprobación',operationId:randomUUID(),expectedVersion:detail.license.version});
    assert.equal(response.status,409);assert.equal((await prisma.licensePaymentOrder.findUniqueOrThrow({where:{id:order.id}})).status,'SETTLED');
    assert.equal((await prisma.company.findUniqueOrThrow({where:{id:companyId}})).licenseExpiresAt.toISOString(),before.licenseExpiresAt.toISOString());
  });
  await check('order without a receipt cannot be marked paid; rejection preserves a previously paid period', async()=>{
    const before=await prisma.company.findUniqueOrThrow({where:{id:companyId}});
    const pending=ok(await request(base,'/license/orders',{token,body:{planCode:'pro',months:1}}),201);
    let detail=ok(await crmApi(`/api/admin/licensing/licenses/${companyId}`));
    const command={licenseId:companyId,paymentOrderId:pending.id,status:'SETTLED',reason:'Prueba local sin comprobante',operationId:randomUUID(),expectedVersion:detail.license.version};
    assert.equal((await crmApi('/api/admin/billing/orders/payment-status',command)).status,409);
    let proof;await new Promise(resolve=>{const d=new PDFDocument(),chunks=[];d.on('data',b=>chunks.push(b));d.on('end',()=>{proof=Buffer.concat(chunks);resolve();});d.text('RECHAZO SINTÉTICO. SIN PAGO REAL. '+randomUUID());d.end();});
    const form=new FormData();form.append('file',new Blob([proof],{type:'application/pdf'}),'rechazo.pdf');ok(await request(base,`/license/orders/${pending.id}/evidence`,{token,body:form}),201);
    detail=ok(await crmApi(`/api/admin/licensing/licenses/${companyId}`));
    ok(await crmApi('/api/admin/billing/orders/payment-status',{...command,status:'REJECTED',reason:'Ingreso sintético no recibido',operationId:randomUUID(),expectedVersion:detail.license.version}));
    const company=await prisma.company.findUniqueOrThrow({where:{id:companyId}});assert.equal(company.licenseStatus,before.licenseStatus);assert.equal(company.licenseExpiresAt.toISOString(),before.licenseExpiresAt.toISOString());
    const rejected=await prisma.licensePaymentOrder.findUniqueOrThrow({where:{id:pending.id},include:{evidences:true}});assert.equal(rejected.status,'REJECTED');assert.equal(rejected.evidences.length,1);
  });
  if(process.argv.includes('--windows') && errors.length===0) await check('Windows CRM reads the private PDF and confirms a renewal using real HTTP',async()=>{
    const before=await prisma.company.findUniqueOrThrow({where:{id:companyId}});
    const nativeOrder=ok(await request(base,'/license/orders',{token,body:{planCode:'pro',months:3}}),201);
    let proof;await new Promise(resolve=>{const d=new PDFDocument(),chunks=[];d.on('data',b=>chunks.push(b));d.on('end',()=>{proof=Buffer.concat(chunks);resolve();});d.text('PDF SINTÉTICO WINDOWS. SIN VALIDEZ. '+randomUUID());d.end();});
    const nativeForm=new FormData();nativeForm.append('file',new Blob([proof],{type:'application/pdf'}),'windows.pdf');
    ok(await request(base,`/license/orders/${nativeOrder.id}/evidence`,{token,body:nativeForm}),201);
    await fs.writeFile(path.join(dir,'native-fixture.json'),JSON.stringify({crmUrl:crm.url,username:'admin@example.test',password,companyId,orderId:nativeOrder.id,companyName:`Empresa sintética CRM ${run}`}));
    const log=await fs.open(path.join(dir,'windows.log'),'w');
    const child=spawn(process.env.ComSpec||'C:/Windows/System32/cmd.exe',['/d','/c','C:\\src\\flutter\\bin\\flutter.bat','test','integration_test/fullpos_payment_flow_test.dart','-d','windows','--no-pub','--dart-define=APP_ENV=uat',`--dart-define=PLANS_CRM_LAB_DIR=${dir.replaceAll('\\','/')}`],{cwd:path.join(crmRoot,'app'),env:{...clean},windowsHide:true,stdio:['ignore',log.fd,log.fd]});
    const code=await new Promise(resolve=>child.on('exit',resolve));await log.close();assert.equal(code,0,'Windows integration log');
    const saved=await prisma.licensePaymentOrder.findUniqueOrThrow({where:{id:nativeOrder.id}});const after=await prisma.company.findUniqueOrThrow({where:{id:companyId}});
    assert.equal(saved.status,'SETTLED');assert.equal(saved.activationState,'CONFIRMED');assert.equal(saved.periodStart.toISOString(),before.licenseExpiresAt.toISOString());
    const expected=new Date(before.licenseExpiresAt);expected.setUTCMonth(expected.getUTCMonth()+3);assert.equal(after.licenseExpiresAt.toISOString(),expected.toISOString());
    report.windows={orderId:nativeOrder.id,periodStart:saved.periodStart,periodEnd:saved.periodEnd,sqlVerified:true};
  });
  if (process.argv.includes('--admin-windows')) {
    const adminDir=path.join(root,'.uat/plans-admin');await fs.mkdir(adminDir,{recursive:true});
    const adminName=`Administración sintética ${run}`, adminEmail=`admin-flow-${run}@example.test`;
    const adminPassword=randomBytes(24).toString('hex')+'aA1!';
    const customer=ok(await request(base,'/auth/register-business',{body:{commercialName:adminName,firstName:'Prueba',lastName:'Administración',email:adminEmail,password:adminPassword,confirmPassword:adminPassword,phone:'8095550100'}}),201);
    const id=customer.user.companyId;
    await check('manual CRM confirmation activates a Basic plan without bypassing payment verification',async()=>{
      const purchase=ok(await request(base,'/license/orders',{token:customer.accessToken,body:{planCode:'basico',months:1}}),201);
      let bytes;await new Promise(resolve=>{const d=new PDFDocument(),chunks=[];d.on('data',b=>chunks.push(b));d.on('end',()=>{bytes=Buffer.concat(chunks);resolve();});d.text('ACTIVACIÓN SINTÉTICA. SIN PAGO REAL. '+randomUUID());d.end();});
      const body=new FormData();body.append('file',new Blob([bytes],{type:'application/pdf'}),'activacion.pdf');ok(await request(base,`/license/orders/${purchase.id}/evidence`,{token:customer.accessToken,body}),201);
      const detail=ok(await crmApi(`/api/admin/licensing/licenses/${id}`)).license;
      ok(await crmApi('/api/admin/billing/orders/payment-status',{licenseId:id,paymentOrderId:purchase.id,status:'SETTLED',reason:'Validación manual sintética autorizada',operationId:randomUUID(),expectedVersion:detail.version}));
      const saved=await prisma.company.findUniqueOrThrow({where:{id}});assert.equal(saved.licenseStatus,'ACTIVE');assert.equal(saved.planCode,'basico');assert.ok(saved.licenseKey);
    });
    const product=await prisma.product.create({data:{companyId:id,nombre:'Artículo sintético conservado',categoria:'Pruebas',precio:1,costo:0,stock:0}});
    const before=await prisma.company.findUniqueOrThrow({where:{id}});
    await fs.writeFile(path.join(adminDir,'native-fixture.json'),JSON.stringify({crmUrl:crm.url,username:'admin@example.test',password,companyId:id,companyName:adminName,
      fullposApi:base,customerToken:customer.accessToken,customerEmail:adminEmail,customerPassword:adminPassword}));
    await check('Windows CRM edits effective quotas/features, suspends, reactivates and revokes while retaining data',async()=>{
      const log=await fs.open(path.join(adminDir,'windows.log'),'w');
      const child=spawn(process.env.ComSpec||'C:/Windows/System32/cmd.exe',['/d','/c','C:\\src\\flutter\\bin\\flutter.bat','test','integration_test/fullpos_license_management_test.dart','-d','windows','--no-pub','--dart-define=APP_ENV=uat',`--dart-define=PLANS_ADMIN_LAB_DIR=${adminDir.replaceAll('\\','/')}`],{cwd:path.join(crmRoot,'app'),env:{...clean},windowsHide:true,stdio:['ignore',log.fd,log.fd]});
      const code=await new Promise(resolve=>child.on('exit',resolve));await log.close();assert.equal(code,0,'Windows administrative integration log');
      const result=JSON.parse(await fs.readFile(path.join(adminDir,'native-result.json'),'utf8'));assert.equal(result.result,'PASS');
      const after=await prisma.company.findUniqueOrThrow({where:{id}});assert.equal(after.licenseStatus,'BLOCKED');assert.equal(after.licenseKey,null);
      assert.ok(await prisma.product.findUnique({where:{id:product.id}}));assert.equal(await prisma.user.count({where:{companyId:id}}),1);
      for(const key of ['planCode','ncfEnabled','taxEnabled','wholesalePriceListsEnabled','measurementUnitsEnabled'])assert.equal(after[key],before[key],key);
      const logRows=await prisma.companyLicenseAuditLog.findMany({where:{companyId:id,action:{startsWith:'license.crm.'}}});
      for(const action of ['license.crm.update','license.crm.suspend','license.crm.reactivate','license.crm.revoke'])assert.ok(logRows.some(row=>row.action===action),action);
      assert.equal(await prisma.licensePaymentOrder.count({where:{companyId:id,status:'SETTLED'}}),1);
      report.administration={companyId:id,actualWindows:true,sqlVerified:true,productRetained:true,paidOrderRetained:true,fiscalSettingsUnchanged:true};
    });
    await check('revoked license cannot be reactivated without a valid license and paid period',async()=>{
      const detail=ok(await crmApi(`/api/admin/licensing/licenses/${id}`)).license;
      const response=await crmApi(`/api/admin/licensing/licenses/${id}/commands`,{operationId:randomUUID(),expectedVersion:detail.version,action:'reactivate',reason:'Prueba de rechazo tras revocación'});
      assert.equal(response.status,409);assert.equal((await prisma.company.findUniqueOrThrow({where:{id}})).licenseKey,null);
    });
  }
  report.result=errors.length?'FAIL':'PASS';report.companyId=companyId;report.orderId=order.id;
}
main().catch(error=>{report.result='FAIL';errors.push({name:'setup',message:error.message.slice(0,1000)});console.error(error.stack);}).finally(async()=>{
  await fs.mkdir(dir,{recursive:true});await fs.writeFile(path.join(dir,'result.json'),JSON.stringify(report,null,2));
  if(crm)await crm.close();if(bridge)await new Promise(resolve=>bridge.close(resolve));if(api)api.kill();if(apiLog)await apiLog.close();
  if(prisma)await prisma.$disconnect();if(bridgeDb)await bridgeDb.end();if(admin)await admin.end();
  process.exitCode=report.result==='PASS'?0:1;
});
