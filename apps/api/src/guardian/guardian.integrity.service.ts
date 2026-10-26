import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export type GuardianSeverityName = 'SEV1' | 'SEV2' | 'SEV3';

export type GuardianFinding = {
  checkCode: string;
  severity: GuardianSeverityName;
  title: string;
  description: string;
  rowCount: number;
  samples: Array<Record<string, unknown>>;
};

type CheckDefinition = {
  code: string;
  severity: GuardianSeverityName;
  title: string;
  description: string;
  /** SQL de solo lectura, parametrizado por `$1` = companyId. */
  sql: string;
};

/**
 * Reglas de auditoría preventiva (solo lectura).
 *
 * Todas las consultas filtran por `company_id` y están acotadas con `LIMIT`.
 * Ninguna escribe, bloquea ni modifica operaciones: se ejecutan fuera del flujo
 * comercial (job nocturno o bajo demanda del panel).
 *
 * Calibración: las operaciones legítimas multiusuario (varios turnos en
 * terminales distintos, ventas rápidas, sync masivo tras offline) no producen
 * hallazgos; solo se señalan patrones con evidencia objetiva.
 */
const CHECKS: CheckDefinition[] = [
  {
    code: 'CASH_STALE_OPEN_SESSION',
    severity: 'SEV3',
    title: 'Turno abierto demasiado tiempo',
    description: 'Existe un turno abierto hace más de 24 horas. Puede indicar un cierre no realizado.',
    sql: `
      SELECT id, terminal_id, "openedAt", "status"
      FROM cash_sessions
      WHERE company_id = $1::uuid
        AND "status" = 'OPEN'
        AND "openedAt" < now() - interval '24 hours'
      ORDER BY "openedAt" ASC
      LIMIT 20
    `,
  },
  {
    code: 'CASH_DUPLICATE_OPEN_PER_TERMINAL',
    severity: 'SEV2',
    title: 'Dos turnos abiertos en el mismo terminal',
    description: 'El mismo terminal tiene más de un turno abierto simultáneamente.',
    sql: `
      SELECT COALESCE(terminal_id::text, 'sin-terminal') AS terminal_ref, COUNT(*) AS open_sessions
      FROM cash_sessions
      WHERE company_id = $1::uuid AND "status" = 'OPEN'
      GROUP BY COALESCE(terminal_id::text, 'sin-terminal')
      HAVING COUNT(*) > 1
      LIMIT 20
    `,
  },
  {
    code: 'SALE_AFTER_SESSION_CLOSED',
    severity: 'SEV1',
    title: 'Venta registrada después del cierre de su turno',
    description:
      'Patrón documentado de cierre contaminado: hay ventas con fecha posterior al cierre de la sesión a la que pertenecen.',
    sql: `
      SELECT s.id AS sale_id, s."cashSessionId", s."createdAt" AS sale_created_at, cs."closedAt"
      FROM "Sale" s
      INNER JOIN cash_sessions cs ON cs.id = s."cashSessionId"
      WHERE s.company_id = $1::uuid
        AND cs."closedAt" IS NOT NULL
        AND s."createdAt" > cs."closedAt"
      ORDER BY s."createdAt" DESC
      LIMIT 20
    `,
  },
  {
    code: 'SALE_WITHOUT_ITEMS',
    severity: 'SEV2',
    title: 'Venta sin líneas de detalle',
    description: 'Existe una venta sin ítems asociados; el total no es verificable.',
    sql: `
      SELECT s.id AS sale_id, s."totalSold", s."createdAt"
      FROM "Sale" s
      LEFT JOIN "SaleItem" i ON i."saleId" = s.id
      WHERE s.company_id = $1::uuid
        AND s."isDeleted" = false
        AND i.id IS NULL
      ORDER BY s."createdAt" DESC
      LIMIT 20
    `,
  },
  {
    code: 'SALE_PAYMENT_MISMATCH',
    severity: 'SEV2',
    title: 'Total de venta no coincide con los pagos',
    description: 'La suma de métodos de pago difiere del total registrado de la venta.',
    sql: `
      SELECT s.id AS sale_id, s."totalSold",
             COALESCE(s."paymentCashAmount", 0)
           + COALESCE(s."paymentTransferAmount", 0)
           + COALESCE(s."creditAmount", 0) AS paid_total,
             s."createdAt"
      FROM "Sale" s
      WHERE s.company_id = $1::uuid
        AND s."isDeleted" = false
        AND ABS(
          s."totalSold" - (
            COALESCE(s."paymentCashAmount", 0)
          + COALESCE(s."paymentTransferAmount", 0)
          + COALESCE(s."creditAmount", 0)
          )
        ) > 0.01
      ORDER BY s."createdAt" DESC
      LIMIT 20
    `,
  },
  {
    code: 'SYNC_OUTBOX_STUCK',
    severity: 'SEV2',
    title: 'Cola de sincronización detenida',
    description:
      'Hay eventos de sincronización pendientes o fallidos con más de 6 horas de antigüedad.',
    sql: `
      SELECT id, "status", "attempt_count", "next_attempt_at"
      FROM telemetry_outbox
      WHERE company_id = $1::uuid
        AND "status" IN ('PENDING', 'FAILED')
        AND "next_attempt_at" < now() - interval '6 hours'
      ORDER BY "next_attempt_at" ASC
      LIMIT 20
    `,
  },
];

