import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { UsageTelemetryService } from './usage-telemetry.service';

describe('UsageTelemetryService reliable outbox', () => {
  const companyId = '11111111-1111-4111-8111-111111111111';

  function buildService(overrides: { config?: Record<string, string>; prisma?: any } = {}) {
    const prisma = overrides.prisma ?? {
      telemetryOutbox: {
        create: jest.fn(),
        updateMany: jest.fn(),
        count: jest.fn(),
        findFirst: jest.fn(),
      },
      $queryRaw: jest.fn(),
    };
    const config = {
      get: jest.fn((key: string) => {
        const values: Record<string, string> = {
          APPYRA_USAGE_TELEMETRY_ENABLED: 'true',
          APPYRA_USAGE_API_BASE_URL: 'https://appyra.test',
          APPYRA_USAGE_INGEST_SECRET: 'secret',
          ...overrides.config,
        };
        return values[key];
      }),
    } as unknown as ConfigService;
    return { service: new UsageTelemetryService(prisma as never, config), prisma, config };
  }

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-09-07T05:00:00.000Z'));
    jest.restoreAllMocks();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('persists canonical schema-v1 events without sensitive metadata', async () => {
    const { service, prisma } = buildService();
    prisma.telemetryOutbox.create.mockImplementation(async (args: any) => ({
      id: 'outbox-1',
      ...args.data,
    }));

    const row = await service.enqueueEvent({
      companyId,
      eventType: 'PRODUCT_CREATED',
      actorUserId: 'user-1',
      entityType: 'product',
      entityId: 'product-1',
      feature: 'PRODUCTS',
      metadata: {
        sku: 'P-1',
        password: 'never',
        items: [{ productId: 'private' }],
      },
    });

    expect(row).toBeTruthy();
    expect(prisma.telemetryOutbox.create).toHaveBeenCalledTimes(1);
    const data = prisma.telemetryOutbox.create.mock.calls[0][0].data;
    expect(data.schemaVersion).toBe(1);
    expect(data.companyId).toBe(companyId);
    expect(data.eventType).toBe('PRODUCT_CREATED');
    expect(data.payload).toEqual(
      expect.objectContaining({
        eventId: data.eventId,
        event_id: data.eventId,
        schemaVersion: 1,
        schema_version: 1,
        companyId,
        business_id: companyId,
        eventType: 'PRODUCT_CREATED',
        event_type: 'PRODUCT_CREATED',
        actorUserId: 'user-1',
        actor_user_id: 'user-1',
        entityType: 'product',
        entityId: 'product-1',
        feature: 'PRODUCTS',
        deviceId: `daleventas-api-${companyId}`,
        platform: 'api',
      }),
    );
    expect(data.payload.metadata).toMatchObject({
      sku: 'P-1',
      privacy: 'minimal_activity_metadata',
    });
    expect(data.payload.metadata.password).toBeUndefined();
    expect(data.payload.metadata.items).toBeUndefined();
  });

  it('coalesces duplicate dedupe keys locally', async () => {
    const { service, prisma } = buildService();
    prisma.telemetryOutbox.create.mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
        code: 'P2002',
        clientVersion: 'test',
      }),
    );

    await expect(
      service.enqueueEvent({
        companyId,
        eventType: 'MODULE_USED',
        feature: 'SALES',
        dedupeKey: `${companyId}:device:sales`,
      }),
    ).resolves.toBeNull();
  });

  it('claims pending events and delivers them through the Appyra batch endpoint', async () => {
    const fetchMock = jest.spyOn(global, 'fetch' as never).mockResolvedValue({
      ok: true,
      status: 200,
      text: jest.fn(),
    } as never);
    const { service, prisma } = buildService();
    prisma.$queryRaw.mockResolvedValue([
      {
        id: 'outbox-1',
        payload_json: {
          eventId: 'event-1',
          schemaVersion: 1,
          companyId,
          eventType: 'PRODUCT_CREATED',
        },
      },
    ]);
    prisma.telemetryOutbox.updateMany.mockResolvedValue({ count: 1 });

    const result = await service.processOutboxBatch();

    expect(result).toEqual({ ok: true, enabled: true, claimed: 1, sent: 1 });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://appyra.test/api/usage/batch',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'Content-Type': 'application/json',
          'x-usage-ingest-secret': 'secret',
        }),
        body: JSON.stringify({
          events: [
            {
              eventId: 'event-1',
              schemaVersion: 1,
              companyId,
              eventType: 'PRODUCT_CREATED',
            },
          ],
        }),
      }),
    );
    expect(prisma.telemetryOutbox.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'SENT',
          lockedAt: null,
          lockedBy: null,
          lastError: null,
        }),
      }),
    );
  });

  it('retries retryable delivery failures with backoff', async () => {
    jest.spyOn(global, 'fetch' as never).mockResolvedValue({
      ok: false,
      status: 503,
      text: jest.fn(async () => 'temporarily unavailable'),
    } as never);
    const { service, prisma } = buildService();
    prisma.$queryRaw.mockResolvedValue([
      {
        id: 'outbox-1',
        attempt_count: 1,
        payload_json: { eventId: 'event-1', schemaVersion: 1 },
      },
    ]);
    prisma.telemetryOutbox.updateMany.mockResolvedValue({ count: 1 });

    const result = await service.processOutboxBatch();

    expect(result).toEqual({
      ok: false,
      enabled: true,
      claimed: 1,
      sent: 0,
      status: 'PENDING',
      retryable: true,
    });
    expect(prisma.telemetryOutbox.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'PENDING',
          attemptCount: 2,
          lockedAt: null,
          lockedBy: null,
        }),
      }),
    );
  });

  it('dead-letters non-retryable delivery failures', async () => {
    jest.spyOn(global, 'fetch' as never).mockResolvedValue({
      ok: false,
      status: 400,
      text: jest.fn(async () => 'bad event'),
    } as never);
    const { service, prisma } = buildService();
    prisma.$queryRaw.mockResolvedValue([
      {
        id: 'outbox-1',
        attempt_count: 0,
        payload_json: { eventId: 'event-1', schemaVersion: 1 },
      },
    ]);
    prisma.telemetryOutbox.updateMany.mockResolvedValue({ count: 1 });

    const result = await service.processOutboxBatch();

    expect(result).toEqual({
      ok: false,
      enabled: true,
      claimed: 1,
      sent: 0,
      status: 'FAILED',
      retryable: false,
    });
    expect(prisma.telemetryOutbox.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'FAILED',
          attemptCount: 1,
          lockedAt: null,
          lockedBy: null,
        }),
      }),
    );
  });
});
