const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const sources = [
  ['checkinvoices', '/invoices/{id}', 'F55DB04BD29C0EA53A51219492F8F3A573652137F426A0CBCEBB9BC15EAB4201'],
  ['checkinvoicesbycompany', '/invoices/{id}/idCompany/{idCompany}', '0E783B1977A7545C83058B689186385ED78CC8697F9A036FF3364D6A994941E2'],
];
const dependency = ['checkpurchases', '320ADCB00390315385F64DEF0AF0486E0E18E68C37635DFA2C9739C4576AF426'];
const documents = new Map();
for (const [slug, hash] of [...sources.map(([slug, , hash]) => [slug, hash]), dependency]) {
  const bytes = fs.readFileSync(path.join(root, 'artifacts/alanube-public-contracts', `${slug}.openapi.json`));
  if (createHash('sha256').update(bytes).digest('hex').toUpperCase() !== hash) throw Error('E32_QUERY_SOURCE_HASH_MISMATCH');
  const doc = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
  if (doc.openapi !== '3.0.3' || doc.info.title !== 'API FE DOM') throw Error('E32_QUERY_COUNTRY_INVALID');
  documents.set(slug, doc);
}
const result = {};
for (const [slug, endpoint, hash] of sources) {
  const bytes = fs.readFileSync(path.join(root, 'artifacts/alanube-public-contracts', `${slug}.openapi.json`));
  if (createHash('sha256').update(bytes).digest('hex').toUpperCase() !== hash) throw Error('E32_QUERY_SOURCE_HASH_MISMATCH');
  const doc = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
  const op = doc.paths[endpoint]?.get;
  if (doc.openapi !== '3.0.3' || doc.info.title !== 'API FE DOM' || !op || !op.security?.some(x => x.BearerAuth)) throw Error('E32_QUERY_CONTRACT_INVALID');
  function resolve(value, trail = []) {
    if (Array.isArray(value)) return value.map(x => resolve(x, trail));
    if (!value || typeof value !== 'object') return value;
    if (value.$ref) {
      if (!value.$ref.startsWith('#/') || trail.includes(value.$ref)) throw Error('E32_QUERY_REF_INVALID');
      const keys = decodeURIComponent(value.$ref.slice(2)).split('/').map(key => key.replace(/~1/g, '/').replace(/~0/g, '~'));
      const candidates = [doc, ...documents.values()].map(candidate => keys.reduce((node, key) => node?.[key], candidate)).filter(Boolean);
      const target = candidates[0];
      if (!target) throw Error('E32_QUERY_REF_MISSING');
      return resolve(target, [...trail, value.$ref]);
    }
    return Object.fromEntries(Object.entries(value).filter(([key]) => !['description', 'example', 'examples', 'title', 'default', 'xml', 'externalDocs'].includes(key)).map(([key, node]) => [key, resolve(node, trail)]));
  }
  const responses = {};
  for (const [status, response] of Object.entries(op.responses)) {
    const schema = resolve(response).content?.['application/json']?.schema;
    if (schema) responses[status] = schema;
  }
  result[slug] = { source: `https://developer.alanube.co/reference/${slug}`, sourceSha256: hash, endpoint,
    schemaSha256: createHash('sha256').update(JSON.stringify(responses)).digest('hex'), responses };
}
const output = path.join(root, 'apps/api/src/ecf/alanube/contracts/alanube-e32-query.generated.ts');
const code = '// Generated from hash-pinned official DOM GET schemas. Do not hand-edit.\n' +
  'export const ALANUBE_E32_QUERY: Record<string, { source: string; sourceSha256: string; endpoint: string; schemaSha256: string; responses: Record<string, Record<string, unknown>> }> = ' + JSON.stringify(result, null, 2) + ';\n';
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8') !== code) throw Error('E32_QUERY_GENERATED_DRIFT');
  console.log('E32 GET source hashes and generated schemas MATCH. No network.');
} else { fs.writeFileSync(output, code); console.log('Generated E32 GET schemas. No network.'); }
