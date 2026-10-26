/**
 * FASE 0 / ETAPA 0 — Concurrencia del claim del outbox contra PostgreSQL REAL.
 *
 * No usa dobles: crea dos `PrismaClient` independientes (dos pools de conexión,
 * equivalente a dos réplicas del API) y ejecuta dos workers concurrentes sobre
 * las mismas filas de `notification_outbox`.
 *
 * Requiere una base aislada (nunca producción). Se salta si la variable no existe:
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 *   npx jest --runInBand src/notifications/notifications.claim.pg.integration-spec.ts
 */
import { PrismaClient } from '@prisma/client';
import { NotificationsService } from './notifications.service';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const MARKER = 'uat_guardian_claim';

const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;

type Send = { message: string; toNumber: string };

function createEvolutionDouble(sink: Send[], delayMs = 1) {
  return {
    normalizeWhatsAppNumber: (raw: string) => String(raw ?? '').replace(/[^0-9]/g, ''),
    sendTextMessage: async ({ message, toNumber }: { message: string; toNumber: string }) => {
      if (delayMs > 0) await new Promise((resolve) => setTimeout(resolve, delayMs));
      sink.push({ message, toNumber });
      return { ok: true };
    },
    sendPdfDocument: async ({ caption, toNumber }: { caption: string; toNumber: string }) => {
      sink.push({ message: caption, toNumber });
      return { ok: true };
    },
  } as any;
}

async function drain(
  service: NotificationsService,
  prisma: PrismaClient,
  { maxIterations = 200, batchSize = 25 } = {},
) {
  for (let iteration = 0; iteration < maxIterations; iteration += 1) {
    await service.processOutboxBatch(batchSize);
    const remaining = await prisma.notificationOutbox.count({
      where: { templateKey: MARKER, status: { in: ['PENDING', 'SENDING'] } },
    });
    if (remaining === 0) return { iterations: iteration + 1, remaining };
  }
  const remaining = await prisma.notificationOutbox.count({
    where: { templateKey: MARKER, status: { in: ['PENDING', 'SENDING'] } },
  });
  return { iterations: maxIterations, remaining };
}

