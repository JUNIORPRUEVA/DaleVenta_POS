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
  WarehouseTransferStatus,
} from "@prisma/client";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import { ProductSourceResolver } from "../products/product-source.resolver";
import {
  CreateWarehouseTransferDto,
  CreateWarehouseDto,
  UpdateTerminalWarehouseDto,
  UpdateWarehouseDto,
} from "./dto/warehouse.dto";

type Tx = Prisma.TransactionClient;
type StockUpdateRow = {
  previous_quantity: string;
  resulting_quantity: string;
};

@Injectable()
export class WarehousesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productSourceResolver: ProductSourceResolver,
  ) {}

  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const rows = await this.prisma.warehouse.findMany({
      where: { companyId },
      orderBy: [{ isDefault: "desc" }, { isActive: "desc" }, { name: "asc" }],
      include: {
        _count: {
          select: {
            defaultTerminals: { where: { isActive: true } },
            stocks: true,
          },
        },
      },
    });
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      code: row.code,
      isDefault: row.isDefault,
      isActive: row.isActive,
      terminalCount: row._count.defaultTerminals,
      stockRowCount: row._count.stocks,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deactivatedAt: row.deactivatedAt,
    }));
  }

  async listTerminals(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const rows = await this.prisma.terminal.findMany({
      where: { companyId },
      orderBy: [{ isDefault: "desc" }, { isActive: "desc" }, { name: "asc" }],
      include: {
        defaultWarehouse: {
          select: { id: true, name: true, code: true, isActive: true },
        },
      },
    });
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      code: row.code,
      isDefault: row.isDefault,
      isActive: row.isActive,
      defaultWarehouseId: row.defaultWarehouseId,
      defaultWarehouse: row.defaultWarehouse,
      deviceBound: (row.deviceFingerprint ?? "").trim().length > 0,
    }));
  }

  async create(user: TenantUser, dto: CreateWarehouseDto) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const name = this.cleanName(dto.name);
    const code = this.cleanCode(dto.code);
    return this.prisma.warehouse.create({
      data: {
        companyId,
        name,
        code,
        isActive: true,
        isDefault: false,
      },
    });
  }

  async update(user: TenantUser, id: string, dto: UpdateWarehouseDto) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const data: Prisma.WarehouseUpdateInput = {};
    if (dto.name !== undefined) data.name = this.cleanName(dto.name);
    if (dto.code !== undefined) data.code = this.cleanCode(dto.code);
    if (Object.keys(data).length === 0) {
      throw new BadRequestException("No hay cambios para guardar.");
    }
    await this.ensureWarehouse(companyId, id);
    try {
      return await this.prisma.warehouse.update({
        where: { id },
        data,
      });
    } catch (error) {
      if (this.isUniqueConstraint(error)) {
        throw new ConflictException(
          "Ya existe un almacen con ese codigo en esta empresa.",
        );
      }
      throw error;
    }
  }

  async setDefault(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    return this.prisma.$transaction(async (tx) => {
      const warehouse = await this.ensureWarehouse(companyId, id, tx);
      if (!warehouse.isActive) {
        throw new BadRequestException(
          "Solo un almacen activo puede ser predeterminado.",
        );
      }
      await tx.warehouse.updateMany({
        where: { companyId, isDefault: true, id: { not: id } },
        data: { isDefault: false },
      });
      await tx.warehouse.update({
        where: { id },
        data: { isDefault: true },
      });
      return this.ensureWarehouse(companyId, id, tx);
    });
  }

  async activate(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    await this.ensureWarehouse(companyId, id);
    return this.prisma.warehouse.update({
      where: { id },
      data: { isActive: true, deactivatedAt: null, deactivatedById: null },
    });
  }

  async deactivate(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    return this.prisma.$transaction(async (tx) => {
      const warehouse = await this.ensureWarehouse(companyId, id, tx);
      if (warehouse.isDefault) {
        throw new BadRequestException(
          "No se puede desactivar el almacen predeterminado.",
        );
      }
      const nonZero = await tx.warehouseStock.count({
        where: {
          companyId,
          warehouseId: id,
          quantity: { not: new Prisma.Decimal(0) },
        },
      });
      if (nonZero > 0) {
        throw new ConflictException(
          "No se puede desactivar un almacen con stock distinto de cero.",
        );
      }
      const linkedTerminals = await tx.terminal.count({
        where: { companyId, defaultWarehouseId: id, isActive: true },
      });
      if (linkedTerminals > 0) {
        throw new ConflictException(
          "Reasigna las terminales activas antes de desactivar este almacen.",
        );
      }
      return tx.warehouse.update({
        where: { id },
        data: {
          isActive: false,
          deactivatedAt: new Date(),
          deactivatedById: user.id ?? null,
        },
      });
    });
  }

  async updateTerminalWarehouse(
    user: TenantUser,
    terminalId: string,
    dto: UpdateTerminalWarehouseDto,
  ) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    return this.prisma.$transaction(async (tx) => {
      const terminal = await tx.terminal.findFirst({
        where: { id: terminalId, companyId },
      });
      if (!terminal) throw new NotFoundException("Terminal no encontrada.");
      await this.ensureActiveWarehouse(companyId, dto.warehouseId, tx);
      return tx.terminal.update({
        where: { id: terminalId },
        data: { defaultWarehouseId: dto.warehouseId },
        include: {
          defaultWarehouse: {
            select: { id: true, name: true, code: true, isActive: true },
          },
        },
      });
    });
  }

  async productStockBreakdown(user: TenantUser, productId: string) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const source =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (source.source !== ProductSource.LOCAL) {
      return {
        productId,
        source: source.source,
        readOnly: true,
        total: null,
        reconciled: true,
        warehouses: [],
        message:
          "La disponibilidad por almacen solo esta disponible para productos LOCAL.",
      };
    }

    const product = await this.prisma.product.findFirst({
      where: { id: productId, companyId },
      select: { id: true, stock: true },
    });
    if (!product) throw new NotFoundException("Producto no encontrado.");

    const warehouses = await this.prisma.warehouse.findMany({
      where: { companyId },
      orderBy: [{ isDefault: "desc" }, { isActive: "desc" }, { name: "asc" }],
      include: {
        stocks: {
          where: { productId },
          select: { quantity: true },
          take: 1,
        },
      },
    });
    const rows = warehouses.map((warehouse) => {
      const quantity = warehouse.stocks[0]?.quantity ?? new Prisma.Decimal(0);
      return {
        warehouseId: warehouse.id,
        warehouseName: warehouse.name,
        warehouseCode: warehouse.code,
        isDefault: warehouse.isDefault,
        isActive: warehouse.isActive,
        quantity: Number(quantity),
        quantityDecimal: quantity.toString(),
      };
    });
    const total = rows.reduce(
      (sum, row) => sum.plus(row.quantityDecimal),
      new Prisma.Decimal(0),
    );
    return {
      productId: product.id,
      source: source.source,
      readOnly: false,
      total: Number(product.stock ?? 0),
      totalDecimal: product.stock?.toString?.() ?? "0",
      warehouseTotal: Number(total),
      warehouseTotalDecimal: total.toString(),
      reconciled: total.equals(product.stock ?? 0),
      warehouses: rows,
    };
  }

  async listTransfers(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const rows = await this.prisma.warehouseTransfer.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take: 100,
      include: this.transferInclude(),
    });
    return rows.map((row) => this.mapTransfer(row));
  }

  async getTransfer(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const transfer = await this.prisma.warehouseTransfer.findFirst({
      where: { id, companyId },
      include: this.transferInclude(),
    });
    if (!transfer) throw new NotFoundException("Transferencia no encontrada.");
    return this.mapTransfer(transfer);
  }

  async createTransfer(user: TenantUser, dto: CreateWarehouseTransferDto) {
    const companyId = requireTenant(user);
    await this.assertMultiWarehouseEnabled(companyId);
    const sourceWarehouseId = dto.sourceWarehouseId;
    const destinationWarehouseId = dto.destinationWarehouseId;
    if (sourceWarehouseId === destinationWarehouseId) {
      throw new BadRequestException(
        "El origen y el destino deben ser almacenes distintos.",
      );
    }
    const clientRequestId = (dto.clientRequestId ?? "").trim() || null;
    const notes = (dto.notes ?? "").trim() || null;

    return this.runTransferTransaction(async (tx) => {
      if (clientRequestId) {
        const existing = await tx.warehouseTransfer.findFirst({
          where: { companyId, clientRequestId },
          include: this.transferInclude(),
        });
        if (existing) return this.mapTransfer(existing);
      }

      const source = await this.ensureActiveWarehouse(
        companyId,
        sourceWarehouseId,
        tx,
      );
      const destination = await this.ensureActiveWarehouse(
        companyId,
        destinationWarehouseId,
        tx,
      );
      const items = this.normalizeTransferItems(dto.items);
      const productIds = items.map((item) => item.productId);
      const products = await tx.product.findMany({
        where: { companyId, id: { in: productIds } },
        select: {
          id: true,
          nombre: true,
          codigo: true,
          stock: true,
          company: { select: { productSource: true } },
          unitOfMeasure: {
            select: {
              code: true,
              name: true,
              symbol: true,
              precision: true,
              allowDecimals: true,
            },
          },
        },
      });
      if (products.length !== productIds.length) {
        throw new NotFoundException("Producto no encontrado.");
      }
      const productsById = new Map(
        products.map((product) => [product.id, product]),
      );

      for (const item of items) {
        const product = productsById.get(item.productId)!;
        if (
          product.company.productSource &&
          product.company.productSource !== ProductSource.LOCAL
        ) {
          throw new BadRequestException(
            "Solo productos LOCAL pueden transferirse entre almacenes.",
          );
        }
        this.validateQuantityForUnit(
          item.quantity,
          product.unitOfMeasure,
          "cantidad",
        );
        await this.assertProductStockReconciled(tx, companyId, item.productId);
      }

      const transfer = await tx.warehouseTransfer.create({
        data: {
          companyId,
          sourceWarehouseId,
          destinationWarehouseId,
          sourceWarehouseNameSnapshot: source.name,
          sourceWarehouseCodeSnapshot: source.code,
          destinationWarehouseNameSnapshot: destination.name,
          destinationWarehouseCodeSnapshot: destination.code,
          status: WarehouseTransferStatus.COMPLETED,
          clientRequestId,
          operationId: clientRequestId,
          createdByUserId: user.id ?? null,
          completedAt: new Date(),
          notes,
        },
      });

      for (const item of items) {
        const product = productsById.get(item.productId)!;
        const transferItem = await tx.warehouseTransferItem.create({
          data: {
            companyId,
            transferId: transfer.id,
            productId: product.id,
            productNameSnapshot: product.nombre,
            productCodeSnapshot: product.codigo,
            quantity: item.quantity,
            unitCodeSnapshot: product.unitOfMeasure.code,
            unitNameSnapshot: product.unitOfMeasure.name,
            unitSymbolSnapshot: product.unitOfMeasure.symbol,
            unitPrecisionSnapshot: product.unitOfMeasure.precision,
          },
        });

        await tx.warehouseStock.upsert({
          where: {
            companyId_warehouseId_productId: {
              companyId,
              warehouseId: destinationWarehouseId,
              productId: product.id,
            },
          },
          update: {},
          create: {
            companyId,
            warehouseId: destinationWarehouseId,
            productId: product.id,
            quantity: new Prisma.Decimal(0),
          },
        });

        const out = await this.updateWarehouseStockByDelta(tx, {
          companyId,
          warehouseId: sourceWarehouseId,
          productId: product.id,
          quantityDelta: item.quantity.negated(),
        });
        const outRow = out[0];
        if (!outRow) {
          throw new ConflictException(
            "Stock insuficiente en el almacen origen.",
          );
        }

        const inRows = await this.updateWarehouseStockByDelta(tx, {
          companyId,
          warehouseId: destinationWarehouseId,
          productId: product.id,
          quantityDelta: item.quantity,
        });
        const inRow = inRows[0];
        if (!inRow) {
          throw new ConflictException(
            "No se pudo actualizar el almacen destino.",
          );
        }

        await tx.inventoryMovement.createMany({
          data: [
            {
              companyId,
              productId: product.id,
              warehouseId: sourceWarehouseId,
              type: InventoryMovementType.TRANSFER_OUT,
              quantityDelta: item.quantity.negated(),
              previousQuantity: this.decimal(outRow.previous_quantity),
              resultingQuantity: this.decimal(outRow.resulting_quantity),
              unitCodeSnapshot: product.unitOfMeasure.code,
              unitNameSnapshot: product.unitOfMeasure.name,
              unitSymbolSnapshot: product.unitOfMeasure.symbol,
              unitPrecisionSnapshot: product.unitOfMeasure.precision,
              sourceWarehouseId,
              destinationWarehouseId,
              sourceType: "WAREHOUSE_TRANSFER",
              sourceId: transfer.id,
              sourceItemId: transferItem.id,
              reason: notes,
              createdByUserId: user.id ?? null,
            },
            {
              companyId,
              productId: product.id,
              warehouseId: destinationWarehouseId,
              type: InventoryMovementType.TRANSFER_IN,
              quantityDelta: item.quantity,
              previousQuantity: this.decimal(inRow.previous_quantity),
              resultingQuantity: this.decimal(inRow.resulting_quantity),
              unitCodeSnapshot: product.unitOfMeasure.code,
              unitNameSnapshot: product.unitOfMeasure.name,
              unitSymbolSnapshot: product.unitOfMeasure.symbol,
              unitPrecisionSnapshot: product.unitOfMeasure.precision,
              sourceWarehouseId,
              destinationWarehouseId,
              sourceType: "WAREHOUSE_TRANSFER",
              sourceId: transfer.id,
              sourceItemId: transferItem.id,
              reason: notes,
              createdByUserId: user.id ?? null,
            },
          ],
        });

        await this.assertProductStockReconciled(tx, companyId, product.id);
      }

      const completed = await tx.warehouseTransfer.findFirstOrThrow({
        where: { id: transfer.id, companyId },
        include: this.transferInclude(),
      });
      return this.mapTransfer(completed);
    });
  }

  deleteTransfer() {
    throw new BadRequestException(
      "Las transferencias completadas no se eliminan. Crea una transferencia inversa auditada en una version futura.",
    );
  }

  private async ensureWarehouse(
    companyId: string,
    id: string,
    tx: Tx | PrismaService = this.prisma,
  ) {
    const warehouse = await tx.warehouse.findFirst({
      where: { id, companyId },
    });
    if (!warehouse) throw new NotFoundException("Almacen no encontrado.");
    return warehouse;
  }

  private async assertMultiWarehouseEnabled(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { multiWarehouseEnabled: true },
    });
    if (company?.multiWarehouseEnabled !== true) {
      throw new BadRequestException(
        "La gestion de multiples almacenes no esta activa para esta empresa.",
      );
    }
  }

  private async ensureActiveWarehouse(companyId: string, id: string, tx: Tx) {
    const warehouse = await tx.warehouse.findFirst({
      where: { id, companyId, isActive: true },
    });
    if (!warehouse) {
      throw new BadRequestException("Almacen activo no encontrado.");
    }
    return warehouse;
  }

  private normalizeTransferItems(
    items: CreateWarehouseTransferDto["items"],
  ): Array<{ productId: string; quantity: Prisma.Decimal }> {
    const seen = new Set<string>();
    return items.map((item) => {
      if (seen.has(item.productId)) {
        throw new BadRequestException(
          "Cada producto solo puede aparecer una vez por transferencia.",
        );
      }
      seen.add(item.productId);
      const quantity = this.decimal(item.quantity);
      if (quantity.lte(0)) {
        throw new BadRequestException("La cantidad debe ser mayor que cero.");
      }
      return { productId: item.productId, quantity };
    });
  }

  private async assertProductStockReconciled(
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
    if (!row) throw new NotFoundException("Producto no encontrado.");
    if (this.decimal(row.product_stock).cmp(row.warehouse_total) !== 0) {
      throw new ConflictException(
        "Product.stock no coincide con el total de WarehouseStock.",
      );
    }
  }

  private updateWarehouseStockByDelta(
    tx: Tx,
    input: {
      companyId: string;
      warehouseId: string;
      productId: string;
      quantityDelta: Prisma.Decimal;
    },
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

  private validateQuantityForUnit(
    quantity: Prisma.Decimal,
    unit: { allowDecimals: boolean; precision: number },
    label: string,
  ) {
    const [, fraction = ""] = quantity.toFixed(6).split(".");
    const scale = fraction.replace(/0+$/, "").length;
    if (!unit.allowDecimals && scale > 0) {
      throw new BadRequestException(`${label} no permite decimales.`);
    }
    if (scale > unit.precision) {
      throw new BadRequestException(
        `${label} excede la precision permitida por la unidad.`,
      );
    }
  }

  private transferInclude() {
    return {
      sourceWarehouse: { select: { id: true, name: true, code: true } },
      destinationWarehouse: { select: { id: true, name: true, code: true } },
      createdBy: { select: { id: true, nombreCompleto: true, email: true } },
      items: {
        orderBy: { createdAt: "asc" as const },
        include: {
          product: { select: { id: true, nombre: true, codigo: true } },
        },
      },
    };
  }

  private mapTransfer(row: any) {
    return {
      id: row.id,
      companyId: row.companyId,
      sourceWarehouseId: row.sourceWarehouseId,
      destinationWarehouseId: row.destinationWarehouseId,
      sourceWarehouse: {
        id: row.sourceWarehouse?.id ?? row.sourceWarehouseId,
        name:
          row.sourceWarehouseNameSnapshot ??
          row.sourceWarehouse?.name ??
          "Almacen origen",
        code:
          row.sourceWarehouseCodeSnapshot ?? row.sourceWarehouse?.code ?? "",
      },
      destinationWarehouse: {
        id: row.destinationWarehouse?.id ?? row.destinationWarehouseId,
        name:
          row.destinationWarehouseNameSnapshot ??
          row.destinationWarehouse?.name ??
          "Almacen destino",
        code:
          row.destinationWarehouseCodeSnapshot ??
          row.destinationWarehouse?.code ??
          "",
      },
      status: row.status,
      clientRequestId: row.clientRequestId,
      createdBy: row.createdBy,
      completedAt: row.completedAt,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      itemCount: row.items?.length ?? 0,
      items: (row.items ?? []).map((item: any) => ({
        id: item.id,
        productId: item.productId,
        productName: item.productNameSnapshot ?? item.product?.nombre ?? "",
        productCode: item.productCodeSnapshot ?? item.product?.codigo ?? "",
        quantity: Number(item.quantity),
        quantityDecimal: item.quantity?.toString?.() ?? "0",
        unitCodeSnapshot: item.unitCodeSnapshot,
        unitNameSnapshot: item.unitNameSnapshot,
        unitSymbolSnapshot: item.unitSymbolSnapshot,
        unitPrecisionSnapshot: item.unitPrecisionSnapshot,
      })),
    };
  }

  private decimal(value: Prisma.Decimal.Value) {
    return new Prisma.Decimal(value);
  }

  private async runTransferTransaction<T>(
    fn: (tx: Tx) => Promise<T>,
  ): Promise<T> {
    let lastError: unknown;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(fn, {
          isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted,
          timeout: 30_000,
        });
      } catch (error) {
        lastError = error;
        if (!this.isSerializationConflict(error)) throw error;
      }
    }
    throw lastError;
  }

  private isSerializationConflict(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2034"
    );
  }

  private cleanName(value: string) {
    const clean = value.trim().replace(/\s+/g, " ");
    if (!clean) throw new BadRequestException("El nombre es obligatorio.");
    return clean;
  }

  private cleanCode(value: string) {
    const clean = value.trim().replace(/\s+/g, "-").toUpperCase();
    if (!clean) throw new BadRequestException("El codigo es obligatorio.");
    return clean;
  }

  private isUniqueConstraint(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    );
  }
}
