// Offline generation from hash-pinned public DOM snapshots. No API or credentials.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const sources = [
  ['E31', 'createinvoicefiscals', '/fiscal-invoices', '8E665554B8EFC8F41189449E64327F5888F44B05625E48B90BD09F6B8EAE3459'],
  ['E32', 'createinvoices', '/invoices', '483A7220F503AF4FAEEE1D42CF2124449CF8524105F94172D633099CEAF836DF'],
  ['E34', 'createcreditnotes', '/credit-notes', '7B118AC204B241B79E5F4EAF7D2445C094933B6A979D83BDBB56AB53B18698E0'],
];
const annotations = new Set(['description', 'example', 'examples', 'title', 'default', 'xml', 'externalDocs']);
const contracts = {};
const matrix = ['# Matriz contractual Alanube DOM — fases 71–74', '',
  'Generado por prepare-alanube-contracts.cjs desde snapshots públicos verificados.',
  'Consulta 2026-10-14; comparación con HTML oficial actual: sin diferencias.',
  'OpenAPI 3.0.3, API FE DOM 1.0.0. No contratos de otros países.', '',
  'Obligatorio significa required en su objeto; si el padre es opcional solo aplica al incluirlo.',
  'Condicional se identifica desde la descripción oficial y requiere revisión semántica adicional.',
  'Soportado indica el subconjunto del mapper; los demás campos se omiten, no se inventan.',
  'Los límites maxLength sobre números se conservan, pero JSON Schema solo los aplica a strings.', ''];
