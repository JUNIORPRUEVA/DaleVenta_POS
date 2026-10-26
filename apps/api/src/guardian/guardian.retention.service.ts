import { Injectable, Logger } from '@nestjs/common';
import { GuardianIncidentStatus, GuardianSeverity, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const DEFAULT_RETENTION_DAYS = 90;
const DEFAULT_CRITICAL_DAYS = 365;
const DEFAULT_MAX_PER_COMPANY = 5_000;
const DEFAULT_BATCH_SIZE = 500;
const DEFAULT_MAX_BATCHES = 20;

function readInt(raw: string | undefined, fallback: number, min: number): number {
  const parsed = Number.parseInt(String(raw ?? '').trim(), 10);
  return Number.isFinite(parsed) && parsed >= min ? parsed : fallback;
}

export type GuardianRetentionResult = {
  dryRun: boolean;
  retentionDays: number;
  criticalDays: number;
  expiredIncidents: number;
  overLimitIncidents: number;
  purgedAccessLogs: number;
  keptForInvestigation: number;
  /** Lotes de borrado ejecutados en esta corrida. */
  batches: number;
  /** Incidentes borrados por lotes acotados. */
  deletedInBatches: number;
};

/**
 * Retención y purga controlada.
 *
 * Reglas de seguridad:
 * - Nunca toca incidentes abiertos, reconocidos ni en investigación.
 * - Nunca toca SEV1/SEV2 antes del plazo crítico (por defecto 365 días).
 * - Nunca toca un incidente con alerta pendiente/en envío (entrega sin confirmar).
 * - `dryRun` es el modo por defecto: sin `GUARDIAN_RETENTION_APPLY=true` solo cuenta.
 */
@Injectable()
export class GuardianRetentionService {
  private readonly logger = new Logger(GuardianRetentionService.name);

  constructor(private readonly prisma: PrismaService) {}

  private get retentionDays() {
    return readInt(process.env.GUARDIAN_RETENTION_DAYS, DEFAULT_RETENTION_DAYS, 7);
  }

  private get criticalDays() {
    return readInt(process.env.GUARDIAN_RETENTION_CRITICAL_DAYS, DEFAULT_CRITICAL_DAYS, 30);
  }

  private get maxPerCompany() {
    return readInt(process.env.GUARDIAN_RETENTION_MAX_PER_COMPANY, DEFAULT_MAX_PER_COMPANY, 100);
  }

  private get apply() {
    return String(process.env.GUARDIAN_RETENTION_APPLY ?? '').trim().toLowerCase() === 'true';
  }

  /** Tamano de lote: acota la duracion de cada transaccion de borrado. */
  private get batchSize() {
    return readInt(process.env.GUARDIAN_RETENTION_BATCH_SIZE, DEFAULT_BATCH_SIZE, 1);
  }

  /** Maximo de lotes por ejecucion (cada ejecucion es corta y repetible). */
  private get maxBatches() {
    return readInt(process.env.GUARDIAN_RETENTION_MAX_BATCHES, DEFAULT_MAX_BATCHES, 1);
  }

  /**
   * Borra en lotes pequenos en lugar de una sola sentencia masiva: mantiene
   * cortas las transacciones (menos bloqueos) y es reanudable, porque la
   * seleccion se recalcula con el mismo predicado en cada lote. Si el proceso se
   * interrumpe, la siguiente ejecucion continua donde quedo sin duplicar trabajo.
   */
  private async deleteInBatches(
    where: Prisma.GuardianIncidentWhereInput,
    counters: { batches: number; deleted: number },
  ): Promise<void> {
    for (let batch = 0; batch < this.maxBatches; batch++) {
      const rows = await this.prisma.guardianIncident.findMany({
        where,
        orderBy: { occurredAt: 'asc' },
        take: this.batchSize,
        select: { id: true },
      });
      if (rows.length === 0) return;
      const result = await this.prisma.guardianIncident.deleteMany({
        where: { id: { in: rows.map((row) => row.id) } },
      });
      counters.batches += 1;
      counters.deleted += result.count;
      if (rows.length < this.batchSize) return;
    }
  }

  /** Métricas de almacenamiento por tabla (para panel y watchdog). */
  async metrics() {
    const rows = await this.prisma.$queryRawUnsafe<Array<{ table_name: string; bytes: string; filas: string }>>(`
      SELECT c.relname AS table_name,
             pg_total_relation_size(c.oid)::text AS bytes,
             (SELECT COALESCE(n_live_tup, 0) FROM pg_stat_user_tables t WHERE t.relid = c.oid)::text AS filas
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname LIKE 'guardian%'
      ORDER BY pg_total_relation_size(c.oid) DESC
    `);

    const byTable = rows.map((row) => ({
      table: row.table_name,
      bytes: Number(row.bytes),
      rows: Number(row.filas),
    }));

    return {
      byTable,
      totalBytes: byTable.reduce((sum, item) => sum + item.bytes, 0),
      totalRows: byTable.reduce((sum, item) => sum + item.rows, 0),
    };
  }

  async run(options: { dryRun?: boolean } = {}): Promise<GuardianRetentionResult> {
    const dryRun = options.dryRun ?? !this.apply;
    const now = Date.now();
    const cutoff = new Date(now - this.retentionDays * 24 * 60 * 60 * 1000);
    const criticalCutoff = new Date(now - this.criticalDays * 24 * 60 * 60 * 1000);

    const closableStatuses = [
      GuardianIncidentStatus.RESOLVED,
      GuardianIncidentStatus.CLOSED,
      GuardianIncidentStatus.WONT_FIX,
    ];

    const expiredWhere: Prisma.GuardianIncidentWhereInput = {
      status: { in: closableStatuses },
      alerts: { none: { state: { in: ['PENDING', 'SENDING'] } } },
      OR: [
        {
          severity: { in: [GuardianSeverity.SEV3, GuardianSeverity.SEV4] },
          occurredAt: { lt: cutoff },
        },
        {
          severity: { in: [GuardianSeverity.SEV1, GuardianSeverity.SEV2] },
          occurredAt: { lt: criticalCutoff },
        },
      ],
    };

    const expiredIncidents = await this.prisma.guardianIncident.count({ where: expiredWhere });
    const keptForInvestigation = await this.prisma.guardianIncident.count({
      where: {
        status: { in: [GuardianIncidentStatus.OPEN, GuardianIncidentStatus.ACKNOWLEDGED, GuardianIncidentStatus.INVESTIGATING] },
        occurredAt: { lt: cutoff },
      },
    });

    let overLimitIncidents = 0;
    const companies = await this.prisma.guardianIncident.groupBy({
      by: ['companyId'],
      _count: { _all: true },
    });

    for (const company of companies) {
      const overflow = company._count._all - this.maxPerCompany;
      if (overflow <= 0) continue;

      const candidates = await this.prisma.guardianIncident.findMany({
        where: {
          companyId: company.companyId,
          status: { in: closableStatuses },
          severity: { in: [GuardianSeverity.SEV3, GuardianSeverity.SEV4] },
          alerts: { none: { state: { in: ['PENDING', 'SENDING'] } } },
        },
        orderBy: { occurredAt: 'asc' },
        take: overflow,
        select: { id: true },
      });

      overLimitIncidents += candidates.length;

      if (!dryRun && candidates.length) {
        await this.prisma.guardianIncident.deleteMany({
          where: { id: { in: candidates.map((row) => row.id) } },
        });
      }
    }

    let purgedAccessLogs = 0;
    const batches = { batches: 0, deleted: 0 };
    if (!dryRun) {
      if (expiredIncidents > 0) {
        await this.deleteInBatches(expiredWhere, batches);
      }
      const logCutoff = new Date(now - this.criticalDays * 24 * 60 * 60 * 1000);
      const purged = await this.prisma.guardianAccessLog.deleteMany({
        where: { createdAt: { lt: logCutoff } },
      });
      purgedAccessLogs = purged.count;
    }

    const result: GuardianRetentionResult = {
      dryRun,
      retentionDays: this.retentionDays,
      criticalDays: this.criticalDays,
      expiredIncidents,
      overLimitIncidents,
      purgedAccessLogs,
      keptForInvestigation,
      batches: batches.batches,
      deletedInBatches: batches.deleted,
    };

    this.logger.log(`Retención Guardian ${dryRun ? '(dry-run)' : '(aplicada)'}: ${JSON.stringify(result)}`);
    return result;
  }
}
