import { PriceListRuleMode, Prisma } from "@prisma/client";
import { PricingEngineService } from "./pricing-engine.service";

describe("PricingEngineService", () => {
  const service = new PricingEngineService();

  it("keeps the base price when the module is disabled", () => {
    const result = service.resolveLine({
      moduleEnabled: false,
      baseUnitPrice: 100,
      quantity: 10,
      rule: {
        id: "rule-1",
        priceListId: "list-1",
        priceListName: "Mayorista",
        mode: PriceListRuleMode.PERCENT_DISCOUNT,
        discountPercent: 20,
        minQuantity: 1,
      },
    });

    expect(result.applied).toBe(false);
    expect(result.reason).toBe("MODULE_DISABLED");
    expect(result.unitPrice.toNumber()).toBe(100);
  });

  it("applies a percentage discount rule", () => {
    const result = service.resolveLine({
      moduleEnabled: true,
      baseUnitPrice: 200,
      quantity: 2,
      rule: {
        id: "rule-1",
        priceListId: "list-1",
        priceListName: "Mayorista",
        mode: PriceListRuleMode.PERCENT_DISCOUNT,
        discountPercent: 15,
        minQuantity: 1,
      },
    });

    expect(result.applied).toBe(true);
    expect(result.unitPrice.toNumber()).toBe(170);
    expect(result.originalUnitPrice.toNumber()).toBe(200);
    expect(result.ruleMode).toBe(PriceListRuleMode.PERCENT_DISCOUNT);
  });

  it("applies a fixed price rule", () => {
    const result = service.resolveLine({
      moduleEnabled: true,
      baseUnitPrice: new Prisma.Decimal("99.99"),
      quantity: 1,
      rule: {
        id: "rule-1",
        priceListId: "list-1",
        priceListName: "Especial",
        mode: PriceListRuleMode.FIXED_PRICE,
        fixedPrice: 75,
        minQuantity: 1,
      },
    });

    expect(result.applied).toBe(true);
    expect(result.unitPrice.toNumber()).toBe(75);
  });

  it("uses the highest applicable quantity tier", () => {
    const result = service.resolveLine({
      moduleEnabled: true,
      baseUnitPrice: 100,
      quantity: 12,
      rule: {
        id: "rule-1",
        priceListId: "list-1",
        priceListName: "Escalas",
        mode: PriceListRuleMode.PERCENT_DISCOUNT,
        discountPercent: 5,
        minQuantity: 1,
        tiers: [
          { minQuantity: 5, discountPercent: 10 },
          { minQuantity: 10, discountPercent: 25 },
        ],
      },
    });

    expect(result.applied).toBe(true);
    expect(result.unitPrice.toNumber()).toBe(75);
    expect(result.minQuantity?.toNumber()).toBe(10);
  });
});
