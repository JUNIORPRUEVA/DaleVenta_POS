// Automated browser regression against the loopback review build, fresh profile.
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {spawn}=require('node:child_process'),WebSocket=require('ws');
const root=path.resolve(__dirname,'../..'),evidence=path.join(root,'.uat/product-lifecycle/web');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
class Cdp{
 constructor(url){this.id=0;this.pending=new Map();this.ws=new WebSocket(url);this.ws.on('message',raw=>{const m=JSON.parse(raw);if(!m.id)return;const p=this.pending.get(m.id);if(!p)return;this.pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);});}
 ready(){return new Promise((resolve,reject)=>{this.ws.once('open',resolve);this.ws.once('error',reject);});}
 send(method,params={}){const id=++this.id;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.ws.send(JSON.stringify({id,method,params}));});}
 async js(expression){const r=await this.send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.text);return r.result.value;}
}
async function main(){
 await fs.mkdir(evidence,{recursive:true});
 const fixture=JSON.parse(await fs.readFile(path.join(root,'.uat/product-lifecycle/native-fixture.json'),'utf8'));
 const login=await fetch('http://127.0.0.1:4017/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:fixture.email,password:fixture.password})});assert.ok(login.ok);
 const auth=await login.json();const label=`Web visible ${Date.now()}`;
 const created=await fetch('http://127.0.0.1:4017/products',{method:'POST',headers:{'content-type':'application/json',authorization:`Bearer ${auth.accessToken}`},body:JSON.stringify({nombre:label,categoria:'UAT',precio:10,costo:2,stock:0,operationId:require('node:crypto').randomUUID()})});assert.equal(created.status,201);const product=await created.json();
 try{await fetch('http://127.0.0.1:9232/json/version');throw Error('Browser port already occupied');}catch(e){if(e.message==='Browser port already occupied')throw e;}
 const child=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless=new','--disable-gpu','--no-first-run','--disable-background-networking','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9232',`--user-data-dir=${path.join(evidence,'profile')}`,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let cdp;
 try{
  let page;for(let n=0;n<50;n++){try{const r=await fetch('http://127.0.0.1:9232/json/new?http://127.0.0.1:4492/',{method:'PUT'});page=await r.json();break;}catch(_){await sleep(200);}}
  assert.ok(page?.webSocketDebuggerUrl);cdp=new Cdp(page.webSocketDebuggerUrl);await cdp.ready();await cdp.send('Page.enable');
  const text=()=>cdp.js(`document.body.innerText+'\\n'+Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join('\\n')`);
  async function wait(value){for(let n=0;n<100;n++){await cdp.js(`document.querySelector('flt-semantics-placeholder')?.click();Array.from(document.querySelectorAll('[aria-label]')).find(e=>(e.getAttribute('aria-label')||'').includes('Enable accessibility'))?.click()`);if((await text()).includes(value))return;await sleep(200);}throw Error(`Visible text missing: ${value}`);}
  async function click(value){const found=await cdp.js(`(()=>{const a=Array.from(document.querySelectorAll('[role="button"],button,flt-semantics')).filter(e=>(e.getAttribute('aria-label')||e.innerText||e.textContent||'').trim().includes(${JSON.stringify(value)})).sort((a,b)=>a.getBoundingClientRect().width*a.getBoundingClientRect().height-b.getBoundingClientRect().width*b.getBoundingClientRect().height);if(!a[0])return false;a[0].click();return true;})()`);assert.ok(found,`Button ${value}`);await sleep(400);}
  async function capture(name){const shot=await cdp.send('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(evidence,`${name}.png`),Buffer.from(shot.data,'base64'));}
  await cdp.send('Emulation.setDeviceMetricsOverride',{width:1280,height:900,deviceScaleFactor:1,mobile:false});
  await wait(label);await capture('01-desktop-list');await click(label);await wait('Gestionar producto');await capture('02-desktop-actions');
  await click('Cerrar');await click('Archivados');await wait('Productos archivados');await capture('03-desktop-archived');await click('Cerrar');
  await cdp.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await sleep(400);await capture('04-mobile-list');
  await click(label);await wait('Gestionar producto');await capture('05-mobile-actions');
  const mobileText=await text();assert.ok(mobileText.includes('Archivar'));assert.ok(mobileText.includes('Eliminar definitivamente'));
  const overflow=await cdp.js('document.documentElement.scrollWidth>window.innerWidth');assert.equal(overflow,false);
  await click('Cerrar');await click('Archivados');await wait('Productos archivados');await capture('06-mobile-archived');
  await fs.writeFile(path.join(evidence,'result.json'),JSON.stringify({result:'PASS',viewports:[[1280,900],[390,844]],realHttp:true,archivedAndActiveDialogs:true,mobileDocumentOverflow:false,productId:product.id},null,2));
  console.log('PASS: desktop/mobile Web catalog and real lifecycle dialogs; archived list accessible; no horizontal document overflow.');
 }finally{if(cdp){await cdp.send('Browser.close').catch(()=>{});cdp.ws.close();}if(!child.killed)child.kill();}
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
