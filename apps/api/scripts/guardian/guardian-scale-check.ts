/**
 * Fase E — Prueba a gran escala (1000 empresas).
 *
 * Mide la ruta de agregación de incidentes Guardian (huella -> grupo único,
 * incremento de contador y marca de última aparición) contra PostgreSQL real.
 * NO pasa por HTTP: mide la capa de almacenamiento con las mismas restricciones
 * (fingerprint UNIQUE global y agregación multiempresa), no el pipeline completo.
 *
 * Uso:
 *   GUARDIAN_UAT_DATABASE_URL=postgresql://... npx ts-node --transpile-only \
 *     -P tsconfig.scripts.json scripts/guardian/guardian-scale-check.ts
 *
 * Se niega a ejecutar si la URL no apunta a 127.0.0.1 / localhost.
 */
import { randomUUID } from 'crypto';
import { PrismaClient } from '@prisma/client';
import { buildFingerprint } from '../../src/guardian/guardian.fingerprint';

const COMPANIES = Number(process.env.SCALE_COMPANIES ?? 1000);
const EVENTS_PER_COMPANY = Number(process.env.SCALE_EVENTS_PER_COMPANY ?? 10);
const SIGNATURES = 3;
const RUN_TAG = `scale${Date.now()}`;

function assertLocal(url: string): void {
  let host = '';
  try {
    host = new URL(url).hostname;
  } catch {
    host = '';
  }
  if (host !== '127.0.0.1' && host !== 'localhost') {
    throw new Error(`Negado: la URL no apunta a un host local (${host || 'invalida'}).`);
  }
}

async function main(): Promise<void> {
  const url = process.env.GUARDIAN_UAT_DATABASE_URL;
  if (!url) throw new Error('Falta GUARDIAN_UAT_DATABASE_URL');
  assertLocal(url);

  const prisma = new PrismaClient({ datasources: { db: { url } } });
  const totalEvents = COMPANIES * EVENTS_PER_COMPANY;
  const companyIds = Array.from({ length: COMPANIES }, () => randomUUID());

  console.log(`Escala: ${COMPANIES} empresas x ${EVENTS_PER_COMPANY} eventos = ${totalEvents} eventos`);

  try {
    await prisma.company.createMany({
      data: companyIds.map((id, i) => ({ id, name: `${RUN_TAG}-co-${i}`, slug: `${RUN_TAG}-${i}` })),
      skipDuplicates: true,
    });

    const fingerprints = companyIds.map((companyId) =>
      Array.from({ length: SIGNATURES }, (_, k) =>
        buildFingerprint({
          module: 'pos',
          operation: `scale.${companyId}.${k}`,
          exceptionType: 'ScaleProbeException',
          stack: 'at run (package:app/main.dart:10:5)',
          appVersion: '1.0.0',
        }),
      ),
    );

    const started = Date.now();
    let created = 0;
    let deduped = 0;

    for (let company = 0; company < companyIds.length; company++) {
      const companyId = companyIds[company];
      for (let event = 0; event < EVENTS_PER_COMPANY; event++) {
        const fingerprint = fingerprints[company][event % SIGNATURES];
        const now = new Date();
        const updated = await prisma.guardianIncidentGroup.updateMany({
          where: { fingerprint },
          data: { incidentCount: { increment: 1 }, lastSeenAt: now },
        });
        if (updated.count > 0) {
          deduped++;
          continue;
        }
        await prisma.guardianIncidentGroup.create({
          data: {
            fingerprint,
            module: 'pos',
            operation: `scale.${companyId}`,
            exceptionType: 'ScaleProbeException',
            severity: 'SEV3',
            firstSeenAt: now,
            lastSeenAt: now,
            incidentCount: 1,
            companyCount: 1,
            companies: [companyId],
          },
        });
        created++;
      }
    }

    const elapsedMs = Date.now() - started;
    const expectedGroups = COMPANIES * SIGNATURES;
    const groups = await prisma.guardianIncidentGroup.count({
      where: { operation: { startsWith: 'scale.' } },
    });
    const dupGroups = await prisma.$queryRawUnsafe<Array<{ n: bigint }>>(
      `SELECT COUNT(*)::bigint AS n FROM (
         SELECT fingerprint FROM "guardian_incident_groups"
         WHERE operation LIKE 'scale.%' GROUP BY 1 HAVING COUNT(*) > 1
       ) d`,
    );
    const sum = await prisma.guardianIncidentGroup.aggregate({
      where: { operation: { startsWith: 'scale.' } },
      _sum: { incidentCount: true },
    });

    const report = {
      companies: COMPANIES,
      events: totalEvents,
      elapsedMs,
      eventsPerSecond: Math.round((totalEvents / elapsedMs) * 1000),
      groupsCreated: created,
      deduped,
      groupsInDb: groups,
      expectedGroups,
      duplicateGroups: Number(dupGroups[0]?.n ?? 0),
      occurrencesSum: sum._sum.incidentCount ?? 0,
      expectedOccurrences: totalEvents,
    };
    console.log(JSON.stringify(report, null, 2));

    if (report.duplicateGroups !== 0) throw new Error('Huellas duplicadas detectadas');
    if (groups !== expectedGroups) throw new Error(`Grupos esperados ${expectedGroups}, obtenidos ${groups}`);
    if (report.occurrencesSum !== totalEvents) {
      throw new Error(`Ocurrencias esperadas ${totalEvents}, obtenidas ${report.occurrencesSum}`);
    }

    await prisma.guardianIncidentGroup.deleteMany({ where: { operation: { startsWith: 'scale.' } } });
    await prisma.company.deleteMany({ where: { id: { in: companyIds } } });
    console.log('OK: sin duplicados, contadores exactos, limpieza completada');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
