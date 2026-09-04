import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  Optional,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  InventoryMovementType,
  Prisma,
  ProductItemType,
  ProductSource,
  PurchaseOrderStatus,
  Role,
} from "@prisma/client";
import { randomUUID } from "node:crypto";
import * as fs from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import * as path from "node:path";
import type { Express } from "express";
import { PrismaService } from "../prisma/prisma.service";
import { requireTenant } from "../auth/tenant-context";
import { R2Service } from "../storage/r2.service";
import { buildTenantObjectKey } from "../storage/helpers/storage_helpers";
import {
  DEFAULT_UNIT_OF_MEASURE,
  unitSnapshotFields,
  validateQuantityForUnit,
  type UnitOfMeasureSnapshot,
} from "../products/unit-of-measure.util";
import {
  CreatePurchaseInvoiceDto,
  CreatePurchaseOrderPdfShareLinkDto,
  CreatePurchaseOrderDto,
  PurchaseOrderItemDto,
  ReceivePurchaseOrderDto,
  UpsertSupplierDto,
} from "./dto/purchases.dto";
import { InventoryMutationService } from "../inventory/inventory-mutation.service";

type RequestUser = { id: string; role: Role; companyId?: string | null };
type ResolvedPurchaseWarehouse = { id: string; name: string; code: string };
const PURCHASE_TRANSACTION_OPTIONS = { maxWait: 10000, timeout: 30000 } as const;

