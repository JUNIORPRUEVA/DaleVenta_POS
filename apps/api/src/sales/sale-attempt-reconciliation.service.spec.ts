import { BadRequestException } from "@nestjs/common";
import type { TenantUser } from "../auth/tenant-context";
import type { PrismaService } from "../prisma/prisma.service";
import { SaleAttemptReconciliationService } from "./sale-attempt-reconciliation.service";

const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const OTHER_COMPANY_ID = "bbbbbbbb-0000-4000-8000-000000000002";
const REQUEST_ID = "3f2c1b90-8b1e-4b39-9b0e-6c2f5d7a1e44";

const user = {
  id: "user-cajera",
  companyId: COMPANY_ID,
  role: "CAJERO",
} as unknown as TenantUser;

function buildHarness() {
  const saleFindFirst = jest.fn();
  const movementFindFirst = jest.fn();
  const writes = {
    saleCreate: jest.fn(),
    saleUpdate: jest.fn(),
    saleDelete: jest.fn(),
    movementCreate: jest.fn(),
    movementUpdate: jest.fn(),
  };
  const prisma = {
    sale: {
      findFirst: saleFindFirst,
      create: writes.saleCreate,
      update: writes.saleUpdate,
      delete: writes.saleDelete,
    },
    cashMovement: {
      findFirst: movementFindFirst,
      create: writes.movementCreate,
      update: writes.movementUpdate,
    },
  } as unknown as PrismaService;
  const service = new SaleAttemptReconciliationService(prisma);
  return { service, saleFindFirst, movementFindFirst, writes };
}

const confirmedSale = {
  id: "sale-1",
  saleDate: new Date("2026-10-07T21:26:17.439Z"),
  totalSold: "1305.00",
  paymentMethod: "cash",
  status: "PAID",
  kind: "invoice",
  isDeleted: false,
  cancelledAt: null as Date | null,
  cashSessionId: "session-1",
  terminalNameSnapshot: "Default Terminal",
};

describe("SaleAttemptReconciliationService", () => {
  it("CONFIRMED cuando la venta existe y está viva", async () => {
    const { service, saleFindFirst, movementFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue(confirmedSale);

    const result = await service.reconcile(user, REQUEST_ID, "1305.00");

    expect(result.status).toBe("CONFIRMED");
    expect(result.guidance).toBe("ALREADY_REGISTERED");
    expect(result.retryAllowed).toBe(false);
    expect(result.assertsPaymentReceived).toBe(false);
    expect(result.voided).toBe(false);
    expect(result.matchesExpected).toBe(true);
    expect(result.recordedTotalSold).toBe(1305);
    expect(result.sale?.id).toBe("sale-1");
    expect(result.sale?.paymentMethod).toBe("cash");
    // Con venta encontrada no hace falta mirar movimientos.
    expect(movementFindFirst).not.toHaveBeenCalled();
  });

  it("busca siempre dentro de la empresa del token", async () => {
    const { service, saleFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue(confirmedSale);

    await service.reconcile(user, REQUEST_ID);

    expect(saleFindFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: COMPANY_ID, clientRequestId: REQUEST_ID },
      }),
    );
    expect(saleFindFirst).not.toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: OTHER_COMPANY_ID }),
      }),
    );
  });

  it("CONFIRMED y marcar anulada cuando la venta fue borrada: el registro ocurrió", async () => {
    const { service, saleFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue({ ...confirmedSale, isDeleted: true });

    const result = await service.reconcile(user, REQUEST_ID);

    // Borrar la fila NO convierte el cobro en rechazado: se registró una vez.
    expect(result.status).toBe("CONFIRMED");
    expect(result.guidance).toBe("REGISTERED_THEN_VOIDED");
    expect(result.voided).toBe(true);
    expect(result.voidReason).toBe("DELETED");
    expect(result.retryAllowed).toBe(false);
  });

  it("CONFIRMED y marcar anulada cuando la venta fue cancelada", async () => {
    const { service, saleFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue({
      ...confirmedSale,
      cancelledAt: new Date("2026-10-08T10:00:00.000Z"),
    });

    const result = await service.reconcile(user, REQUEST_ID);

    expect(result.status).toBe("CONFIRMED");
    expect(result.voided).toBe(true);
    expect(result.voidReason).toBe("CANCELLED");
    expect(result.sale?.cancelledAt).toBe("2026-10-08T10:00:00.000Z");
  });

  it("NOT_FOUND cuando no hay venta ni movimiento, sin autorizar reintento", async () => {
    const { service, saleFindFirst, movementFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue(null);
    movementFindFirst.mockResolvedValue(null);

    const result = await service.reconcile(user, REQUEST_ID, "500.00");

    expect(result.status).toBe("NOT_FOUND");
    expect(result.guidance).toBe("NOT_REGISTERED");
    expect(result.retryAllowed).toBe(false);
    expect(result.sale).toBeNull();
    expect(result.movement).toBeNull();
    expect(result.matchesExpected).toBeNull();
  });

  it("UNKNOWN cuando solo hay un movimiento con ese identificador: no es una venta", async () => {
    const { service, saleFindFirst, movementFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue(null);
    movementFindFirst.mockResolvedValue({
      id: "mov-1",
      type: "expense",
      amount: "75.00",
      createdAt: new Date("2026-10-07T21:00:00.000Z"),
    });

    const result = await service.reconcile(user, REQUEST_ID);

    expect(result.status).toBe("UNKNOWN");
    expect(result.guidance).toBe("INCONCLUSIVE");
    expect(result.retryAllowed).toBe(false);
    expect(result.movement?.id).toBe("mov-1");
    expect(movementFindFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: COMPANY_ID, operationId: REQUEST_ID },
      }),
    );
  });

  it("marca el importe como distinto cuando no coincide con lo esperado", async () => {
    const { service, saleFindFirst } = buildHarness();
    saleFindFirst.mockResolvedValue(confirmedSale);

    const result = await service.reconcile(user, REQUEST_ID, "1200.00");

    expect(result.status).toBe("CONFIRMED");
    expect(result.matchesExpected).toBe(false);
    expect(result.expectedTotalSold).toBe(1200);
    expect(result.recordedTotalSold).toBe(1305);
  });

  it("no escribe absolutamente nada", async () => {
    const { service, saleFindFirst, movementFindFirst, writes } =
      buildHarness();
    saleFindFirst.mockResolvedValue(confirmedSale);

    await service.reconcile(user, REQUEST_ID, "1305.00");

    saleFindFirst.mockResolvedValue(null);
    movementFindFirst.mockResolvedValue(null);
    await service.reconcile(user, REQUEST_ID);

    for (const spy of Object.values(writes)) {
      expect(spy).not.toHaveBeenCalled();
    }
  });

  it("rechaza un identificador vacío o desmedido", async () => {
    const { service, saleFindFirst } = buildHarness();

    await expect(service.reconcile(user, "   ")).rejects.toBeInstanceOf(
      BadRequestException,
    );
    await expect(
      service.reconcile(user, "x".repeat(201)),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(saleFindFirst).not.toHaveBeenCalled();
  });

  it("rechaza cuando el token no trae empresa", async () => {
    const { service } = buildHarness();
    const sinEmpresa = { id: "user-1" } as unknown as TenantUser;

    await expect(service.reconcile(sinEmpresa, REQUEST_ID)).rejects.toThrow();
  });
});
