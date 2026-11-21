import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { CashService } from './cash.service';

describe('offline cash recovery', () => {
  const user = { id: 'user-a', companyId: 'company-a', role: 'ADMIN' };
  const dto = { sessionId: 'shift-a', operationId: 'op-a', type: 'IN' as const, amount: 10 };
  function harness() {
    const prisma = { cashMovement: {
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation(({ data }) => ({ id: 'movement-a', ...data })),
    } };
    const service = new CashService(prisma as never, { emitCompany: jest.fn() } as never);
    const gate = jest.spyOn(service as any, 'requireOpenSession')
      .mockResolvedValue({ id: dto.sessionId, businessDate: '2026-11-20' });
    return { service, prisma, gate };
  }
  it('validates and persists occurrence separately from receipt time', async () => {
    const { service, prisma, gate } = harness();
    const at = new Date(Date.now() - 60_000).toISOString();
    await service.addMovement(user, { ...dto, occurredAt: at });
    expect(gate).toHaveBeenCalledWith(user.id, user.companyId, dto.sessionId, new Date(at));
    expect(prisma.cashMovement.create.mock.calls[0][0].data.occurredAt).toEqual(new Date(at));
    expect(prisma.cashMovement.create.mock.calls[0][0].data.createdAt).toBeUndefined();
  });
  it.each(['not-a-date', '2026-11-20T12:00:00', '2099-01-01T00:00:00Z'])(
    'rejects an invalid, ambiguous or future timestamp without writing: %s', async at => {
      const { service, prisma, gate } = harness();
      await expect(service.addMovement(user, { ...dto, occurredAt: at })).rejects.toBeInstanceOf(BadRequestException);
      expect(gate).not.toHaveBeenCalled();
      expect(prisma.cashMovement.create).not.toHaveBeenCalled();
    },
  );
  it('does not confirm a reused operation id with a different amount or user', async () => {
    const { service, prisma } = harness();
    prisma.cashMovement.findFirst.mockResolvedValue({ ...dto, amount: new Prisma.Decimal(99), userId: user.id } as never);
    await expect(service.addMovement(user, dto)).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.cashMovement.create).not.toHaveBeenCalled();
  });
  it('returns the original movement on exact replay without a second write', async () => {
    const { service, prisma, gate } = harness();
    const original = { id: 'movement-a', ...dto, amount: new Prisma.Decimal(10), userId: user.id };
    prisma.cashMovement.findFirst.mockResolvedValue(original as never);
    expect(await service.addMovement(user, dto)).toEqual(original);
    expect(prisma.cashMovement.create).not.toHaveBeenCalled();
    expect(gate).not.toHaveBeenCalled();
  });
});
