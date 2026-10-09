import { ServiceOrderStatus } from '@prisma/client';
import { ServiceOrdersService } from './service-orders.service';

describe('ServiceOrdersService pagination contract', () => {
  const user = {
    id: 'user-a',
    role: 'ADMIN',
    companyId: 'company-a',
  };

  it('lists service orders with tenant scope, bounded pagination and last status date filtering', async () => {
    const findMany = jest.fn().mockResolvedValue(
      Array.from({ length: 51 }, (_, index) => orderRow(`order-${index}`)),
    );
    const service = new ServiceOrdersService({
      serviceOrder: { findMany },
    } as never);

    const result = await service.list(user as never, {
      page: 2,
      limit: 50,
      statuses: 'pendiente,en_proceso',
      from: '2026-10-01T00:00:00.000Z',
      to: '2026-10-08T23:59:59.999Z',
    });

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          client: { companyId: 'company-a' },
          status: {
            in: [
              ServiceOrderStatus.PENDIENTE,
              ServiceOrderStatus.EN_PROCESO,
            ],
          },
          lastStatusChangedAt: {
            gte: new Date('2026-10-01T00:00:00.000Z'),
            lte: new Date('2026-10-08T23:59:59.999Z'),
          },
        }),
        skip: 50,
        take: 51,
      }),
    );
    expect(result.items).toHaveLength(50);
    expect(result.page).toBe(2);
    expect(result.limit).toBe(50);
    expect(result.hasMore).toBe(true);
    expect(result.nextPage).toBe(3);
  });

  it('scopes non-admin users to created or assigned service orders', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const service = new ServiceOrdersService({
      serviceOrder: { findMany },
    } as never);

    await service.list(
      { ...user, role: 'TECNICO' } as never,
      { page: 1, limit: 200 },
    );

    expect(findMany.mock.calls[0][0].where).toMatchObject({
      client: { companyId: 'company-a' },
      OR: [{ createdById: 'user-a' }, { assignedToId: 'user-a' }],
    });
    expect(findMany.mock.calls[0][0].take).toBe(201);
  });

  it('syncs service orders by server cursor and emits cancellation tombstones', async () => {
    const rows = [
      orderRow('order-1', {
        status: ServiceOrderStatus.PENDIENTE,
        updatedAt: new Date('2026-10-08T10:00:00.000Z'),
      }),
      orderRow('order-2', {
        status: ServiceOrderStatus.CANCELADO,
        updatedAt: new Date('2026-10-08T10:01:00.000Z'),
        lastStatusChangedAt: new Date('2026-10-08T10:01:00.000Z'),
      }),
      orderRow('order-3', {
        status: ServiceOrderStatus.EN_PROCESO,
        updatedAt: new Date('2026-10-08T10:02:00.000Z'),
      }),
    ];
    const findMany = jest.fn().mockResolvedValue(rows);
    const service = new ServiceOrdersService({
      serviceOrder: { findMany },
    } as never);
    const cursor = Buffer.from(
      JSON.stringify({
        updatedAt: '2026-10-08T09:59:00.000Z',
        id: 'order-0',
      }),
      'utf8',
    ).toString('base64url');

    const result = await service.sync(user as never, { cursor, limit: 2 });

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          client: { companyId: 'company-a' },
          OR: [
            { updatedAt: { gt: new Date('2026-10-08T09:59:00.000Z') } },
            {
              updatedAt: new Date('2026-10-08T09:59:00.000Z'),
              id: { gt: 'order-0' },
            },
          ],
        }),
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
        take: 3,
      }),
    );
    expect(result.items).toHaveLength(1);
    expect(result.items[0].id).toBe('order-1');
    expect(result.tombstones).toEqual([
      {
        id: 'order-2',
        deletedAt: '2026-10-08T10:01:00.000Z',
        reason: 'cancelled',
        version: '2026-10-08T10:01:00.000Z',
      },
    ]);
    expect(result.hasMore).toBe(true);
    expect(result.nextCursor).toBe(
      Buffer.from(
        JSON.stringify({
          updatedAt: '2026-10-08T10:01:00.000Z',
          id: 'order-2',
        }),
        'utf8',
      ).toString('base64url'),
    );
  });

  it('emits deleted service orders as durable tombstones and hides them from active lists', async () => {
    const deletedAt = new Date('2026-10-08T11:00:00.000Z');
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([
        orderRow('order-deleted', {
          deletedAt,
          updatedAt: deletedAt,
        }),
      ])
      .mockResolvedValueOnce([]);
    const service = new ServiceOrdersService({
      serviceOrder: { findMany },
    } as never);

    const sync = await service.sync(user as never, { limit: 50 });
    await service.list(user as never, { page: 1, limit: 50 });

    expect(sync.items).toEqual([]);
    expect(sync.tombstones).toEqual([
      {
        id: 'order-deleted',
        deletedAt: '2026-10-08T11:00:00.000Z',
        reason: 'deleted',
        version: '2026-10-08T11:00:00.000Z',
      },
    ]);
    expect(findMany.mock.calls[1][0].where).toEqual(
      expect.objectContaining({ deletedAt: null }),
    );
  });

  it('deletes service orders by soft-delete so delta sync can publish a tombstone', async () => {
    const findFirst = jest.fn().mockResolvedValue(orderRow('order-delete'));
    const update = jest.fn().mockResolvedValue(orderRow('order-delete'));
    const service = new ServiceOrdersService({
      serviceOrder: { findFirst, update },
    } as never);

    await service.delete(user as never, 'order-delete');

    expect(update).toHaveBeenCalledWith({
      where: { id: 'order-delete' },
      data: { deletedAt: expect.any(Date) },
    });
  });

  it('rejects malformed service order sync cursors before querying', async () => {
    const findMany = jest.fn();
    const service = new ServiceOrdersService({
      serviceOrder: { findMany },
    } as never);

    await expect(
      service.sync(user as never, { cursor: 'not-a-valid-cursor' }),
    ).rejects.toThrow('Cursor de sincronización inválido');
    expect(findMany).not.toHaveBeenCalled();
  });
});

function orderRow(
  id: string,
  overrides: Partial<ReturnType<typeof orderRowBase>> = {},
) {
  return { ...orderRowBase(id), ...overrides };
}

function orderRowBase(id: string) {
  const now = new Date('2026-10-08T12:00:00.000Z');
  return {
    id,
    clientId: 'client-a',
    client: {
      id: 'client-a',
      ownerId: 'user-a',
      nombre: 'Cliente A',
      telefono: '8090000000',
      direccion: null,
      locationUrl: null,
      latitude: null,
      longitude: null,
      email: null,
      taxId: null,
      businessName: null,
      taxIdType: null,
      createdAt: now,
      updatedAt: now,
      isDeleted: false,
    },
    quotationId: null,
    category: 'CAMARA',
    serviceType: 'INSTALACION',
    status: 'PENDIENTE',
    technicalNote: null,
    extraRequirements: null,
    parentOrderId: null,
    createdById: 'user-a',
    assignedToId: null,
    scheduledFor: null,
    finalizedAt: null,
    technicianConfirmedAt: null,
    technicianConfirmedById: null,
    lastStatusChangedAt: now,
    lastStatusChangedByUserId: null,
    deletedAt: null,
    createdAt: now,
    updatedAt: now,
    statusHistory: [],
    evidences: [],
    reports: [],
  };
}
