import { BadRequestException, Injectable } from "@nestjs/common";
import { PriceListRuleMode, Prisma } from "@prisma/client";

export type PricingTierInput = {
  id?: string;
  minQuantity: Prisma.Decimal | number | string;
  mode?: PriceListRuleMode | null;
  fixedPrice?: Prisma.Decimal | number | string | null;
  discountPercent?: Prisma.Decimal | number | string | null;
};

export type PricingRuleInput = {
  id: string;
  priceListId: string;
  priceListName: string;
  mode: PriceListRuleMode;
  fixedPrice?: Prisma.Decimal | number | string | null;
  discountPercent?: Prisma.Decimal | number | string | null;
  minQuantity: Prisma.Decimal | number | string;
  tiers?: PricingTierInput[];
};

export type ResolvedLinePrice = {
  moduleEnabled: boolean;
  applied: boolean;
  reason:
    | "MODULE_DISABLED"
    | "NO_PRICE_LIST"
    | "NO_RULE"
    | "RULE_APPLIED";
  unitPrice: Prisma.Decimal;
  originalUnitPrice: Prisma.Decimal;
  priceListId: string | null;
  priceListName: string | null;
  ruleId: string | null;
  ruleMode: PriceListRuleMode | null;
  discountPercent: Prisma.Decimal | null;
  minQuantity: Prisma.Decimal | null;
};

@Injectable()
export class PricingEngineService {
  resolveLine(input: {
    moduleEnabled: boolean;
    baseUnitPrice: Prisma.Decimal | number | string;
    quantity: Prisma.Decimal | number | string;
    rule?: PricingRuleInput | null;
  }): ResolvedLinePrice {
    const baseUnitPrice = this.decimal(input.baseUnitPrice, "precio base");
    const quantity = this.decimal(input.quantity, "cantidad");
    if (baseUnitPrice.lt(0)) {
      throw new BadRequestException("El precio base no puede ser negativo");
    }
    if (quantity.lte(0)) {
      throw new BadRequestException("La cantidad debe ser mayor que cero");
    }
    if (!input.moduleEnabled) {
      return this.unchanged("MODULE_DISABLED", baseUnitPrice);
    }
    if (!input.rule) {
      return this.unchanged("NO_RULE", baseUnitPrice);
    }

    const selected = this.selectApplicableTier(input.rule, quantity);
    if (!selected) {
      return this.unchanged("NO_RULE", baseUnitPrice);
    }

    const mode = selected.mode ?? input.rule.mode;
    const minQuantity = this.decimal(selected.minQuantity, "cantidad minima");
    const fixedPrice = selected.fixedPrice ?? input.rule.fixedPrice;
    const discountPercent = selected.discountPercent ?? input.rule.discountPercent;
    const unitPrice = this.applyRule({
      mode,
      fixedPrice,
      discountPercent,
      baseUnitPrice,
    });

    return {
      moduleEnabled: true,
      applied: true,
      reason: "RULE_APPLIED",
      unitPrice,
      originalUnitPrice: baseUnitPrice,
      priceListId: input.rule.priceListId,
      priceListName: input.rule.priceListName,
      ruleId: input.rule.id,
      ruleMode: mode,
      discountPercent:
        mode === PriceListRuleMode.PERCENT_DISCOUNT
          ? this.decimal(discountPercent ?? 0, "descuento")
          : null,
      minQuantity,
    };
  }

  private unchanged(
    reason: ResolvedLinePrice["reason"],
    baseUnitPrice: Prisma.Decimal,
  ): ResolvedLinePrice {
    return {
      moduleEnabled: reason !== "MODULE_DISABLED",
      applied: false,
      reason,
      unitPrice: baseUnitPrice,
      originalUnitPrice: baseUnitPrice,
      priceListId: null,
      priceListName: null,
      ruleId: null,
      ruleMode: null,
      discountPercent: null,
      minQuantity: null,
    };
  }

  private selectApplicableTier(rule: PricingRuleInput, quantity: Prisma.Decimal) {
    const candidates: Array<
      PricingTierInput & { mode?: PriceListRuleMode | null }
    > = [
      {
        minQuantity: rule.minQuantity,
        mode: rule.mode,
        fixedPrice: rule.fixedPrice,
        discountPercent: rule.discountPercent,
      },
      ...(rule.tiers ?? []),
    ];

    return candidates
      .filter((tier) => this.decimal(tier.minQuantity, "cantidad minima").lte(quantity))
      .sort((a, b) =>
        this.decimal(b.minQuantity, "cantidad minima").cmp(
          this.decimal(a.minQuantity, "cantidad minima"),
        ),
      )[0];
  }

  private applyRule(input: {
    mode: PriceListRuleMode;
    fixedPrice?: Prisma.Decimal | number | string | null;
    discountPercent?: Prisma.Decimal | number | string | null;
    baseUnitPrice: Prisma.Decimal;
  }) {
    if (input.mode === PriceListRuleMode.FIXED_PRICE) {
      if (input.fixedPrice == null) {
        throw new BadRequestException("La regla requiere precio fijo");
      }
      const fixedPrice = this.decimal(input.fixedPrice, "precio fijo");
      if (fixedPrice.lt(0)) {
        throw new BadRequestException("El precio fijo no puede ser negativo");
      }
      return fixedPrice.toDecimalPlaces(2);
    }

    if (input.discountPercent == null) {
      throw new BadRequestException("La regla requiere porcentaje de descuento");
    }
    const discount = this.decimal(input.discountPercent, "descuento");
    if (discount.lt(0) || discount.gt(100)) {
      throw new BadRequestException("El descuento debe estar entre 0 y 100");
    }
    return Prisma.Decimal.max(
      new Prisma.Decimal(0),
      input.baseUnitPrice.mul(new Prisma.Decimal(100).minus(discount)).div(100),
    ).toDecimalPlaces(2);
  }

  private decimal(
    value: Prisma.Decimal | number | string,
    label: string,
  ): Prisma.Decimal {
    try {
      return new Prisma.Decimal(value);
    } catch {
      throw new BadRequestException(`${label} invalido`);
    }
  }
}
