import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import {
  DEFAULT_UNIT_OF_MEASURE,
  unitSnapshotFields,
  validateQuantityForUnit,
} from "./unit-of-measure.util";

describe("unit-of-measure quantity validation", () => {
  const yard = {
    code: "YARD",
    name: "Yarda",
    symbol: "yd",
    allowDecimals: true,
    precision: 3,
  };

  it("keeps existing UNIT integer quantities valid", () => {
    expect(() =>
      validateQuantityForUnit({
        quantity: new Prisma.Decimal("2"),
        unit: DEFAULT_UNIT_OF_MEASURE,
        label: "item #1",
      }),
    ).not.toThrow();
  });

  it("rejects decimal quantities for UNIT", () => {
    expect(() =>
      validateQuantityForUnit({
        quantity: new Prisma.Decimal("1.5"),
        unit: DEFAULT_UNIT_OF_MEASURE,
        label: "item #1",
      }),
    ).toThrow(BadRequestException);
  });

  it("accepts configured decimal precision without floating-point tolerance", () => {
    const quantity = new Prisma.Decimal("2.375");
    validateQuantityForUnit({ quantity, unit: yard, label: "item #1" });
    expect(quantity.toString()).toBe("2.375");
  });

  it("rejects quantities beyond the configured precision", () => {
    expect(() =>
      validateQuantityForUnit({
        quantity: new Prisma.Decimal("2.3759"),
        unit: yard,
        label: "item #1",
      }),
    ).toThrow(BadRequestException);
  });

  it("creates immutable transaction snapshot fields", () => {
    expect(unitSnapshotFields(yard)).toEqual({
      unitCodeSnapshot: "YARD",
      unitNameSnapshot: "Yarda",
      unitSymbolSnapshot: "yd",
      unitPrecisionSnapshot: 3,
    });
  });
});
