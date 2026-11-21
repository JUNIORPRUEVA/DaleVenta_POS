// Serves only a local Flutter review build and its synthetic account fixture.
const http=require('node:http'),fs=require('node:fs/promises'),path=require('node:path');
const types={'.js':'application/javascript','.json':'application/json','.wasm':'application/wasm',
 '.png':'image/png','.svg':'image/svg+xml','.ttf':'font/ttf','.woff2':'font/woff2'};
const root=path.resolve(__dirname,'../..');
const web=path.join(root,'apps/fulltech_app/build/web');
http.createServer(async(req,res)=>{
 if(req.headers.host!=='127.0.0.1:4492'){res.writeHead(403);res.end();return;}
 try{
  const url=new URL(req.url,'http://127.0.0.1:4492');res.setHeader('cache-control','no-store');res.setHeader('referrer-policy','no-referrer');
  if(url.pathname==='/uat-product-fixture'){
   const fixture=JSON.parse(await fs.readFile(path.join(root,'.uat/product-lifecycle/native-fixture.json'),'utf8'));
   res.setHeader('content-type','application/json');res.end(JSON.stringify({email:fixture.email,password:fixture.password}));return;
  }
  if(url.pathname==='/'){
   res.setHeader('content-type','text/html');res.end('<!doctype html><html lang="es"><head><base href="/"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FullPOS · Productos UAT</title></head><body><script src="flutter_bootstrap.js" async></script></body></html>');return;
  }
  const file=path.resolve(web,'.'+path.sep+decodeURIComponent(url.pathname).replace(/^[/\\]+/,''));
  if(!file.startsWith(web+path.sep))throw Error('Invalid path');
  res.setHeader('content-type',types[path.extname(file)]||'application/octet-stream');res.end(await fs.readFile(file));
 }catch(_){res.writeHead(404);res.end('Local file unavailable');}
}).listen(4492,'127.0.0.1',()=>console.log('Local product preview: http://127.0.0.1:4492/'));
