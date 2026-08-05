import * as fs from 'node:fs';
import * as path from 'node:path';

type ModelInventory = {
  modelName: string;
  tableName: string;
  primaryKey: string | null;
  tenantColumn: string | null;
  tenantNullable: boolean | null;
  tenantForeignKey: 'present' | 'missing' | 'not_applicable';
  tenantIndex: 'present' | 'missing' | 'not_applicable';
  parentOwnershipRelationship: string | null;
  uniqueConstraints: string[];
  indexes: string[];
  deleteBehavior: string[];
  storageDependencies: string[];
  recommendedMigrationAction: string;
  classification: string;
};

const root = path.resolve(__dirname, '..');
const schemaPath = path.join(root, 'prisma', 'schema.prisma');
const docsDir = path.join(root, 'docs');
const schema = fs.readFileSync(schemaPath, 'utf8');

function mapName(block: string, fallback: string) {
  const match = block.match(/@@map\("([^"]+)"\)/);
  return match?.[1] ?? fallback;
}

function physicalColumn(fieldLine: string, fallback: string) {
  const match = fieldLine.match(/@map\("([^"]+)"\)/);
  return match?.[1] ?? fallback;
}

function classify(modelName: string, block: string, tableName: string) {
  if (modelName === 'Company') return 'Global platform data';
  if (modelName === 'CompanyMember') return 'Join table';
  if (modelName === 'AuthSession') return 'Session/security data';
  if (modelName === 'User' || modelName.includes('WhatsappInstance') || modelName === 'UserLocation') {
    return 'User-personal data';
  }
  if (/Audit|ActivityLog|History|Outbox|Job|Memory|Conversation|Message/i.test(modelName)) {
    return 'Audit/retention data';
  }
  if (/\bcompanyId\b/.test(block)) return 'Company-owned root entity';
  if (/(saleId|serviceId|serviceOrderId|purchaseOrderId|cotizacionId|warningId|closeId|transferId|periodId|employeeId|templateId|conversationId)/.test(block)) {
    return 'Company-owned child entity';
  }
  if (/Category|Phase|Template|PrecioCombustible/.test(modelName)) return 'Global platform data';
  return tableName.includes('_') ? 'Company-owned child entity' : 'Global platform data';
}

const models: ModelInventory[] = [];
for (const match of schema.matchAll(/model\s+(\w+)\s+\{([\s\S]*?)\n\}/g)) {
  const modelName = match[1];
  const block = match[2];
  const tableName = mapName(block, modelName);
  const lines = block.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const idLine = lines.find((line) => line.includes('@id') && !line.startsWith('@@'));
  const companyLine = lines.find((line) => /^companyId\s+/.test(line));
  const tenantColumn = companyLine ? physicalColumn(companyLine, 'companyId') : null;
  const tenantNullable = companyLine ? /\?/.test(companyLine.split(/\s+/)[1] ?? '') : null;
  const hasCompanyRelation = /\bcompany\s+Company\??\s+@relation/.test(block);
  const uniqueConstraints = lines.filter((line) => line.startsWith('@@unique') || line.includes('@unique'));
  const indexes = lines.filter((line) => line.startsWith('@@index'));
  const deleteBehavior = [...block.matchAll(/onDelete:\s*(\w+)/g)].map((m) => m[1]);
  const relationFields = lines
    .filter((line) => line.includes('@relation') && !/^company\s+/.test(line))
    .map((line) => line.split(/\s+/)[0])
    .slice(0, 6);
  const storageDependencies = lines
    .filter((line) => /Url|objectKey|fileUrl|imageKey|storage/i.test(line))
    .map((line) => line.split(/\s+/)[0]);
  const classification = classify(modelName, block, tableName);
  const tenantIndex = tenantColumn
    ? indexes.some((line) => line.includes('[companyId') || line.includes('[companyId,'))
      ? 'present'
      : 'missing'
    : 'not_applicable';
  const tenantForeignKey = tenantColumn
    ? hasCompanyRelation
      ? 'present'
      : 'missing'
    : 'not_applicable';

  let recommendedMigrationAction = 'No tenant migration required.';
  if (classification.startsWith('Company-owned') && !tenantColumn) {
    recommendedMigrationAction = 'Add companyId through trusted parent backfill or document inherited parent ownership.';
  } else if (classification === 'Company-owned root entity' && tenantNullable) {
    recommendedMigrationAction = 'Backfill deterministically, add FK/index, then make companyId NOT NULL.';
  } else if (tenantColumn && tenantForeignKey === 'missing') {
    recommendedMigrationAction = 'Add Company foreign key after ownership audit passes.';
  } else if (tenantColumn && tenantIndex === 'missing') {
    recommendedMigrationAction = 'Add companyId-leading index.';
  }

  models.push({
    modelName,
    tableName,
    primaryKey: idLine ? idLine.split(/\s+/)[0] : null,
    tenantColumn,
    tenantNullable,
    tenantForeignKey,
    tenantIndex,
    parentOwnershipRelationship: relationFields.length ? relationFields.join(', ') : null,
    uniqueConstraints,
    indexes,
    deleteBehavior,
    storageDependencies,
    recommendedMigrationAction,
    classification,
  });
}

fs.mkdirSync(docsDir, { recursive: true });
fs.writeFileSync(
  path.join(docsDir, 'tenant-data-model-inventory.json'),
  JSON.stringify({ generatedAt: new Date().toISOString(), models }, null, 2),
);

const md = [
  '# Tenant Data Model Inventory',
  '',
  `Generated at: ${new Date().toISOString()}`,
  '',
  '| Model | Table | Classification | Tenant Column | Nullable | FK | Index | Recommended Action |',
  '| --- | --- | --- | --- | --- | --- | --- | --- |',
  ...models.map((item) =>
    `| ${item.modelName} | ${item.tableName} | ${item.classification} | ${item.tenantColumn ?? '-'} | ${item.tenantNullable ?? '-'} | ${item.tenantForeignKey} | ${item.tenantIndex} | ${item.recommendedMigrationAction.replace(/\|/g, '/')} |`,
  ),
  '',
  '## Notes',
  '',
  '- This inventory is generated from Prisma schema text.',
  '- Company-owned root entities with nullable companyId require database audit and deterministic backfill before NOT NULL enforcement.',
  '- Child entities without direct companyId must be protected through required parent ownership or migrated to direct ownership where high-risk.',
  '',
].join('\n');

fs.writeFileSync(path.join(docsDir, 'TENANT_DATA_MODEL_INVENTORY.md'), md);
console.log(`Wrote ${models.length} model inventory rows to apps/api/docs`);
