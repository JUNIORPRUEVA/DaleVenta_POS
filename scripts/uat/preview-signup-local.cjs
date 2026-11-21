// Local unified Astro/Flutter preview. Never connects to a production API.
const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const root = path.resolve(__dirname,'../..');
const web = path.join(root,'website/dist');
const app = path.join(root,'apps/fulltech_app/build/web');
const types = {'.html':'text/html','.js':'application/javascript','.mjs':'application/javascript',
  '.css':'text/css','.json':'application/json','.wasm':'application/wasm','.svg':'image/svg+xml',
  '.png':'image/png','.webp':'image/webp','.woff2':'font/woff2','.ttf':'font/ttf'};
const evidence = path.join(root,'.uat/signup/http-statuses.jsonl');
const server = http.createServer(async (req,res) => {
  const url = new URL(req.url,'http://127.0.0.1:4490');
  if (url.pathname.startsWith('/api/')) {
    const upstream = http.request({hostname:'127.0.0.1',port:4005,
      path:url.pathname.slice(4)+url.search,method:req.method,headers:{...req.headers,host:'127.0.0.1:4005'}},reply=>{
      fs.appendFile(evidence,JSON.stringify({method:req.method,path:url.pathname,status:reply.statusCode})+'\n').catch(()=>{});
      res.writeHead(reply.statusCode,reply.headers);reply.pipe(res);
    });
    upstream.on('error',()=>{res.writeHead(502);res.end('Local API unavailable');});req.pipe(upstream);return;
  }
  try {
    const pathname = decodeURIComponent(url.pathname);
    const candidates = pathname === '/' ? [[web,'index.html']] :
      pathname === '/pos.html' ? [[app,'index.html']] :
      [[web,pathname],[web,path.join(pathname,'index.html')],[app,pathname]];
    if (!path.extname(pathname)) candidates.push([app,'index.html']);
    for (const [base,relative] of candidates) {
      const file=path.resolve(base,'.'+path.sep+relative.replace(/^[/\\]+/,''));
      if (!file.startsWith(base+path.sep)) continue;
      const stat=await fs.stat(file).catch(()=>null);if(!stat?.isFile())continue;
      res.writeHead(200,{'content-type':types[path.extname(file)]||'application/octet-stream',
        'cache-control':'no-store','referrer-policy':'no-referrer'});
      res.end(await fs.readFile(file));return;
    }
    res.writeHead(404);res.end('Not found');
  } catch (_) {res.writeHead(400);res.end('Invalid local request');}
});
server.listen(4490,'127.0.0.1',()=>console.log('Local signup preview: http://127.0.0.1:4490/registro'));