@Injectable()
export class GuardianIntegrityService implements OnModuleDestroy {
  private readonly logger = new Logger(GuardianIntegrityService.name);
  private readerClient: PrismaClient | null = null;

  constructor(private readonly prisma: PrismaService) {}

  private get client(): PrismaClient {
    const url = String(process.env.GUARDIAN_READER_DATABASE_URL ?? '').trim();
    if (!url) return this.prisma as unknown as PrismaClient;
    if (!this.readerClient) {
      this.readerClient = new PrismaClient({ datasources: { db: { url } } });
    }
    return this.readerClient;
  }

  async onModuleDestroy() {
    await this.readerClient?.$disconnect().catch(() => undefined);
    this.readerClient = null;
  }

  /** Catálogo de reglas disponibles (para el panel y la documentación). */
  listChecks() {
    return CHECKS.map((check) => ({
      code: check.code,
      severity: check.severity,
      title: check.title,
      description: check.description,
    }));
  }

  async runForCompany(companyId: string, options: { codes?: string[] } = {}) {
    const company = await this.client.company.findUnique({
      where: { id: companyId },
      select: { id: true, name: true },
    });
    if (!company) throw new Error(`Empresa no encontrada: ${companyId}`);

    const selected = options.codes?.length
      ? CHECKS.filter((check) => options.codes!.includes(check.code))
      : CHECKS;

    const findings: GuardianFinding[] = [];

    for (const check of selected) {
      try {
        const rows = await this.client.$transaction(async (tx) => {
          await tx.$executeRawUnsafe(`SET LOCAL statement_timeout = '8000ms'`);
          return tx.$queryRawUnsafe<Record<string, unknown>[]>(check.sql, companyId);
        });

        if (!rows.length) continue;
        findings.push({
          checkCode: check.code,
          severity: check.severity,
          title: check.title,
          description: check.description,
          rowCount: rows.length,
          samples: rows.slice(0, 10),
        });
      } catch (error) {
        this.logger.warn(
          `Regla ${check.code} no pudo ejecutarse para ${companyId}: ${
            error instanceof Error ? error.message.slice(0, 160) : String(error)
          }`,
        );
      }
    }

    return {
      companyId: company.id,
      companyName: company.name,
      generatedAt: new Date().toISOString(),
      checksRun: selected.length,
      totalFindings: findings.length,
      findings,
    };
  }
}
