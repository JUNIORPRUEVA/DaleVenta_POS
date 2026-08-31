import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  InventoryMovementType,
  Prisma,
  ProductSource,
} from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

type Tx = Prisma.TransactionClient;

type MovementSource = {
  sourceWarehouseId?: string | null;
  destinationWarehouseId?: string | null;
  sourceType?: string | null;
  sourceId?: string | null;
  sourceItemId?: string | null;
  reason?: string | null;
  createdByUserId?: string | null;
};

export type InventoryMutationInput = MovementSource & {
  companyId: string;
  productId: string;
  warehouseId: string;
  quantity: Prisma.Decimal.Value;
  type: InventoryMovementType;
};

export type SetCountedStockInput = MovementSource & {
  companyId: string;
  productId: string;
  warehouseId: string;
  countedQuantity: Prisma.Decimal.Value;
  expectedCurrentQuantity: Prisma.Decimal.Value;
};

export type InventoryMutationResult = {
  companyId: string;
  productId: string;
  warehouseId: string;
  movementId: string;
  quantityDelta: Prisma.Decimal;
  previousQuantity: Prisma.Decimal;
  resultingQuantity: Prisma.Decimal;
  productStock: Prisma.Decimal;
};

type StockUpdateRow = {
  previous_quantity: string;
  resulting_quantity: string;
};

type StockConflictDetails = {
  productId: string;
  warehouseId: string;
  requestedQuantity: string;
  availableQuantity: string;
  productName?: string;
  warehouseName?: string;
  warehouseCode?: string;
};

@Injectable()
export class InventoryMutationService {
  constructor(private readonly prisma: PrismaService) {}

  increaseStock(input: InventoryMutationInput) {
    return this.adjustStockByDelta({
      ...input,
      quantityDelta: this.requirePositive(input.quantity, "quantity"),
    });
  }

  decreaseStock(input: InventoryMutationInput) {
    return this.adjustStockByDelta({
      ...input,
      quantityDelta: this.requirePositive(input.quantity, "quantity").negated(),
    });
  }

  increaseStockInTransaction(tx: Tx, input: InventoryMutationInput) {
    return this.adjustStockByDeltaInTransaction(tx, {
      ...input,
      quantityDelta: this.requirePositive(input.quantity, "quantity"),
    });
  }

  decreaseStockInTransaction(tx: Tx, input: InventoryMutationInput) {
    return this.adjustStockByDeltaInTransaction(tx, {
      ...input,
      quantityDelta: this.requirePositive(input.quantity, "quantity").negated(),
    });
  }

  async setCountedStock(input: SetCountedStockInput) {
    const expected = this.requireNonNegative(
      input.expectedCurrentQuantity,
      "expectedCurrentQuantity",
    );
    const counted = this.requireNonNegative(
      input.countedQuantity,
      "countedQuantity",
    );
    const delta = counted.minus(expected);
    const type = delta.gte(0)
      ? InventoryMovementType.ADJUSTMENT_IN
      : InventoryMovementType.ADJUSTMENT_OUT;

    return this.runMutation(
      {
        ...input,
        type,
        quantityDelta: delta,
      },
      { expectedCurrentQuantity: expected },
    );
  }

  setCountedStockInTransaction(tx: Tx, input: SetCountedStockInput) {
    const expected = this.requireNonNegative(
      input.expectedCurrentQuantity,
      "expectedCurrentQuantity",
    );
    const counted = this.requireNonNegative(
      input.countedQuantity,
      "countedQuantity",
    );
    const delta = counted.minus(expected);
    const type = delta.gte(0)
      ? InventoryMovementType.ADJUSTMENT_IN
      : InventoryMovementType.ADJUSTMENT_OUT;

    return this.runMutationInTransaction(
      tx,
      {
        ...input,
        type,
        quantityDelta: delta,
      },
      { expectedCurrentQuantity: expected },
    );
  }

  adjustStockByDelta(
    input: MovementSource & {
      companyId: string;
      productId: string;
      warehouseId: string;
      quantityDelta: Prisma.Decimal.Value;
      type: InventoryMovementType;
    },
  ) {
    const quantityDelta = this.requireNonZero(input.quantityDelta, "delta");
    return this.runMutation({ ...input, quantityDelta });
  }

  adjustStockByDeltaInTransaction(
    tx: Tx,
    input: MovementSource & {
      companyId: string;
      productId: string;
      warehouseId: string;
      quantityDelta: Prisma.Decimal.Value;
      type: InventoryMovementType;
    },
  ) {
    const quantityDelta = this.requireNonZero(input.quantityDelta, "delta");
    return this.runMutationInTransaction(tx, { ...input, quantityDelta });
  }