const supported = new Set([
  'company', 'company.id',
  'idDoc', 'idDoc.encf', 'idDoc.sequenceDueDate', 'idDoc.incomeType', 'idDoc.paymentType',
  'idDoc.creditNoteIndicator', 'idDoc.paymentDeadline', 'sender', 'sender.rnc', 'sender.companyName', 'sender.tradename',
  'sender.address', 'sender.stampDate', 'sender.mail', 'buyer', 'buyer.rnc', 'buyer.companyName',
  'buyer.address', 'buyer.mail', 'totals', 'totals.totalAmount', 'totals.totalTaxedAmount',
  'totals.i1AmountTaxed', 'totals.i2AmountTaxed', 'totals.i3AmountTaxed', 'totals.itbisS1',
  'totals.itbisS2', 'totals.itbisS3', 'totals.itbisTotal', 'totals.itbis1Total', 'totals.itbis2Total',
  'totals.itbis3Total', 'totals.exemptAmount', 'itemDetails', 'itemDetails[].lineNumber',
  'itemDetails[].billingIndicator', 'itemDetails[].itemName', 'itemDetails[].goodServiceIndicator',
  'itemDetails[].itemDescription', 'itemDetails[].quantityItem', 'itemDetails[].unitPriceItem',
  'itemDetails[].discountAmount', 'itemDetails[].subDiscounts',
  'itemDetails[].subDiscounts[].subDiscountAmount', 'itemDetails[].subDiscounts[].subDiscountRate', 'itemDetails[].itemAmount',
  'informationReference', 'informationReference.ncfModified', 'informationReference.ncfModifiedDate',
  'informationReference.modificationCode', 'informationReference.reasonForModification',
]);
for (const [type, slug, endpoint, hash] of sources) {
  const bytes = fs.readFileSync(path.join(root, 'artifacts/alanube-public-contracts', `${slug}.openapi.json`));
  if (createHash('sha256').update(bytes).digest('hex').toUpperCase() !== hash) throw Error(`Snapshot integrity mismatch: ${type}`);
  const document = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
  if (document.openapi !== '3.0.3' || document.info.title !== 'API FE DOM' || !document.paths[endpoint]?.post) throw Error('Wrong DOM contract');
  function resolve(node, ancestors = []) {
    if (Array.isArray(node)) return node.map((x) => resolve(x, ancestors));
    if (!node || typeof node !== 'object') return node;
    if (node.$ref) {
      if (!node.$ref.startsWith('#/') || ancestors.includes(node.$ref)) throw Error('Unresolved/cyclic contract reference');
      let target = document;
      for (const key of node.$ref.slice(2).split('/')) target = target[key.replace(/~1/g, '/').replace(/~0/g, '~')];
      if (!target) throw Error('Missing contract reference');
      return resolve(target, [...ancestors, node.$ref]);
    }
    return Object.fromEntries(Object.entries(node).map(([k, v]) => [k, resolve(v, ancestors)]));
  }
  function constraints(node) {
    if (Array.isArray(node)) return node.map(constraints);
    if (!node || typeof node !== 'object') return node;
    return Object.fromEntries(Object.entries(node).filter(([k]) => !annotations.has(k)).map(([k, v]) => [k, constraints(v)]));
  }
  const operation = document.paths[endpoint].post;
  const request = resolve(operation.requestBody.content['application/json'].schema);
  const responses = {};
  for (const [status, value] of Object.entries(operation.responses)) {
    const response = resolve(value);
    if (response.content?.['application/json']?.schema) responses[status] = constraints(response.content['application/json'].schema);
  }
  const source = `https://developer.alanube.co/reference/${slug}`;
  const schemas = { request: constraints(request), responses };
  contracts[type] = { source, sourceSha256: hash, consultedOn: '2026-10-14', country: 'DOM',
    openapi: document.openapi, version: document.info.version, endpoint,
    schemaSha256: createHash('sha256').update(JSON.stringify(schemas)).digest('hex'), ...schemas };
  matrix.push(`## ${type}`, '', `[Fuente oficial](${source}); SHA-256 original: ${hash}.`, '',
    `POST ${endpoint}; respuestas documentadas: ${Object.keys(responses).join(', ')}.`, '',
    '| Campo | Tipo | Regla oficial | Mapper |', '| --- | --- | --- | --- |');
  function fields(node, prefix = '') {
    for (const [name, value] of Object.entries(node.properties ?? {})) {
      const field = prefix ? `${prefix}.${name}` : name;
      const rule = node.required?.includes(name) ? 'OBLIGATORIO' : /condicional/i.test(value.description ?? '') ? 'CONDICIONAL' : 'OPCIONAL';
      matrix.push(`| ${field} | ${value.type ?? 'DESCONOCIDO'} | ${rule} | ${supported.has(field) ? 'SOPORTADO' : 'NO_SOPORTADO'} |`);
      if (value.type === 'object') fields(value, field);
      if (value.type === 'array') fields(value.items ?? {}, `${field}[]`);
    }
  }
  fields(request);
  matrix.push('');
}
matrix.push('## Integridad local E34 — fases 81–90', '',
  'La relación fiscal no equivale a un ID interno ni al identificador del proveedor.',
  'El servicio interno verifica tenant, original E31/E32 DGII_ACCEPTED con snapshot y log de evidencia coincidente, e-NCF/fecha/moneda y saldo.',
  'PostgreSQL protege relaciones compuestas por empresa, unicidad de e-NCF y reservas monetarias con historial inmutable.',
  'RESERVED y UNKNOWN_RESULT retienen saldo; APPLIED solo con evidencia coincidente. DRAFT no es crédito aplicado.',
  'Estas son garantías locales conservadoras: las pruebas usan evidencia sintética y no acreditan aceptación DGII.',
  'Campos/reglas DGII no confirmados, ingestión de evidencia y orquestación del sender siguen pendientes; toda emisión E34 permanece bloqueada.', '');
const output = path.join(root, 'apps/api/src/ecf/alanube/contracts/alanube-dom-schemas.generated.ts');
fs.mkdirSync(path.dirname(output), { recursive: true });
const generatedCode = '// Generated from verified public DOM OpenAPI snapshots; do not hand-edit.\n' +
  'export const ALANUBE_DOM_SCHEMAS: Record<string, { source: string; sourceSha256: string; consultedOn: string; country: string; openapi: string; version: string; endpoint: string; schemaSha256: string; request: Record<string, unknown>; responses: Record<string, Record<string, unknown>> }> = ' + JSON.stringify(contracts, null, 2) + ';\n';
const matrixPath = path.join(root, 'docs/ECF_ALANUBE_CONTRACT_MATRIX_PHASES_71_74.md');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8') !== generatedCode || fs.readFileSync(matrixPath, 'utf8') !== matrix.join('\n') + '\n') throw Error('Contract generation drift detected');
  console.log('Pinned schema hashes and generated sources MATCH; no writes or network calls.');
} else {
  fs.writeFileSync(output, generatedCode);
  fs.writeFileSync(matrixPath, matrix.join('\n') + '\n');
  console.log('Generated pinned E31/E32/E34 schemas and field matrix; no network calls.');
}
