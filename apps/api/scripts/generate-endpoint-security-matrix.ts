import * as fs from 'node:fs';
import * as path from 'node:path';

type EndpointRow = {
  method: string;
  route: string;
  controller: string;
  authentication: string;
  permissions: string;
  tenantSource: string;
  classification: string;
  idorTestStatus: string;
  relationshipTestStatus: string;
  storageAccessStatus: string;
  verdict: string;
};

const root = path.resolve(__dirname, '..');
const srcDir = path.join(root, 'src');
const docsDir = path.join(root, 'docs');

function walk(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(full);
    return entry.isFile() && entry.name.endsWith('.controller.ts') ? [full] : [];
  });
}

function decoratorArg(line: string, name: string) {
  const match = line.match(new RegExp(`@${name}\\(([^)]*)\\)`));
  if (!match) return '';
  return match[1].replace(/['"`]/g, '').trim();
}

function routeJoin(base: string, child: string) {
  const clean = [base, child].map((part) => part.trim().replace(/^\/+|\/+$/g, '')).filter(Boolean);
  return `/${clean.join('/')}`;
}

const rows: EndpointRow[] = [];
for (const file of walk(srcDir)) {
  const source = fs.readFileSync(file, 'utf8');
  const controller = path.relative(srcDir, file).replace(/\\/g, '/');
  const controllerMatch = source.match(/@Controller\(([^)]*)\)/);
  const baseRoute = controllerMatch ? controllerMatch[1].replace(/['"`]/g, '').trim() : '';
  const classUseGuards = source.slice(0, source.indexOf('export class')).includes('@UseGuards');
  const classRoles = [...source.slice(0, source.indexOf('export class')).matchAll(/@Roles\(([^)]*)\)/g)]
    .map((m) => m[1].replace(/\s+/g, ' ').trim())
    .join('; ');
  const lines = source.split(/\r?\n/);
  let pendingDecorators: string[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('@')) {
      pendingDecorators.push(trimmed);
      const methodMatch = trimmed.match(/^@(Get|Post|Patch|Delete|Put)\(([^)]*)\)/);
      if (!methodMatch) continue;

      const method = methodMatch[1].toUpperCase();
      const childRoute = decoratorArg(trimmed, methodMatch[1]);
      const localDecorators = pendingDecorators.join(' ');
      const requiresAuth = classUseGuards || localDecorators.includes('AuthGuard');
      const roles = [...localDecorators.matchAll(/@Roles\(([^)]*)\)/g)]
        .map((m) => m[1].replace(/\s+/g, ' ').trim())
        .join('; ') || classRoles || '-';
      const route = routeJoin(baseRoute, childRoute);
      const destructive = ['POST', 'PATCH', 'PUT', 'DELETE'].includes(method);
      const storage = /upload|media|object|pdf|image|file|voucher/i.test(route);
      const publicish = !requiresAuth || /public|health|uploads\//i.test(route);
      rows.push({
        method,
        route,
        controller,
        authentication: requiresAuth ? 'AuthGuard or class guard' : 'Public/no guard detected',
        permissions: roles,
        tenantSource: requiresAuth ? 'JWT verified user.companyId / membership' : 'none',
        classification: storage ? 'storage' : destructive ? 'write/destructive' : 'read',
        idorTestStatus: requiresAuth && /:id|Id|object|pdf/i.test(route) ? 'required' : 'not_applicable',
        relationshipTestStatus: destructive ? 'required' : 'not_applicable',
        storageAccessStatus: storage ? 'required' : 'not_applicable',
        verdict: publicish && !/health|public/.test(route)
          ? 'needs explicit public-risk review'
          : requiresAuth
            ? 'reviewed by matrix; automated tests required'
            : 'public endpoint',
      });
      pendingDecorators = [];
    } else if (trimmed.length && !trimmed.startsWith('//')) {
      pendingDecorators = [];
    }
  }
}

fs.mkdirSync(docsDir, { recursive: true });
const md = [
  '# Endpoint Tenant Security Matrix',
  '',
  `Generated at: ${new Date().toISOString()}`,
  '',
  '| Method | Route | Controller | Auth | Permissions | Tenant Source | Class | IDOR | Relationship | Storage | Verdict |',
  '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
  ...rows.map((row) =>
    `| ${row.method} | ${row.route} | ${row.controller} | ${row.authentication} | ${row.permissions.replace(/\|/g, '/')} | ${row.tenantSource} | ${row.classification} | ${row.idorTestStatus} | ${row.relationshipTestStatus} | ${row.storageAccessStatus} | ${row.verdict} |`,
  ),
  '',
].join('\n');
fs.writeFileSync(path.join(docsDir, 'ENDPOINT_TENANT_SECURITY_MATRIX.md'), md);
fs.writeFileSync(path.join(docsDir, 'endpoint-tenant-security-matrix.json'), JSON.stringify({ generatedAt: new Date().toISOString(), endpoints: rows }, null, 2));
console.log(`Wrote ${rows.length} endpoint rows to apps/api/docs`);