  async assertProductStockReconciled(
    tx: Tx,
    companyId: string,
    productId: string,
  ) {
    const [row] = await tx.$queryRaw<
      Array<{ product_stock: string; warehouse_total: string }>
    >`
      SELECT
        p.stock::text AS product_stock,
        COALESCE(SUM(ws.quantity), 0)::text AS warehouse_total
      FROM "Product" p
      LEFT JOIN warehouse_stocks ws
        ON ws.company_id = p.company_id
       AND ws.product_id = p.id
      WHERE p.company_id = ${companyId}::uuid
        AND p.id = ${productId}::uuid
      GROUP BY p.id, p.stock
    `;
    if (!row) throw new NotFoundException("Producto no encontrado");
    if (this.decimal(row.product_stock).cmp(row.warehouse_total) !== 0) {
      throw new ConflictException(
        "Product.stock no coincide con el total de WarehouseStock",
      );
    }
  }

  private runMutation(
    input: MovementSource & {
      companyId: string;
      productId: string;
      warehouseId: string;
      quantityDelta: Prisma.Decimal;
      type: InventoryMovementType;
    },
    options: { expectedCurrentQuantity?: Prisma.Decimal } = {},
  ) {
    return this.prisma.$transaction(
      (tx) => this.runMutationInTransaction(tx, input, options),
      {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        timeout: 30_000,
      },
    );
  }

  private async runMutationInTransaction(
    tx: Tx,
    input: MovementSource & {
      companyId: string;
      productId: string;
      warehouseId: string;
      quantityDelta: Prisma.Decimal;
      type: InventoryMovementType;
    },
    options: { expectedCurrentQuantity?: Prisma.Decimal } = {},
  ) {
    const product = await tx.product.findFirst({
      where: { id: input.productId, companyId: input.companyId },
      select: {
        id: true,
        nombre: true,
        stock: true,
        unitOfMeasure: {
          select: {
            code: true,
            name: true,
            symbol: true,
            precision: true,
            allowDecimals: true,
          },
        },
        company: { select: { productSource: true } },
      },
    });
    if (!product) throw new NotFoundException("Producto no encontrado");
    if (
      product.company.productSource &&
      product.company.productSource !== ProductSource.LOCAL
    ) {
      throw new BadRequestException(
        "Solo productos LOCAL pueden mutar inventario local",
      );
    }

    const warehouse = await tx.warehouse.findFirst({
      where: {
        id: input.warehouseId,
        companyId: input.companyId,
        isActive: true,
      },
      select: { id: true, name: true, code: true },
    });
    if (!warehouse) {
      throw this.conflict("WAREHOUSE_INACTIVE", "Almacen activo no encontrado", {
        warehouseId: input.warehouseId,
      });
    }

    this.validateQuantityForUnit(
      input.quantityDelta.abs(),
      product.unitOfMeasure,
      "cantidad",
    );
    if (options.expectedCurrentQuantity) {
      this.validateQuantityForUnit(
        options.expectedCurrentQuantity,
        product.unitOfMeasure,
        "existencia esperada",
      );
    }

    await this.assertProductStockReconciled(
      tx,
      input.companyId,
      input.productId,
    );

    const stockRows = options.expectedCurrentQuantity
      ? await this.updateWarehouseStockWithExpectedQuantity(
          tx,
          input,
          options.expectedCurrentQuantity,
        )
      : await this.updateWarehouseStockByDelta(tx, input);
    const stockRow = stockRows[0];
    if (!stockRow) {
      if (input.quantityDelta.lt(0)) {
        throw await this.insufficientStockConflict(tx, input, {
          productName: product.nombre,
          warehouseName: warehouse.name,
          warehouseCode: warehouse.code,
        });
      }
      throw this.conflict(
        "WAREHOUSE_STOCK_CONCURRENT_MODIFICATION",
        "WarehouseStock no encontrado o modificado concurrentemente",
        {
          productId: input.productId,
          warehouseId: input.warehouseId,
        },
      );
    }

    const previousQuantity = this.decimal(stockRow.previous_quantity);
    const resultingQuantity = this.decimal(stockRow.resulting_quantity);

    const productUpdate = await tx.product.updateMany({
      where: { id: input.productId, companyId: input.companyId },
      data: { stock: { increment: input.quantityDelta } },
    });
    if (productUpdate.count !== 1) {
      throw new NotFoundException("Producto no encontrado");
    }

    const movement = await tx.inventoryMovement.create({
      data: {
        companyId: input.companyId,
        productId: input.productId,
        warehouseId: input.warehouseId,
        type: input.type,
        quantityDelta: input.quantityDelta,
        previousQuantity,
        resultingQuantity,
        unitCodeSnapshot: product.unitOfMeasure.code,
        unitNameSnapshot: product.unitOfMeasure.name,
        unitSymbolSnapshot: product.unitOfMeasure.symbol,
        unitPrecisionSnapshot: product.unitOfMeasure.precision,
        sourceWarehouseId: input.sourceWarehouseId ?? null,
        destinationWarehouseId: input.destinationWarehouseId ?? null,
        sourceType: input.sourceType ?? null,
        sourceId: input.sourceId ?? null,
        sourceItemId: input.sourceItemId ?? null,
        reason: input.reason ?? null,
        createdByUserId: input.createdByUserId ?? null,
      },
    });

    await this.assertProductStockReconciled(
      tx,
      input.companyId,
      input.productId,
    );

    const updatedProduct = await tx.product.findFirstOrThrow({
      where: { id: input.productId, companyId: input.companyId },
      select: { stock: true },
    });

    return {
      companyId: input.companyId,
      productId: input.productId,
      warehouseId: input.warehouseId,
      movementId: movement.id,
      quantityDelta: input.quantityDelta,
      previousQuantity,
      resultingQuantity,
      productStock: updatedProduct.stock,
    };
  }

