/* Read-only classification of an existing Jest JSON result; never runs fixtures. */
const fs = require('node:fs');
const path = require('node:path');
const [input, destination] = process.argv.slice(2);
if (!input || !destination) throw new Error('Usage: node audit-ai-skipped-tests.cjs <jest.json> <report-directory>');
const root = path.resolve(__dirname, '..');
const result = JSON.parse(fs.readFileSync(input, 'utf8'));
const groups = {
  fiscal: { label: 'Fiscal / ventas e-CF', execution: 'Suite PostgreSQL fiscal aislada requerida para release del área; sin ejecución en esta tarea de IA.' },
  licenses: { label: 'Licencias / pagos / actividad', execution: 'Fixtures PostgreSQL dedicadas requeridas para release del área; sin ejecución ni modificación de licencias en esta tarea.' },
  guardian: { label: 'Guardian / diagnóstico', execution: 'PostgreSQL y rol lector dedicados; ejecución pendiente fuera del chat de IA. No confundir Guardian con APPYRA runtime.' },
  notifications: { label: 'Outbox de notificaciones', execution: 'PostgreSQL y transporte simulado; ejecución pendiente. Nunca activar envíos externos para contar estas pruebas.' },
  legacy: { label: 'Importación legacy', execution: 'Ensayo de importación/rollback con SQLite y PostgreSQL desechables; fuera del alcance actual.' },
};
const files = [];
for (const suite of result.testResults) {
  const assertions = suite.assertionResults.filter(test => test.status === 'pending' || test.status === 'todo');
  if (!assertions.length) continue;
  const relative = path.relative(root, suite.name).replaceAll('\\', '/');
  if (relative.startsWith('../')) throw new Error('Result contains a suite outside apps/api');
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const group = relative.includes('/migration/') ? 'legacy' : relative.includes('/guardian/') ? 'guardian' : relative.includes('/notifications/') ? 'notifications' : relative.includes('/license/') ? 'licenses' : 'fiscal';
  const gates = [...new Set([...source.matchAll(/process\.env\.([A-Z][A-Z0-9_]*)/g)].map(match => match[1]))];
  const conditional = /\?\s*describe\s*:\s*describe\.skip/.test(source);
  files.push({ path: relative, group, count: assertions.length, intentionalDefaultOptIn: conditional, gateNames: gates, execution: groups[group].execution, tests: assertions.map(test => ({ name: test.fullName, status: test.status })) });
}
const total = files.reduce((n, file) => n + file.count, 0);
if (total !== result.numPendingTests + (result.numTodoTests || 0)) throw new Error('Pending count mismatch');
const summary = Object.entries(groups).map(([key, group]) => ({ group: key, label: group.label, files: files.filter(file => file.group === key).length, tests: files.filter(file => file.group === key).reduce((n, file) => n + file.count, 0), execution: group.execution }));
const report = { passed: result.numPassedTests, pending: total, completelyPendingSuites: result.numPendingTestSuites, filesWithPendingTests: files.length, aiPending: files.filter(file => file.path.includes('/ai-assistant/')).reduce((n, file) => n + file.count, 0), allDefaultSkipsAreConditional: files.every(file => file.intentionalDefaultOptIn), summary, files };
fs.mkdirSync(destination, { recursive: true });
fs.writeFileSync(path.join(destination, 'pruebas-omitidas.json'), JSON.stringify(report, null, 2) + '\n');
const table = files.map(file => `| \`${file.path}\` | ${file.count} | ${file.intentionalDefaultOptIn ? 'Opt-in intencional' : 'REVISAR'} | ${file.gateNames.filter(name => /UAT|FIXTURE|LEGACY_DB|READER_DATABASE/.test(name)).join(', ')} |`).join('\n');
fs.writeFileSync(path.join(destination, 'pruebas-omitidas.md'), `# Inventario de pruebas omitidas de la auditoría IA\n\nGenerado desde resultados reales de Jest, sin ejecutar ni cambiar fixtures.\n\n${total} pruebas pendientes; ${files.length} archivos contienen pendientes; ${result.numPendingTestSuites} suites completamente omitidas. IA: ${report.aiPending} pendientes.\n\nUna omisión intencional en el comando habitual no equivale a una validación aprobada. Las suites PostgreSQL siguen siendo necesarias cuando se publica su área. Las pruebas e2e excluidas por el comando npm test son adicionales y no están incluidas en las 597.\n\n| Área | Archivos | Pruebas | Ejecución |\n| --- | ---: | ---: | --- |\n${summary.map(row => `| ${row.label} | ${row.files} | ${row.tests} | ${row.execution} |`).join('\n')}\n\n## Detalle por archivo\n\n| Archivo | Omitidas | Clasificación | Variables de activación/requisitos |\n| --- | ---: | --- | --- |\n${table}\n\nEl JSON adjunto enumera cada una de las pruebas y su estado observado. Ninguna omisión se convirtió en PASS.\n`);
console.log(JSON.stringify({ pending: total, files: files.length, aiPending: report.aiPending, conditional: report.allDefaultSkipsAreConditional, summary }));
