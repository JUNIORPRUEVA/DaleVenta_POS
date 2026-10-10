import { Role } from '@prisma/client';
import { UsersService } from './users.service';

function buildService(prisma: Record<string, unknown>) {
  return new UsersService(
    prisma as never,
    { get: jest.fn().mockReturnValue(undefined) } as never,
    {
      assertCanCreateUser: jest.fn(),
      assertCanCreateUserInTransaction: jest.fn(),
    } as never,
    { emitCompanyUser: jest.fn() } as never,
  );
}

describe('UsersService pagination', () => {
  const actor = {
    id: 'admin-a',
    role: Role.ADMIN,
    companyId: 'company-a',
  };

  it('keeps legacy list responses flat when no pagination is requested', async () => {
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([{ id: 'user-a' }]),
      },
    };
    const service = buildService(prisma);

    const result = await service.findAll(actor);

    expect(Array.isArray(result)).toBe(true);
    expect(result).toEqual([{ id: 'user-a' }]);
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: actor.companyId },
        skip: 0,
        take: 500,
      }),
    );
  });

  it('returns a page envelope with tenant scope for admin screens', async () => {
    const rows = Array.from({ length: 51 }, (_, index) => ({
      id: `user-${index}`,
    }));
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue(rows),
      },
    };
    const service = buildService(prisma);

    const result = await service.findAll(actor, { page: '2', limit: '50' });

    expect(result).toMatchObject({
      page: 2,
      limit: 50,
      hasMore: true,
      nextPage: 3,
    });
    expect((result as { items: unknown[] }).items).toHaveLength(50);
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: actor.companyId },
        orderBy: { createdAt: 'desc' },
        skip: 50,
        take: 51,
      }),
    );
  });
});