  private updateWarehouseStockByDelta(
    tx: Tx,
    input: { companyId: string; warehouseId: string; productId: string; quantityDelta: Prisma.Decimal },
  ) {
    return tx.$queryRaw<StockUpdateRow[]>`
      UPDATE warehouse_stocks
      SET quantity = quantity + ${input.quantityDelta},
          updated_at = CURRENT_TIMESTAMP
      WHERE company_id = ${input.companyId}::uuid
        AND warehouse_id = ${input.warehouseId}::uuid
        AND product_id = ${input.productId}::uuid
        AND quantity + ${input.quantityDelta} >= 0
      RETURNING (quantity - ${input.quantityDelta})::text AS previous_quantity,
                quantity::text AS resulting_quantity
    `;
  }

  private async insufficientStockConflict(
    tx: Tx,
    input: {
      companyId: string;
      warehouseId: string;
      productId: string;
      quantityDelta: Prisma.Decimal;
    },
    snapshots: {
      productName?: string;
      warehouseName?: string;
      warehouseCode?: string;
    },
  ) {
    const row = await tx.warehouseStock.findFirst({
      where: {
        companyId: input.companyId,
        warehouseId: input.warehouseId,
        productId: input.productId,
      },
      select: { quantity: true },
    });
    const details: StockConflictDetails = {
      productId: input.productId,
      warehouseId: input.warehouseId,
      requestedQuantity: input.quantityDelta.abs().toFixed(6),
      availableQuantity: new Prisma.Decimal(row?.quantity ?? 0).toFixed(6),
      productName: snapshots.productName,
      warehouseName: snapshots.warehouseName,
      warehouseCode: snapshots.warehouseCode,
    };
    return this.conflict(
      "INSUFFICIENT_WAREHOUSE_STOCK",
      "Esta venta no pudo sincronizarse porque el stock cambió mientras el dispositivo estaba sin conexión.",
      details,
    );
  }

  private conflict(
    code: string,
    message: string,
    details?: Record<string, unknown>,
  ) {
    return new ConflictException({
      code,
      errorCode: code,
      message,
      details,
    });
  }

  private updateWarehouseStockWithExpectedQuantity(
    tx: Tx,
    input: { companyId: string; warehouseId: string; productId: string; quantityDelta: Prisma.Decimal },
    expectedCurrentQuantity: Prisma.Decimal,
  ) {
    return tx.$queryRaw<StockUpdateRow[]>`
      UPDATE warehouse_stocks
      SET quantity = quantity + ${input.quantityDelta},
          updated_at = CURRENT_TIMESTAMP
      WHERE company_id = ${input.companyId}::uuid
        AND warehouse_id = ${input.warehouseId}::uuid
        AND product_id = ${input.productId}::uuid
        AND quantity = ${expectedCurrentQuantity}
        AND quantity + ${input.quantityDelta} >= 0
      RETURNING (quantity - ${input.quantityDelta})::text AS previous_quantity,
                quantity::text AS resulting_quantity
    `;
  }

  private validateQuantityForUnit(
    quantity: Prisma.Decimal,
    unit: { allowDecimals: boolean; precision: number },
    label: string,
  ) {
    if (quantity.lt(0)) {
      throw new BadRequestException(`${label} no puede ser negativa`);
    }
    const [, fraction = ""] = quantity.toFixed(6).split(".");
    const scale = fraction.replace(/0+$/, "").length;
    if (!unit.allowDecimals && scale > 0) {
      throw new BadRequestException(`${label} no permite decimales`);
    }
    if (scale > unit.precision) {
      throw new BadRequestException(
        `${label} excede la precision permitida por la unidad`,
      );
    }
  }

  private requirePositive(value: Prisma.Decimal.Value, label: string) {
    const decimal = this.decimal(value);
    if (decimal.lte(0)) {
      throw new BadRequestException(`${label} debe ser mayor que cero`);
    }
    return decimal;
  }

  private requireNonNegative(value: Prisma.Decimal.Value, label: string) {
    const decimal = this.decimal(value);
    if (decimal.lt(0)) {
      throw new BadRequestException(`${label} no puede ser negativo`);
    }
    return decimal;
  }

  private requireNonZero(value: Prisma.Decimal.Value, label: string) {
    const decimal = this.decimal(value);
    if (decimal.isZero()) {
      throw new BadRequestException(`${label} no puede ser cero`);
    }
    return decimal;
  }

  private decimal(value: Prisma.Decimal.Value) {
    return new Prisma.Decimal(value);
  }
}
