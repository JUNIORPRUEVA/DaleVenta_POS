import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Consultas SQL predefinidas y parametrizadas.
 *
 * La IA no puede enviar SQL: solo puede pedir una de estas claves. Cada consulta
 * es de solo lectura, tiene `LIMIT`, y se ejecuta con `statement_timeout` corto.
 */
const PREDEFINED_QUERIES: Record<string, string> = {
  cash_activity_24h: `
    SELECT
      COUNT(*) FILTER (WHERE "status" = 'OPEN') AS open_sessions,
      COUNT(*) AS total_sessions,
      COUNT(*) FILTER (WHERE "closedAt" IS NULL AND "openedAt" < (now() AT TIME ZONE 'UTC') - interval '12 hours') AS stale_sessions
    FROM cash_sessions
    WHERE "company_id" = $1::uuid AND "openedAt" >= (now() AT TIME ZONE 'UTC') - interval '24 hours'
    LIMIT 1
  `,
  sales_activity_24h: `
    SELECT COUNT(*) AS sales_count, COALESCE(SUM("totalSold"), 0) AS total_amount
    FROM "Sale"
    WHERE "company_id" = $1::uuid AND "createdAt" >= (now() AT TIME ZONE 'UTC') - interval '24 hours'
    LIMIT 1
  `,
  sync_recent_errors: `
    SELECT COUNT(*) AS failed_rows
    FROM telemetry_outbox
    WHERE "company_id" = $1::uuid AND "status" = 'FAILED'
    LIMIT 1
  `,
  license_state: `
    SELECT "license_status", "license_expires_at", "plan", "status"
    FROM companies
    WHERE "id" = $1::uuid
    LIMIT 1
  `,
};

const CODE_SEARCH_MAX_FILES = 4_000;
const CODE_SEARCH_MAX_MATCHES = 20;
const CODE_SEARCH_MAX_BYTES = 256 * 1024;

export type GuardianToolTrace = { tool: string; status: 'ok' | 'error' | 'skipped'; detail?: string; ms?: number };

@Injectable()
export class GuardianToolsService implements OnModuleDestroy {
  private readonly logger = new Logger(GuardianToolsService.name);
  private readerClient: PrismaClient | null = null;

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Cliente de solo lectura.
   *
   * Si existe `GUARDIAN_READER_DATABASE_URL` se usa un usuario PostgreSQL
   * `guardian_reader` (SELECT únicamente). Así la IA no puede escribir aunque
   * el código lo intentara: el permiso no existe en la base.
   */
  private get reader(): { $transaction: PrismaClient['$transaction'] } | PrismaClient {
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

  /**
   * Ejecuta una consulta predefinida. Cualquier clave no listada se rechaza.
   * `statement_timeout` acota el tiempo de ejecución a nivel de sesión/transacción.
   */
  async runPredefinedQuery(key: string, params: unknown[]) {
    const sql = PREDEFINED_QUERIES[key];
    if (!sql) {
      throw new Error(`Consulta no permitida: ${key}`);
    }

    return (this.reader as PrismaClient).$transaction(async (tx) => {
      await tx.$executeRawUnsafe(`SET LOCAL statement_timeout = '5000ms'`);
      return tx.$queryRawUnsafe<Record<string, unknown>[]>(sql, ...params);
    });
  }

  /**
   * Búsqueda de identificadores en el código autorizado (solo lectura, sin shell,
   * sin git). Devuelve como máximo 20 coincidencias.
   */
  searchCode(identifiers: string[], root = process.env.GUARDIAN_CODE_ROOT ?? join(process.cwd(), 'src')) {
    const startedAt = Date.now();
    const needles = identifiers
      .map((value) => String(value ?? '').trim())
      .filter((value) => value.length >= 5 && value.length <= 80)
      .slice(0, 5);

    if (!needles.length) {
      return { matches: [] as Array<{ file: string; line: number; snippet: string }>, trace: this.trace('searchCode', 'skipped', 'sin identificadores', startedAt) };
    }

    const matches: Array<{ file: string; line: number; snippet: string }> = [];
    let scanned = 0;

    const walk = (dir: string) => {
      if (matches.length >= CODE_SEARCH_MAX_MATCHES || scanned >= CODE_SEARCH_MAX_FILES) return;
      let entries: string[];
      try {
        entries = readdirSync(dir);
      } catch {
        return;
      }
      for (const entry of entries) {
        if (matches.length >= CODE_SEARCH_MAX_MATCHES || scanned >= CODE_SEARCH_MAX_FILES) return;
        if (['node_modules', 'dist', '.git', 'prisma'].includes(entry)) continue;
        const full = join(dir, entry);
        let stat;
        try {
          stat = statSync(full);
        } catch {
          continue;
        }
        if (stat.isDirectory()) {
          walk(full);
          continue;
        }
        if (!entry.endsWith('.ts') || stat.size > CODE_SEARCH_MAX_BYTES) continue;
        // Los archivos de prueba no son código de producción y suelen contener
        // literales sintéticos que provocarían falsas coincidencias.
        if (/\.(spec|integration-spec|e2e-spec)\.ts$/.test(entry)) continue;
        scanned += 1;
        let content = '';
        try {
          content = readFileSync(full, 'utf8');
        } catch {
          continue;
        }
        const lines = content.split(/\r?\n/);
        for (let index = 0; index < lines.length; index += 1) {
          const line = lines[index];
          if (!needles.some((needle) => line.includes(needle))) continue;
          matches.push({
            file: relative(root, full).split(sep).join('/'),
            line: index + 1,
            snippet: line.trim().slice(0, 160),
          });
          if (matches.length >= CODE_SEARCH_MAX_MATCHES) break;
        }
      }
    };

    try {
      walk(root);
    } catch (error) {
      this.logger.warn(`searchCode falló: ${error instanceof Error ? error.message : String(error)}`);
      return { matches, trace: this.trace('searchCode', 'error', 'fallo de lectura', startedAt) };
    }

    return { matches, trace: this.trace('searchCode', 'ok', `${scanned} archivos`, startedAt) };
  }

  private trace(tool: string, status: 'ok' | 'error' | 'skipped', detail?: string, startedAt?: number): GuardianToolTrace {
    return { tool, status, detail, ms: startedAt ? Date.now() - startedAt : undefined };
  }
}
