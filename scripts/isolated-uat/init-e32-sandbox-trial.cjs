const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const directory = path.resolve(__dirname,'../../artifacts/e32-first-trial');
fs.mkdirSync(directory,{recursive:true});
const target = path.join(directory,'manifest.json');
const exists=fs.existsSync(target);
const manifest = exists ? JSON.parse(fs.readFileSync(target,'utf8')) : { version:1, mode:'SANDBOX', clientRequestId:randomUUID(), issueDate:new Date().toISOString().slice(0,10),
  sender:{legalName:null,taxId:null,address:null}, metadata:{alanubeCompanyId:null,encf:null,paymentType:1,incomeType:1},
  companyAuthorizationRef:null, numbering:{from:null,to:null,validUntil:null,authorizationRef:null} };
// Preserve identity and explicit choices. Only copy already configured nonsecret
// profile values; never construct an e-NCF from the numeric range.
if (manifest.sender?.taxId == null && /^\d{9,11}$/.test(process.env.ALANUBE_TEST_RNC??'')) manifest.sender.taxId=process.env.ALANUBE_TEST_RNC;
if (manifest.numbering?.validUntil == null && /^\d{4}-\d\d-\d\d$/.test(process.env.ALANUBE_TEST_SEQUENCE_EXPIRES_ON??'')) manifest.numbering.validUntil=process.env.ALANUBE_TEST_SEQUENCE_EXPIRES_ON;
if (manifest.metadata && manifest.metadata.incomeType == null) manifest.metadata.incomeType=1;
fs.writeFileSync(target,JSON.stringify(manifest,null,2),{flag:exists?'w':'wx'});
console.log('Stable first E32 draft preserved/prepared; nonsecret profile copied where available. No e-NCF invented. No network/database calls.');