describeOnPg('notification_outbox sobre PostgreSQL real — claim concurrente', () => {
  let prismaA: PrismaClient;
  let prismaB: PrismaClient;

  beforeAll(async () => {
    prismaA = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    prismaB = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prismaA.$connect();
    await prismaB.$connect();
  });

  afterAll(async () => {
    await prismaA?.notificationOutbox.deleteMany({ where: { templateKey: MARKER } });
    await prismaA?.$disconnect();
    await prismaB?.$disconnect();
  });

  beforeEach(async () => {
    await prismaA.notificationOutbox.deleteMany({ where: { templateKey: MARKER } });
  });

  async function seed(count: number) {
    const now = Date.now();
    await prismaA.notificationOutbox.createMany({
      data: Array.from({ length: count }, (_, index) => ({
        channel: 'WHATSAPP' as const,
        status: 'PENDING' as const,
        contentType: 'TEXT' as const,
        templateKey: MARKER,
        messageText: `pg-${index}`,
        toNumber: '+18095550000',
        toNumberNormalized: '18095550000',
        attempts: 0,
        nextAttemptAt: new Date(now - 60_000),
      })),
    });
  }

  it('dos workers con pools independientes entregan 500 filas exactamente una vez', async () => {
    await seed(500);

    const sinkA: Send[] = [];
    const sinkB: Send[] = [];
    const workerA = new NotificationsService(prismaA as any, createEvolutionDouble(sinkA));
    const workerB = new NotificationsService(prismaB as any, createEvolutionDouble(sinkB));

    const startedAt = Date.now();
    const [resultA, resultB] = await Promise.all([
      drain(workerA, prismaA),
      drain(workerB, prismaB),
    ]);
    const elapsedMs = Date.now() - startedAt;

    const allSends = [...sinkA, ...sinkB].map((send) => send.message);
    const counts = new Map<string, number>();
    for (const message of allSends) counts.set(message, (counts.get(message) ?? 0) + 1);
    const duplicates = [...counts.entries()].filter(([, times]) => times > 1);

    const sentRows = await prismaA.notificationOutbox.count({
      where: { templateKey: MARKER, status: 'SENT' },
    });
    const stuckRows = await prismaA.notificationOutbox.count({
      where: { templateKey: MARKER, status: { in: ['PENDING', 'SENDING'] } },
    });

    // Evidencia explícita en la salida de la prueba.
    // eslint-disable-next-line no-console
    console.log(
      `[uat] filas=500 enviadas=${allSends.length} duplicados=${duplicates.length} ` +
        `sentBd=${sentRows} pendientes=${stuckRows} ms=${elapsedMs} ` +
        `workerA=${sinkA.length} workerB=${sinkB.length} iterA=${resultA.iterations} iterB=${resultB.iterations}`,
    );

    expect(allSends).toHaveLength(500);
    expect(new Set(allSends).size).toBe(500);
    expect(duplicates).toEqual([]);
    expect(sentRows).toBe(500);
    expect(stuckRows).toBe(0);
    expect(resultA.remaining).toBe(0);
    expect(resultB.remaining).toBe(0);
  }, 120_000);

  it('un lock vigente no se roba y uno vencido se recupera (muerte de worker)', async () => {
    const now = Date.now();
    await prismaA.notificationOutbox.createMany({
      data: [
        {
          channel: 'WHATSAPP' as const,
          status: 'SENDING' as const,
          contentType: 'TEXT' as const,
          templateKey: MARKER,
          messageText: 'pg-lock-vigente',
          toNumber: '+18095550001',
          toNumberNormalized: '18095550001',
          attempts: 1,
          nextAttemptAt: new Date(now - 60_000),
          lockedAt: new Date(now),
          lockedBy: 'worker-vivo',
        },
        {
          channel: 'WHATSAPP' as const,
          status: 'SENDING' as const,
          contentType: 'TEXT' as const,
          templateKey: MARKER,
          messageText: 'pg-lock-vencido',
          toNumber: '+18095550002',
          toNumberNormalized: '18095550002',
          attempts: 1,
          nextAttemptAt: new Date(now - 60_000),
          lockedAt: new Date(now - 5 * 60_000),
          lockedBy: 'worker-muerto',
        },
      ],
    });

    const sink: Send[] = [];
    const worker = new NotificationsService(prismaA as any, createEvolutionDouble(sink, 0));
    await worker.processOutboxBatch(10);

    const vigente = await prismaA.notificationOutbox.findFirst({
      where: { templateKey: MARKER, messageText: 'pg-lock-vigente' },
    });
    const vencido = await prismaA.notificationOutbox.findFirst({
      where: { templateKey: MARKER, messageText: 'pg-lock-vencido' },
    });

    expect(vigente?.status).toBe('SENDING');
    expect(vigente?.lockedBy).toBe('worker-vivo');
    expect(vencido?.status).toBe('SENT');
    expect(vencido?.lockedAt).toBeNull();
    expect(sink.map((send) => send.message)).toEqual(['pg-lock-vencido']);
  }, 60_000);

  it('la cola concurrente no produce deadlocks ni deja filas bloqueadas', async () => {
    await seed(120);

    const sinkA: Send[] = [];
    const sinkB: Send[] = [];
    const workerA = new NotificationsService(prismaA as any, createEvolutionDouble(sinkA, 0));
    const workerB = new NotificationsService(prismaB as any, createEvolutionDouble(sinkB, 0));

    const [a, b] = await Promise.all([drain(workerA, prismaA), drain(workerB, prismaB)]);

    const locked = await prismaA.notificationOutbox.count({
      where: { templateKey: MARKER, lockedAt: { not: null } },
    });

    expect(locked).toBe(0);
    expect(sinkA.length + sinkB.length).toBe(120);
    expect(a.remaining + b.remaining).toBe(0);
  }, 120_000);

  it('dedupeKey único bajo concurrencia real: una sola fila, sin excepción', async () => {
    const evolution = createEvolutionDouble([]);
    const service = new NotificationsService(prismaA as any, evolution);

    const attempts = await Promise.allSettled(
      Array.from({ length: 8 }, () =>
        service.enqueueWhatsAppRawText({
          toNumber: '+18095550003',
          messageText: 'pg-dedupe',
          dedupeKey: 'uat-guardian-dedupe-key',
        }),
      ),
    );

    const rejected = attempts.filter((attempt) => attempt.status === 'rejected');
    const rows = await prismaA.notificationOutbox.count({
      where: { dedupeKey: 'uat-guardian-dedupe-key' },
    });

    // eslint-disable-next-line no-console
    console.log(
      `[uat] dedupe concurrente: filas=${rows} rechazadas=${rejected.length}` +
        (rejected.length ? ` motivo=${String((rejected[0] as any).reason).slice(0, 120)}` : ''),
    );

    await prismaA.notificationOutbox.deleteMany({ where: { dedupeKey: 'uat-guardian-dedupe-key' } });

    expect(rows).toBe(1);
    expect(rejected).toEqual([]);
  }, 60_000);
});
