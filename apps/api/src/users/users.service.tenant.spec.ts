import { NotFoundException } from '@nestjs/common';
import { Role } from '@prisma/client';
import { UsersService } from './users.service';

function buildService(prisma: any) {
  const config = { get: jest.fn().mockReturnValue(undefined) };
  return new UsersService(prisma, config as any);
}

describe('UsersService tenant isolation', () => {
  it('rejects updating a user that is not in the request tenant', async () => {
    const prisma = {
      user: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = buildService(prisma);

    await expect(
      service.update(
        { id: 'admin-a', role: Role.ADMIN, companyId: 'company-a' },
        'user-from-company-b',
        { nombreCompleto: 'Cross tenant edit' } as any,
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        id: 'user-from-company-b',
        OR: [
          { companyId: 'company-a' },
          {
            companyMemberships: {
              some: {
                companyId: 'company-a',
                status: 'ACTIVE',
              },
            },
          },
        ],
      },
      select: { id: true },
    });
  });
});
