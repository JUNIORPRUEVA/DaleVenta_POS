// Isolated HTTP fixture of the actual baseline DTO/pipe, not an old full API.
require('reflect-metadata');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const ts = require('typescript');
const { ValidationPipe } = require('@nestjs/common');

async function main() {
  const requested = process.argv[2] || '6b3e38ed';
  assert.ok(['6b3e38ed', '69dd871b', '5278477e', '07664153'].includes(requested));
  const revision = spawnSync('git', ['rev-parse', requested], { encoding: 'utf8' }).stdout.trim();
  assert.ok(revision.startsWith(requested));
  function snapshot(path) {
    const result = spawnSync('git', ['show', `${revision}:${path}`], { encoding: 'utf8' });
    assert.equal(result.status, 0);
    return result.stdout;
  }
  const pubspec = snapshot('apps/fulltech_app/pubspec.yaml');
  const salesClient = snapshot('apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart');
  const main = snapshot('apps/api/src/main.ts');
  for (const flag of ['whitelist', 'forbidNonWhitelisted', 'transform']) assert.match(main, new RegExp(flag + ':\\s*true'));
  const source = { status: 0, stdout: snapshot('apps/api/src/products/dto/adjust-product-stock.dto.ts') };
  assert.equal(source.status, 0);
  const compiled = ts.transpileModule(source.stdout, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
    experimentalDecorators: true, emitDecoratorMetadata: true,
  } }).outputText;
  const fixture = {};
  new Function('exports', 'require', compiled)(fixture, require);
  const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });
  const server = http.createServer(async (request, response) => {
    response.setHeader('content-type', 'application/json');
    if (request.method !== 'PATCH' || request.url !== '/products/uat-product/stock') {
      response.writeHead(404).end(JSON.stringify({ fixtureOnly: true })); return;
    }
    try {
      let raw = '';
      for await (const part of request) { raw += part; if (raw.length > 4096) throw new Error('Fixture payload too large'); }
      const dto = await pipe.transform(JSON.parse(raw), { type: 'body', metatype: fixture.AdjustProductStockDto });
      response.writeHead(200).end(JSON.stringify({ fixtureOnly: true, dto }));
    } catch (error) {
      response.writeHead(400).end(JSON.stringify(error.getResponse?.() || { message: 'Invalid fixture request' }));
    }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(46553, '127.0.0.1', resolve); });
  try {
    const cases = [];
    for (const payload of [{ delta: '20', reason: 'UAT legacy' },
      { delta: 20, reason: 'UAT advanced', operationId: 'c552deab-5468-430b-bace-e4a3982ebdd8' }]) {
      const response = await fetch('http://127.0.0.1:46553/products/uat-product/stock', {
        method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload),
        signal: AbortSignal.timeout(5000),
      });
      cases.push({ method: 'PATCH', path: '/products/uat-product/stock', payload, status: response.status, response: await response.json() });
    }
    assert.equal(cases[0].status, 200);
    assert.equal(cases[0].response.dto.delta, 20);
    assert.equal(cases[1].status, 400);
    assert.ok(cases[1].response.message.includes('property operationId should not exist'));
    const result = { status: 'PASS', revision, declaredClientVersion: pubspec.match(/^version:\s*(.+)$/m)[1].trim(),
      legacySalesSource: { clientRequestId: salesClient.includes("'clientRequestId': clientRequestId"),
        originCashSessionId: salesClient.includes("'originCashSessionId': originCashSessionId"),
        sha256: createHash('sha256').update(salesClient).digest('hex') },
      dtoSha256: createHash('sha256').update(source.stdout).digest('hex'),
      pipe: { whitelist: true, forbidNonWhitelisted: true, transform: true }, cases,
      scope: 'Real HTTP + baseline DTO snapshot; no DB mutation or full legacy API/client execution' };
    fs.writeFileSync(`.uat/evidence/phase13-baseline-http-contract-${requested}.json`, JSON.stringify(result, null, 2));
    if (requested === '6b3e38ed') fs.writeFileSync('.uat/evidence/phase13-baseline-http-contract.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await new Promise(resolve => server.close(resolve)); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
