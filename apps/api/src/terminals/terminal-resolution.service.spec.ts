import { BadRequestException } from "@nestjs/common";
import { TerminalResolutionService } from "./terminal-resolution.service";

function terminal(overrides: Record<string, unknown> = {}) {
  return {
    id: "terminal-main",
    companyId: "company-a",
    name: "Main POS",
    code: "MAIN-POS",
    defaultWarehouseId: "warehouse-main",
    deviceFingerprint: null,
    defaultWarehouse: {
      id: "warehouse-main",
      companyId: "company-a",
      name: "Main Warehouse",
      code: "MAIN",
      isActive: true,
    },
    ...overrides,
  };
}

describe("TerminalResolutionService", () => {
  function serviceWith(tx: any) {
    return new TerminalResolutionService(tx as never);
  }

  it("resolves legacy requests to the active default terminal warehouse", async () => {
    const tx = {
      terminal: {
        findFirst: jest.fn().mockResolvedValue(terminal()),
        findMany: jest.fn(),
      },
    };

    const result = await serviceWith(tx).resolveForSale(tx, {
      companyId: "company-a",
    });

    expect(result.resolution).toBe("default-terminal");
    expect(result.terminal.id).toBe("terminal-main");
    expect(result.warehouse.id).toBe("warehouse-main");
  });

  it("resolves an explicit active same-company terminal", async () => {
    const tx = {
      terminal: {
        findFirst: jest.fn().mockResolvedValue(terminal()),
      },
    };

    const result = await serviceWith(tx).resolveForSale(tx, {
      companyId: "company-a",
      terminalId: "terminal-main",
    });

    expect(tx.terminal.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          id: "terminal-main",
          companyId: "company-a",
          isActive: true,
        },
      }),
    );
    expect(result.resolution).toBe("explicit-terminal");
  });

  it("uses a pre-bound device fingerprint without rebinding", async () => {
    const tx = {
      terminal: {
        findMany: jest.fn().mockResolvedValue([
          terminal({ id: "terminal-bound", deviceFingerprint: "install-1" }),
        ]),
        findFirst: jest.fn(),
      },
    };

    const result = await serviceWith(tx).resolveForSale(tx, {
      companyId: "company-a",
      deviceFingerprint: "install-1",
    });

    expect(result.resolution).toBe("bound-device");
    expect(result.terminal.id).toBe("terminal-bound");
    expect(tx.terminal.findFirst).not.toHaveBeenCalled();
  });

  it("rejects inactive or cross-company terminal ids", async () => {
    const tx = {
      terminal: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
    };

    await expect(
      serviceWith(tx).resolveForSale(tx, {
        companyId: "company-a",
        terminalId: "terminal-b",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("rejects warehouse overrides that do not match terminal default", async () => {
    const tx = {
      terminal: {
        findFirst: jest.fn().mockResolvedValue(terminal()),
      },
    };

    await expect(
      serviceWith(tx).resolveForSale(tx, {
        companyId: "company-a",
        terminalId: "terminal-main",
        requestedWarehouseId: "warehouse-branch",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("does not randomly choose when there is no default and multiple terminals exist", async () => {
    const tx = {
      terminal: {
        findFirst: jest.fn().mockResolvedValue(null),
        findMany: jest
          .fn()
          .mockResolvedValue([terminal({ id: "a" }), terminal({ id: "b" })]),
      },
    };

    await expect(
      serviceWith(tx).resolveForSale(tx, {
        companyId: "company-a",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
