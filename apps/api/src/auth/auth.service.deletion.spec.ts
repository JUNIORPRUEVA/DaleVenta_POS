import { BadRequestException, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';
import { CompanyMemberRole, CompanyMemberStatus } from '@prisma/client';

function buildService(prisma: any, r2: any = { deleteAllCompanyObjects: jest.fn().mockResolvedValue({ ok: true }) }) {
  const jwt = { signAsync: jest.fn(), verifyAsync: jest.fn() };
  const config = { get: jest.fn().mockReturnValue(undefined) };
  return new AuthService(prisma, jwt as any, config as any, r2);
}

describe('AuthService account deletion', () => {
  const companyId = '11111111-1111-4111-8111-111111111111';
  const userId = '22222222-2222-4222-8222-222222222222';

  it('rejects account deletion when password is wrong', async () => {
    const passwordHash = await bcrypt.hash('correct-password', 4);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: userId,
          email: 'u@example.com',
          passwordHash,
          companyId,
          companyMemberships: [
            { id: 'm1', companyId, role: CompanyMemberRole.CASHIER, status: CompanyMemberStatus.ACTIVE },
          ],
        }),
      },
      companyMember: { findMany: jest.fn(), count: jest.fn() },
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(service.deleteAccount(userId, companyId, { password: 'bad' })).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('requires DELETE MY COMPANY for sole-owner company deletion', async () => {
    const passwordHash = await bcrypt.hash('correct-password', 4);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: userId,
          email: 'u@example.com',
          passwordHash,
          companyId,
          companyMemberships: [
            { id: 'm1', companyId, role: CompanyMemberRole.OWNER, status: CompanyMemberStatus.ACTIVE },
          ],
        }),
      },
      companyMember: {
        findMany: jest.fn().mockResolvedValue([{ companyId }]),
        count: jest.fn().mockResolvedValue(1),
      },
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(service.deleteAccount(userId, companyId, { password: 'correct-password' })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects account deletion when the active user is not the company owner', async () => {
    const passwordHash = await bcrypt.hash('correct-password', 4);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: userId,
          email: 'u@example.com',
          passwordHash,
          companyId,
          companyMemberships: [
            { id: 'm1', companyId, role: CompanyMemberRole.CASHIER, status: CompanyMemberStatus.ACTIVE },
          ],
        }),
      },
      companyMember: {
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
      },
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(service.deleteAccount(userId, companyId, { password: 'correct-password' })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('cleans storage and revokes company sessions during sole-owner deletion', async () => {
    const passwordHash = await bcrypt.hash('correct-password', 4);
    const r2 = { deleteAllCompanyObjects: jest.fn().mockResolvedValue({ ok: true, deleted: 3 }) };
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([]),
      companyMember: { deleteMany: jest.fn().mockResolvedValue({ count: 1 }), updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      company: { delete: jest.fn().mockResolvedValue({ id: companyId }) },
      authSession: { updateMany: jest.fn().mockResolvedValue({ count: 4 }) },
      user: { update: jest.fn().mockResolvedValue({ id: userId }) },
    };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: userId,
          email: 'u@example.com',
          passwordHash,
          companyId,
          companyMemberships: [
            { id: 'm1', companyId, role: CompanyMemberRole.OWNER, status: CompanyMemberStatus.ACTIVE },
          ],
        }),
      },
      companyMember: {
        findMany: jest.fn().mockResolvedValue([{ companyId }]),
        count: jest.fn().mockResolvedValue(1),
      },
      $transaction: jest.fn(async (callback: any) => callback(tx)),
    };
    const service = buildService(prisma, r2);

    const result = await service.deleteAccount(userId, companyId, {
      password: 'correct-password',
      confirmationPhrase: 'DELETE MY COMPANY',
    });

    expect(result.companyDeleted).toBe(true);
    expect(r2.deleteAllCompanyObjects).toHaveBeenCalledWith(companyId);
    expect(tx.authSession.updateMany).toHaveBeenCalledWith({
      where: { companyId, revokedAt: null },
      data: { revokedAt: expect.any(Date), revocationReason: 'company_deleted' },
    });
  });
});
