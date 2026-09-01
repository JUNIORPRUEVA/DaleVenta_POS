import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { InventoryMovementType, Prisma, Product } from "@prisma/client";
import { createHash } from "node:crypto";
import { PrismaService } from "../prisma/prisma.service";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { LicenseService } from "../license/license.service";
import { CatalogProductsService } from "./catalog-products.service";
import { AdjustProductStockDto } from "./dto/adjust-product-stock.dto";
import { CreateProductDto } from "./dto/create-product.dto";
import {
  ProductSourceResolver,
  type ProductSource,
} from "./product-source.resolver";
import { UpdateProductDto } from "./dto/update-product.dto";
import {
  DEFAULT_UNIT_OF_MEASURE,
  DEFAULT_UNIT_OF_MEASURE_ID,
  validateQuantityForUnit,
  type UnitOfMeasureSnapshot,
} from "./unit-of-measure.util";
import { InventoryMutationService } from "../inventory/inventory-mutation.service";

type ResolvedProductWarehouse = { id: string; name: string; code: string };
const PRODUCT_INVENTORY_TRANSACTION_OPTIONS = {
  maxWait: 10000,
  timeout: 30000,
} as const;

@Injectable()
export class ProductsService {
  private readonly logger = new Logger(ProductsService.name);
  private readonly publicBaseUrl: string;
  private readonly allowLocalFallback: boolean;

  constructor(
    private readonly prisma: PrismaService,
    private readonly catalogProducts: CatalogProductsService,
    private readonly productSourceResolver: ProductSourceResolver,
    private readonly config: ConfigService,
    private readonly licenses: LicenseService,
    @Optional()
    private readonly inventoryMutations?: InventoryMutationService,
  ) {
    const base =
      this.config.get<string>("PUBLIC_BASE_URL") ??
      this.config.get<string>("API_BASE_URL") ??
      "";
    this.publicBaseUrl = this.normalizePublicBaseUrl(base);

    const rawFallback = (
      this.config.get<string>("PRODUCTS_ALLOW_LOCAL_FALLBACK") ?? ""
    )
      .trim()
      .toLowerCase();
    this.allowLocalFallback =
      rawFallback === "1" || rawFallback === "true" || rawFallback === "yes";
  }

  async isReadOnly(user: TenantUser) {
    const companyId = requireTenant(user);
    return (await this.productSourceResolver.resolveForCompany(companyId))
      .readOnly;
  }

  async getSource(user: TenantUser): Promise<ProductSource> {
    const companyId = requireTenant(user);
    return (await this.productSourceResolver.resolveForCompany(companyId))
      .source;
  }

  async sourceInfo(user: TenantUser) {
    const companyId = requireTenant(user);
    const context =
      await this.productSourceResolver.resolveForCompany(companyId);
    return {
      source: context.source,
      readOnly: context.readOnly,
      capabilities: {
        supportsDecimalStock: context.supportsDecimalStock,
        supportsNativeUom: context.supportsNativeUom,
        supportsProductCreate: context.supportsProductCreate,
        supportsProductEdit: context.supportsProductEdit,
        supportsStockAdjustment: context.supportsStockAdjustment,
      },
      resolution: context.resolution,
    };
  }

  private async assertWritable(companyId: string) {
    const context =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (context.readOnly) {
      throw new ConflictException(
        "Productos en modo solo-lectura: fuente FULLPOS. Las escrituras, stock decimal y UoM de FULLPOS quedan bloqueadas hasta validar soporte writable en staging.",
      );
    }
    return context;
  }

  private inventoryMutationService() {
    return this.inventoryMutations ?? new InventoryMutationService(this.prisma);
  }

  private async resolveInventoryWarehouse(
    tx: Prisma.TransactionClient,
    companyId: string,
    requestedWarehouseId?: string | null,
    options: { rejectAmbiguousGlobal?: boolean } = {},
  ): Promise<ResolvedProductWarehouse> {
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

    const activeWarehouses = await tx.warehouse.findMany({
      where: { companyId, isActive: true },
      orderBy: { createdAt: "asc" },
      take: 2,
      select: { id: true, name: true, code: true, isDefault: true },
    });

    if (options.rejectAmbiguousGlobal && activeWarehouses.length > 1) {
      throw new BadRequestException(
        "Ajuste de stock ambiguo: selecciona un almacen para companias multi-almacen.",
      );
    }

    const defaultWarehouse = await tx.warehouse.findFirst({
      where: { companyId, isDefault: true, isActive: true },
      orderBy: { createdAt: "asc" },
      select: { id: true, name: true, code: true },
    });
    if (defaultWarehouse) return defaultWarehouse;

    if (activeWarehouses.length === 1) {
      const [warehouse] = activeWarehouses;
      return { id: warehouse.id, name: warehouse.name, code: warehouse.code };
    }

    throw new BadRequestException(
      activeWarehouses.length === 0
        ? "No hay almacenes activos para mutar inventario."
        : "Hay multiples almacenes activos; selecciona un almacen.",
    );
  }

