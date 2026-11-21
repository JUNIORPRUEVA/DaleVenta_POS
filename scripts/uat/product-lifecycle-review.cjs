const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'../..'),file=path.join(root,'.uat/product-lifecycle/source-manifest.json');
// HEAD differences include staged additions too: git add must not change the
// reviewed file set. Failure screenshots are artifacts, not source or tests.
const gitLines=args=>execFileSync('git',args,{cwd:root,encoding:'utf8'}).trim().split('\n');
const names=[...new Set([...gitLines(['diff','--name-only','HEAD']),...gitLines(['ls-files','-o','--exclude-standard'])])]
 .filter(n=>/^(apps\/api\/(src|prisma)|apps\/fulltech_app\/(lib|test|integration_test)|scripts\/uat)\//.test(n)&&!n.includes('/test/features/products/failures/')).sort();
const current=Object.fromEntries(names.map(n=>[n,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,n))).digest('hex')]));
if(process.argv.includes('--verify')){
 if(JSON.stringify(current)!==fs.readFileSync(file,'utf8'))throw Error('Source changed since review snapshot');
 console.log(`PASS: ${names.length} source/test files unchanged since review.`);
}else{fs.writeFileSync(file,JSON.stringify(current));console.log(`Captured ${names.length} source/test hashes.`);}
