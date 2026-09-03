import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import {
  deriveCashTenderChange,
  type CashTenderInput,
} from "./cash-change.util";

function dec(value: number | string): Prisma.Decimal {
  return new Prisma.Decimal(value);
}

function call(input: Omit<CashTenderInput, "paymentCashAmount"> & {
  paymentCashAmount?: Prisma.Decimal;
}) {
  return deriveCashTenderChange({
    cashReceived: input.cashReceived,
    changeAmount: input.changeAmount,
    paymentCashAmount: input.paymentCashAmount ?? dec(0),
  });
}

describe("deriveCashTenderChange (TICKET-CASH-CHANGE-02)", () => {
  it("cash over-tender: total 850, received 1000 => change 150, net 850", () => {
    const r = call({ cashReceived: 1000, paymentCashAmount: dec(850) });
    expect(Number(r.cashReceived)).toBeCloseTo(1000, 2);
    expect(Number(r.changeAmount)).toBeCloseTo(150, 2);
  });

  it("exact cash: 850/850 => change 0", () => {
    const r = call({ cashReceived: 850, paymentCashAmount: dec(850) });
    expect(Number(r.cashReceived)).toBeCloseTo(850, 2);
    expect(Number(r.changeAmount)).toBe(0);
  });

  it("decimal: total 999.99, received 1000 => change 0.01", () => {
    const r = call({ cashReceived: 1000, paymentCashAmount: dec("999.99") });
    expect(Number(r.changeAmount)).toBeCloseTo(0.01, 2);
    // No floating point artifact (0.010000000000000009).
    expect(Number(r.changeAmount)).toBe(0.01);
  });

  it("transfer-only: no cash tender => cashReceived 0 / change 0", () => {
    const r = call({ cashReceived: 0, paymentCashAmount: dec(0) });
    expect(Number(r.cashReceived)).toBe(0);
    expect(Number(r.changeAmount)).toBe(0);
  });

  it("legacy sale without tender data => NULL (never fabricated)", () => {
    const r = call({ cashReceived: undefined, paymentCashAmount: dec(850) });
    expect(r.cashReceived).toBeNull();
    expect(r.changeAmount).toBeNull();
  });

  it("validates a client-provided change that matches the derived value", () => {
    const r = call({
      cashReceived: 1000,
      changeAmount: 150,
      paymentCashAmount: dec(850),
    });
    expect(Number(r.changeAmount)).toBe(150);
  });

  it("rejects impossible negative tender", () => {
    expect(() => call({ cashReceived: -1, paymentCashAmount: dec(850) })).toThrow(
      BadRequestException,
    );
  });

  it("rejects impossible negative change", () => {
    expect(() =>
      call({ cashReceived: 1000, changeAmount: -1, paymentCashAmount: dec(850) }),
    ).toThrow(BadRequestException);
  });

  it("rejects change greater than cash received", () => {
    expect(() =>
      call({ cashReceived: 1000, changeAmount: 1100, paymentCashAmount: dec(850) }),
    ).toThrow(BadRequestException);
  });

  it("rejects change that does not match received/net relationship", () => {
    expect(() =>
      call({ cashReceived: 1000, changeAmount: 100, paymentCashAmount: dec(850) }),
    ).toThrow(BadRequestException);
  });

  it("rejects cash received lower than net cash applied", () => {
    expect(() => call({ cashReceived: 800, paymentCashAmount: dec(850) })).toThrow(
      BadRequestException,
    );
  });

  it("keeps net invariant: received - change === paymentCashAmount", () => {
    const r = call({ cashReceived: 1000, paymentCashAmount: dec(850) });
    const net = (r.cashReceived as Prisma.Decimal).minus(
      r.changeAmount as Prisma.Decimal,
    );
    expect(net.toNumber()).toBeCloseTo(850, 2);
  });
});
