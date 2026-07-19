import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma, PurchaseOrderStatus, Role } from "@prisma/client";
import * as fs from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import * as path from "node:path";
import { PrismaService } from "../prisma/prisma.service";
import {
  CreatePurchaseOrderPdfShareLinkDto,
  CreatePurchaseOrderDto,
  PurchaseOrderItemDto,
  ReceivePurchaseOrderDto,
  UpsertSupplierDto,
} from "./dto/purchases.dto";

type RequestUser = { id: string; role: Role };

@Injectable()
export class PurchasesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  private includeOrder() {
    return {
      supplier: true,
      createdBy: { select: { id: true, nombreCompleto: true, email: true } },
      approvedBy: { select: { id: true, nombreCompleto: true, email: true } },
      items: { orderBy: { createdAt: "asc" }, include: { product: true, supplier: true } },
      receipts: { orderBy: { createdAt: "desc" }, include: { items: true, receivedBy: { select: { id: true, nombreCompleto: true } } } },
    } satisfies Prisma.PurchaseOrderInclude;
  }

  async listSuppliers(q?: string, includeInactive = false) {
    const query = (q ?? "").trim();
    const rows = await this.prisma.supplier.findMany({
      where: {
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
    return this.suppliersWithStats(rows);
  }

  async createSupplier(dto: UpsertSupplierDto) {
    this.validateSupplier(dto);
    return this.prisma.supplier.create({ data: this.supplierData(dto) });
  }

  async updateSupplier(id: string, dto: UpsertSupplierDto) {
    await this.assertSupplier(id);
    this.validateSupplier(dto);
    return this.prisma.supplier.update({ where: { id }, data: this.supplierData(dto) });
  }

  async deactivateSupplier(id: string) {
    await this.assertSupplier(id);
    return this.prisma.supplier.update({
      where: { id },
      data: { isActive: false, deletedAt: new Date() },
    });
  }

  async listOrders(user: RequestUser, filters: { q?: string; status?: string; supplierId?: string }) {
    const q = (filters.q ?? "").trim();
    const status = this.parseStatus(filters.status, false);
    return this.prisma.purchaseOrder.findMany({
      where: {
        deletedAt: null,
        ...(this.canSeeAll(user) ? {} : { createdById: user.id }),
        ...(status ? { status } : {}),
        ...(filters.supplierId ? { supplierId: filters.supplierId } : {}),
        ...(q
          ? {
              OR: [
                { orderNumber: { contains: q, mode: "insensitive" } },
                { supplier: { commercialName: { contains: q, mode: "insensitive" } } },
                { items: { some: { productNameSnapshot: { contains: q, mode: "insensitive" } } } },
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
      where: { id, deletedAt: null, ...(this.canSeeAll(user) ? {} : { createdById: user.id }) },
      include: this.includeOrder(),
    });
    if (!order) throw new NotFoundException("Orden de compra no encontrada.");
    return order;
  }

  async createOrder(user: RequestUser, dto: CreatePurchaseOrderDto) {
    const items = await this.normalizeItems(dto.items ?? []);
    const totals = this.computeTotals(items, dto);
    return this.prisma.$transaction(async (tx) => {
      const orderNumber = await this.nextOrderNumber(tx);
      return tx.purchaseOrder.create({
        data: {
          orderNumber,
          supplierId: this.cleanId(dto.supplierId),
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
    });
  }

  async updateOrder(user: RequestUser, id: string, dto: CreatePurchaseOrderDto) {
    const current = await this.getOrder(user, id);
    if (current.status === PurchaseOrderStatus.RECEIVED || current.status === PurchaseOrderStatus.CANCELLED) {
      throw new BadRequestException("Esta orden ya no puede editarse.");
    }
    if (current.status !== PurchaseOrderStatus.DRAFT && !this.canApprove(user)) {
      throw new ForbiddenException("Necesitas permiso para editar una orden aprobada o enviada.");
    }
    const items = await this.normalizeItems(dto.items ?? []);
    const totals = this.computeTotals(items, dto);
    return this.prisma.$transaction(async (tx) => {
      await tx.purchaseOrderItem.deleteMany({ where: { purchaseOrderId: id } });
      return tx.purchaseOrder.update({
        where: { id },
        data: {
          supplierId: this.cleanId(dto.supplierId),
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
    if (!order.items.length) throw new BadRequestException("Agrega al menos un producto.");
    if (!order.supplierId) throw new BadRequestException("Selecciona un suplidor para continuar.");
    return this.prisma.purchaseOrder.update({
      where: { id },
      data: { status: PurchaseOrderStatus.APPROVED, approvedById: user.id, approvedAt: new Date() },
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
      data: { status: PurchaseOrderStatus.CANCELLED, cancelledAt: new Date(), cancellationReason: this.clean(reason) },
      include: this.includeOrder(),
    });
  }

  async deleteDraft(user: RequestUser, id: string) {
    const order = await this.getOrder(user, id);
    if (order.status !== PurchaseOrderStatus.DRAFT) {
      throw new BadRequestException("Solo se pueden eliminar borradores.");
    }
    await this.prisma.purchaseOrder.update({ where: { id }, data: { deletedAt: new Date() } });
    return { ok: true };
  }

  async receiveOrder(user: RequestUser, id: string, dto: ReceivePurchaseOrderDto) {
    const order = await this.getOrder(user, id);
    if (order.status === PurchaseOrderStatus.CANCELLED) {
      throw new BadRequestException("Una orden cancelada no puede recibir mercancía.");
    }
    const itemMap = new Map(order.items.map((item) => [item.id, item]));
    const normalized = dto.items.map((item) => {
      const current = itemMap.get(item.purchaseOrderItemId);
      if (!current) throw new BadRequestException("Producto de orden inválido.");
      const qty = new Prisma.Decimal(item.quantityReceived);
      const pending = new Prisma.Decimal(current.pendingQuantity);
      if (qty.lte(0)) throw new BadRequestException("La cantidad recibida debe ser mayor que cero.");
      if (qty.greaterThan(pending)) throw new BadRequestException(`La cantidad recibida supera lo pendiente para ${current.productNameSnapshot}.`);
      return {
        current,
        quantityReceived: qty,
        unitCost: new Prisma.Decimal(item.unitCost),
        condition: this.clean(item.condition),
        notes: this.clean(item.notes),
      };
    });

    return this.prisma.$transaction(async (tx) => {
      const receipt = await tx.purchaseReceipt.create({
        data: {
          purchaseOrderId: id,
          supplierInvoiceNumber: this.clean(dto.supplierInvoiceNumber),
          notes: this.clean(dto.notes),
          invoiceImage: this.clean(dto.invoiceImage),
          receivedById: user.id,
          inventoryUpdated: Boolean(dto.updateInventory),
          inventoryUpdatedAt: dto.updateInventory ? new Date() : null,
          items: {
            create: normalized.map((item) => ({
              purchaseOrderItemId: item.current.id,
              quantityReceived: item.quantityReceived,
              unitCost: item.unitCost,
              condition: item.condition,
              notes: item.notes,
            })),
          },
        },
        include: { items: true },
      });

      for (const item of normalized) {
        const nextReceived = new Prisma.Decimal(item.current.receivedQuantity).plus(item.quantityReceived);
        const nextPending = new Prisma.Decimal(item.current.quantity).minus(nextReceived);
        await tx.purchaseOrderItem.update({
          where: { id: item.current.id },
          data: {
            receivedQuantity: nextReceived,
            pendingQuantity: nextPending.lessThan(0) ? new Prisma.Decimal(0) : nextPending,
            actualUnitCost: item.unitCost,
          },
        });

        if (dto.updateInventory) {
          if (item.current.productId) {
            await tx.product.update({
              where: { id: item.current.productId },
              data: { stock: { increment: item.quantityReceived }, costo: item.unitCost },
            });
          } else if (item.current.createInventoryProductOnReceipt) {
            const created = await tx.product.create({
              data: {
                nombre: item.current.productNameSnapshot,
                categoria: item.current.descriptionSnapshot?.slice(0, 80) || "Sin categoría",
                precio: item.unitCost,
                costo: item.unitCost,
                stock: item.quantityReceived,
                imagen: item.current.imageSnapshot,
              },
            });
            await tx.purchaseOrderItem.update({ where: { id: item.current.id }, data: { productId: created.id } });
          }
        }
      }

      const refreshedItems = await tx.purchaseOrderItem.findMany({ where: { purchaseOrderId: id } });
      const allReceived = refreshedItems.every((item) => new Prisma.Decimal(item.pendingQuantity).lte(0));
      const someReceived = refreshedItems.some((item) => new Prisma.Decimal(item.receivedQuantity).gt(0));
      const status = allReceived
        ? PurchaseOrderStatus.RECEIVED
        : someReceived
          ? PurchaseOrderStatus.PARTIALLY_RECEIVED
          : order.status;
      const updated = await tx.purchaseOrder.update({ where: { id }, data: { status }, include: this.includeOrder() });
      return { receipt, order: updated };
    });
  }

  async recommendations() {
    const products = await this.prisma.product.findMany({ orderBy: { nombre: "asc" } });
    const pending = await this.prisma.purchaseOrderItem.groupBy({
      by: ["productId"],
      where: {
        productId: { not: null },
        purchaseOrder: { deletedAt: null, status: { in: [PurchaseOrderStatus.APPROVED, PurchaseOrderStatus.SENT, PurchaseOrderStatus.PARTIALLY_RECEIVED] } },
      },
      _sum: { pendingQuantity: true },
    });
    const ordered = new Map(pending.map((row) => [row.productId, this.num(row._sum.pendingQuantity)]));
    return products.map((product) => {
      const stock = this.num(product.stock);
      const minStock = 5;
      const alreadyOrdered = ordered.get(product.id) ?? 0;
      const suggested = Math.max(0, minStock * 2 - stock - alreadyOrdered);
      const reason = stock <= 0 ? "Agotado" : stock < minStock ? "Por debajo del mínimo" : suggested > 0 ? "Compra recomendada" : "Disponible";
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
    const orderDir = path.join(this.resolveUploadDir(), "compras", purchaseOrderId);
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
    const safeFileName = this.sanitizePdfFileName(fileName ?? "", "orden_compra.pdf");
    if (!safeOrderId || safeOrderId.includes("/") || safeOrderId.includes("\\")) {
      throw new NotFoundException("PDF de orden de compra no encontrado.");
    }

    const absolutePath = path.join(this.resolveUploadDir(), "compras", safeOrderId, safeFileName);
    if (!fs.existsSync(absolutePath)) {
      throw new NotFoundException("PDF de orden de compra no encontrado.");
    }

    return { absolutePath, fileName: safeFileName };
  }

  private async normalizeItems(items: PurchaseOrderItemDto[]) {
    const productIds = [...new Set(items.map((item) => item.productId).filter((id): id is string => Boolean(id)))];
    const products = productIds.length
      ? await this.prisma.product.findMany({ where: { id: { in: productIds } } })
      : [];
    const productMap = new Map(products.map((product) => [product.id, product]));
    return items.map((item, index) => {
      const product = item.productId ? productMap.get(item.productId) : null;
      if (item.productId && !product) throw new BadRequestException(`Producto inválido en línea ${index + 1}.`);
      const name = (product?.nombre ?? item.productName ?? "").trim();
      if (!name) throw new BadRequestException(`Producto sin nombre en línea ${index + 1}.`);
      const quantity = new Prisma.Decimal(item.quantity);
      const unitCost = new Prisma.Decimal(item.unitCost);
      if (quantity.lte(0)) throw new BadRequestException("Las cantidades deben ser mayores que cero.");
      if (unitCost.lt(0)) throw new BadRequestException("Los montos no pueden ser negativos.");
      const subtotal = quantity.mul(unitCost).toDecimalPlaces(2);
      return {
        data: {
          productId: product?.id,
          externalProductId: this.cleanId(item.externalProductId),
          productNameSnapshot: name,
          productCodeSnapshot: this.clean(item.productCode),
          descriptionSnapshot: this.clean(item.description),
          imageSnapshot: this.clean(product?.imagen ?? item.image),
          quantity,
          receivedQuantity: new Prisma.Decimal(0),
          pendingQuantity: quantity,
          unitCost,
          subtotal,
          supplierId: this.cleanId(item.supplierId),
          notes: this.clean(item.notes),
          createInventoryProductOnReceipt: Boolean(item.createInventoryProductOnReceipt),
        },
        subtotal,
      };
    });
  }

  private computeTotals(items: Array<{ subtotal: Prisma.Decimal }>, dto: CreatePurchaseOrderDto) {
    const subtotal = items.reduce((acc, item) => acc.plus(item.subtotal), new Prisma.Decimal(0)).toDecimalPlaces(2);
    const discount = new Prisma.Decimal(dto.discount ?? 0).toDecimalPlaces(2);
    const shippingCost = new Prisma.Decimal(dto.shippingCost ?? 0).toDecimalPlaces(2);
    const additionalCost = new Prisma.Decimal(dto.additionalCost ?? 0).toDecimalPlaces(2);
    const tax = new Prisma.Decimal(dto.tax ?? 0).toDecimalPlaces(2);
    for (const amount of [discount, shippingCost, additionalCost, tax]) {
      if (amount.lt(0)) throw new BadRequestException("Los montos no pueden ser negativos.");
    }
    const total = subtotal.minus(discount).plus(shippingCost).plus(additionalCost).plus(tax).toDecimalPlaces(2);
    if (total.lt(0)) throw new BadRequestException("El total no puede ser negativo.");
    return { subtotal, discount, shippingCost, additionalCost, tax, total };
  }

  private async nextOrderNumber(tx: Prisma.TransactionClient) {
    const scope = "default";
    const current = await tx.purchaseOrderSequence.upsert({
      where: { scope },
      create: { scope, nextValue: 2 },
      update: { nextValue: { increment: 1 } },
    });
    const number = current.nextValue === 2 ? 1 : current.nextValue - 1;
    return `OC-${number.toString().padStart(6, "0")}`;
  }

  private async suppliersWithStats(rows: Array<{ id: string; [key: string]: unknown }>) {
    const ids = rows.map((row) => row.id);
    if (!ids.length) return rows;

    const [totals, latestRows] = await Promise.all([
      this.prisma.purchaseOrder.groupBy({
        by: ["supplierId"],
        where: {
          supplierId: { in: ids },
          deletedAt: null,
          status: { not: PurchaseOrderStatus.CANCELLED },
        },
        _count: { _all: true },
        _sum: { total: true },
      }),
      this.prisma.purchaseOrder.findMany({
        where: { supplierId: { in: ids }, deletedAt: null },
        orderBy: [{ supplierId: "asc" }, { orderDate: "desc" }],
        select: { supplierId: true, orderNumber: true, orderDate: true, total: true, status: true },
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
    const latest = new Map<string, { orderNumber: string; orderDate: Date; total: Prisma.Decimal; status: PurchaseOrderStatus }>();
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
    if (!this.clean(dto.commercialName)) throw new BadRequestException("El nombre comercial es obligatorio.");
  }

  private supplierData(dto: UpsertSupplierDto): Prisma.SupplierUncheckedCreateInput {
    return {
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

  private async assertSupplier(id: string) {
    const supplier = await this.prisma.supplier.findFirst({ where: { id, deletedAt: null } });
    if (!supplier) throw new NotFoundException("Suplidor no encontrado.");
    return supplier;
  }

  private parseStatus(value?: string, throwOnInvalid = true): PurchaseOrderStatus | null {
    const raw = (value ?? "").trim().toUpperCase();
    if (!raw) return null;
    if (Object.values(PurchaseOrderStatus).includes(raw as PurchaseOrderStatus)) return raw as PurchaseOrderStatus;
    if (throwOnInvalid) throw new BadRequestException("Estado de orden inválido.");
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
    if (Number.isNaN(parsed.getTime())) throw new BadRequestException("Fecha inválida.");
    return parsed;
  }

  private clean(value?: string | null) {
    const text = (value ?? "").trim();
    return text ? text : null;
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
    if (!trimmed) throw new BadRequestException("Debes enviar el PDF de la orden de compra.");
    const base64 = trimmed.startsWith("data:") ? trimmed.slice(trimmed.indexOf(",") + 1) : trimmed;
    const bytes = Buffer.from(base64, "base64");
    if (!bytes.length) throw new BadRequestException("El PDF de la orden de compra llegó vacío.");
    const maxPdfBytes = 8 * 1024 * 1024;
    if (bytes.length > maxPdfBytes) {
      const sizeMb = (bytes.length / (1024 * 1024)).toFixed(2);
      throw new BadRequestException(`El PDF de la orden de compra pesa ${sizeMb} MB y supera el límite de 8 MB.`);
    }
    return bytes;
  }

  private resolveUploadDir() {
    const fromEnv = (this.config.get<string>("UPLOAD_DIR") ?? "").trim();
    const volumeDir = "/uploads";
    const volumeExists = fs.existsSync(volumeDir);
    if (fromEnv) {
      if ((fromEnv === "./uploads" || fromEnv === "uploads") && volumeExists) return volumeDir;
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
    const base = path.basename(source).replace(/[^a-zA-Z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
    const withExt = base.toLowerCase().endsWith(".pdf") ? base : `${base}.pdf`;
    return withExt || fallback;
  }
}
