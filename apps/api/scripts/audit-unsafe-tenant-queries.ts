import * as fs from 'node:fs';
import * as path from 'node:path';

type Finding = {
  file: string;
  line: number;
  severity: 'error' | 'warning';
  pattern: string;
  text: string;
};

const root = path.resolve(__dirname, '..');
const srcDir = path.join(root, 'src');
const warnOnly = process.argv.includes('--warn-only');
const allowlist = new Set([
  'auth/auth.service.ts',
  'auth/jwt.strategy.ts',
  'health/health.controller.ts',
]);

function walk(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(full);
    return entry.isFile() && full.endsWith('.ts') ? [full] : [];
  });
}

const findings: Finding[] = [];
for (const file of walk(srcDir)) {
  const rel = path.relative(srcDir, file).replace(/\\/g, '/');
  if (allowlist.has(rel)) continue;
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, index) => {
    const text = line.trim();
    if (!text || text.startsWith('//')) return;
    const prismaQuery = text.match(/\.([a-zA-Z0-9_]+)\.(findUnique|update|delete|findMany|count|aggregate)\s*\(/);
    if (!prismaQuery) return;
    const method = prismaQuery[2];
    const hasCompanyIdSameLine = text.includes('companyId') || text.includes('requireTenant');
    const likelyIdOnly = /where:\s*\{\s*id\s*[,}]/.test(text) || /where:\s*\{\s*id:/.test(text);
    if ((method === 'findUnique' || method === 'update' || method === 'delete') && likelyIdOnly && !hasCompanyIdSameLine) {
      findings.push({ file: rel, line: index + 1, severity: 'error', pattern: `${method} id-only`, text });
    } else if ((method === 'findMany' || method === 'count' || method === 'aggregate') && !hasCompanyIdSameLine) {
      findings.push({ file: rel, line: index + 1, severity: 'warning', pattern: `${method} possibly unscoped`, text });
    }
  });
}

const docsDir = path.join(root, 'docs');
fs.mkdirSync(docsDir, { recursive: true });
fs.writeFileSync(path.join(docsDir, 'unsafe-tenant-query-audit.json'), JSON.stringify({ generatedAt: new Date().toISOString(), findings }, null, 2));

const errors = findings.filter((finding) => finding.severity === 'error');
const warnings = findings.filter((finding) => finding.severity === 'warning');
const markdown = [
  '# Unsafe Tenant Query Audit',
  '',
  `Generated at: ${new Date().toISOString()}`,
  '',
  `Errors: ${errors.length}`,
  `Warnings: ${warnings.length}`,
  '',
  '| Severity | File | Line | Pattern | Query |',
  '| --- | --- | --- | --- | --- |',
  ...findings.map((finding) => `| ${finding.severity} | ${finding.file} | ${finding.line} | ${finding.pattern} | \`${finding.text.replaceAll('|', '\\|')}\` |`),
  '',
].join('\n');
fs.writeFileSync(path.join(docsDir, 'UNSAFE_TENANT_QUERY_AUDIT.md'), markdown);

if (findings.length) {
  for (const finding of findings) {
    console.error(`${finding.severity.toUpperCase()} ${finding.file}:${finding.line} ${finding.pattern} ${finding.text}`);
  }
}

if (errors.length && !warnOnly) {
  console.error(`Unsafe tenant query audit failed with ${errors.length} error(s).`);
  process.exitCode = 2;
} else {
  console.log(`Unsafe tenant query audit completed with ${warnings.length} warning(s), ${errors.length} error(s).`);
}