  private async ensureZeroWarehouseStock(
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

  private async normalizeProductFiscalInput(
    tx: Prisma.TransactionClient,
    companyId: string,
    dto: CreateProductDto | UpdateProductDto,
  ) {
    const treatment =
      dto.taxTreatment == null || String(dto.taxTreatment).trim() === ""
        ? undefined
        : dto.taxTreatment;
    const rawTaxRate = dto.taxRate;
    const hasTaxRate = rawTaxRate !== undefined && rawTaxRate !== null;
    const taxPriceMode =
      dto.taxPriceMode == null || String(dto.taxPriceMode).trim() === ""
        ? undefined
        : dto.taxPriceMode;

    if (treatment === undefined) {
      return {
        taxRate: hasTaxRate ? new Prisma.Decimal(rawTaxRate) : undefined,
        taxPriceMode,
      };
    }

    if (treatment === "INHERIT") {
      return {
        taxTreatment: "INHERIT" as const,
        taxRate: null,
        taxPriceMode: null,
      };
    }

    if (treatment === "EXEMPT") {
      return {
        taxTreatment: "EXEMPT" as const,
        taxRate: null,
        taxPriceMode: null,
      };
    }

    if (!hasTaxRate || rawTaxRate <= 0) {
      throw new BadRequestException(
        "Selecciona un impuesto activo para productos gravados",
      );
    }

    const rate = new Prisma.Decimal(rawTaxRate);
    const activeTax = await tx.tax.findFirst({
      where: { companyId, isActive: true, rate },
      select: { id: true },
    });
    if (!activeTax) {
      throw new BadRequestException(
        "El impuesto seleccionado no pertenece a esta empresa",
      );
    }

    return {
      taxTreatment: "TAXABLE" as const,
      taxRate: rate,
      taxPriceMode: taxPriceMode ?? null,
    };
  }

  private async resolveUnitOfMeasure(
    tx: Prisma.TransactionClient,
    companyId: string,
    unitOfMeasureId?: string | null,
  ): Promise<UnitOfMeasureSnapshot & { id: string }> {
    const measurementUnitsEnabled = await this.measurementUnitsEnabled(
      tx,
      companyId,
    );
    const id = (
      measurementUnitsEnabled
        ? (unitOfMeasureId ?? DEFAULT_UNIT_OF_MEASURE_ID)
        : DEFAULT_UNIT_OF_MEASURE_ID
    ).trim();
    if (!id) {
      throw new BadRequestException("Unidad de medida inválida.");
    }

    if (!(tx as any).unitOfMeasure?.findFirst) {
      if (id === DEFAULT_UNIT_OF_MEASURE_ID) {
        return {
          id: DEFAULT_UNIT_OF_MEASURE_ID,
          ...DEFAULT_UNIT_OF_MEASURE,
        };
      }
      throw new BadRequestException(
        "La unidad de medida no pertenece a esta empresa.",
      );
    }

    const unit = await tx.unitOfMeasure.findFirst({
      where: {
        id,
        active: true,
        OR: [{ companyId: null }, { companyId }],
      },
      select: {
        id: true,
        code: true,
        name: true,
        symbol: true,
        allowDecimals: true,
        precision: true,
      },
    });

    if (!unit) {
      throw new BadRequestException(
        "La unidad de medida no pertenece a esta empresa.",
      );
    }

    return unit;
  }

  private async measurementUnitsEnabled(
    tx: Prisma.TransactionClient | PrismaService,
    companyId: string,
  ) {
    const companyApi = (tx as any).company;
    if (!companyApi?.findUnique) {
      return true;
    }
    const company = await companyApi.findUnique({
      where: { id: companyId },
      select: { measurementUnitsEnabled: true },
    });
    return company?.measurementUnitsEnabled === true;
  }

  private mapUnitOfMeasure(unit: any) {
    const source = unit ?? {
      id: DEFAULT_UNIT_OF_MEASURE_ID,
      category: "COUNT",
      ...DEFAULT_UNIT_OF_MEASURE,
    };
    return {
      id: source.id ?? DEFAULT_UNIT_OF_MEASURE_ID,
      code: source.code ?? DEFAULT_UNIT_OF_MEASURE.code,
      name: source.name ?? DEFAULT_UNIT_OF_MEASURE.name,
      symbol: source.symbol ?? DEFAULT_UNIT_OF_MEASURE.symbol,
      category: source.category ?? "COUNT",
      allowDecimals:
        source.allowDecimals ?? DEFAULT_UNIT_OF_MEASURE.allowDecimals,
      precision: source.precision ?? DEFAULT_UNIT_OF_MEASURE.precision,
    };
  }

  async listUnitOfMeasures(user: TenantUser) {
    const companyId = requireTenant(user);
    if (!(await this.measurementUnitsEnabled(this.prisma, companyId))) {
      return [this.mapUnitOfMeasure(null)];
    }
    if (!(this.prisma as any).unitOfMeasure?.findMany) {
      return [this.mapUnitOfMeasure(null)];
    }
    const rows = await this.prisma.unitOfMeasure.findMany({
      where: {
        active: true,
        OR: [{ companyId: null }, { companyId }],
      },
      orderBy: [{ companyId: "asc" }, { category: "asc" }, { name: "asc" }],
      select: {
        id: true,
        code: true,
        name: true,
        symbol: true,
        category: true,
        allowDecimals: true,
        precision: true,
      },
    });
    if (rows.length === 0) return [this.mapUnitOfMeasure(null)];
    return rows.map((row) => this.mapUnitOfMeasure(row));
  }

  private normalizeProductCode(dto: {
    codigo?: string;
    code?: string;
    sku?: string;
    barcode?: string;
  }): string | null {
    const raw = dto.codigo ?? dto.code ?? dto.sku ?? dto.barcode;
    const value = raw?.trim().replace(/\s+/g, " ");
    return value && value.length > 0 ? value : null;
  }

  private normalizeProductCodeForLookup(code?: string | null): string | null {
    const value = (code ?? "").trim().replace(/\s+/g, " ");
    return value ? value.toLowerCase() : null;
  }

  private hasProductCodeInput(dto: {
    codigo?: string;
    code?: string;
    sku?: string;
    barcode?: string;
  }): boolean {
    return (
      dto.codigo !== undefined ||
      dto.code !== undefined ||
      dto.sku !== undefined ||
      dto.barcode !== undefined
    );
  }

  private isSchemaMismatch(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === "P2021" || error.code === "P2022";
    }

    if (typeof error === "object" && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === "string" ? value.code : "";
      const message = typeof value.message === "string" ? value.message : "";
      return (
        code === "P2021" ||
        code === "P2022" ||
        message.includes("does not exist in the current database") ||
        message.toLowerCase().includes("column")
      );
    }

    return false;
  }

