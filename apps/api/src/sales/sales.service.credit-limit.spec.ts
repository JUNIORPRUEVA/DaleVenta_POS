import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { SalesService } from "./sales.service";

/**
 * Hardening de crédito — ENDURECIMIENTO de `creditAmount` (FASE 21).
 *
 * Contrato del POS Flutter (`cotizaciones_screen.dart`):
 *   creditAmount = (total - efectivoAbonado - transferenciaAbonada).clamp(0, total)
 *
 * El backend no debe confiar en un `creditAmount` mayor al saldo real: inflaba
 * `Sale.creditBalance` (cuenta por cobrar) y descuadraba la factura.
 */
describe("SalesService · límite del monto a crédito", () => {
  function buildService() {
    return new SalesService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );
  }

  function normalize(
    service: SalesService,
    dto: Record<string, unknown>,
    totalSold: Prisma.Decimal,
  ) {
    return (service as any).normalizeSalePayment(dto, totalSold);
  }

  it("financia exactamente el saldo real cuando el cliente no envía creditAmount", () => {
    const service = buildService();

    const payment = normalize(
      service,
      { paymentMethod: "credit" },
      new Prisma.Decimal(10000),
    );

    expect(payment.creditAmount.toString()).toBe("10000");
    expect(payment.creditBalance.toString()).toBe("10000");
    expect(payment.paymentCashAmount.toString()).toBe("0");
  });

  it("financia el saldo real menos el abono inicial (contrato del POS)", () => {
    const service = buildService();

    const payment = normalize(
      service,
      {
        paymentMethod: "credit",
        paymentCashAmount: 4000,
        creditAmount: 6000,
      },
      new Prisma.Decimal(10000),
    );

    expect(payment.paymentCashAmount.toString()).toBe("4000");
    expect(payment.creditAmount.toString()).toBe("6000");
    expect(payment.creditBalance.toString()).toBe("6000");
  });

  it("rechaza un creditAmount mayor al saldo pendiente de la factura", () => {
    const service = buildService();

    expect(() =>
      normalize(
        service,
        {
          paymentMethod: "credit",
          paymentCashAmount: 4000,
          creditAmount: 9000,
        },
        new Prisma.Decimal(10000),
      ),
    ).toThrow(BadRequestException);
  });

  it("ignora un creditAmount menor al saldo real (nunca subfinancia al cliente)", () => {
    const service = buildService();

    const payment = normalize(
      service,
      { paymentMethod: "credit", creditAmount: 500 },
      new Prisma.Decimal(10000),
    );

    expect(payment.creditAmount.toString()).toBe("10000");
  });

  it("acepta el borde exacto del saldo y rechaza un centavo por encima", () => {
    const service = buildService();

    const exact = normalize(
      service,
      { paymentMethod: "credit", paymentCashAmount: 4000, creditAmount: 6000 },
      new Prisma.Decimal(10000),
    );
    expect(exact.creditAmount.toString()).toBe("6000");
    expect(exact.creditBalance.toString()).toBe("6000");

    expect(() =>
      normalize(
        service,
        {
          paymentMethod: "credit",
          paymentCashAmount: 4000,
          creditAmount: 6000.01,
        },
        new Prisma.Decimal(10000),
      ),
    ).toThrow(BadRequestException);
  });

  it("no crea crédito cuando el método no es credit", () => {
    const service = buildService();

    const payment = normalize(
      service,
      { paymentMethod: "cash", creditAmount: 5000 },
      new Prisma.Decimal(10000),
    );

    expect(payment.creditAmount.toString()).toBe("0");
    expect(payment.creditBalance.toString()).toBe("0");
  });
});
