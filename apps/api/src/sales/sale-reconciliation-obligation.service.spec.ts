import { Prisma } from "@prisma/client";
import type { TenantUser } from "../auth/tenant-context";
import { SaleReconciliationObligationService } from "./sale-reconciliation-obligation.service";

/**
 * Obligaciones de conciliación: contrato y garantías.
 *
 * Lo que estas pruebas protegen por encima de todo: una declaración humana
 * NUNCA se convierte en dinero registrado. Solo abre una obligación de revisión,
 * es idempotente y queda aislada por empresa.
 */
describe("SaleReconciliationObligationService", () => {
  const companyId = "11111111-1111-4111-8111-111111111111";
  const otherCompany = "22222222-2222-4222-8222-222222222222";

  const user = {
    id: "user-1",
    companyId,
    role: "OWNER",
  } as unknown as TenantUser;

  function build(overrides: Record<string, jest.Mock> = {}) {
    const prisma = {
      saleReconciliationObligation: {
        create: jest.fn(async ({ data }: { data: Record<string, unknown> }) => ({
          id: "obl-1",
          ...data,
          totalDeclared: new Prisma.Decimal(data.totalDeclared as string),
          createdAt: new Date("2026-10-29T12:00:00.000Z"),
          resolvedAt: null,
          resolvedByUserId: null,
          resolutionNote: null,
        })),
        findFirst: jest.fn(async () => null),
        findMany: jest.fn(async () => []),
      },
      // Si algo intentara tocar ventas, caja o inventario desde aquí, la prueba
      // falla de inmediato.
      sale: {
        create: jest.fn(() => {
          throw new Error("una declaración NO puede crear ventas");
        }),
        update: jest.fn(() => {
          throw new Error("una declaración NO puede modificar ventas");
        }),
      },
      cashMovement: {
        create: jest.fn(() => {
          throw new Error("una declaración NO puede crear movimientos de caja");
        }),
      },
      ...overrides,
    } as unknown as ConstructorParameters<
      typeof SaleReconciliationObligationService
    >[0];

    return {
      prisma: prisma as unknown as {
        saleReconciliationObligation: {
          create: jest.Mock;
          findFirst: jest.Mock;
          findMany: jest.Mock;
        };
        sale: { create: jest.Mock; update: jest.Mock };
        cashMovement: { create: jest.Mock };
      },
      service: new SaleReconciliationObligationService(prisma),
    };
  }

  const dto = {
    totalDeclared: 50,
    declaredAtUtc: "2026-10-27T20:39:00.000Z",
    paymentMethod: "cash",
    note: "Cliente pagó en efectivo, no salió el ticket",
    declaredByRole: "OWNER",
  };

  it("registra la obligación con identidad, importe, usuario, hora y nota", async () => {
    const { service, prisma } = build();
    const result = await service.recordDeclaration(user, "sale_req_1", dto);

    expect(prisma.saleReconciliationObligation.create).toHaveBeenCalledTimes(1);
    const data = prisma.saleReconciliationObligation.create.mock.calls[0][0].data;
    expect(data.companyId).toBe(companyId);
    expect(data.clientRequestId).toBe("sale_req_1");
    expect(String(data.totalDeclared)).toBe("50");
    expect(data.declaredByUserId).toBe("user-1");
    expect(data.declaredByRole).toBe("OWNER");
    expect(data.note).toContain("efectivo");
    expect(data.status).toBe("PENDING");
    expect(data.declaredAtUtc).toEqual(new Date("2026-10-27T20:39:00.000Z"));
    expect(result.duplicate).toBe(false);
    expect(result.obligation.totalDeclared).toBe(50);
    // Nunca habilita repetir el cobro ni afirma que el dinero entró.
    expect(result.obligation.retryAllowed).toBe(false);
    expect(result.obligation.assertsPaymentReceived).toBe(false);
  });

  it("no toca ventas ni caja", async () => {
    const { service, prisma } = build();
    await service.recordDeclaration(user, "sale_req_2", dto);
    expect(prisma.sale.create).not.toHaveBeenCalled();
    expect(prisma.sale.update).not.toHaveBeenCalled();
    expect(prisma.cashMovement.create).not.toHaveBeenCalled();
  });

  it("es idempotente: el reenvío exacto devuelve la existente y no duplica", async () => {
    const existing = {
      id: "obl-existing",
      companyId,
      clientRequestId: "sale_req_3",
      declarationHash: "x",
      totalDeclared: new Prisma.Decimal("50"),
      paymentMethod: "cash",
      declaredAtUtc: new Date("2026-10-27T20:39:00.000Z"),
      declaredByUserId: "user-1",
      declaredByRole: "OWNER",
      note: null,
      operationFingerprint: null,
      status: "PENDING",
      createdAt: new Date("2026-10-29T12:00:00.000Z"),
      resolvedAt: null,
      resolvedByUserId: null,
      resolutionNote: null,
    };
    const { service, prisma } = build();
    prisma.saleReconciliationObligation.create.mockRejectedValueOnce(
      new Prisma.PrismaClientKnownRequestError("duplicado", {
        code: "P2002",
        clientVersion: "5.22.0",
      }),
    );
    prisma.saleReconciliationObligation.findFirst.mockResolvedValueOnce(existing);

    const result = await service.recordDeclaration(user, "sale_req_3", dto);
    expect(result.duplicate).toBe(true);
    expect(result.obligation.id).toBe("obl-existing");
  });

  it("una declaración con otro importe NO se considera duplicada", () => {
    const base = {
      companyId,
      clientRequestId: "sale_req_4",
      totalDeclared: "50.00",
      declaredAtUtc: "2026-10-27T20:39:00.000Z",
      declaredByUserId: "user-1",
      declaredByRole: "OWNER",
      note: "nota",
    };
    const a = SaleReconciliationObligationService.declarationHash(base);
    const same = SaleReconciliationObligationService.declarationHash({
      ...base,
      declaredByRole: "owner",
      note: "NOTA",
    });
    const otherTotal = SaleReconciliationObligationService.declarationHash({
      ...base,
      totalDeclared: "75.00",
    });
    const otherCompany = SaleReconciliationObligationService.declarationHash({
      ...base,
      companyId: "33333333-3333-4333-8333-333333333333",
    });
    expect(a).toMatch(/^[0-9a-f]{64}$/);
    // Normaliza mayúsculas: el mismo hecho declarado no genera otra obligación.
    expect(same).toBe(a);
    expect(otherTotal).not.toBe(a);
    expect(otherCompany).not.toBe(a);
  });

  it("siempre usa la empresa del token, nunca la del cuerpo", async () => {
    const { service, prisma } = build();
    await service.recordDeclaration(
      { ...user, companyId: otherCompany } as TenantUser,
      "sale_req_5",
      { ...dto, companyId } as never,
    );
    const data = prisma.saleReconciliationObligation.create.mock.calls[0][0].data;
    expect(data.companyId).toBe(otherCompany);
  });

  it("rechaza una operación sin empresa (aislamiento multiempresa)", async () => {
    const { service } = build();
    await expect(
      service.recordDeclaration(
        { id: "user-1", role: "OWNER" } as unknown as TenantUser,
        "sale_req_6",
        dto,
      ),
    ).rejects.toBeTruthy();
  });

  it("lista solo las obligaciones de la empresa del token", async () => {
    const { service, prisma } = build();
    await service.list(user, "pending");
    const args = prisma.saleReconciliationObligation.findMany.mock.calls[0][0];
    expect(args.where.companyId).toBe(companyId);
    expect(args.where.status).toBe("PENDING");
  });
});