  private isUniqueConstraint(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    );
  }

  private operationProductId(companyId: string, operationId?: string | null) {
    const cleanOperationId = (operationId ?? "").trim();
    if (!cleanOperationId) return null;
    const digest = createHash("sha256")
      .update(`${companyId}:${cleanOperationId}`)
      .digest("hex");
    return [
      digest.substring(0, 8),
      digest.substring(8, 12),
      `4${digest.substring(13, 16)}`,
      `8${digest.substring(17, 20)}`,
      digest.substring(20, 32),
    ].join("-");
  }

  private logProductSave(params: {
    action: "create" | "update";
    decision: string;
    companyId: string;
    productId?: string | null;
    normalizedCode?: string | null;
    operationId?: string | null;
    result?: string;
  }) {
    this.logger.log(
      `product-save action=${params.action} decision=${params.decision} companyId=${params.companyId} productId=${params.productId ?? ""} normalizedCode=${params.normalizedCode ?? ""} operationId=${params.operationId ?? ""} result=${params.result ?? ""}`,
    );
  }

  private async findByNormalizedCode(
    tx: Prisma.TransactionClient,
    companyId: string,
    normalizedCode: string,
  ) {
    const candidates = await tx.product.findMany({
      where: {
        companyId,
        codigo: { not: null },
      },
    });
    return (
      candidates.find(
        (product) =>
          this.normalizeProductCodeForLookup((product as any).codigo) ===
          normalizedCode,
      ) ?? null
    );
  }

  private normalizeTextKey(value?: string | null) {
    return (value ?? "").trim().replace(/\s+/g, " ").toLowerCase();
  }

  private hasEmptyProductCode(product: Product) {
    return this.normalizeProductCodeForLookup((product as any).codigo) === null;
  }

  private productIdentityWhere(
    companyId: string,
    data: {
      nombre?: string | null;
      categoria?: string | null;
      precio?: Prisma.Decimal | number | string | null;
      costo?: Prisma.Decimal | number | string | null;
      stock?: Prisma.Decimal | number | string | null;
      unitOfMeasureId?: string | null;
    },
  ) {
    return {
      companyId,
      nombre: { equals: data.nombre ?? "", mode: "insensitive" as const },
      categoria: {
        equals: data.categoria ?? "",
        mode: "insensitive" as const,
      },
      precio: new Prisma.Decimal(data.precio ?? 0),
      costo: new Prisma.Decimal(data.costo ?? 0),
      stock: new Prisma.Decimal(data.stock ?? 0),
      unitOfMeasureId: data.unitOfMeasureId ?? DEFAULT_UNIT_OF_MEASURE_ID,
    };
  }

  private async productReferenceCount(
    tx: Prisma.TransactionClient,
    productId: string,
  ) {
    const [saleItems, cotizacionItems, purchaseOrderItems, websiteOverrides] =
      await Promise.all([
        tx.saleItem.count({ where: { productId } }),
        tx.cotizacionItem.count({ where: { productId } }),
        tx.purchaseOrderItem.count({ where: { productId } }),
        tx.websiteProductOverride.count({ where: { productId } }),
      ]);
    return saleItems + cotizacionItems + purchaseOrderItems + websiteOverrides;
  }

  private async findEquivalentProducts(
    tx: Prisma.TransactionClient,
    companyId: string,
    data: {
      nombre?: string | null;
      categoria?: string | null;
      precio?: Prisma.Decimal | number | string | null;
      costo?: Prisma.Decimal | number | string | null;
      stock?: Prisma.Decimal | number | string | null;
      unitOfMeasureId?: string | null;
    },
    excludeId?: string,
  ) {
    const candidates = await tx.product.findMany({
      where: this.productIdentityWhere(companyId, data),
    });
    return candidates.filter(
      (product) =>
        product.id !== excludeId &&
        this.normalizeTextKey(product.nombre) ===
          this.normalizeTextKey(data.nombre) &&
        this.normalizeTextKey(product.categoria) ===
          this.normalizeTextKey(data.categoria),
    );
  }

  private async pruneSafeDuplicateProducts(
    tx: Prisma.TransactionClient,
    companyId: string,
    canonical: Product,
  ) {
    const duplicates = await this.findEquivalentProducts(
      tx,
      companyId,
      canonical,
      canonical.id,
    );
    let deleted = 0;
    let skipped = 0;
    for (const duplicate of duplicates) {
      const duplicateCode = this.normalizeProductCodeForLookup(
        (duplicate as any).codigo,
      );
      const canonicalCode = this.normalizeProductCodeForLookup(
        (canonical as any).codigo,
      );
      if (duplicateCode && duplicateCode !== canonicalCode) {
        skipped += 1;
        continue;
      }
      const references = await this.productReferenceCount(tx, duplicate.id);
      if (references > 0) {
        skipped += 1;
        this.logger.warn(
          `product-duplicate-prune skipped companyId=${companyId} canonicalProductId=${canonical.id} duplicateProductId=${duplicate.id} references=${references}`,
        );
        continue;
      }
      await tx.product.deleteMany({ where: { id: duplicate.id, companyId } });
      deleted += 1;
      this.logger.log(
        `product-duplicate-prune deleted companyId=${companyId} canonicalProductId=${canonical.id} duplicateProductId=${duplicate.id}`,
      );
    }
    return { deleted, skipped };
  }

  private async productResponse(
    tx: Prisma.TransactionClient | PrismaService,
    companyId: string,
    productId: string,
  ) {
    let product: any = null;
    try {
      product = await tx.product.findFirst({
        where: { id: productId, companyId },
        select: this.catalogProductSelect(),
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      product = await tx.product.findFirst({
        where: { id: productId, companyId },
        select: this.legacyCatalogProductSelect(),
      });
    }
    if (!product) {
      throw new NotFoundException("Producto no encontrado");
    }
    return this.mapProduct(product as any);
  }

  async create(user: TenantUser, dto: CreateProductDto): Promise<any> {
    const companyId = requireTenant(user);
    await this.assertWritable(companyId);
    await this.licenses.assertCanCreateProduct(companyId);
    const operationProductIdForRecovery = this.operationProductId(
      companyId,
      dto.operationId,
    );

    try {
      return await this.prisma.$transaction(async (tx) => {
        const normalizedCodeForLookup = this.normalizeProductCodeForLookup(
          this.normalizeProductCode(dto),
        );
        const operationProductId = this.operationProductId(
          companyId,
          dto.operationId,
        );
        if (operationProductId) {
          const existingOperationProduct = await tx.product.findFirst({
            where: { id: operationProductId, companyId },
          });
          if (existingOperationProduct) {
            this.logProductSave({
              action: "create",
              decision: "idempotent-return-existing",
              companyId,
              productId: existingOperationProduct.id,
              normalizedCode: normalizedCodeForLookup,
              operationId: dto.operationId,
              result: "existing",
            });
            return this.productResponse(
              tx,
              companyId,
              existingOperationProduct.id,
            );
          }
        }

        if (normalizedCodeForLookup) {
          const existingByCode = await this.findByNormalizedCode(
            tx,
            companyId,
            normalizedCodeForLookup,
          );
          if (existingByCode) {
            this.logProductSave({
              action: "create",
              decision: "reject-duplicate-code",
              companyId,
              productId: existingByCode.id,
              normalizedCode: normalizedCodeForLookup,
              operationId: dto.operationId,
              result: "conflict",
            });
            throw new ConflictException(
              "Ya existe un producto con ese código en esta empresa",
            );
          }
        }

        const imageKey = this.extractR2Key(dto.imageKey ?? dto.fotoUrl);
        const normalizedImagePath = imageKey
          ? this.buildObjectMediaUrl(imageKey)
          : this.normalizeImagePathForStorage(dto.fotoUrl);
        const fiscalData = await this.normalizeProductFiscalInput(
          tx,
          companyId,
          dto,
        );
        const unitOfMeasure = await this.resolveUnitOfMeasure(
          tx,
          companyId,
          dto.unitOfMeasureId,
        );
        const initialStock = new Prisma.Decimal(dto.stock ?? 0);
        validateQuantityForUnit({
          quantity: initialStock,
          unit: unitOfMeasure,
          label: "stock del producto",
          allowZero: true,
        });
        const data = {
          id: operationProductId ?? undefined,
          nombre: dto.nombre,
          codigo: this.normalizeProductCode(dto),
          categoria: dto.categoria,
          precio: new Prisma.Decimal(dto.precio),
          costo: new Prisma.Decimal(dto.costo),
          stock: new Prisma.Decimal(0),
          unitOfMeasureId: unitOfMeasure.id,
          ...fiscalData,
          imagen: normalizedImagePath,
          imageStorageProvider: imageKey ? "r2" : undefined,
          imageKey: imageKey ?? undefined,
          imageMimeType: imageKey
            ? dto.imageMimeType?.trim() || undefined
            : undefined,
          imageOriginalFileName: imageKey
            ? dto.imageOriginalFileName?.trim() || undefined
            : undefined,
          imageUpdatedAt: imageKey ? new Date() : undefined,
          companyId,
        };

        if (dto.fotoUrl !== normalizedImagePath) {
          this.logger.log(
            `normalize create image path: "${dto.fotoUrl ?? ""}" -> "${normalizedImagePath ?? ""}"`,
          );
        }

        const equivalentProducts = await this.findEquivalentProducts(
          tx,
          companyId,
          { ...data, stock: initialStock },
        );
        const reusableEquivalent = equivalentProducts.find((product) => {
          const productCode = this.normalizeProductCodeForLookup(
            (product as any).codigo,
          );
          return (
            productCode === null || productCode === normalizedCodeForLookup
          );
        });
        if (reusableEquivalent) {
          const updateData = { ...data };
          delete (updateData as { id?: string }).id;
          delete (updateData as { stock?: Prisma.Decimal }).stock;
          const product = await tx.product.update({
            where: { id: reusableEquivalent.id },
            data: updateData,
          });
          const prune = await this.pruneSafeDuplicateProducts(
            tx,
            companyId,
            product,
          );
          this.logProductSave({
            action: "create",
            decision: "reuse-equivalent-product",
            companyId,
            productId: product.id,
            normalizedCode: normalizedCodeForLookup,
            operationId: dto.operationId,
            result: `updated-existing deletedDuplicates=${prune.deleted} skippedDuplicates=${prune.skipped}`,
          });
          return this.productResponse(tx, companyId, product.id);
        }

        try {
          const product = operationProductId
            ? await tx.product.upsert({
                where: { id: operationProductId },
                create: data,
                update: {},
              })
            : await tx.product.create({ data });
          const warehouse = await this.resolveInventoryWarehouse(
            tx,
            companyId,
            dto.warehouseId,
          );
          await this.ensureZeroWarehouseStock(
            tx,
            companyId,
            warehouse.id,
            product.id,
          );
          if (initialStock.gt(0)) {
            await this.inventoryMutationService().increaseStockInTransaction(
              tx,
              {
                companyId,
                productId: product.id,
                warehouseId: warehouse.id,
                quantity: initialStock,
                type: InventoryMovementType.INITIAL_STOCK,
                sourceType: "PRODUCT_CREATE",
                sourceId: product.id,
                reason: "PRODUCT_INITIAL_STOCK",
                createdByUserId: user.id,
              },
            );
          }
          this.logProductSave({
            action: "create",
            decision: operationProductId ? "upsert-idempotent" : "insert",
            companyId,
            productId: product.id,
            normalizedCode: normalizedCodeForLookup,
            operationId: dto.operationId,
            result: "created",
          });
          await this.pruneSafeDuplicateProducts(tx, companyId, product);
          return this.productResponse(tx, companyId, product.id);
        } catch (error) {
          if (this.isUniqueConstraint(error)) {
            throw error;
          }
          if (!this.isSchemaMismatch(error)) throw error;
          const product = await tx.product.create({ data });
          const warehouse = await this.resolveInventoryWarehouse(
            tx,
            companyId,
            dto.warehouseId,
          );
          await this.ensureZeroWarehouseStock(
            tx,
            companyId,
            warehouse.id,
            product.id,
          );
          if (initialStock.gt(0)) {
            await this.inventoryMutationService().increaseStockInTransaction(
              tx,
              {
                companyId,
                productId: product.id,
                warehouseId: warehouse.id,
                quantity: initialStock,
                type: InventoryMovementType.INITIAL_STOCK,
                sourceType: "PRODUCT_CREATE",
                sourceId: product.id,
                reason: "PRODUCT_INITIAL_STOCK",
                createdByUserId: user.id,
              },
            );
          }
          await this.pruneSafeDuplicateProducts(tx, companyId, product);
          return this.productResponse(tx, companyId, product.id);
        }
      }, PRODUCT_INVENTORY_TRANSACTION_OPTIONS);
    } catch (error) {
      if (this.isUniqueConstraint(error)) {
        if (operationProductIdForRecovery) {
          const existing = await this.prisma.product.findFirst({
            where: { id: operationProductIdForRecovery, companyId },
          });
          if (existing) {
            this.logProductSave({
              action: "create",
              decision: "idempotent-recovered-after-conflict",
              companyId,
              productId: existing.id,
              normalizedCode: this.normalizeProductCodeForLookup(
                this.normalizeProductCode(dto),
              ),
              operationId: dto.operationId,
              result: "existing",
            });
            return this.productResponse(this.prisma, companyId, existing.id);
          }
        }
        throw new ConflictException(
          "Ya existe un producto con ese código en esta empresa",
        );
      }
      throw error;
    }
  }

  async findAll(user: TenantUser): Promise<any[]> {
    const companyId = requireTenant(user);
    const sourceContext =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (
      sourceContext.source === "FULLPOS" ||
      sourceContext.source === "FULLPOS_DIRECT"
    ) {
      try {
        const response = await this.catalogProducts.findAll({
          companyId,
          source: sourceContext.source,
          fullposCompanyId: sourceContext.fullposCompanyId,
        });
        return response.items;
      } catch (error) {
        if (!this.allowLocalFallback) {
          throw error;
        }

        const message = error instanceof Error ? error.message : String(error);
        this.logger.warn(
          `FULLPOS products failed; falling back to LOCAL because PRODUCTS_ALLOW_LOCAL_FALLBACK=true. error=${message}`,
        );
        // fall through to LOCAL
      }
    }

    try {
      const products = await this.prisma.product.findMany({
        where: { companyId },
        orderBy: { nombre: "asc" },
        select: this.catalogProductSelect(),
      });
      return products.map((p) => this.mapProduct(p));
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      const products = await this.prisma.product.findMany({
        where: { companyId },
        orderBy: { nombre: "asc" },
        select: this.legacyCatalogProductSelect(),
      });
      return products.map((p) => this.mapProduct(p));
    }
  }

  async findOne(user: TenantUser, id: string): Promise<any> {
    const companyId = requireTenant(user);
    const sourceContext =
      await this.productSourceResolver.resolveForCompany(companyId);
    if (
      sourceContext.source === "FULLPOS" ||
      sourceContext.source === "FULLPOS_DIRECT"
    ) {
      try {
        return await this.catalogProducts.findOne(id, {
          companyId,
          source: sourceContext.source,
          fullposCompanyId: sourceContext.fullposCompanyId,
        });
      } catch (error) {
        if (!this.allowLocalFallback) {
          throw error;
        }

        const message = error instanceof Error ? error.message : String(error);
        this.logger.warn(
          `FULLPOS product lookup failed; falling back to LOCAL because PRODUCTS_ALLOW_LOCAL_FALLBACK=true. id=${id} error=${message}`,
        );
        // fall through to LOCAL
      }
    }

    let product: Product | null = null;
    try {
      product = await this.prisma.product.findFirst({
        where: { id, companyId },
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      product = await this.prisma.product.findFirst({
        where: { id, companyId },
      });
    }
    if (!product) throw new NotFoundException("Product not found");
    return this.productResponse(this.prisma, companyId, product.id);
  }

  async update(
    user: TenantUser,
    id: string,
    dto: UpdateProductDto,
  ): Promise<any> {
    const companyId = requireTenant(user);
    await this.assertWritable(companyId);
    const hasLegacyStockEcho = dto.stock !== undefined && dto.stock !== null;
    await this.findOne(user, id);
    return this.prisma.$transaction(async (tx) => {
      const normalizedCodeForLookup = this.hasProductCodeInput(dto)
        ? this.normalizeProductCodeForLookup(this.normalizeProductCode(dto))
        : null;
      if (normalizedCodeForLookup) {
        const existingByCode = await this.findByNormalizedCode(
          tx,
          companyId,
          normalizedCodeForLookup,
        );
        if (existingByCode && existingByCode.id !== id) {
          this.logProductSave({
            action: "update",
            decision: "reject-duplicate-code",
            companyId,
            productId: id,
            normalizedCode: normalizedCodeForLookup,
            operationId: dto.operationId,
            result: "conflict",
          });
          throw new ConflictException(
            "Ya existe un producto con ese código en esta empresa",
          );
        }
      }

      const imageKey =
        dto.fotoUrl === undefined && dto.imageKey === undefined
          ? undefined
          : this.extractR2Key(dto.imageKey ?? dto.fotoUrl);
      const normalizedImagePath =
        dto.fotoUrl === undefined
          ? undefined
          : imageKey
            ? this.buildObjectMediaUrl(imageKey)
            : this.normalizeImagePathForStorage(dto.fotoUrl);
      const fiscalData = await this.normalizeProductFiscalInput(
        tx,
        companyId,
        dto,
      );
      const current = await tx.product.findFirst({
        where: { id, companyId },
        select: {
          stock: true,
          unitOfMeasureId: true,
          unitOfMeasure: {
            select: {
              id: true,
              code: true,
              name: true,
              symbol: true,
              allowDecimals: true,
              precision: true,
            },
          },
        },
      });
      if (!current) {
        throw new NotFoundException("Producto no encontrado");
      }
      if (hasLegacyStockEcho) {
        const echoedStock = new Prisma.Decimal(dto.stock ?? 0);
        validateQuantityForUnit({
          quantity: echoedStock,
          unit: this.mapUnitOfMeasure(current.unitOfMeasure),
          label: "stock del producto",
          allowZero: true,
        });
        if (!echoedStock.equals(new Prisma.Decimal(current.stock ?? 0))) {
          throw new BadRequestException(
            "El stock no se puede cambiar desde la edición del producto. Usa ajuste de stock.",
          );
        }
      }
      const measurementUnitsEnabled = await this.measurementUnitsEnabled(
        tx,
        companyId,
      );
      const requestedUnitOfMeasureId = measurementUnitsEnabled
        ? dto.unitOfMeasureId
        : undefined;
      const unitOfMeasure =
        requestedUnitOfMeasureId === undefined
          ? this.mapUnitOfMeasure(current.unitOfMeasure)
          : await this.resolveUnitOfMeasure(
              tx,
              companyId,
              requestedUnitOfMeasureId,
            );
      if (
        requestedUnitOfMeasureId !== undefined &&
        unitOfMeasure.id !== current.unitOfMeasureId
      ) {
        const hasStock = new Prisma.Decimal(current.stock ?? 0).abs().gt(0);
        const referenceCount = await this.productReferenceCount(tx, id);
        if (hasStock || referenceCount > 0) {
          throw new BadRequestException(
            "No se puede cambiar la unidad de medida de un producto con stock o historial.",
          );
        }
      }
      const data = {
        nombre: dto.nombre,
        codigo: this.hasProductCodeInput(dto)
          ? this.normalizeProductCode(dto)
          : undefined,
        categoria: dto.categoria,
        precio:
          dto.precio === undefined ? undefined : new Prisma.Decimal(dto.precio),
        costo:
          dto.costo === undefined ? undefined : new Prisma.Decimal(dto.costo),
        unitOfMeasureId:
          requestedUnitOfMeasureId === undefined ? undefined : unitOfMeasure.id,
        ...fiscalData,
        imagen: normalizedImagePath,
        imageStorageProvider:
          imageKey === undefined ? undefined : imageKey ? "r2" : null,
        imageKey: imageKey === undefined ? undefined : imageKey,
        imageMimeType:
          imageKey === undefined
            ? undefined
            : dto.imageMimeType?.trim() || null,
        imageOriginalFileName:
          imageKey === undefined
            ? undefined
            : dto.imageOriginalFileName?.trim() || null,
        imageUpdatedAt:
          imageKey === undefined ? undefined : imageKey ? new Date() : null,
      };

      if (dto.fotoUrl !== undefined && dto.fotoUrl !== normalizedImagePath) {
        this.logger.log(
          `normalize update image path: "${dto.fotoUrl}" -> "${normalizedImagePath ?? ""}"`,
        );
      }

      try {
        const updateResult = await tx.product.updateMany({
          where: { id, companyId },
          data,
        });
        if (updateResult.count !== 1) {
          throw new NotFoundException("Producto no encontrado");
        }
        const updated = await tx.product.findFirst({
          where: { id, companyId },
        });
        if (!updated) {
          throw new NotFoundException("Producto no encontrado");
        }
        const prune = await this.pruneSafeDuplicateProducts(
          tx,
          companyId,
          updated,
        );
        this.logProductSave({
          action: "update",
          decision: "update-by-id",
          companyId,
          productId: updated.id,
          normalizedCode: normalizedCodeForLookup,
          operationId: dto.operationId,
          result: `updated deletedDuplicates=${prune.deleted} skippedDuplicates=${prune.skipped}`,
        });
        return this.productResponse(tx, companyId, updated.id);
      } catch (error) {
        if (this.isUniqueConstraint(error)) {
          throw new ConflictException(
            "Ya existe un producto con ese código en esta empresa",
          );
        }
        if (!this.isSchemaMismatch(error)) throw error;
        const updateResult = await tx.product.updateMany({
          where: { id, companyId },
          data,
        });
        if (updateResult.count !== 1) {
          throw new NotFoundException("Producto no encontrado");
        }
        const updated = await tx.product.findFirst({
          where: { id, companyId },
        });
        if (!updated) {
          throw new NotFoundException("Producto no encontrado");
        }
        await this.pruneSafeDuplicateProducts(tx, companyId, updated);
        return this.productResponse(tx, companyId, updated.id);
      }
    });
  }

  async adjustStock(
    user: TenantUser,
    id: string,
    dto: AdjustProductStockDto,
  ): Promise<any> {
    const companyId = requireTenant(user);
    const source = await this.assertWritable(companyId);
    if (!source.supportsStockAdjustment) {
      throw new ConflictException(
        "La fuente de productos actual no permite ajustes de stock.",
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const current = await tx.product.findFirst({
        where: { id, companyId },
        select: {
          id: true,
          stock: true,
          unitOfMeasureId: true,
          unitOfMeasure: {
            select: {
              id: true,
              code: true,
              name: true,
              symbol: true,
              category: true,
              allowDecimals: true,
              precision: true,
              active: true,
            },
          },
        },
      });
      if (!current) {
        throw new NotFoundException("Producto no encontrado");
      }

      const unitOfMeasure = this.mapUnitOfMeasure(current.unitOfMeasure);
      const hasCountedStock = dto.stock !== undefined && dto.stock !== null;
      const hasDelta = dto.delta !== undefined && dto.delta !== null;
      if (hasCountedStock === hasDelta) {
        throw new BadRequestException(
          "Indica stock contado o delta, pero no ambos.",
        );
      }
      const warehouse = await this.resolveInventoryWarehouse(
        tx,
        companyId,
        dto.warehouseId,
        { rejectAmbiguousGlobal: !dto.warehouseId },
      );
      if (hasCountedStock) {
        const countedStock = new Prisma.Decimal(dto.stock ?? 0);
        const expectedCurrentStock =
          dto.expectedCurrentStock === undefined ||
          dto.expectedCurrentStock === null
            ? new Prisma.Decimal(current.stock ?? 0)
            : new Prisma.Decimal(dto.expectedCurrentStock);
        validateQuantityForUnit({
          quantity: countedStock,
          unit: unitOfMeasure,
          label: "stock del producto",
          allowZero: true,
        });
        validateQuantityForUnit({
          quantity: expectedCurrentStock,
          unit: unitOfMeasure,
          label: "stock esperado del producto",
          allowZero: true,
        });
        if (!countedStock.equals(expectedCurrentStock)) {
          await this.inventoryMutationService().setCountedStockInTransaction(
            tx,
            {
              companyId,
              productId: id,
              warehouseId: warehouse.id,
              countedQuantity: countedStock,
              expectedCurrentQuantity: expectedCurrentStock,
              sourceType: "PRODUCT_STOCK_COUNT",
              sourceId: id,
              reason: dto.reason?.trim() || "Conteo fisico de stock",
              createdByUserId: user.id,
            },
          );
        }
      } else {
        const delta = new Prisma.Decimal(dto.delta ?? 0);
        if (delta.equals(0)) {
          throw new BadRequestException("El delta de stock no puede ser cero.");
        }
        validateQuantityForUnit({
          quantity: delta.abs(),
          unit: unitOfMeasure,
          label: "delta de stock",
        });
        const input = {
          companyId,
          productId: id,
          warehouseId: warehouse.id,
          quantity: delta.abs(),
          type: delta.gt(0)
            ? InventoryMovementType.ADJUSTMENT_IN
            : InventoryMovementType.ADJUSTMENT_OUT,
          sourceType: "PRODUCT_STOCK_ADJUSTMENT",
          sourceId: id,
          reason: dto.reason?.trim() || "Ajuste manual de stock",
          createdByUserId: user.id,
        };
        if (delta.gt(0)) {
          await this.inventoryMutationService().increaseStockInTransaction(
            tx,
            input,
          );
        } else {
          await this.inventoryMutationService().decreaseStockInTransaction(
            tx,
            input,
          );
        }
      }

      return this.productResponse(tx, companyId, id);
    }, PRODUCT_INVENTORY_TRANSACTION_OPTIONS);
  }

  async remove(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    await this.assertWritable(companyId);
    const existing = await this.prisma.product.findFirst({
      where: { id, companyId },
      select: { id: true },
    });
    if (!existing) return { ok: true };
    try {
      await this.prisma.product.deleteMany({ where: { id, companyId } });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2003"
      ) {
        throw new ConflictException(
          "No se puede eliminar el producto porque tiene historial de inventario o transferencias asociado.",
        );
      }
      throw error;
    }
    return { ok: true };
  }

  async purgeAllForDebug(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.assertWritable(companyId);
    const deleted = await this.prisma.product.deleteMany({
      where: { companyId },
    });
    return {
      ok: true,
      deletedProducts: deleted.count,
    };
  }

  /**
   * Explicit SELECT for the catalog listing (/products).
   *
   * Keeps every column the response contract needs (all consumed by the
   * Flutter POS + PWA clients) and only skips columns the mobile/desktop/web
   * clients never read (raw storage metadata). The output shape produced by
   * mapProduct() is unchanged for consumed fields; the skipped ones were
   * already emitted as null for products without images.
   */
  private catalogProductSelect(): Prisma.ProductSelect {
    return {
      id: true,
      companyId: true,
      nombre: true,
      codigo: true,
      categoria: true,
      costo: true,
      precio: true,
      stock: true,
      taxTreatment: true,
      taxRate: true,
      taxPriceMode: true,
      imagen: true,
      imageKey: true,
      imageUpdatedAt: true,
      unitOfMeasureId: true,
      unitOfMeasure: {
        select: {
          id: true,
          code: true,
          name: true,
          symbol: true,
          category: true,
          allowDecimals: true,
          precision: true,
          active: true,
        },
      },
    };
  }

  private legacyCatalogProductSelect(): Prisma.ProductSelect {
    return {
      id: true,
      companyId: true,
      nombre: true,
      codigo: true,
      categoria: true,
      costo: true,
      precio: true,
      stock: true,
      taxTreatment: true,
      taxRate: true,
      taxPriceMode: true,
      imagen: true,
      imageKey: true,
      imageUpdatedAt: true,
    };
  }

  private mapProduct(product: Product) {
    const productAny = product as any;
    const imageKey =
      typeof productAny.imageKey === "string" ? productAny.imageKey : null;
    const fotoUrl = imageKey
      ? this.buildProductMediaUrl(product.id)
      : this.resolveUrl(product.imagen ?? null);
    return {
      ...product,
      fotoUrl,
      imageKey,
      storageProvider: imageKey
        ? "r2"
        : (productAny.imageStorageProvider ?? null),
      imageMimeType: productAny.imageMimeType ?? null,
      imageOriginalFileName: productAny.imageOriginalFileName ?? null,
      imageUpdatedAt: productAny.imageUpdatedAt ?? null,
      codigo: productAny.codigo ?? null,
      code: productAny.codigo ?? null,
      sku: productAny.codigo ?? null,
      barcode: productAny.codigo ?? null,
      stock: Number(product.stock ?? 0),
      cantidadDisponible: Number(product.stock ?? 0),
      stockDecimal: product.stock?.toString?.() ?? String(product.stock ?? 0),
      categoria: product.categoria ?? null,
      categoriaNombre: product.categoria ?? null,
      unitOfMeasureId: productAny.unitOfMeasureId ?? DEFAULT_UNIT_OF_MEASURE_ID,
      unitOfMeasure: this.mapUnitOfMeasure(productAny.unitOfMeasure),
      taxTreatment: productAny.taxTreatment ?? "INHERIT",
      taxRate: productAny.taxRate == null ? null : Number(productAny.taxRate),
      taxPriceMode: productAny.taxPriceMode ?? null,
    };
  }

  private resolveUrl(url: string | null): string | null {
    if (!url) return null;

    const extractUploadsPath = (value: string): string | null => {
      const normalized = value.replace(/\\/g, "/").trim();
      const marker = "/uploads/";
      const markerIndex = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        return normalized.substring(markerIndex);
      }
      if (normalized.startsWith("uploads/")) {
        return `/${normalized}`;
      }
      if (normalized.startsWith("./uploads/")) {
        return normalized.substring(1);
      }
      return null;
    };

    if (/^https?:\/\//i.test(url)) {
      if (!this.publicBaseUrl) return url;

      try {
        const parsed = new URL(url);
        const publicHost = new URL(this.publicBaseUrl).host.toLowerCase();
        const currentHost = parsed.host.toLowerCase();
        const normalizedPath = extractUploadsPath(parsed.pathname);

        // Preserve fully-qualified URLs to external hosts.
        // Do not rewrite FULLPOS-hosted upload URLs to the API public host unless
        // they are already served from the same domain.
        if (currentHost !== publicHost) {
          return url;
        }

        if (normalizedPath) {
          const query = parsed.search ?? "";
          return `${this.publicBaseUrl}${normalizedPath}${query}`;
        }
      } catch {
        return url;
      }

      return url;
    }

    const uploadsPath = extractUploadsPath(url);
    if (uploadsPath) {
      if (!this.publicBaseUrl) return uploadsPath;
      return `${this.publicBaseUrl}${uploadsPath}`;
    }

    if (!this.publicBaseUrl) return url;
    const normalized = url.startsWith("/") ? url : `/${url}`;
    return `${this.publicBaseUrl}${normalized}`;
  }

  private normalizeImagePathForStorage(raw?: string | null): string | null {
    if (raw === undefined || raw === null) return null;

    const extractUploadsPath = (value: string): string | null => {
      const normalized = value.replace(/\\/g, "/").trim();
      const marker = "/uploads/";
      const markerIndex = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        return normalized.substring(markerIndex);
      }
      if (normalized.startsWith("uploads/")) {
        return `/${normalized}`;
      }
      if (normalized.startsWith("./uploads/")) {
        return normalized.substring(1);
      }
      return null;
    };

    const value = raw.trim();
    if (!value) return null;

    if (/^https?:\/\//i.test(value)) {
      try {
        const parsed = new URL(value);
        const uploadsPath = extractUploadsPath(parsed.pathname);
        if (uploadsPath) {
          if (!this.publicBaseUrl) return value;
          try {
            const publicHost = new URL(this.publicBaseUrl).host.toLowerCase();
            const currentHost = parsed.host.toLowerCase();
            if (currentHost === publicHost) return uploadsPath;
          } catch {
            return value;
          }
          return value;
        }
        return value;
      } catch {
        return null;
      }
    }

    const uploadsPath = extractUploadsPath(value);
    if (uploadsPath) return uploadsPath;

    return null;
  }

  private extractR2Key(raw?: string | null): string | null {
    const value = (raw ?? "").trim().replace(/\\/g, "/");
    if (!value || value.includes("..")) return null;

    const normalizeKey = (candidate: string): string | null => {
      const key = candidate.trim().replace(/^\/+/, "");
      if (!key || key.includes("..") || key.includes("\\")) return null;
      return key.startsWith("uploads/companies/") ? key : null;
    };

    const direct = normalizeKey(value);
    if (direct) return direct;

    try {
      const parsed = new URL(value, "https://daleventa.local");
      const queryKey = parsed.searchParams.get("key");
      const fromQuery = normalizeKey(queryKey ?? "");
      if (fromQuery) return fromQuery;

      const marker = "/uploads/companies/";
      const markerIndex = parsed.pathname.indexOf(marker);
      if (markerIndex >= 0) {
        return normalizeKey(parsed.pathname.substring(markerIndex + 1));
      }
    } catch {
      // Keep falling through to path-style checks.
    }

    const marker = "/uploads/companies/";
    const markerIndex = value.indexOf(marker);
    if (markerIndex >= 0) {
      return normalizeKey(value.substring(markerIndex + 1));
    }

    return null;
  }

  private buildObjectMediaUrl(imageKey: string) {
    const path = `/media/object?key=${encodeURIComponent(imageKey)}`;
    return this.publicBaseUrl ? `${this.publicBaseUrl}${path}` : path;
  }

  private buildProductMediaUrl(productId: string) {
    const path = `/media/products/${encodeURIComponent(productId)}`;
    return this.publicBaseUrl ? `${this.publicBaseUrl}${path}` : path;
  }

  private normalizePublicBaseUrl(raw: string) {
    const value = raw.trim().replace(/\/$/, "");
    if (!value) return "";
    if (value.includes(" ") || value.includes('"') || value.includes("'")) {
      this.logger.warn(
        "PUBLIC_BASE_URL/API_BASE_URL inválido para construir URLs públicas de media",
      );
      return "";
    }
    if (/localhost|31\.97\.99\.70/i.test(value)) {
      this.logger.warn(
        "PUBLIC_BASE_URL/API_BASE_URL apunta a localhost/IP antigua; se usarán rutas relativas de media",
      );
      return "";
    }
    if (
      process.env.NODE_ENV === "production" &&
      !value.startsWith("https://")
    ) {
      this.logger.warn(
        "PUBLIC_BASE_URL/API_BASE_URL debe usar https:// en producción para media",
      );
      return "";
    }
    return value;
  }
}
