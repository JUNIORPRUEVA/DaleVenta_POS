import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";

export type UnitOfMeasureSnapshot = {
  code: string;
  name: string;
  symbol: string;
  precision: number;
  allowDecimals: boolean;
};

export const DEFAULT_UNIT_OF_MEASURE_ID = "UNIT";

export const DEFAULT_UNIT_OF_MEASURE: UnitOfMeasureSnapshot = {
  code: "UNIT",
  name: "Unidad",
  symbol: "u",
  precision: 0,
  allowDecimals: false,
};

export function unitSnapshotFields(unit?: UnitOfMeasureSnapshot | null) {
  const source = unit ?? DEFAULT_UNIT_OF_MEASURE;
  return {
    unitCodeSnapshot: source.code,
    unitNameSnapshot: source.name,
    unitSymbolSnapshot: source.symbol,
    unitPrecisionSnapshot: source.precision,
  };
}

export function validateQuantityForUnit(params: {
  quantity: Prisma.Decimal;
  unit?: UnitOfMeasureSnapshot | null;
  label: string;
  allowZero?: boolean;
}) {
  const unit = params.unit ?? DEFAULT_UNIT_OF_MEASURE;
  const quantity = params.quantity;

  if (params.allowZero ? quantity.lt(0) : quantity.lte(0)) {
    throw new BadRequestException(`Cantidad inválida en ${params.label}`);
  }

  if (!unit.allowDecimals && !quantity.isInteger()) {
    throw new BadRequestException(
      `${params.label}: la unidad ${unit.code} no permite decimales.`,
    );
  }

  const decimalPlaces = quantity.decimalPlaces();
  if (decimalPlaces > unit.precision) {
    throw new BadRequestException(
      `${params.label}: la cantidad excede la precisión permitida para ${unit.code} (${unit.precision} decimales).`,
    );
  }
}
