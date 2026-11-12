import { AuthService } from "./auth.service";

describe("AuthService logout (revocacion de sesion actual)", () => {
  function buildService(prisma: any) {
    return new AuthService(
      prisma,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
    ) as any;
  }

  it("revoca solo la sesion del token que cierra sesion", async () => {
    const updateMany = jest.fn().mockResolvedValue({ count: 1 });
    const service = buildService({ authSession: { updateMany } });

    await expect(
      service.logout({ id: "user-a", sessionId: "session-a" }),
    ).resolves.toEqual({ ok: true });

    expect(updateMany).toHaveBeenCalledTimes(1);
    expect(updateMany).toHaveBeenCalledWith({
      where: { id: "session-a", userId: "user-a", revokedAt: null },
      data: {
        revokedAt: expect.any(Date),
        revocationReason: "user_logout",
      },
    });
  });

  it("no toca sesiones de otros dispositivos (no usa tokenFamily ni userId)", async () => {
    const updateMany = jest.fn().mockResolvedValue({ count: 0 });
    const service = buildService({ authSession: { updateMany } });

    await service.logout({ id: "user-a", sessionId: "session-of-device-1" });

    const arg = updateMany.mock.calls[0][0];
    expect(arg.where).toEqual({
      id: "session-of-device-1",
      userId: "user-a",
      revokedAt: null,
    });
    expect(arg.where.tokenFamily).toBeUndefined();
    expect(arg.where.userId).toBe("user-a");
  });

  it("es idempotente y no consulta la base si falta la sesion", async () => {
    const updateMany = jest.fn();
    const service = buildService({ authSession: { updateMany } });

    await expect(service.logout({ id: "user-a" })).resolves.toEqual({
      ok: true,
    });
    await expect(
      service.logout({ id: "user-a", sessionId: "   " }),
    ).resolves.toEqual({ ok: true });

    expect(updateMany).not.toHaveBeenCalled();
  });
});
