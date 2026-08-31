import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { InventoryMovementType, Prisma, ProductSource } from "@prisma/client";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import { ProductSourceResolver } from "../products/product-source.resolver";

type MovementQuery = {
  productId?: string;
  warehouseId?: string;
  type?: string;
  sourceType?: string;
  userId?: string;
  search?: string;
  from?: string;
  to?: string;
  take?: string;
  skip?: string;
};

type SourceReference = {
  label: string;
  rawId: string | null;
  sourceType: string | null;
};

const movementLabels: Record<
  InventoryMovementType,
  { label: string; direction: "IN" | "OUT" }
> = {
  INITIAL_STOCK: { label: "Stock inicial", direction: "IN" },
  SALE: { label: "Venta", direction: "OUT" },
  SALE_CANCELLATION: { label: "Restauracion por cancelacion", direction: "IN" },
  PURCHASE_RECEIPT: { label: "Recepcion de compra", direction: "IN" },
  RETURN: { label: "Devolucion", direction: "IN" },
  ADJUSTMENT_IN: { label: "Ajuste positivo", direction: "IN" },
  ADJUSTMENT_OUT: { label: "Ajuste negativo", direction: "OUT" },
  TRANSFER_OUT: { label: "Transferencia enviada", direction: "OUT" },
  TRANSFER_IN: { label: "Transferencia recibida", direction: "IN" },
};

