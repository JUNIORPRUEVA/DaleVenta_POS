import { BadRequestException, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";

export type TaxPriceMode = "NO_TAX" | "TAX_ADDED" | "TAX_INCLUDED";
export type TaxTreatment = "INHERIT" | "TAXABLE" | "EXEMPT";

export interface TaxCalculationLineInput {
  description: string;
  quantity: number | string | Prisma.Decimal;
  unitPrice: number | string | Prisma.Decimal;
  discountAmount?: number | string | Prisma.Decimal;
  taxTreatment?: TaxTreatment;
  taxRate?: number | string | Prisma.Decimal;
  priceMode?: TaxPriceMode;
}

export interface TaxCalculationInput {
  taxEnabled: boolean;
  defaultTaxRate?: number | string | Prisma.Decimal;
  defaultPriceMode?: TaxPriceMode;
  globalDiscountAmount?: number | string | Prisma.Decimal;
  lines: TaxCalculationLineInput[];
}

export interface TaxCalculationLineResult {
  index: number;
  description: string;
  quantity: Prisma.Decimal;
  unitPrice: Prisma.Decimal;
  grossAmount: Prisma.Decimal;
  discountAmount: Prisma.Decimal;
  taxableBase: Prisma.Decimal;
  taxRate: Prisma.Decimal;
  taxAmount: Prisma.Decimal;
  exemptAmount: Prisma.Decimal;
  lineTotal: Prisma.Decimal;
  taxIncluded: boolean;
  taxExempt: boolean;
  roundingAdjustment: Prisma.Decimal;
}

export interface TaxCalculationResult {
  lines: TaxCalculationLineResult[];
  subtotal: Prisma.Decimal;
  discountAmount: Prisma.Decimal;
  taxableBase: Prisma.Decimal;
  taxAmount: Prisma.Decimal;
  exemptAmount: Prisma.Decimal;
  total: Prisma.Decimal;
}

type MutableLine = TaxCalculationLineResult & {
  exactBase: Prisma.Decimal;
  exactTax: Prisma.Decimal;
  rateKey: string;
  baseRemainder: Prisma.Decimal;
};

@Injectable()
export class TaxCalculationService {
  calculate(input: TaxCalculationInput): TaxCalculationResult {
    if (!input.lines.length) {
      throw new BadRequestException("La factura requiere al menos una linea.");
    }

    const defaultRate = this.rate(input.defaultTaxRate ?? 0);
    const defaultPriceMode = input.defaultPriceMode ?? "NO_TAX";
    const taxEnabled = input.taxEnabled === true;
    const grossLines = input.lines.map((line, index) => {
      const quantity = this.quantity(line.quantity);
      const unitPrice = this.money(line.unitPrice);
      if (quantity.lte(0)) {
        throw new BadRequestException(`Cantidad invalida en linea #${index + 1}.`);
      }
      if (unitPrice.lt(0)) {
        throw new BadRequestException(`Precio invalido en linea #${index + 1}.`);
      }
      const grossAmount = quantity.mul(unitPrice);
      const lineDiscount = Prisma.Decimal.min(
        Prisma.Decimal.max(this.money(line.discountAmount ?? 0), new Prisma.Decimal(0)),
        grossAmount,
      );
      const netBeforeGlobalDiscount = grossAmount.minus(lineDiscount);
      return { line, index, quantity, unitPrice, grossAmount, lineDiscount, netBeforeGlobalDiscount };
    });

    const subtotal = grossLines.reduce(
      (sum, entry) => sum.plus(entry.grossAmount),
      new Prisma.Decimal(0),
    );
    const globalDiscountBase = grossLines.reduce(
      (sum, entry) => sum.plus(entry.netBeforeGlobalDiscount),
      new Prisma.Decimal(0),
    );
    const requestedGlobalDiscount = this.money(input.globalDiscountAmount ?? 0);
    const globalDiscount = Prisma.Decimal.min(
      Prisma.Decimal.max(requestedGlobalDiscount, new Prisma.Decimal(0)),
      globalDiscountBase,
    );

    const discountedLines = grossLines.map((entry) => {
      const proportionalGlobalDiscount = globalDiscountBase.gt(0)
        ? entry.netBeforeGlobalDiscount.div(globalDiscountBase).mul(globalDiscount)
        : new Prisma.Decimal(0);
      const discountAmount = entry.lineDiscount.plus(proportionalGlobalDiscount);
      const netAmount = entry.grossAmount.minus(discountAmount);

      return {
        line: entry.line,
        index: entry.index,
        quantity: entry.quantity,
        unitPrice: entry.unitPrice,
        grossAmount: entry.grossAmount,
        discountAmount,
        netAmount,
      };
    });

    const mutable = discountedLines.map((entry): MutableLine => {
      const treatment = entry.line.taxTreatment ?? "INHERIT";
      const priceMode = taxEnabled ? entry.line.priceMode ?? defaultPriceMode : "NO_TAX";
      const rate = taxEnabled ? this.rate(entry.line.taxRate ?? defaultRate) : new Prisma.Decimal(0);
      const taxExempt = !taxEnabled || treatment === "EXEMPT" || rate.lte(0) || priceMode === "NO_TAX";
      const taxIncluded = !taxExempt && priceMode === "TAX_INCLUDED";
      const rateKey = rate.toFixed(6);

      let exactBase = new Prisma.Decimal(0);
      let exactTax = new Prisma.Decimal(0);
      let exemptAmount = new Prisma.Decimal(0);
      let lineTotal = entry.netAmount;

      if (taxExempt) {
        exemptAmount = entry.netAmount;
      } else if (taxIncluded) {
        exactBase = entry.netAmount.div(new Prisma.Decimal(1).plus(rate));
        exactTax = entry.netAmount.minus(exactBase);
      } else {
        exactBase = entry.netAmount;
        exactTax = exactBase.mul(rate);
        lineTotal = exactBase.plus(exactTax);
      }

      const taxableBase = this.roundMoney(exactBase);
      const taxAmount = this.roundMoney(exactTax);

      return {
        index: entry.index,
        description: entry.line.description,
        quantity: entry.quantity,
        unitPrice: entry.unitPrice,
        grossAmount: this.roundMoney(entry.grossAmount),
        discountAmount: this.roundMoney(entry.discountAmount),
        taxableBase,
        taxRate: rate,
        taxAmount,
        exemptAmount: this.roundMoney(exemptAmount),
        lineTotal: this.roundMoney(lineTotal),
        taxIncluded,
        taxExempt,
        roundingAdjustment: new Prisma.Decimal(0),
        exactBase,
        exactTax,
        rateKey,
        baseRemainder: exactBase.minus(taxableBase),
      };
    });

    this.allocateIncludedTaxRemainders(mutable);

    const lines = mutable.map(({ exactBase, exactTax, rateKey, baseRemainder, ...line }) => line);
    const totals = lines.reduce(
      (acc, line) => ({
        taxableBase: acc.taxableBase.plus(line.taxableBase),
        taxAmount: acc.taxAmount.plus(line.taxAmount),
        exemptAmount: acc.exemptAmount.plus(line.exemptAmount),
        total: acc.total.plus(line.lineTotal),
        discountAmount: acc.discountAmount.plus(line.discountAmount),
      }),
      {
        taxableBase: new Prisma.Decimal(0),
        taxAmount: new Prisma.Decimal(0),
        exemptAmount: new Prisma.Decimal(0),
        total: new Prisma.Decimal(0),
        discountAmount: new Prisma.Decimal(0),
      },
    );

    return {
      lines,
      subtotal: this.roundMoney(subtotal),
      discountAmount: this.roundMoney(totals.discountAmount),
      taxableBase: this.roundMoney(totals.taxableBase),
      taxAmount: this.roundMoney(totals.taxAmount),
      exemptAmount: this.roundMoney(totals.exemptAmount),
      total: this.roundMoney(totals.total),
    };
  }

  validateFiscalCustomer(params: {
    voucherType?: string | null;
    customerTaxId?: string | null;
    customerBusinessName?: string | null;
  }) {
    const type = (params.voucherType ?? "").trim().toUpperCase();
    const requiresCustomer = new Set(["B01", "B14", "B15"]).has(type);
    if (!requiresCustomer) return;

    if (!(params.customerTaxId ?? "").trim() || !(params.customerBusinessName ?? "").trim()) {
      throw new BadRequestException(
        "El comprobante fiscal seleccionado requiere RNC/cédula y nombre del cliente.",
      );
    }
  }

  validateNcfFormat(voucherType: string, ncf: string) {
    const type = voucherType.trim().toUpperCase();
    const normalized = ncf.trim().toUpperCase();
    if (!/^B\d{2}$/.test(type)) {
      throw new BadRequestException("Tipo de comprobante invalido.");
    }
    if (!normalized.startsWith(type)) {
      throw new BadRequestException(`El NCF debe iniciar con el tipo seleccionado (${type}).`);
    }
    if (!/^B\d{10}$/.test(normalized)) {
      throw new BadRequestException("El NCF tiene formato invalido.");
    }
    return normalized;
  }

  assertNcfNotDuplicated(existing: Set<string>, companyId: string, ncf: string) {
    const key = `${companyId}:${ncf.trim().toUpperCase()}`;
    if (existing.has(key)) {
      throw new BadRequestException("El NCF ya fue usado por esta empresa.");
    }
    return key;
  }

  private allocateIncludedTaxRemainders(lines: MutableLine[]) {
    const includedByRate = new Map<string, MutableLine[]>();
    for (const line of lines) {
      if (!line.taxIncluded) continue;
      const bucket = includedByRate.get(line.rateKey) ?? [];
      bucket.push(line);
      includedByRate.set(line.rateKey, bucket);
    }

    for (const bucket of includedByRate.values()) {
      const grossTotal = bucket.reduce((sum, line) => sum.plus(line.lineTotal), new Prisma.Decimal(0));
      const rate = bucket[0]?.taxRate ?? new Prisma.Decimal(0);
      if (rate.lte(0)) continue;
      const targetBase = this.roundMoney(grossTotal.div(new Prisma.Decimal(1).plus(rate)));
      const currentBase = bucket.reduce((sum, line) => sum.plus(line.taxableBase), new Prisma.Decimal(0));
      let difference = targetBase.minus(currentBase);
      if (difference.eq(0)) continue;

      const direction = difference.gt(0) ? new Prisma.Decimal(0.01) : new Prisma.Decimal(-0.01);
      const ordered = [...bucket].sort((a, b) => {
        const remainderCompare = difference.gt(0)
          ? b.baseRemainder.comparedTo(a.baseRemainder)
          : a.baseRemainder.comparedTo(b.baseRemainder);
        return remainderCompare || a.index - b.index;
      });

      let cursor = 0;
      while (!difference.eq(0)) {
        const target = ordered[cursor % ordered.length];
        target.taxableBase = this.roundMoney(target.taxableBase.plus(direction));
        target.taxAmount = this.roundMoney(target.lineTotal.minus(target.taxableBase));
        target.roundingAdjustment = this.roundMoney(target.roundingAdjustment.plus(direction));
        difference = this.roundMoney(difference.minus(direction));
        cursor += 1;
      }
    }
  }

  private money(value: number | string | Prisma.Decimal) {
    return new Prisma.Decimal(value);
  }

  private quantity(value: number | string | Prisma.Decimal) {
    return new Prisma.Decimal(value);
  }

  private rate(value: number | string | Prisma.Decimal) {
    const decimal = new Prisma.Decimal(value);
    if (decimal.lt(0) || decimal.gt(1)) {
      throw new BadRequestException("La tasa de impuesto debe estar entre 0 y 1.");
    }
    return decimal;
  }

  private roundMoney(value: Prisma.Decimal) {
    return value.toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
  }
}
