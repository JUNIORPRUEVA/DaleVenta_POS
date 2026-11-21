/* Content checks against the published quotation procedure, separate from HTTP success. */
const fs = require('node:fs');
const path = require('node:path');
const [input, directory] = process.argv.slice(2);
if (!input || !directory) throw new Error('Usage: node audit-ai-live-results.cjs <local-results.json> <report-directory>');
const data = JSON.parse(fs.readFileSync(input, 'utf8'));
const results = data.results.map(row => {
  const text = row.reply.toLowerCase();
  const quotation = ['open_quote', 'followup_context'].includes(row.case);
  const qualityChecks = quotation ? {
    noInventedButtonOrCustomerLabel: !/consumidor f[ií]sico|\*\*(?:convertir en venta|finalizar)\*\*/i.test(row.reply),
    ...(row.case === 'open_quote'
      ? { publishedQuotationActions: text.includes('cotizar') && text.includes('pasar a ticket') && text.includes('cobrar y facturar') }
      : { optionalEmailExplained: /no necesitas|sin correo|no es necesario|opcional/.test(text), noInventedEmailRequirement: row.checks.doesNotInventRequiredEmail === true }),
  } : { scenarioChecks: row.passed };
  return { ...row, transportAndScenarioChecksPassed: row.passed, qualityChecks,
    approved: row.passed && Object.values(qualityChecks).every(Boolean) };
});
const report = { productionConnected: false, source: `Real local FullPOS -> APPYRA -> PostgreSQL; model: ${data.modelAvailable ?? 'not declared'}; curated replies identified per turn`,
  quotationReference: 'APPYRA apps/api/content/fullpos-support/knowledge/17-cotizaciones.md',
  technicalPassed: results.filter(row => row.transportAndScenarioChecksPassed).length,
  qualityApproved: results.filter(row => row.approved).length, total: results.length,
  limits: ['Keyword checks are not a complete semantic validator.', 'Requires manual review of generated content.', 'No production environment was evaluated.'], results };
fs.mkdirSync(directory, { recursive: true });
fs.writeFileSync(path.join(directory, 'conversaciones-reales.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({technicalPassed: report.technicalPassed,qualityApproved:report.qualityApproved,total:report.total,status:report.qualityApproved===report.total?'PASS':'FAIL'}));
if (report.qualityApproved !== report.total) process.exitCode = 1;
