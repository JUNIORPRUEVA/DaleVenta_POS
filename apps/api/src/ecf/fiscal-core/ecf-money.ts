import { Prisma } from "@prisma/client";

export type EcfDecimalInput = string | number | Prisma.Decimal;

export const ECF_MONEY_SCALE = 2;
export const ECF_QUANTITY_SCALE = 6;
export const ECF_MONEY_EPSILON = new Prisma.Decimal("0.01");

export function dec(value: EcfDecimalInput) {
  return new Prisma.Decimal(value as Prisma.Decimal.Value);
}

export function money(value: EcfDecimalInput) {
  return dec(value).toDecimalPlaces(ECF_MONEY_SCALE, Prisma.Decimal.ROUND_HALF_UP);
}

export function quantity(value: EcfDecimalInput) {
  return dec(value).toDecimalPlaces(
    ECF_QUANTITY_SCALE,
    Prisma.Decimal.ROUND_HALF_UP,
  );
}

export function moneyString(value: EcfDecimalInput) {
  return money(value).toFixed(ECF_MONEY_SCALE);
}

export function moneyNumber(value: EcfDecimalInput) {
  return Number(moneyString(value));
}

export function isSameMoney(a: EcfDecimalInput, b: EcfDecimalInput) {
  return money(a).minus(money(b)).abs().lte(ECF_MONEY_EPSILON);
}

export function sumMoney(values: EcfDecimalInput[]): Prisma.Decimal {
  return values.reduce<Prisma.Decimal>(
    (sum, value) => sum.plus(money(value)),
    new Prisma.Decimal(0),
  );
}
