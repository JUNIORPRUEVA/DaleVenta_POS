import { BadRequestException } from "@nestjs/common";
import * as bcrypt from "bcryptjs";
import { CompanyMemberRole, CompanyMemberStatus } from "@prisma/client";
import { AuthService } from "./auth.service";

const companyId = "11111111-1111-4111-8111-111111111111";
const otherCompanyId = "22222222-2222-4222-8222-222222222222";
const userId = "33333333-3333-4333-8333-333333333333";

function buildService(prisma: any, emailService?: any) {
  const config = {
    get: jest.fn((key: string) => {
      if (key === "PASSWORD_RESET_URL_BASE") return "https://app.test";
      return undefined;
    }),
  };
  const redis = { isEnabled: jest.fn().mockReturnValue(false) };
  const mailer = emailService ?? {
    sendPasswordResetEmail: jest
      .fn()
      .mockResolvedValue({ sent: true, provider: "test" }),
  };
  return {
    service: new AuthService(
      prisma,
      {} as any,
      config as any,
      {} as any,
      {} as any,
      redis as any,
      mailer as any,
    ) as any,
    mailer,
  };
}

function ownerUser() {
  return {
    id: userId,
    email: "owner@test.local",
    blocked: false,
    companyId,
    companyMemberships: [{ companyId }],
  };
}

function prismaForForgot(user: any) {
  const tx = {
    passwordResetToken: {
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      create: jest.fn().mockResolvedValue({ id: "token-row" }),
    },
  };
  return {
    user: { findUnique: jest.fn().mockResolvedValue(user) },
    passwordResetAuditLog: { create: jest.fn().mockResolvedValue({}) },
    $transaction: jest.fn((callback: any) => callback(tx)),
    tx,
  };
}

function resetTokenRow(overrides: Record<string, unknown> = {}) {
  return {
    id: "reset-row",
    userId,
    companyId,
    tokenHash: "hash",
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    usedAt: null,
    revokedAt: null,
    user: {
      id: userId,
      email: "owner@test.local",
      blocked: false,
      companyMemberships: [{ companyId }],
    },
    ...overrides,
  };
}

function prismaForReset(row: any, updateCount = 1) {
  let passwordHash = "";
  const tx = {
    passwordResetToken: {
      updateMany: jest.fn().mockResolvedValue({ count: updateCount }),
    },
    user: {
      update: jest.fn(async ({ data }: any) => {
        passwordHash = data.passwordHash;
        return { id: userId };
      }),
    },
    authSession: {
      updateMany: jest.fn().mockResolvedValue({ count: 2 }),
    },
  };
  return {
    passwordResetToken: {
      findUnique: jest.fn().mockResolvedValue(row),
    },
    passwordResetAuditLog: { create: jest.fn().mockResolvedValue({}) },
    $transaction: jest.fn((callback: any) => callback(tx)),
    tx,
    get passwordHash() {
      return passwordHash;
    },
  };
}

describe("AuthService password reset", () => {
  it("OWNER válido solicita recuperación y recibe correo", async () => {
    const prisma = prismaForForgot(ownerUser());
    const { service, mailer } = buildService(prisma);

    const response = await service.forgotPassword("OWNER@Test.Local", {
      ipAddress: "10.0.0.1",
      userAgent: "jest",
    });

    expect(response.ok).toBe(true);
    expect(prisma.tx.passwordResetToken.updateMany).toHaveBeenCalledWith({
      where: {
        userId,
        usedAt: null,
        revokedAt: null,
      },
      data: {
        revokedAt: expect.any(Date),
        revocationReason: "superseded",
      },
    });
    expect(prisma.tx.passwordResetToken.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId,
        companyId,
        tokenHash: expect.any(String),
        expiresAt: expect.any(Date),
        requestedIp: "10.0.0.1",
        requestedUserAgent: "jest",
      }),
    });
    expect(mailer.sendPasswordResetEmail).toHaveBeenCalledWith({
      to: "owner@test.local",
      resetUrl: expect.stringContaining(
        "https://app.test/reset-password?token=",
      ),
    });
  });

  it("usuario interno no recibe recuperación", async () => {
    const prisma = prismaForForgot({
      ...ownerUser(),
      companyMemberships: [],
    });
    const { service, mailer } = buildService(prisma);

    const response = await service.forgotPassword("cashier@test.local");

    expect(response.ok).toBe(true);
    expect(mailer.sendPasswordResetEmail).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("correo inexistente devuelve respuesta neutra", async () => {
    const prisma = prismaForForgot(null);
    const { service, mailer } = buildService(prisma);

    const response = await service.forgotPassword("missing@test.local");

    expect(response.ok).toBe(true);
    expect(response.message).toContain("Si tu cuenta permite recuperación");
    expect(mailer.sendPasswordResetEmail).not.toHaveBeenCalled();
  });

  it("token válido actualiza contraseña, invalida token y revoca sesiones", async () => {
    const prisma = prismaForReset(resetTokenRow());
    const { service } = buildService(prisma);

    await expect(
      service.resetPassword("valid-token", "new-password-123", {
        ipAddress: "10.0.0.2",
        userAgent: "jest-reset",
      }),
    ).resolves.toEqual({ ok: true });

    expect(prisma.tx.passwordResetToken.updateMany).toHaveBeenCalledWith({
      where: {
        id: "reset-row",
        usedAt: null,
        revokedAt: null,
        expiresAt: { gt: expect.any(Date) },
      },
      data: {
        usedAt: expect.any(Date),
        usedIp: "10.0.0.2",
        usedUserAgent: "jest-reset",
      },
    });
    expect(await bcrypt.compare("new-password-123", prisma.passwordHash)).toBe(
      true,
    );
    expect(await bcrypt.compare("old-password-123", prisma.passwordHash)).toBe(
      false,
    );
    expect(prisma.tx.authSession.updateMany).toHaveBeenCalledWith({
      where: { userId, revokedAt: null },
      data: {
        revokedAt: expect.any(Date),
        revocationReason: "password_reset",
      },
    });
  });

  it("token expirado se rechaza", async () => {
    const prisma = prismaForReset(
      resetTokenRow({ expiresAt: new Date(Date.now() - 1000) }),
    );
    const { service } = buildService(prisma);

    await expect(
      service.resetPassword("expired-token", "new-password-123"),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("token utilizado se rechaza", async () => {
    const prisma = prismaForReset(resetTokenRow({ usedAt: new Date() }));
    const { service } = buildService(prisma);

    await expect(
      service.resetPassword("used-token", "new-password-123"),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("token incorrecto se rechaza", async () => {
    const prisma = prismaForReset(null);
    const { service } = buildService(prisma);

    await expect(
      service.resetPassword("wrong-token", "new-password-123"),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("reutilización concurrente es imposible", async () => {
    const prisma = prismaForReset(resetTokenRow(), 0);
    const { service } = buildService(prisma);

    await expect(
      service.resetPassword("valid-token", "new-password-123"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("mantiene aislamiento multiempresa al revalidar OWNER del token", async () => {
    const prisma = prismaForReset(
      resetTokenRow({
        companyId: otherCompanyId,
        user: {
          id: userId,
          email: "owner@test.local",
          blocked: false,
          companyMemberships: [
            {
              companyId,
              role: CompanyMemberRole.OWNER,
              status: CompanyMemberStatus.ACTIVE,
            },
          ],
        },
      }),
    );
    const { service } = buildService(prisma);

    await expect(
      service.resetPassword("cross-company-token", "new-password-123"),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});
