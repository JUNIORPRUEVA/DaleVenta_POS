const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {spawn}=require('node:child_process'),WebSocket=require('ws');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'.uat/product-lifecycle/design-evidence');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
class Cdp{
 constructor(url){this.id=0;this.pending=new Map();this.ws=new WebSocket(url);this.ws.on('message',raw=>{const m=JSON.parse(raw);const p=this.pending.get(m.id);if(!p)return;this.pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);});}
 ready(){return new Promise((resolve,reject)=>{this.ws.once('open',resolve);this.ws.once('error',reject);});}
 send(method,params={}){const id=++this.id;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.ws.send(JSON.stringify({id,method,params}));});}
 async js(expression){const r=await this.send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.text);return r.result.value;}
}
async function main(){
 await fs.mkdir(out,{recursive:true});
 const source=await fs.readFile(path.join(root,'apps/fulltech_app/test/preview/product_lifecycle_design_preview.dart'),'utf8');
 const cases=[...source.split('class _NoNetwork')[0].matchAll(/\(\s*'([^']+)',/g)].map(m=>m[1]);assert.ok(cases.length>=36);
 const chrome=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless=new','--disable-gpu','--disable-background-networking','--no-first-run','--remote-debugging-port=9233',`--user-data-dir=${path.join(out,'chrome')}`,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let cdp;
 try{
  let version;for(let n=0;n<40;n++){try{version=await(await fetch('http://127.0.0.1:9233/json/version')).json();break;}catch(_){await sleep(100);}}
  assert.ok(version);const tab=await(await fetch('http://127.0.0.1:9233/json/new?about:blank',{method:'PUT'})).json();
  cdp=new Cdp(tab.webSocketDebuggerUrl);await cdp.ready();await cdp.send('Page.enable');await cdp.send('Runtime.enable');
  const requests=[];cdp.ws.on('message',raw=>{const m=JSON.parse(raw);if(m.method==='Network.requestWillBeSent')requests.push(m.params.request.url);});await cdp.send('Network.enable');
  for(const [width,height] of [[1280,900],[390,844]]){
   await cdp.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<600});
   for(const id of cases){
    await cdp.send('Page.navigate',{url:`http://127.0.0.1:4493/?case=${id}`});
    let ready=false;for(let n=0;n<60;n++){
     ready=await cdp.js("document.querySelector('flutter-view')!==null");if(ready)break;await sleep(100);
    }assert.ok(ready,id);await sleep(300);
    await cdp.js("document.querySelector('flt-semantics-placeholder')?.click()");await sleep(100);
    const shot=await cdp.send('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(out,`${width}-${id}.png`),Buffer.from(shot.data,'base64'));
    assert.equal(await cdp.js('document.documentElement.scrollWidth>window.innerWidth'),false,id);
   }
  }
  const apiRequests=requests.filter(url=>/:(4017|4004|4005)\//.test(url));assert.equal(apiRequests.length,0);
  await fs.writeFile(path.join(out,'result.json'),JSON.stringify({result:'PASS',cases,screenshots:cases.length*2,viewports:[[1280,900],[390,844]],apiRequests:0},null,2));
  console.log(`PASS: ${cases.length} designs, ${cases.length*2} screenshots, no API requests.`);
 }finally{if(cdp){await cdp.send('Browser.close').catch(()=>{});cdp.ws.close();}chrome.kill();}
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
