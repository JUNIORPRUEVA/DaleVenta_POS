/**
 * FASE 0 — APPYRA Guardian AI.
 *
 * Pruebas del outbox de notificaciones (selección concurrente, reintentos,
 * desbloqueo de trabajos abandonados, deduplicación y aislamiento entre empresas).
 *
 * El doble de Prisma de este archivo implementa semántica de PostgreSQL
 * READ COMMITTED: `updateMany` reevalúa el `where` contra el estado actual de la
 * fila, por lo que un `where` sin predicado de bloqueo (el defecto original)
 * permite que dos workers reclamen la misma fila.
 */
import { NotificationsService } from './notifications.service';
import { resolveInitialAttemptAt } from './notification-business-hours.util';

type OutboxRow = {
  id: string;
  channel: string;
  status: string;
  contentType: string;
  templateKey: string;
  dedupeKey: string | null;
  messageText: string;
  mediaBase64: string | null;
  mediaFileName: string | null;
  mediaMimeType: string | null;
  payload: Record<string, unknown> | null;
  recipientUserId: string | null;
  toNumber: string;
  toNumberNormalized: string;
  attempts: number;
  nextAttemptAt: Date;
  lockedAt: Date | null;
  lockedBy: string | null;
  lastError: string | null;
  lastStatusCode: number | null;
  sentAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

/** Barrera simple para forzar el interleaving de dos workers. */
class Barrier {
  private arrived = 0;
  private readonly waiters: Array<() => void> = [];
  constructor(private readonly parties: number) {}

  async arriveAndWait(): Promise<void> {
    this.arrived += 1;
    if (this.arrived >= this.parties) {
      const waiters = this.waiters.splice(0, this.waiters.length);
      waiters.forEach((resolve) => resolve());
      return;
    }
    await new Promise<void>((resolve) => this.waiters.push(resolve));
  }
}

function matches(row: OutboxRow, where: any): boolean {
  if (!where) return true;

  if (Array.isArray(where.OR)) {
    const anyMatch = where.OR.some((clause: any) => matches(row, clause));
    if (!anyMatch) return false;
  }

  for (const [key, expected] of Object.entries(where)) {
    if (key === 'OR') continue;
    const actual = (row as any)[key];

    if (expected === null) {
      if (actual !== null) return false;
      continue;
    }

    if (expected instanceof Date) {
      if (!(actual instanceof Date) || actual.getTime() !== expected.getTime()) return false;
      continue;
    }

    if (expected && typeof expected === 'object') {
      const filter = expected as any;
      if ('in' in filter && !filter.in.includes(actual)) return false;
      if ('lte' in filter) {
        if (!(actual instanceof Date) || actual.getTime() > new Date(filter.lte).getTime()) {
          return false;
        }
      }
      if ('lt' in filter) {
        if (actual === null || actual.getTime() >= new Date(filter.lt).getTime()) return false;
      }
      continue;
    }

    if (actual !== expected) return false;
  }

  return true;
}

class FakeOutboxPrisma {
  rows: OutboxRow[] = [];
  gate: Barrier | null = null;

  private async tick() {
    await new Promise<void>((resolve) => setImmediate(resolve));
  }

  async $transaction<T>(fn: (tx: FakeOutboxPrisma) => Promise<T>): Promise<T> {
    return fn(this);
  }

  readonly notificationOutbox = {
    findMany: async (args: any = {}) => {
      if (this.gate) {
        const gate = this.gate;
        await gate.arriveAndWait();
      }
      await this.tick();
      let result = this.rows.filter((row) => matches(row, args.where));
      if (args.orderBy) {
        const order = Array.isArray(args.orderBy) ? args.orderBy : [args.orderBy];
        result = [...result].sort((a, b) => {
          for (const clause of order) {
            const [field, direction] = Object.entries(clause)[0] as [keyof OutboxRow, string];
            const left = (a as any)[field];
            const right = (b as any)[field];
            const leftTime = left instanceof Date ? left.getTime() : left;
            const rightTime = right instanceof Date ? right.getTime() : right;
            if (leftTime === rightTime) continue;
            return (direction === 'asc' ? 1 : -1) * (leftTime > rightTime ? 1 : -1);
          }
          return 0;
        });
      }
      if (typeof args.take === 'number') result = result.slice(0, args.take);
      return result.map((row) => ({ ...row }));
    },

    updateMany: async (args: any) => {
      await this.tick();
      const matching = this.rows.filter((row) => matches(row, args.where));
      for (const row of matching) {
        Object.assign(row, args.data, { updatedAt: new Date() });
      }
      return { count: matching.length };
    },

    update: async (args: any) => {
      await this.tick();
      const row = this.rows.find((candidate) => candidate.id === args.where.id);
      if (!row) throw new Error(`notification_outbox row not found: ${args.where.id}`);
      Object.assign(row, args.data, { updatedAt: new Date() });
      return { ...row };
    },

    findUnique: async (args: any) => {
      await this.tick();
      const row = this.rows.find((candidate) =>
        args.where.dedupeKey !== undefined
          ? candidate.dedupeKey === args.where.dedupeKey
          : candidate.id === args.where.id,
      );
      return row ? { ...row } : null;
    },

    create: async (args: any) => {
      await this.tick();
      const data = args.data as any;
      if (data.dedupeKey) {
        const duplicate = this.rows.find((row) => row.dedupeKey === data.dedupeKey);
        if (duplicate) {
          const error: any = new Error('Unique constraint failed on the fields: (`dedupe_key`)');
          error.code = 'P2002';
          throw error;
        }
      }
      const row: OutboxRow = {
        id: `row-${this.rows.length + 1}`,
        channel: data.channel ?? 'WHATSAPP',
        status: data.status ?? 'PENDING',
        contentType: data.contentType ?? 'TEXT',
        templateKey: data.templateKey ?? 'custom_text',
        dedupeKey: data.dedupeKey ?? null,
        messageText: data.messageText ?? '',
        mediaBase64: data.mediaBase64 ?? null,
        mediaFileName: data.mediaFileName ?? null,
        mediaMimeType: data.mediaMimeType ?? null,
        payload: (data.payload ?? null) as Record<string, unknown> | null,
        recipientUserId: data.recipientUserId ?? null,
        toNumber: data.toNumber ?? '',
        toNumberNormalized: data.toNumberNormalized ?? '',
        attempts: data.attempts ?? 0,
        nextAttemptAt: data.nextAttemptAt ?? new Date(),
        lockedAt: null,
        lockedBy: null,
        lastError: data.lastError ?? null,
        lastStatusCode: null,
        sentAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      this.rows.push(row);
      return { ...row };
    },

    upsert: async (args: any) => {
      await this.tick();
      const existing = this.rows.find((row) => row.dedupeKey === args.where.dedupeKey);
      if (existing) {
        Object.assign(existing, args.update, { updatedAt: new Date() });
        return { ...existing };
      }
      return this.notificationOutbox.create({ data: args.create });
    },
  };

  readonly user = {
    findUnique: async () => null,
  };

  readonly service = {
    findUnique: async () => null,
  };

  seedRow(overrides: Partial<OutboxRow> = {}): OutboxRow {
    const row: OutboxRow = {
      id: `seed-${this.rows.length + 1}`,
      channel: 'WHATSAPP',
      status: 'PENDING',
      contentType: 'TEXT',
      templateKey: 'custom_text',
      dedupeKey: null,
      messageText: 'mensaje',
      mediaBase64: null,
      mediaFileName: null,
      mediaMimeType: null,
      // Determinismo: estas pruebas miden el claim concurrente, no el horario
      // comercial. Sin esta marca, fuera de 09:00-18:00 (America/Santo_Domingo)
      // el despachador reprograma las filas y la prueba falla por la hora.
      payload: { allowOutsideBusinessHours: true },
      recipientUserId: null,
      toNumber: '+18095551234',
      toNumberNormalized: '18095551234',
      attempts: 0,
      nextAttemptAt: new Date(Date.now() - 60_000),
      lockedAt: null,
      lockedBy: null,
      lastError: null,
      lastStatusCode: null,
      sentAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      ...overrides,
    };
    this.rows.push(row);
    return row;
  }
}

function createEvolutionDouble(behaviour?: (message: string) => Promise<void>) {
  return {
    normalizeWhatsAppNumber: (raw: string) => String(raw ?? '').replace(/[^0-9]/g, ''),
    sendTextMessage: jest.fn(async ({ message }: { message: string }) => {
      if (behaviour) await behaviour(message);
      return { ok: true };
    }),
    sendPdfDocument: jest.fn(async () => ({ ok: true })),
  } as any;
}

function createService(prisma: FakeOutboxPrisma, evolution: any) {
  return new NotificationsService(prisma as any, evolution);
}

describe('notification_outbox — selección concurrente', () => {
  it('dos workers concurrentes no envían la misma notificación dos veces', async () => {
    const prisma = new FakeOutboxPrisma();
    for (let i = 0; i < 50; i += 1) prisma.seedRow({ messageText: `msg-${i}` });

    // Fuerza que ambos workers lean el mismo conjunto antes de escribir.
    prisma.gate = new Barrier(2);

    const evolution = createEvolutionDouble();
    const workerA = createService(prisma, evolution);
    const workerB = createService(prisma, evolution);

    await Promise.all([workerA.processOutboxBatch(50), workerB.processOutboxBatch(50)]);

    const sentMessages = evolution.sendTextMessage.mock.calls.map(
      (call: any[]) => call[0].message as string,
    );
    expect(sentMessages).toHaveLength(50);
    expect(new Set(sentMessages).size).toBe(50);
    expect(prisma.rows.every((row) => row.status === 'SENT')).toBe(true);
  });

  it('procesa 500 notificaciones con dos workers sin duplicados ni pérdidas', async () => {
    const prisma = new FakeOutboxPrisma();
    for (let i = 0; i < 500; i += 1) prisma.seedRow({ messageText: `bulk-${i}` });

    const evolution = createEvolutionDouble();
    const workers = [createService(prisma, evolution), createService(prisma, evolution)];

    let guard = 0;
    while (prisma.rows.some((row) => row.status !== 'SENT') && guard < 200) {
      guard += 1;
      await Promise.all(workers.map((worker) => worker.processOutboxBatch(25)));
    }

    const sentMessages = evolution.sendTextMessage.mock.calls.map(
      (call: any[]) => call[0].message as string,
    );
    expect(sentMessages).toHaveLength(500);
    expect(new Set(sentMessages).size).toBe(500);
    expect(prisma.rows.filter((row) => row.status === 'SENT')).toHaveLength(500);
  });

  it('reclama un trabajo abandonado (lock vencido) tras reinicio del worker', async () => {
    const prisma = new FakeOutboxPrisma();
    prisma.seedRow({
      status: 'SENDING',
      lockedAt: new Date(Date.now() - 10 * 60_000),
      lockedBy: 'worker-caido',
      messageText: 'abandonado',
    });

    const evolution = createEvolutionDouble();
    const restarted = createService(prisma, evolution);

    await restarted.processOutboxBatch(10);

    expect(evolution.sendTextMessage).toHaveBeenCalledTimes(1);
    expect(prisma.rows[0].status).toBe('SENT');
    expect(prisma.rows[0].lockedAt).toBeNull();
  });

  it('no reclama un trabajo con lock vigente de otro worker', async () => {
    const prisma = new FakeOutboxPrisma();
    prisma.seedRow({
      status: 'SENDING',
      lockedAt: new Date(),
      lockedBy: 'worker-activo',
      messageText: 'en curso',
    });

    const evolution = createEvolutionDouble();
    const other = createService(prisma, evolution);

    await other.processOutboxBatch(10);

    expect(evolution.sendTextMessage).not.toHaveBeenCalled();
    expect(prisma.rows[0].status).toBe('SENDING');
  });
});

describe('notification_outbox — reintentos y fallos del proveedor', () => {
  it('un fallo transitorio (503) reprograma con backoff y conserva el intento', async () => {
    const prisma = new FakeOutboxPrisma();
    prisma.seedRow({ messageText: 'transitorio' });

    const evolution = createEvolutionDouble(async () => {
      const error: any = new Error('Evolution API error 503');
      error.status = 503;
      throw error;
    });
    const service = createService(prisma, evolution);

    const before = Date.now();
    await service.processOutboxBatch(10);

    const row = prisma.rows[0];
    expect(row.status).toBe('PENDING');
    expect(row.attempts).toBe(1);
    expect(row.lastStatusCode).toBe(503);
    expect(row.lockedAt).toBeNull();
    expect(row.nextAttemptAt.getTime() - before).toBeGreaterThanOrEqual(55_000);
  });

  it('comportamiento actual fijado: agota los 6 intentos y marca FAILED', async () => {
    const prisma = new FakeOutboxPrisma();
    const row = prisma.seedRow({ messageText: 'permanente' });

    const evolution = createEvolutionDouble(async () => {
      const error: any = new Error('Evolution API error 400');
      error.status = 400;
      throw error;
    });
    const service = createService(prisma, evolution);

    for (let attempt = 1; attempt <= 6; attempt += 1) {
      prisma.rows[0].nextAttemptAt = new Date(Date.now() - 1_000);
      prisma.rows[0].lockedAt = null;
      await service.processOutboxBatch(10);
    }

    expect(row.attempts).toBe(6);
    expect(row.status).toBe('FAILED');
    expect(row.lastStatusCode).toBe(400);
  });

  it('desbloquea la fila tras un fallo y permite que otro worker la reintente', async () => {
    const prisma = new FakeOutboxPrisma();
    prisma.seedRow({ messageText: 'reintento' });

    const failing = createEvolutionDouble(async () => {
      const error: any = new Error('timeout');
      error.status = 500;
      throw error;
    });
    await createService(prisma, failing).processOutboxBatch(10);
    expect(prisma.rows[0].lockedAt).toBeNull();

    const recovering = createEvolutionDouble();
    prisma.rows[0].nextAttemptAt = new Date(Date.now() - 1_000);
    await createService(prisma, recovering).processOutboxBatch(10);

    expect(recovering.sendTextMessage).toHaveBeenCalledTimes(1);
    expect(prisma.rows[0].status).toBe('SENT');
    expect(prisma.rows[0].attempts).toBe(1);
  });
});

describe('notification_outbox — deduplicación', () => {
  it('el mismo dedupeKey no genera una segunda fila ni un segundo envío', async () => {
    const prisma = new FakeOutboxPrisma();
    const evolution = createEvolutionDouble();
    const service = createService(prisma, evolution);

    const first = await service.enqueueWhatsAppRawText({
      toNumber: '+18095551234',
      messageText: 'hola',
      dedupeKey: 'guardian:incident:1',
      // Igual que las alertas de Guardian: envio 24/7, sin ventana comercial.
      allowOutsideBusinessHours: true,
    });
    const second = await service.enqueueWhatsAppRawText({
      toNumber: '+18095551234',
      messageText: 'hola',
      dedupeKey: 'guardian:incident:1',
      allowOutsideBusinessHours: true,
    });

    expect(prisma.rows).toHaveLength(1);
    expect(second.id).toBe(first.id);

    // Independiente de la hora del entorno: simula que ya pasó el momento programado.
    prisma.rows[0].nextAttemptAt = new Date(Date.now() - 1_000);

    await service.processOutboxBatch(10);
    expect(evolution.sendTextMessage).toHaveBeenCalledTimes(1);
  });
});

describe('notification_outbox — aislamiento entre empresas', () => {
  it('entrega exactamente una vez las filas de dos empresas y aísla el fallo de una', async () => {
    const prisma = new FakeOutboxPrisma();
    prisma.seedRow({ messageText: 'empresa-A-ok', payload: { companyId: 'company-a', allowOutsideBusinessHours: true } });
    prisma.seedRow({ messageText: 'empresa-B-falla', payload: { companyId: 'company-b', allowOutsideBusinessHours: true } });

    const evolution = createEvolutionDouble(async (message: string) => {
      if (message.includes('empresa-B')) {
        const error: any = new Error('Evolution API error 500');
        error.status = 500;
        throw error;
      }
    });
    const service = createService(prisma, evolution);

    await service.processOutboxBatch(10);

    const rowA = prisma.rows.find((row) => row.messageText === 'empresa-A-ok')!;
    const rowB = prisma.rows.find((row) => row.messageText === 'empresa-B-falla')!;

    expect(rowA.status).toBe('SENT');
    expect(rowB.status).toBe('PENDING');
    expect(rowB.attempts).toBe(1);
    expect(prisma.rows.filter((row) => row.status === 'SENT')).toHaveLength(1);
    expect(evolution.sendTextMessage).toHaveBeenCalledTimes(2);
  });
});

describe('notification-business-hours — alertas críticas', () => {
  it('sin autorización explícita desplaza el envío al siguiente horario comercial', () => {
    // Domingo 2026-10-25 03:00 hora RD (UTC-4) => 07:00 UTC
    const sundayEarly = new Date('2026-10-25T07:00:00.000Z');
    const aligned = resolveInitialAttemptAt(sundayEarly, false);
    expect(aligned.getTime()).toBeGreaterThan(sundayEarly.getTime());
  });

  it('con allowOutsideBusinessHours=true no desplaza la alerta crítica', () => {
    const sundayEarly = new Date('2026-10-25T07:00:00.000Z');
    const aligned = resolveInitialAttemptAt(sundayEarly, true);
    expect(aligned.getTime()).toBe(sundayEarly.getTime());
  });
});
