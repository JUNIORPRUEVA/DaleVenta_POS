const assert=require('node:assert/strict'),fs=require('node:fs/promises'),crypto=require('node:crypto');
const {io}=require('socket.io-client');const base='http://127.0.0.1:4017';
async function main(){
 const a=JSON.parse(await fs.readFile('.uat/product-lifecycle/native-fixture.json','utf8'));
 async function req(path,token,body,method='POST'){
  const r=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
  assert.ok(r.ok,`${path}: ${r.status}`);return r.json();
 }
 const password=crypto.randomBytes(24).toString('base64url')+'aA1!';const run=Date.now();
 const b=await req('/auth/register-business',null,{commercialName:`Realtime foreign ${run}`,firstName:'Synthetic',lastName:'Foreign',email:`realtime-${run}@example.test`,password,confirmPassword:password,phone:'8095550100'});
 const sockets=[];
 async function connect(token){const socket=io(base,{transports:['websocket'],auth:{token},reconnection:false});sockets.push(socket);
  await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Socket timeout')),5000);socket.once('connect',()=>{clearTimeout(timeout);resolve();});socket.once('connect_error',()=>{clearTimeout(timeout);reject(Error('Socket authentication failed'));});});return socket;}
 try{
  const one=await connect(a.token),two=await connect(a.token),foreign=await connect(b.accessToken);
  const first=[],second=[],other=[];one.on('product.changed',e=>first.push(e));two.on('product.changed',e=>second.push(e));foreign.on('product.changed',e=>other.push(e));
  const product=await req('/products',a.token,{nombre:`Realtime product ${run}`,categoria:'UAT',precio:10,costo:2,stock:0,operationId:crypto.randomUUID()});
  await req(`/products/${product.id}/archive`,a.token,{},'PATCH');await req(`/products/${product.id}/reactivate`,a.token,{},'PATCH');
  await new Promise(resolve=>setTimeout(resolve,250));
  assert.equal(first.length,3);assert.deepEqual(second,first);assert.equal(other.length,0);
  for(const event of first){assert.deepEqual(Object.keys(event).sort(),['action','companyId','eventId','productId']);assert.equal(event.companyId,a.user.companyId);assert.equal(event.productId,product.id);}
  await fs.writeFile('.uat/product-lifecycle/realtime.json',JSON.stringify({result:'PASS',sameTenantDevices:2,events:first.length,foreignTenantEvents:0,minimalPayload:true},null,2));
  console.log('PASS: two authorized clients received three committed hints; foreign company received none; no prices/costs exposed.');
 }finally{sockets.forEach(s=>s.disconnect());}
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
