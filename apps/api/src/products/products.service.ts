import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma, Product } from "@prisma/client";
import { createHash } from "node:crypto";
import { PrismaService } from "../prisma/prisma.service";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { CatalogProductsService } from "./catalog-products.service";
import { CreateProductDto } from "./dto/create-product.dto";
import { UpdateProductDto } from "./dto/update-product.dto";

type ProductsSource = "FULLPOS" | "FULLPOS_DIRECT" | "LOCAL";

@Injectable()
export class ProductsService {
  private readonly logger = new Logger(ProductsService.name);
  private readonly publicBaseUrl: string;
  private readonly productsSource: ProductsSource;
  private readonly allowLocalFallback: boolean;

  constructor(
    private readonly prisma: PrismaService,
    private readonly catalogProducts: CatalogProductsService,
    private readonly config: ConfigService,
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

    const rawSource = (this.config.get<string>("PRODUCTS_SOURCE") ?? "")
      .trim()
      .toUpperCase();
    let computed: ProductsSource = "LOCAL";
    if (rawSource && rawSource !== "LOCAL") {
      this.logger.warn(
        `PRODUCTS_SOURCE=${rawSource} ignorado: el catálogo administrado por FullTech usa fuente LOCAL.`,
      );
    }

    this.productsSource = computed;
  }

  isReadOnly() {
    return (
      this.productsSource === "FULLPOS" ||
      this.productsSource === "FULLPOS_DIRECT"
    );
  }

  getSource(): ProductsSource {
    return this.productsSource;
  }

  private assertWritable() {
    if (
      this.productsSource === "FULLPOS" ||
      this.productsSource === "FULLPOS_DIRECT"
    ) {
      throw new ConflictException(
        "Productos en modo solo-lectura: fuente FULLPOS (cloud). Administra productos en FULLPOS.",
      );
    }
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
      await tx.product.delete({ where: { id: duplicate.id } });
      deleted += 1;
      this.logger.log(
        `product-duplicate-prune deleted companyId=${companyId} canonicalProductId=${canonical.id} duplicateProductId=${duplicate.id}`,
      );
    }
    return { deleted, skipped };
  }

  async create(user: TenantUser, dto: CreateProductDto): Promise<any> {
    this.assertWritable();
    const companyId = requireTenant(user);
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
            return this.mapProduct(existingOperationProduct);
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
        const data = {
          id: operationProductId ?? undefined,
          nombre: dto.nombre,
          codigo: this.normalizeProductCode(dto),
          categoria: dto.categoria,
          precio: new Prisma.Decimal(dto.precio),
          costo: new Prisma.Decimal(dto.costo),
          stock: new Prisma.Decimal(dto.stock ?? 0),
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
          data,
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
          return this.mapProduct(product);
        }

        try {
          const product = operationProductId
            ? await tx.product.upsert({
                where: { id: operationProductId },
                create: data,
                update: {},
              })
            : await tx.product.create({ data });
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
          return this.mapProduct(product);
        } catch (error) {
          if (this.isUniqueConstraint(error)) {
            throw error;
          }
          if (!this.isSchemaMismatch(error)) throw error;
          const product = await tx.product.create({ data });
          await this.pruneSafeDuplicateProducts(tx, companyId, product);
          return this.mapProduct(product);
        }
      });
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
            return this.mapProduct(existing);
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
    if (
      this.productsSource === "FULLPOS" ||
      this.productsSource === "FULLPOS_DIRECT"
    ) {
      try {
        const response = await this.catalogProducts.findAll();
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
      });
      return products.map((p) => this.mapProduct(p));
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      const products = await this.prisma.product.findMany({
        where: { companyId },
        orderBy: { nombre: "asc" },
      });
      return products.map((p) => this.mapProduct(p));
    }
  }

  async findOne(user: TenantUser, id: string): Promise<any> {
    const companyId = requireTenant(user);
    if (this.productsSource === "FULLPOS") {
      try {
        return await this.catalogProducts.findOne(id);
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
    return this.mapProduct(product);
  }

  async update(
    user: TenantUser,
    id: string,
    dto: UpdateProductDto,
  ): Promise<any> {
    this.assertWritable();
    const companyId = requireTenant(user);
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
        stock:
          dto.stock === undefined ? undefined : new Prisma.Decimal(dto.stock),
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
        const updated = await tx.product.update({ where: { id }, data });
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
        return this.mapProduct(updated);
      } catch (error) {
        if (this.isUniqueConstraint(error)) {
          throw new ConflictException(
            "Ya existe un producto con ese código en esta empresa",
          );
        }
        if (!this.isSchemaMismatch(error)) throw error;
        const updated = await tx.product.update({ where: { id }, data });
        await this.pruneSafeDuplicateProducts(tx, companyId, updated);
        return this.mapProduct(updated);
      }
    });
  }

  async remove(user: TenantUser, id: string) {
    this.assertWritable();
    await this.findOne(user, id);
    await this.prisma.product.delete({ where: { id } });
    return { ok: true };
  }

  async purgeAllForDebug(user: TenantUser) {
    this.assertWritable();
    const companyId = requireTenant(user);
    const deleted = await this.prisma.product.deleteMany({
      where: { companyId },
    });
    return {
      ok: true,
      deletedProducts: deleted.count,
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
      categoria: product.categoria ?? null,
      categoriaNombre: product.categoria ?? null,
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
        if (uploadsPath) return uploadsPath;
        return null;
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