@Injectable()
export class InventoryReportingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productSourceResolver: ProductSourceResolver,
  ) {}

  async listMovements(user: TenantUser, query: MovementQuery) {
    const companyId = requireTenant(user);
    const source =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (source.source !== ProductSource.LOCAL) {
      return this.externalInventoryResponse(source.source, "movements");
    }

    const where = await this.buildMovementWhere(companyId, query);
    const take = this.parseTake(query.take);
    const skip = this.parseSkip(query.skip);

    const [total, rows] = await this.prisma.$transaction([
      this.prisma.inventoryMovement.count({ where }),
      this.prisma.inventoryMovement.findMany({
        where,
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        skip,
        take,
        include: {
          product: {
            select: { id: true, nombre: true, codigo: true, stock: true },
          },
          warehouse: {
            select: { id: true, name: true, code: true, isActive: true },
          },
          sourceWarehouse: {
            select: { id: true, name: true, code: true, isActive: true },
          },
          destinationWarehouse: {
            select: { id: true, name: true, code: true, isActive: true },
          },
          createdBy: {
            select: { id: true, nombreCompleto: true, email: true },
          },
        },
      }),
    ]);

    const references = await this.resolveReferences(companyId, rows);
    return {
      source: source.source,
      readOnly: true,
      total,
      take,
      skip,
      hasMore: skip + rows.length < total,
      items: rows.map((row) => this.mapMovement(row, references)),
    };
  }

  async stockReport(user: TenantUser) {
    const companyId = requireTenant(user);
    const source =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (source.source !== ProductSource.LOCAL) {
      return this.externalInventoryResponse(source.source, "stock-report");
    }

    const [warehouses, products] = await this.prisma.$transaction([
      this.prisma.warehouse.findMany({
        where: { companyId },
        orderBy: [{ isDefault: "desc" }, { isActive: "desc" }, { name: "asc" }],
        select: {
          id: true,
          name: true,
          code: true,
          isDefault: true,
          isActive: true,
        },
      }),
      this.prisma.product.findMany({
        where: { companyId },
        orderBy: { nombre: "asc" },
        select: {
          id: true,
          nombre: true,
          codigo: true,
          stock: true,
          unitOfMeasure: {
            select: { code: true, name: true, symbol: true, precision: true },
          },
          warehouseStocks: {
            select: { warehouseId: true, quantity: true },
          },
        },
      }),
    ]);

    const quantityBuckets = new Map<
      string,
      { unitSymbol: string; productCount: number }
    >();
    const rows = products.map((product) => {
      const byWarehouse = new Map(
        product.warehouseStocks.map((stock) => [
          stock.warehouseId,
          stock.quantity,
        ]),
      );
      const warehouseRows = warehouses.map((warehouse) => {
        const quantity = byWarehouse.get(warehouse.id) ?? new Prisma.Decimal(0);
        return {
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          warehouseCode: warehouse.code,
          isActive: warehouse.isActive,
          quantityDecimal: quantity.toString(),
          quantity: Number(quantity),
        };
      });
      const warehouseTotal = warehouseRows.reduce(
        (sum, row) => sum.plus(row.quantityDecimal),
        new Prisma.Decimal(0),
      );
      const unitSymbol = product.unitOfMeasure.symbol;
      const bucket = quantityBuckets.get(unitSymbol) ?? {
        unitSymbol,
        productCount: 0,
      };
      bucket.productCount += 1;
      quantityBuckets.set(unitSymbol, bucket);
      return {
        productId: product.id,
        productName: product.nombre,
        sku: product.codigo ?? "",
        unit: product.unitOfMeasure,
        companyTotalDecimal: warehouseTotal.toString(),
        companyTotal: Number(warehouseTotal),
        compatibilityStockDecimal: product.stock?.toString?.() ?? "0",
        reconciled: warehouseTotal.equals(product.stock ?? 0),
        warehouses: warehouseRows,
      };
    });

    return {
      source: source.source,
      readOnly: true,
      warehouseCount: warehouses.length,
      productCount: products.length,
      warehouses,
      quantityBuckets: [...quantityBuckets.values()],
      incompatibleUnitsSummed: false,
      rows,
    };
  }

  async reconciliation(user: TenantUser) {
    const companyId = requireTenant(user);
    const source =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (source.source !== ProductSource.LOCAL) {
      return this.externalInventoryResponse(source.source, "reconciliation");
    }
    const rows = await this.prisma.product.findMany({
      where: { companyId },
      orderBy: { nombre: "asc" },
      select: {
        id: true,
        nombre: true,
        codigo: true,
        stock: true,
        unitOfMeasure: { select: { symbol: true, precision: true } },
        warehouseStocks: { select: { quantity: true } },
      },
    });
    const items = rows.map((product) => {
      const warehouseTotal = product.warehouseStocks.reduce(
        (sum, row) => sum.plus(row.quantity),
        new Prisma.Decimal(0),
      );
      const productStock = product.stock ?? new Prisma.Decimal(0);
      return {
        productId: product.id,
        productName: product.nombre,
        sku: product.codigo ?? "",
        unitSymbol: product.unitOfMeasure.symbol,
        productStockDecimal: productStock.toString(),
        warehouseTotalDecimal: warehouseTotal.toString(),
        differenceDecimal: productStock.minus(warehouseTotal).toString(),
        reconciled: productStock.equals(warehouseTotal),
      };
    });
    return {
      source: source.source,
      readOnly: true,
      totalProducts: items.length,
      driftCount: items.filter((item) => !item.reconciled).length,
      items,
    };
  }

  private async buildMovementWhere(companyId: string, query: MovementQuery) {
    const where: Prisma.InventoryMovementWhereInput = { companyId };
    if (query.productId) {
      await this.assertProduct(companyId, query.productId);
      where.productId = query.productId;
    }
    if (query.warehouseId) {
      await this.assertWarehouse(companyId, query.warehouseId);
      where.warehouseId = query.warehouseId;
    }
    if (query.userId) {
      await this.assertUser(companyId, query.userId);
      where.createdByUserId = query.userId;
    }
    if (query.type) where.type = this.parseType(query.type);
    if (query.sourceType) where.sourceType = query.sourceType.trim();

    const from = this.parseDate(query.from, "from");
    const to = this.parseDate(query.to, "to");
    if (from || to)
      where.createdAt = {
        ...(from ? { gte: from } : {}),
        ...(to ? { lte: to } : {}),
      };

    const search = query.search?.trim();
    if (search) {
      where.OR = [
        { reason: { contains: search, mode: "insensitive" } },
        { sourceType: { contains: search, mode: "insensitive" } },
        { product: { nombre: { contains: search, mode: "insensitive" } } },
        { product: { codigo: { contains: search, mode: "insensitive" } } },
      ];
      if (this.looksUuid(search)) where.OR.push({ sourceId: search });
    }
    return where;
  }

  private async assertProduct(companyId: string, productId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, companyId },
      select: { id: true },
    });
    if (!product) throw new NotFoundException("Producto no encontrado.");
  }

  private async assertWarehouse(companyId: string, warehouseId: string) {
    const warehouse = await this.prisma.warehouse.findFirst({
      where: { id: warehouseId, companyId },
      select: { id: true },
    });
    if (!warehouse) throw new NotFoundException("Almacen no encontrado.");
  }

  private async assertUser(companyId: string, userId: string) {
    const user = await this.prisma.user.findFirst({
      where: { id: userId, companyId },
      select: { id: true },
    });
    if (!user) throw new NotFoundException("Usuario no encontrado.");
  }

  private parseType(type: string) {
    const value = type.trim() as InventoryMovementType;
    if (!Object.values(InventoryMovementType).includes(value)) {
      throw new BadRequestException("Tipo de movimiento no valido.");
    }
    return value;
  }

  private parseDate(value: string | undefined, label: string) {
    if (!value?.trim()) return undefined;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException(`Fecha ${label} no valida.`);
    }
    return date;
  }

  private parseTake(value: string | undefined) {
    const parsed = Number(value ?? 25);
    if (!Number.isFinite(parsed) || parsed <= 0) return 25;
    return Math.min(Math.trunc(parsed), 100);
  }

  private parseSkip(value: string | undefined) {
    const parsed = Number(value ?? 0);
    if (!Number.isFinite(parsed) || parsed < 0) return 0;
    return Math.trunc(parsed);
  }

  private async resolveReferences(
    companyId: string,
    rows: Array<{ sourceType: string | null; sourceId: string | null }>,
  ) {
    const keys = rows
      .filter((row) => row.sourceId)
      .map((row) => `${row.sourceType ?? ""}:${row.sourceId}`);
    const uniqueKeys = [...new Set(keys)];
    const references = new Map<string, SourceReference>();
    const idsFor = (type: string) =>
      uniqueKeys
        .filter((key) => key.startsWith(`${type}:`))
        .map((key) => key.split(":")[1])
        .filter(Boolean);

    const [transfers, sales, receipts] = await Promise.all([
      this.prisma.warehouseTransfer.findMany({
        where: { companyId, id: { in: idsFor("WAREHOUSE_TRANSFER") } },
        select: {
          id: true,
          sourceWarehouseNameSnapshot: true,
          destinationWarehouseNameSnapshot: true,
        },
      }),
      this.prisma.sale.findMany({
        where: { companyId, id: { in: idsFor("SALE") } },
        select: { id: true, ncf: true, kind: true, saleDate: true },
      }),
      this.prisma.purchaseReceipt.findMany({
        where: {
          purchaseOrder: { companyId },
          id: { in: idsFor("PURCHASE_RECEIPT") },
        },
        select: {
          id: true,
          supplierInvoiceNumber: true,
          purchaseOrder: { select: { orderNumber: true } },
        },
      }),
    ]);

    for (const transfer of transfers) {
      references.set(`WAREHOUSE_TRANSFER:${transfer.id}`, {
        label: `Transferencia ${transfer.sourceWarehouseNameSnapshot} -> ${transfer.destinationWarehouseNameSnapshot}`,
        rawId: transfer.id,
        sourceType: "WAREHOUSE_TRANSFER",
      });
    }
    for (const sale of sales) {
      references.set(`SALE:${sale.id}`, {
        label: `${sale.kind === "refund" ? "Devolucion" : "Venta"} ${sale.ncf || this.shortId(sale.id)}`,
        rawId: sale.id,
        sourceType: "SALE",
      });
    }
    for (const receipt of receipts) {
      references.set(`PURCHASE_RECEIPT:${receipt.id}`, {
        label: `Recepcion ${receipt.supplierInvoiceNumber || receipt.purchaseOrder.orderNumber}`,
        rawId: receipt.id,
        sourceType: "PURCHASE_RECEIPT",
      });
    }
    return references;
  }

  private mapMovement(row: any, references: Map<string, SourceReference>) {
    const label = movementLabels[row.type as InventoryMovementType];
    const reference = references.get(
      `${row.sourceType ?? ""}:${row.sourceId}`,
    ) ?? {
      label: row.reason || row.sourceType || "Movimiento de inventario",
      rawId: row.sourceId,
      sourceType: row.sourceType,
    };
    return {
      id: row.id,
      createdAt: row.createdAt,
      type: row.type,
      label: label.label,
      direction: label.direction,
      product: {
        id: row.product.id,
        name: row.product.nombre,
        sku: row.product.codigo ?? "",
      },
      warehouse: row.warehouse,
      sourceWarehouse: row.sourceWarehouse,
      destinationWarehouse: row.destinationWarehouse,
      quantityDeltaDecimal: row.quantityDelta.toString(),
      previousQuantityDecimal: row.previousQuantity.toString(),
      resultingQuantityDecimal: row.resultingQuantity.toString(),
      unit: {
        code: row.unitCodeSnapshot,
        name: row.unitNameSnapshot,
        symbol: row.unitSymbolSnapshot,
        precision: row.unitPrecisionSnapshot,
      },
      reference,
      sourceItemId: row.sourceItemId,
      reason: row.reason,
      createdBy: row.createdBy
        ? {
            id: row.createdBy.id,
            name: row.createdBy.nombreCompleto,
            email: row.createdBy.email,
          }
        : null,
    };
  }

  private externalInventoryResponse(source: ProductSource, feature: string) {
    return {
      source,
      readOnly: true,
      externalInventory: true,
      feature,
      items: [],
      rows: [],
      message:
        "El Kardex local no esta disponible para inventario externo. La fuente de inventario sigue siendo el proveedor configurado.",
    };
  }

  private shortId(id: string | null) {
    return id ? id.slice(0, 8).toUpperCase() : "SIN-REF";
  }

  private looksUuid(value: string) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }
}