@Injectable()
export class PurchasesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly r2: R2Service,
    @Optional()
    private readonly inventoryMutations?: InventoryMutationService,
  ) {}

  private includeOrder() {
    return {
      supplier: true,
      createdBy: { select: { id: true, nombreCompleto: true, email: true } },
      approvedBy: { select: { id: true, nombreCompleto: true, email: true } },
      items: {
        orderBy: { createdAt: "asc" },
        include: { product: true, supplier: true },
      },
      receipts: {
        orderBy: { createdAt: "desc" },
        include: {
          items: true,
          receivedBy: { select: { id: true, nombreCompleto: true } },
        },
      },
    } satisfies Prisma.PurchaseOrderInclude;
  }

  private inventoryMutationService() {
    return this.inventoryMutations ?? new InventoryMutationService(this.prisma);
  }

  private isInventoryTrackedProduct(
    product?: { itemType?: ProductItemType | null; trackInventory?: boolean | null } | null,
  ) {
    return (
      (product?.itemType ?? ProductItemType.PRODUCT) ===
        ProductItemType.PRODUCT &&
      (product?.trackInventory ?? true) === true
    );
  }

  private async resolveReceiptWarehouse(
    tx: Prisma.TransactionClient,
    companyId: string,
    requestedWarehouseId?: string | null,
  ): Promise<ResolvedPurchaseWarehouse> {
    if (requestedWarehouseId) {
      const warehouse = await tx.warehouse.findFirst({
        where: { id: requestedWarehouseId, companyId, isActive: true },
        select: { id: true, name: true, code: true },
      });
      if (!warehouse) {
        throw new BadRequestException("Almacen activo no encontrado.");
      }
      return warehouse;
    }

    const defaultWarehouse = await tx.warehouse.findFirst({
      where: { companyId, isDefault: true, isActive: true },
      orderBy: { createdAt: "asc" },
      select: { id: true, name: true, code: true },
    });
    if (defaultWarehouse) return defaultWarehouse;

    const activeWarehouses = await tx.warehouse.findMany({
      where: { companyId, isActive: true },
      orderBy: { createdAt: "asc" },
      take: 2,
      select: { id: true, name: true, code: true },
    });
    if (activeWarehouses.length === 1) return activeWarehouses[0];

    throw new BadRequestException(
      activeWarehouses.length === 0
        ? "No hay almacenes activos para recibir mercancía."
        : "Hay multiples almacenes activos; selecciona un almacen destino.",
    );
  }

  private async ensureWarehouseStock(
    tx: Prisma.TransactionClient,
    companyId: string,
    warehouseId: string,
    productId: string,
  ) {
    await tx.warehouseStock.upsert({
      where: {
        companyId_warehouseId_productId: { companyId, warehouseId, productId },
      },
      create: {
        companyId,
        warehouseId,
        productId,
        quantity: new Prisma.Decimal(0),
      },
      update: {},
    });
  }

  async listSuppliers(user: RequestUser, q?: string, includeInactive = false) {
    const companyId = requireTenant(user);
    const query = (q ?? "").trim();
    const rows = await this.prisma.supplier.findMany({
      where: {
        companyId,
        deletedAt: null,
        ...(includeInactive ? {} : { isActive: true }),
        ...(query
          ? {
              OR: [
                { commercialName: { contains: query, mode: "insensitive" } },
                { legalName: { contains: query, mode: "insensitive" } },
                { phone: { contains: query, mode: "insensitive" } },
                { whatsapp: { contains: query, mode: "insensitive" } },
                { email: { contains: query, mode: "insensitive" } },
              ],
            }
          : {}),
      },
      orderBy: { commercialName: "asc" },
    });
    return this.suppliersWithStats(companyId, rows);
  }

  async createSupplier(user: RequestUser, dto: UpsertSupplierDto) {
    this.validateSupplier(dto);
    return this.prisma.supplier.create({
      data: this.supplierData(requireTenant(user), dto),
    });
  }

  async updateSupplier(user: RequestUser, id: string, dto: UpsertSupplierDto) {
    const companyId = requireTenant(user);
    await this.assertSupplier(companyId, id);
    this.validateSupplier(dto);
    return this.prisma.supplier.update({
      where: { id },
      data: this.supplierData(companyId, dto),
    });
  }

  async deactivateSupplier(user: RequestUser, id: string) {
    const companyId = requireTenant(user);
    await this.assertSupplier(companyId, id);
    return this.prisma.supplier.update({
      where: { id },
      data: { isActive: false, deletedAt: new Date() },
    });
  }

  async listInvoices(user: RequestUser, filters: {
    q?: string;
    supplierId?: string;
    purchaseOrderId?: string;
  }) {
    const companyId = requireTenant(user);
    const q = (filters.q ?? "").trim();
    return this.prisma.purchaseInvoice.findMany({
      where: {
        companyId,
        deletedAt: null,
        ...(this.cleanId(filters.supplierId)
          ? { supplierId: this.cleanId(filters.supplierId)! }
          : {}),
        ...(this.cleanId(filters.purchaseOrderId)
          ? { purchaseOrderId: this.cleanId(filters.purchaseOrderId)! }
          : {}),
        ...(q
          ? {
              OR: [
                { invoiceNumber: { contains: q, mode: "insensitive" } },
                { fileName: { contains: q, mode: "insensitive" } },
                { notes: { contains: q, mode: "insensitive" } },
                {
                  supplier: {
                    commercialName: { contains: q, mode: "insensitive" },
                  },
                },
                {
                  purchaseOrder: {
                    orderNumber: { contains: q, mode: "insensitive" },
                  },
                },
              ],
            }
          : {}),
      },
      orderBy: [{ invoiceDate: "desc" }, { createdAt: "desc" }],
      include: {
        supplier: true,
        purchaseOrder: {
          select: { id: true, orderNumber: true, total: true, orderDate: true },
        },
        uploadedBy: { select: { id: true, nombreCompleto: true } },
      },
    });
  }

  async createInvoice(
    user: RequestUser,
    dto: CreatePurchaseInvoiceDto,
    file: Express.Multer.File,
    requestBaseUrl?: string,
  ) {
    const supplierId = this.cleanId(dto.supplierId);
    if (!supplierId) throw new BadRequestException("Selecciona un suplidor.");
    const companyId = requireTenant(user);
    await this.assertSupplier(companyId, supplierId);

    const purchaseOrderId = this.cleanId(dto.purchaseOrderId);
    if (purchaseOrderId) {
      const order = await this.prisma.purchaseOrder.findFirst({
        where: { id: purchaseOrderId, companyId, deletedAt: null },
        select: { id: true, supplierId: true },
      });
      if (!order) throw new NotFoundException("Orden de compra no encontrada.");
      if (order.supplierId && order.supplierId !== supplierId) {
        throw new BadRequestException(
          "La orden seleccionada pertenece a otro suplidor.",
        );
      }
    }

    const uploaded = await this.persistInvoiceFile(user, file, requestBaseUrl);
    const amount =
      dto.amount == null
        ? null
        : new Prisma.Decimal(dto.amount).toDecimalPlaces(2);
    if (amount?.lt(0)) {
      throw new BadRequestException("El monto no puede ser negativo.");
    }

    return this.prisma.purchaseInvoice.create({
      data: {
        companyId,
        supplierId,
        purchaseOrderId,
        invoiceNumber: this.clean(dto.invoiceNumber),
        invoiceDate: this.parseDate(dto.invoiceDate) ?? new Date(),
        amount,
        currency: (this.clean(dto.currency) ?? "DOP").slice(0, 8).toUpperCase(),
        fileName: uploaded.fileName,
        fileUrl: uploaded.fileUrl,
        storageKey: uploaded.storageKey,
        mimeType: uploaded.mimeType,
        fileSize: uploaded.fileSize,
        notes: this.clean(dto.notes),
        uploadedById: user.id,
      },
      include: {
        supplier: true,
        purchaseOrder: {
          select: { id: true, orderNumber: true, total: true, orderDate: true },
        },
        uploadedBy: { select: { id: true, nombreCompleto: true } },
      },
    });
  }

  async deleteInvoice(user: RequestUser, id: string) {
    const companyId = requireTenant(user);
    const updated = await this.prisma.purchaseInvoice.updateMany({
      where: { id, companyId },
      data: { deletedAt: new Date() },
    });
    if (updated.count !== 1) {
      throw new NotFoundException("Factura de compra no encontrada.");
    }
    return { ok: true };
  }

  async listOrders(
    user: RequestUser,
    filters: { q?: string; status?: string; supplierId?: string },
  ) {
    const companyId = requireTenant(user);
    const q = (filters.q ?? "").trim();
    const status = this.parseStatus(filters.status, false);
    return this.prisma.purchaseOrder.findMany({
      where: {
        companyId,
        deletedAt: null,
        ...(this.canSeeAll(user) ? {} : { createdById: user.id }),
        ...(status ? { status } : {}),
        ...(filters.supplierId ? { supplierId: filters.supplierId } : {}),
        ...(q
          ? {
              OR: [
                { orderNumber: { contains: q, mode: "insensitive" } },
                {
                  supplier: {
                    commercialName: { contains: q, mode: "insensitive" },
                  },
                },
                {
                  items: {
                    some: {
                      productNameSnapshot: { contains: q, mode: "insensitive" },
                    },
                  },
                },
              ],
            }
          : {}),
      },
      orderBy: { orderDate: "desc" },
      include: this.includeOrder(),
    });
  }

  async getOrder(user: RequestUser, id: string) {
    const order = await this.prisma.purchaseOrder.findFirst({
      where: {
        id,
        companyId: requireTenant(user),
        deletedAt: null,
        ...(this.canSeeAll(user) ? {} : { createdById: user.id }),
      },
      include: this.includeOrder(),
    });
    if (!order) throw new NotFoundException("Orden de compra no encontrada.");
    return order;
  }

  async createOrder(user: RequestUser, dto: CreatePurchaseOrderDto) {
    const companyId = requireTenant(user);
    const items = await this.normalizeItems(companyId, dto.items ?? []);
    const totals = this.computeTotals(items, dto);
    const supplierId = this.cleanId(dto.supplierId);
    if (supplierId) await this.assertSupplier(companyId, supplierId);
    return this.createOrderWithNumberRetry(async () =>
      this.prisma.$transaction(async (tx) => {
        const orderNumber = await this.nextOrderNumber(tx, companyId);
        return tx.purchaseOrder.create({
          data: {
            companyId,
            orderNumber,
            supplierId,
            expectedDeliveryDate: this.parseDate(dto.expectedDeliveryDate),
            discount: totals.discount,
            shippingCost: totals.shippingCost,
            additionalCost: totals.additionalCost,
            tax: totals.tax,
            subtotal: totals.subtotal,
            total: totals.total,
            paymentTerms: this.clean(dto.paymentTerms),
            paymentMethod: this.clean(dto.paymentMethod),
            shippingMethod: this.clean(dto.shippingMethod),
            notes: this.clean(dto.notes),
            supplierInstructions: this.clean(dto.supplierInstructions),
            createdById: user.id,
            items: { create: items.map((item) => item.data) },
          },
          include: this.includeOrder(),
        });
      }, PURCHASE_TRANSACTION_OPTIONS),
    );
  }

  async updateOrder(
    user: RequestUser,
    id: string,
    dto: CreatePurchaseOrderDto,
  ) {
    const current = await this.getOrder(user, id);
    if (
      current.status === PurchaseOrderStatus.RECEIVED ||
      current.status === PurchaseOrderStatus.CANCELLED
    ) {
      throw new BadRequestException("Esta orden ya no puede editarse.");
    }
    if (
      current.status !== PurchaseOrderStatus.DRAFT &&
      !this.canApprove(user)
    ) {
      throw new ForbiddenException(
        "Necesitas permiso para editar una orden aprobada o enviada.",
      );
    }
    const companyId = requireTenant(user);
    const items = await this.normalizeItems(companyId, dto.items ?? []);
    const totals = this.computeTotals(items, dto);
    const supplierId = this.cleanId(dto.supplierId);
    if (supplierId) await this.assertSupplier(companyId, supplierId);
    return this.prisma.$transaction(async (tx) => {
      await tx.purchaseOrderItem.deleteMany({ where: { purchaseOrderId: id } });
      return tx.purchaseOrder.update({
        where: { id },
        data: {
          supplierId,
          expectedDeliveryDate: this.parseDate(dto.expectedDeliveryDate),
          discount: totals.discount,
          shippingCost: totals.shippingCost,
          additionalCost: totals.additionalCost,
          tax: totals.tax,
          subtotal: totals.subtotal,
          total: totals.total,
          paymentTerms: this.clean(dto.paymentTerms),
          paymentMethod: this.clean(dto.paymentMethod),
          shippingMethod: this.clean(dto.shippingMethod),
          notes: this.clean(dto.notes),
          supplierInstructions: this.clean(dto.supplierInstructions),
          items: { create: items.map((item) => item.data) },
        },
        include: this.includeOrder(),
      });
    });
  }

  async duplicateOrder(user: RequestUser, id: string) {
    const order = await this.getOrder(user, id);
    return this.createOrder(user, {
      supplierId: order.supplierId ?? undefined,
      expectedDeliveryDate: order.expectedDeliveryDate?.toISOString(),
      discount: this.num(order.discount),
      shippingCost: this.num(order.shippingCost),
      additionalCost: this.num(order.additionalCost),
      tax: this.num(order.tax),
      paymentTerms: order.paymentTerms ?? undefined,
      paymentMethod: order.paymentMethod ?? undefined,
      shippingMethod: order.shippingMethod ?? undefined,
      notes: order.notes ?? undefined,
      supplierInstructions: order.supplierInstructions ?? undefined,
      items: order.items.map((item) => ({
        productId: item.productId ?? undefined,
        externalProductId: item.externalProductId ?? undefined,
        productName: item.productNameSnapshot,
        productCode: item.productCodeSnapshot ?? undefined,
        description: item.descriptionSnapshot ?? undefined,
        image: item.imageSnapshot ?? undefined,
        quantity: this.num(item.quantity),
        unitCost: this.num(item.unitCost),
        supplierId: item.supplierId ?? undefined,
        notes: item.notes ?? undefined,
        createInventoryProductOnReceipt: item.createInventoryProductOnReceipt,
      })),
    });
  }

  async approveOrder(user: RequestUser, id: string) {
    const order = await this.getOrder(user, id);
    if (!order.items.length)
      throw new BadRequestException("Agrega al menos un producto.");
    if (!order.supplierId)
      throw new BadRequestException("Selecciona un suplidor para continuar.");
    return this.prisma.purchaseOrder.update({
      where: { id },
      data: {
        status: PurchaseOrderStatus.APPROVED,
        approvedById: user.id,
        approvedAt: new Date(),
      },
      include: this.includeOrder(),
    });
  }

  async markSent(user: RequestUser, id: string) {
    await this.getOrder(user, id);
    return this.prisma.purchaseOrder.update({
      where: { id },
      data: { status: PurchaseOrderStatus.SENT, sentAt: new Date() },
      include: this.includeOrder(),
    });
  }

  async cancelOrder(user: RequestUser, id: string, reason?: string) {
    await this.getOrder(user, id);
    return this.prisma.purchaseOrder.update({
      where: { id },
      data: {
        status: PurchaseOrderStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: this.clean(reason),
      },
      include: this.includeOrder(),
    });
  }

  async deleteDraft(user: RequestUser, id: string) {
    await this.getOrder(user, id);
    await this.prisma.purchaseOrder.update({
      where: { id },
      data: { deletedAt: new Date() },
    });
    return { ok: true };
  }

  async receiveOrder(
    user: RequestUser,
    id: string,
    dto: ReceivePurchaseOrderDto,
  ) {
    const order = await this.getOrder(user, id);
    const clientRequestId = this.clean(dto.clientRequestId);
    if (clientRequestId) {
      const existingReceipt = await this.prisma.purchaseReceipt.findFirst({
        where: { purchaseOrderId: id, clientRequestId },
        include: { items: true },
      });
      if (existingReceipt) return { receipt: existingReceipt, order };
    }
    if (order.status === PurchaseOrderStatus.CANCELLED) {
      throw new BadRequestException(
        "Una orden cancelada no puede recibir mercancía.",
      );
    }
    const company = await this.prisma.company.findUnique({
      where: { id: order.companyId },
      select: { inventoryEnabled: true },
    });
    const inventoryEnabled = company?.inventoryEnabled !== false;
    const itemMap = new Map(order.items.map((item) => [item.id, item]));
    const normalized = dto.items.map((item) => {
      const current = itemMap.get(item.purchaseOrderItemId);
      if (!current)
        throw new BadRequestException("Producto de orden inválido.");
      const qty = new Prisma.Decimal(item.quantityReceived);
      const pending = new Prisma.Decimal(current.pendingQuantity);
      if (qty.lte(0))
        throw new BadRequestException(
          "La cantidad recibida debe ser mayor que cero.",
        );
      if (qty.greaterThan(pending))
        throw new BadRequestException(
          `La cantidad recibida supera lo pendiente para ${current.productNameSnapshot}.`,
        );
      const unit = {
        code: current.unitCodeSnapshot,
        name: current.unitNameSnapshot,
        symbol: current.unitSymbolSnapshot,
        precision: current.unitPrecisionSnapshot,
        allowDecimals: current.unitPrecisionSnapshot > 0,
      };
      validateQuantityForUnit({
        quantity: qty,
        unit,
        label: `recepción de ${current.productNameSnapshot}`,
      });
      return {
        current,
        quantityReceived: qty,
        unit,
        unitCost: new Prisma.Decimal(item.unitCost),
        condition: this.clean(item.condition),
        notes: this.clean(item.notes),
      };
    });

    const shouldUpdateLineInventory = (item: (typeof normalized)[number]) => {
      if (!dto.updateInventory || !inventoryEnabled) return false;
      if (item.current.productId) {
        return this.isInventoryTrackedProduct(item.current.product);
      }
      return item.current.createInventoryProductOnReceipt === true;
    };
    const hasInventoryUpdates = normalized.some((item) =>
      shouldUpdateLineInventory(item),
    );

    if (dto.updateInventory && hasInventoryUpdates) {
      for (const item of normalized) {
        if (!shouldUpdateLineInventory(item)) continue;
        if (
          item.current.productSource &&
          item.current.productSource !== ProductSource.LOCAL
        ) {
          throw new BadRequestException(
            "Recepciones de productos FULLPOS requieren stock writable validado.",
          );
        }
        if (
          !item.current.productId &&
          !item.current.createInventoryProductOnReceipt
        ) {
          throw new BadRequestException(
            "La recepcion requiere producto local o creacion de producto de inventario.",
          );
        }
      }
    }

    try {
      return await this.prisma.$transaction(async (tx) => {
      const destinationWarehouse = hasInventoryUpdates
        ? await this.resolveReceiptWarehouse(
            tx,
            order.companyId,
            dto.destinationWarehouseId ?? dto.warehouseId,
          )
        : null;

      const receipt = await tx.purchaseReceipt.create({
        data: {
          purchaseOrderId: id,
          clientRequestId,
          supplierInvoiceNumber: this.clean(dto.supplierInvoiceNumber),
          notes: this.clean(dto.notes),
          invoiceImage: this.clean(dto.invoiceImage),
          receivedById: user.id,
          inventoryUpdated: hasInventoryUpdates,
          inventoryUpdatedAt: hasInventoryUpdates ? new Date() : null,
        },
      });

      for (const item of normalized) {
        const claimed = await tx.purchaseOrderItem.updateMany({
          where: {
            id: item.current.id,
            purchaseOrderId: id,
            pendingQuantity: { gte: item.quantityReceived },
          },
          data: {
            receivedQuantity: { increment: item.quantityReceived },
            pendingQuantity: { decrement: item.quantityReceived },
            actualUnitCost: item.unitCost,
          },
        });
        if (claimed.count !== 1) {
          throw new BadRequestException(
            `La cantidad recibida supera lo pendiente para ${item.current.productNameSnapshot}.`,
          );
        }

        let productId = item.current.productId;
        const updateLineInventory = shouldUpdateLineInventory(item);
        if (dto.updateInventory) {
          if (
            updateLineInventory &&
            item.current.productSource &&
            item.current.productSource !== ProductSource.LOCAL
          ) {
            throw new BadRequestException(
              "Recepciones de productos FULLPOS requieren stock writable validado.",
            );
          }
          if (productId) {
            await tx.product.updateMany({
              where: {
                id: productId,
                companyId: order.companyId,
                archivedAt: null,
              },
              data: { costo: item.unitCost },
            });
          } else if (updateLineInventory && item.current.createInventoryProductOnReceipt) {
            const created = await tx.product.create({
              data: {
                companyId: order.companyId ?? requireTenant(user),
                nombre: item.current.productNameSnapshot,
                categoria:
                  item.current.descriptionSnapshot?.slice(0, 80) ||
                  "Sin categoría",
                precio: item.unitCost,
                costo: item.unitCost,
                stock: new Prisma.Decimal(0),
                imagen: item.current.imageSnapshot,
                unitOfMeasureId: item.unit.code,
              },
            });
            await tx.purchaseOrderItem.update({
              where: { id: item.current.id },
              data: { productId: created.id },
            });
            productId = created.id;
          }
        }

        const receiptItem = await tx.purchaseReceiptItem.create({
          data: {
            purchaseReceiptId: receipt.id,
            purchaseOrderItemId: item.current.id,
            productSource: item.current.productSource,
            sourceProductId: productId ?? item.current.sourceProductId,
            destinationWarehouseId: destinationWarehouse?.id ?? null,
            warehouseNameSnapshot: destinationWarehouse?.name ?? null,
            warehouseCodeSnapshot: destinationWarehouse?.code ?? null,
            quantityReceived: item.quantityReceived,
            unitCodeSnapshot: item.unit.code,
            unitNameSnapshot: item.unit.name,
            unitSymbolSnapshot: item.unit.symbol,
            unitPrecisionSnapshot: item.unit.precision,
            unitCost: item.unitCost,
            condition: item.condition,
            notes: item.notes,
          },
        });

        if (updateLineInventory && productId && destinationWarehouse) {
          await this.ensureWarehouseStock(
            tx,
            order.companyId,
            destinationWarehouse.id,
            productId,
          );
          const movement =
            await this.inventoryMutationService().increaseStockInTransaction(tx, {
              companyId: order.companyId,
              productId,
              warehouseId: destinationWarehouse.id,
              quantity: item.quantityReceived,
              type: InventoryMovementType.PURCHASE_RECEIPT,
              sourceType: "PURCHASE_RECEIPT",
              sourceId: receipt.id,
              sourceItemId: receiptItem.id,
              reason: "PURCHASE_RECEIPT",
              createdByUserId: user.id,
            });
          await tx.purchaseReceiptItem.update({
            where: { id: receiptItem.id },
            data: { inventoryMovementId: movement.movementId },
          });
        } else if (updateLineInventory && !productId) {
          throw new BadRequestException(
            "La recepcion requiere producto local o creacion de producto de inventario.",
          );
        }
      }

      const refreshedItems = await tx.purchaseOrderItem.findMany({
        where: { purchaseOrderId: id },
      });
      const allReceived = refreshedItems.every((item) =>
        new Prisma.Decimal(item.pendingQuantity).lte(0),
      );
      const someReceived = refreshedItems.some((item) =>
        new Prisma.Decimal(item.receivedQuantity).gt(0),
      );
      const status = allReceived
        ? PurchaseOrderStatus.RECEIVED
        : someReceived
          ? PurchaseOrderStatus.PARTIALLY_RECEIVED
          : order.status;
      const updated = await tx.purchaseOrder.update({
        where: { id },
        data: { status },
        include: this.includeOrder(),
      });
      const refreshedReceipt = await tx.purchaseReceipt.findUniqueOrThrow({
        where: { id: receipt.id },
        include: { items: true },
      });
      return { receipt: refreshedReceipt, order: updated };
    }, PURCHASE_TRANSACTION_OPTIONS);
    } catch (error) {
      if (
        clientRequestId &&
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const existingReceipt = await this.prisma.purchaseReceipt.findFirst({
          where: { purchaseOrderId: id, clientRequestId },
          include: { items: true },
        });
        const updatedOrder = await this.getOrder(user, id);
        if (existingReceipt) return { receipt: existingReceipt, order: updatedOrder };
      }
      throw error;
    }
  }

  async recommendations(user: RequestUser) {
    const companyId = requireTenant(user);
    const products = await this.prisma.product.findMany({
      where: { companyId },
      orderBy: { nombre: "asc" },
    });
    const pending = await this.prisma.purchaseOrderItem.groupBy({
      by: ["productId"],
      where: {
        productId: { not: null },
        purchaseOrder: {
          companyId,
          deletedAt: null,
          status: {
            in: [
              PurchaseOrderStatus.APPROVED,
              PurchaseOrderStatus.SENT,
              PurchaseOrderStatus.PARTIALLY_RECEIVED,
            ],
          },
        },
      },
      _sum: { pendingQuantity: true },
    });
    const ordered = new Map(
      pending.map((row) => [row.productId, this.num(row._sum.pendingQuantity)]),
    );
    return products.map((product) => {
      const stock = this.num(product.stock);
      const minStock = 5;
      const alreadyOrdered = ordered.get(product.id) ?? 0;
      const suggested = Math.max(0, minStock * 2 - stock - alreadyOrdered);
      const reason =
        stock <= 0
          ? "Agotado"
          : stock < minStock
            ? "Por debajo del mínimo"
            : suggested > 0
              ? "Compra recomendada"
              : "Disponible";
      return {
        product,
        stock,
        minStock,
        alreadyOrdered,
        suggestedQuantity: suggested,
        reason,
      };
    });
  }

  async createPdfShareLink(
    user: RequestUser,
    dto: CreatePurchaseOrderPdfShareLinkDto,
    requestBaseUrl?: string,
  ) {
    const purchaseOrderId = dto.purchaseOrderId.trim();
    await this.getOrder(user, purchaseOrderId);

    const bytes = this.parsePdfBase64(dto.pdfBase64);
    const fileName = this.sanitizePdfFileName(
      dto.fileName ?? "",
      `orden_compra_${purchaseOrderId.slice(0, 8)}.pdf`,
    );
    const orderDir = path.join(
      this.resolveUploadDir(),
      "compras",
      purchaseOrderId,
    );
    await mkdir(orderDir, { recursive: true });
    await writeFile(path.join(orderDir, fileName), bytes);

    const baseUrl = this.publicBaseUrl(requestBaseUrl);
    if (!baseUrl) {
      throw new BadRequestException(
        "No se pudo construir el enlace público del PDF. Configura PUBLIC_BASE_URL o API_BASE_URL.",
      );
    }

    return {
      ok: true,
      purchaseOrderId,
      fileName,
      pdfUrl: `${baseUrl}/purchases/public/pdf/${encodeURIComponent(purchaseOrderId)}/${encodeURIComponent(fileName)}`,
      expiresIn: null,
      createdAt: new Date().toISOString(),
    };
  }

  async resolvePublicPdfDownload(purchaseOrderId: string, fileName: string) {
    const safeOrderId = (purchaseOrderId ?? "").trim();
    const safeFileName = this.sanitizePdfFileName(
      fileName ?? "",
      "orden_compra.pdf",
    );
    if (
      !safeOrderId ||
      safeOrderId.includes("/") ||
      safeOrderId.includes("\\")
    ) {
      throw new NotFoundException("PDF de orden de compra no encontrado.");
    }

    const absolutePath = path.join(
      this.resolveUploadDir(),
      "compras",
      safeOrderId,
      safeFileName,
    );
    if (!fs.existsSync(absolutePath)) {
      throw new NotFoundException("PDF de orden de compra no encontrado.");
    }

    return { absolutePath, fileName: safeFileName };
  }

  private async persistInvoiceFile(
    user: RequestUser,
    file: Express.Multer.File,
    requestBaseUrl?: string,
  ) {
    if (!file.buffer?.length) {
      throw new BadRequestException(
        "No se pudo leer el archivo de la factura.",
      );
    }
    const original = this.sanitizeUploadFileName(
      file.originalname || "factura-compra",
    );
    const ext = this.safeInvoiceExtension(original, file.mimetype);
    const baseName = path
      .basename(original, path.extname(original))
      .replace(/[^a-zA-Z0-9_-]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 80);
    const now = new Date();
    const storedName = `${Date.now()}-${randomUUID()}-${baseName || "factura"}${ext}`;
    const storageKey = buildTenantObjectKey({
      companyId: requireTenant(user),
      area: "compras",
      kind: "facturas",
      ownerId: user.id,
      fileName: storedName,
      extension: ext,
      now,
    });
    const absolutePath = path.join(
      this.resolveUploadDir(),
      ...storageKey.split("/"),
    );
    await mkdir(path.dirname(absolutePath), { recursive: true });
    await writeFile(absolutePath, file.buffer);
    try {
      await this.r2.putObject({
        objectKey: `uploads/${storageKey}`,
        body: file.buffer,
        contentType: this.safeInvoiceMimeType(file.mimetype, ext),
      });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn(
        "[purchases/invoices] R2 mirror failed, local file is used:",
        error,
      );
    }
    const baseUrl = this.publicBaseUrl(requestBaseUrl);
    return {
      fileName: original.endsWith(ext) ? original : `${original}${ext}`,
      storageKey,
      fileUrl: baseUrl
        ? `${baseUrl}/uploads/${storageKey
            .split("/")
            .map((part) => encodeURIComponent(part))
            .join("/")}`
        : `/uploads/${storageKey}`,
      mimeType: this.safeInvoiceMimeType(file.mimetype, ext),
      fileSize: file.size ?? file.buffer.length,
    };
  }

  private async normalizeItems(companyId: string, items: PurchaseOrderItemDto[]) {
    const productIds = [
      ...new Set(
        items
          .map((item) => item.productId)
          .filter((id): id is string => Boolean(id)),
      ),
    ];
    const products = productIds.length
      ? await this.prisma.product.findMany({
          where: { id: { in: productIds }, companyId, archivedAt: null },
          include: {
            unitOfMeasure: {
              select: {
                code: true,
                name: true,
                symbol: true,
                allowDecimals: true,
                precision: true,
              },
            },
          },
        })
      : [];
    const supplierIds = [
      ...new Set(
        items
          .map((item) => this.cleanId(item.supplierId))
          .filter((id): id is string => Boolean(id)),
      ),
    ];
    const suppliers = supplierIds.length
      ? await this.prisma.supplier.findMany({
          where: { id: { in: supplierIds }, companyId, deletedAt: null },
          select: { id: true },
        })
      : [];
    const validSupplierIds = new Set(suppliers.map((supplier) => supplier.id));
    const productMap = new Map(
      products.map((product) => [product.id, product]),
    );
    return items.map((item, index) => {
      const product = item.productId ? productMap.get(item.productId) : null;
      if (item.productId && !product)
        throw new BadRequestException(
          `Producto inválido en línea ${index + 1}.`,
        );
      const name = (product?.nombre ?? item.productName ?? "").trim();
      if (!name)
        throw new BadRequestException(
          `Producto sin nombre en línea ${index + 1}.`,
        );
      const quantity = new Prisma.Decimal(item.quantity);
      const unitCost = new Prisma.Decimal(item.unitCost);
      if (quantity.lte(0))
        throw new BadRequestException(
          "Las cantidades deben ser mayores que cero.",
        );
      if (product) {
        validateQuantityForUnit({
          quantity,
          unit: product.unitOfMeasure as UnitOfMeasureSnapshot,
          label: `línea ${index + 1}`,
        });
      }
      if (unitCost.lt(0))
        throw new BadRequestException("Los montos no pueden ser negativos.");
      const unitFields = unitSnapshotFields(
        (product?.unitOfMeasure as UnitOfMeasureSnapshot | undefined) ??
          DEFAULT_UNIT_OF_MEASURE,
      );
      const subtotal = quantity.mul(unitCost).toDecimalPlaces(2);
      return {
        data: {
          productId: product?.id,
          externalProductId: this.cleanId(item.externalProductId),
          productSource: product
            ? ProductSource.LOCAL
            : this.normalizeProductSource(item.productSource),
          sourceProductId: product
            ? product.id
            : this.clean(item.sourceProductId),
          productNameSnapshot: name,
          productCodeSnapshot: this.clean(item.productCode),
          descriptionSnapshot: this.clean(item.description),
          imageSnapshot: this.clean(product?.imagen ?? item.image),
          quantity,
          receivedQuantity: new Prisma.Decimal(0),
          pendingQuantity: quantity,
          ...unitFields,
          unitCost,
          subtotal,
          supplierId: this.validatedSupplierId(
            validSupplierIds,
            item.supplierId,
            index,
          ),
          notes: this.clean(item.notes),
          createInventoryProductOnReceipt: Boolean(
            item.createInventoryProductOnReceipt,
          ),
        },
        subtotal,
      };
    });
  }

  private normalizeProductSource(value: unknown): ProductSource | null {
    const source = String(value ?? "").trim().toUpperCase();
    if (
      source === "LOCAL" ||
      source === "FULLPOS" ||
      source === "FULLPOS_DIRECT"
    ) {
      return source as ProductSource;
    }
    return null;
  }

  private computeTotals(
    items: Array<{ subtotal: Prisma.Decimal }>,
    dto: CreatePurchaseOrderDto,
  ) {
    const subtotal = items
      .reduce((acc, item) => acc.plus(item.subtotal), new Prisma.Decimal(0))
      .toDecimalPlaces(2);
    const discount = new Prisma.Decimal(dto.discount ?? 0).toDecimalPlaces(2);
    const shippingCost = new Prisma.Decimal(
      dto.shippingCost ?? 0,
    ).toDecimalPlaces(2);
    const additionalCost = new Prisma.Decimal(
      dto.additionalCost ?? 0,
    ).toDecimalPlaces(2);
    const tax = new Prisma.Decimal(dto.tax ?? 0).toDecimalPlaces(2);
    for (const amount of [discount, shippingCost, additionalCost, tax]) {
      if (amount.lt(0))
        throw new BadRequestException("Los montos no pueden ser negativos.");
    }
    const total = subtotal
      .minus(discount)
      .plus(shippingCost)
      .plus(additionalCost)
      .plus(tax)
      .toDecimalPlaces(2);
    if (total.lt(0))
      throw new BadRequestException("El total no puede ser negativo.");
    return { subtotal, discount, shippingCost, additionalCost, tax, total };
  }

  private async nextOrderNumber(tx: Prisma.TransactionClient, companyId: string) {
    const scope = companyId;
    await tx.$executeRaw`
      INSERT INTO purchase_order_sequences (scope, next_value, updated_at)
      VALUES (${scope}, 0, now())
      ON CONFLICT (scope) DO NOTHING
    `;
    const [sequence] = await tx.$queryRaw<Array<{ next_value: number }>>`
      SELECT next_value
      FROM purchase_order_sequences
      WHERE scope = ${scope}
      FOR UPDATE
    `;
    const [historical] = await tx.$queryRaw<Array<{ highest: number | null }>>`
      SELECT COALESCE(MAX(substring(order_number from 4)::integer), 0)::integer AS highest
      FROM purchase_orders
      WHERE company_id = ${companyId}::uuid
        AND order_number ~ '^OC-[0-9]{6}$'
    `;
    const storedCurrent = Number(sequence?.next_value ?? 0);
    const historicalCurrent = Number(historical?.highest ?? 0);
    const number = Math.max(storedCurrent, historicalCurrent) + 1;
    await tx.purchaseOrderSequence.update({
      where: { scope },
      data: { nextValue: number },
    });
    return `OC-${number.toString().padStart(6, "0")}`;
  }

  private async createOrderWithNumberRetry<T>(fn: () => Promise<T>) {
    let lastError: unknown;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;
        if (!this.isPurchaseOrderNumberConflict(error)) throw error;
      }
    }
    throw lastError;
  }

  private isPurchaseOrderNumberConflict(error: unknown) {
    if (
      !(error instanceof Prisma.PrismaClientKnownRequestError) ||
      error.code !== "P2002"
    ) {
      return false;
    }
    const target = error.meta?.target;
    return (
      Array.isArray(target) &&
      target.includes("company_id") &&
      target.includes("order_number")
    );
  }

  private async suppliersWithStats(
    companyId: string,
    rows: Array<{ id: string; [key: string]: unknown }>,
  ) {
    const ids = rows.map((row) => row.id);
    if (!ids.length) return rows;

    const [totals, latestRows] = await Promise.all([
      this.prisma.purchaseOrder.groupBy({
        by: ["supplierId"],
        where: {
          supplierId: { in: ids },
          companyId,
          deletedAt: null,
          status: { not: PurchaseOrderStatus.CANCELLED },
        },
        _count: { _all: true },
        _sum: { total: true },
      }),
      this.prisma.purchaseOrder.findMany({
        where: { supplierId: { in: ids }, companyId, deletedAt: null },
        orderBy: [{ supplierId: "asc" }, { orderDate: "desc" }],
        select: {
          supplierId: true,
          orderNumber: true,
          orderDate: true,
          total: true,
          status: true,
        },
      }),
    ]);

    const stats = new Map(
      totals
        .filter((row) => row.supplierId)
        .map((row) => [
          row.supplierId!,
          {
            ordersCount: row._count._all,
            totalPurchased: this.num(row._sum.total),
          },
        ]),
    );
    const latest = new Map<
      string,
      {
        orderNumber: string;
        orderDate: Date;
        total: Prisma.Decimal;
        status: PurchaseOrderStatus;
      }
    >();
    for (const row of latestRows) {
      if (row.supplierId && !latest.has(row.supplierId)) {
        latest.set(row.supplierId, {
          orderNumber: row.orderNumber,
          orderDate: row.orderDate,
          total: row.total,
          status: row.status,
        });
      }
    }

    return rows.map((row) => {
      const stat = stats.get(row.id);
      return {
        ...row,
        ordersCount: stat?.ordersCount ?? 0,
        totalPurchased: stat?.totalPurchased ?? 0,
        latestPurchase: latest.get(row.id) ?? null,
      };
    });
  }

  private validateSupplier(dto: UpsertSupplierDto) {
    if (!this.clean(dto.commercialName))
      throw new BadRequestException("El nombre comercial es obligatorio.");
  }

  private validatedSupplierId(
    validSupplierIds: Set<string>,
    value: string | undefined,
    index: number,
  ) {
    const supplierId = this.cleanId(value);
    if (!supplierId) return null;
    if (!validSupplierIds.has(supplierId)) {
      throw new BadRequestException(
        `Suplidor inválido en línea ${index + 1}.`,
      );
    }
    return supplierId;
  }

  private supplierData(
    companyId: string,
    dto: UpsertSupplierDto,
  ): Prisma.SupplierUncheckedCreateInput {
    return {
      companyId,
      commercialName: this.clean(dto.commercialName)!,
      legalName: this.clean(dto.legalName),
      taxId: this.clean(dto.taxId),
      contactName: this.clean(dto.contactName),
      phone: this.clean(dto.phone),
      whatsapp: this.clean(dto.whatsapp),
      email: this.clean(dto.email),
      address: this.clean(dto.address),
      city: this.clean(dto.city),
      country: this.clean(dto.country),
      website: this.clean(dto.website),
      paymentTerms: this.clean(dto.paymentTerms),
      estimatedDeliveryDays: dto.estimatedDeliveryDays ?? null,
      notes: this.clean(dto.notes),
      logo: this.clean(dto.logo),
      isActive: dto.isActive ?? true,
    };
  }

  private async assertSupplier(companyId: string, id: string) {
    const supplier = await this.prisma.supplier.findFirst({
      where: { id, companyId, deletedAt: null },
    });
    if (!supplier) throw new NotFoundException("Suplidor no encontrado.");
    return supplier;
  }

  private parseStatus(
    value?: string,
    throwOnInvalid = true,
  ): PurchaseOrderStatus | null {
    const raw = (value ?? "").trim().toUpperCase();
    if (!raw) return null;
    if (Object.values(PurchaseOrderStatus).includes(raw as PurchaseOrderStatus))
      return raw as PurchaseOrderStatus;
    if (throwOnInvalid)
      throw new BadRequestException("Estado de orden inválido.");
    return null;
  }

  private canSeeAll(user: RequestUser) {
    return user.role === Role.ADMIN || user.role === Role.ASISTENTE;
  }

  private canApprove(user: RequestUser) {
    return user.role === Role.ADMIN || user.role === Role.ASISTENTE;
  }

  private parseDate(value?: string) {
    if (!value?.trim()) return null;
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime()))
      throw new BadRequestException("Fecha inválida.");
    return parsed;
  }

  private clean(value?: string | null) {
    const text = (value ?? "").trim();
    return text ? text : null;
  }

  private sanitizeUploadFileName(value: string) {
    const base = path.basename(value || "factura-compra");
    return (
      base
        .normalize("NFKD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-zA-Z0-9._ -]+/g, "_")
        .replace(/\s+/g, "_")
        .replace(/^_+|_+$/g, "")
        .slice(0, 160) || "factura-compra"
    );
  }

  private safeInvoiceExtension(fileName: string, mimeType: string) {
    const ext = path.extname(fileName).toLowerCase();
    if (/^\.(png|jpe?g|webp|pdf|doc|docx|xls|xlsx)$/.test(ext)) return ext;
    if (mimeType === "application/pdf") return ".pdf";
    if (mimeType === "image/png") return ".png";
    if (mimeType === "image/webp") return ".webp";
    if (mimeType === "image/jpeg" || mimeType === "image/jpg") return ".jpg";
    if (mimeType === "application/msword") return ".doc";
    if (
      mimeType ===
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ) {
      return ".docx";
    }
    if (mimeType === "application/vnd.ms-excel") return ".xls";
    if (
      mimeType ===
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    ) {
      return ".xlsx";
    }
    return ".pdf";
  }

  private safeInvoiceMimeType(mimeType: string, ext: string) {
    if (mimeType) return mimeType;
    if (ext === ".pdf") return "application/pdf";
    if (ext === ".png") return "image/png";
    if (ext === ".webp") return "image/webp";
    if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
    if (ext === ".doc") return "application/msword";
    if (ext === ".docx") {
      return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    }
    if (ext === ".xls") return "application/vnd.ms-excel";
    if (ext === ".xlsx") {
      return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    }
    return "application/octet-stream";
  }

  private cleanId(value?: string | null) {
    return this.clean(value);
  }

  private num(value: Prisma.Decimal | number | string | null | undefined) {
    if (value === null || value === undefined) return 0;
    return Number(value);
  }

  private parsePdfBase64(value: string) {
    const trimmed = (value ?? "").trim();
    if (!trimmed)
      throw new BadRequestException(
        "Debes enviar el PDF de la orden de compra.",
      );
    const base64 = trimmed.startsWith("data:")
      ? trimmed.slice(trimmed.indexOf(",") + 1)
      : trimmed;
    const bytes = Buffer.from(base64, "base64");
    if (!bytes.length)
      throw new BadRequestException(
        "El PDF de la orden de compra llegó vacío.",
      );
    const maxPdfBytes = 8 * 1024 * 1024;
    if (bytes.length > maxPdfBytes) {
      const sizeMb = (bytes.length / (1024 * 1024)).toFixed(2);
      throw new BadRequestException(
        `El PDF de la orden de compra pesa ${sizeMb} MB y supera el límite de 8 MB.`,
      );
    }
    return bytes;
  }

  private resolveUploadDir() {
    const fromEnv = (this.config.get<string>("UPLOAD_DIR") ?? "").trim();
    const volumeDir = "/uploads";
    const volumeExists = fs.existsSync(volumeDir);
    if (fromEnv) {
      if ((fromEnv === "./uploads" || fromEnv === "uploads") && volumeExists)
        return volumeDir;
      return fromEnv;
    }
    return volumeExists ? volumeDir : path.join(process.cwd(), "uploads");
  }

  private publicBaseUrl(requestBaseUrl?: string) {
    const raw =
      (this.config.get<string>("PUBLIC_BASE_URL") ?? "").trim() ||
      (this.config.get<string>("API_BASE_URL") ?? "").trim() ||
      (process.env.PUBLIC_BASE_URL ?? "").trim() ||
      (process.env.API_BASE_URL ?? "").trim() ||
      (requestBaseUrl ?? "").trim();
    return raw.replace(/\/+$/, "");
  }

  private sanitizePdfFileName(value: string, fallback: string) {
    const source = (value || fallback).trim() || fallback;
    const base = path
      .basename(source)
      .replace(/[^a-zA-Z0-9._-]+/g, "_")
      .replace(/^_+|_+$/g, "");
    const withExt = base.toLowerCase().endsWith(".pdf") ? base : `${base}.pdf`;
    return withExt || fallback;
  }
}
